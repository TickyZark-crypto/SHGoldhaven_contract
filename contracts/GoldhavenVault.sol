// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IGoldhavenNFT} from "./interfaces/IGoldhavenNFT.sol";
import {IGoldhavenPriceOracle} from "./interfaces/IGoldhavenPriceOracle.sol";

interface IArenaFeeReceiver {
    function depositArenaFee() external payable;
    function arenaController() external view returns (address);
}

interface IArenaControllerSchedule {
    function testMode() external view returns (bool);
    function arenaOfDay(uint256 dayId) external view returns (address);
}

interface IArenaFinishedView {
    function finished() external view returns (bool);
}

/// @notice Goldhaven vault.
/// @dev NFT staking is only for arena participation. GHV token staking drives:
///      1) the 24h dividend share, 2) validator permission, and 3) NFT defense bonus at mint time.
contract GoldhavenVault is IERC721Receiver, Ownable, ReentrancyGuard {
    uint256 public constant NFT_STAKE_FEE = 0.001 ether;
    uint256 public constant VALIDATOR_THRESHOLD_USD_WAD = 150e18;
    uint256 public constant WINDOW = 24 hours;
    uint256 public constant MAX_ARENA_PARTICIPANTS = 32;
    uint256 public constant NFT_ACTION_LOCK_START = 11 hours + 50 minutes;
    uint256 public constant NFT_ACTION_LOCK_END = 12 hours + 10 minutes;

    IERC20 public immutable ghv;
    IGoldhavenNFT public immutable nft;
    IGoldhavenPriceOracle public immutable oracle;
    IArenaFeeReceiver public arenaFeeReceiver;

    struct NftStake {
        address owner;
        uint256 tokenId;
        uint64 stakedAt;
        bool active;
    }

    struct Observation {
        uint64 timestamp;
        uint256 cumulativeTokenSeconds;
        uint256 tokenAmount;
    }

    struct DividendEpoch {
        uint64 start;
        uint64 end;
        uint256 amount;
        uint256 totalTokenSeconds;
        uint256 claimed;
    }

    uint256 public nextStakeId = 1;
    uint256 public totalTokenStaked;
    uint64 public lastCheckpointTime;
    uint256 public cumulativeTokenSeconds;

    uint256 public nextDividendEpochId = 1;
    uint256 public pendingUndistributedDividends;

    mapping(uint256 => NftStake) public nftStakes;
    mapping(uint256 => uint256) public stakeIdOfToken;
    mapping(address => uint256) public tokenStakeOf;

    uint256[] internal arenaParticipantTokenIds;
    mapping(uint256 => uint256) public arenaParticipantIndexPlusOne;

    /// @notice Current arena that has taken custody of the active participant queue for settlement.
    address public activeArena;
    bool public arenaInProgress;
    uint256[] internal activeArenaLockedTokenIds;
    mapping(uint256 => bool) public lockedInActiveArena;
    mapping(uint256 => address) public arenaOfToken;
    mapping(uint256 => uint256) public arenaFinishedAtOfToken;

    bool private receivingArenaStake;

    Observation[] public observations;
    mapping(address => Observation[]) internal userObservations;
    mapping(address => uint64) public userLastCheckpointTime;
    mapping(address => uint256) public userCumulativeTokenSeconds;

    mapping(uint256 => DividendEpoch) public dividendEpochs;
    mapping(uint256 => mapping(address => bool)) public dividendClaimed;

    event NftStakedForArena(address indexed user, uint256 indexed tokenId, uint256 indexed stakeId);
    event NftUnstakedFromArena(address indexed user, uint256 indexed tokenId, uint256 indexed stakeId);
    event ArenaParticipantAdded(uint256 indexed tokenId, uint256 indexed stakeId, address indexed owner);
    event ArenaParticipantRemoved(uint256 indexed tokenId, uint256 indexed stakeId, address indexed owner);
    event TokenStaked(address indexed user, uint256 amount);
    event TokenUnstaked(address indexed user, uint256 amount);
    event DividendDeposited(uint256 indexed epochId, uint64 start, uint64 end, uint256 amount, uint256 totalTokenSeconds);
    event DividendRolledOver(uint256 amount, uint64 start, uint64 end);
    event DividendClaimed(uint256 indexed epochId, address indexed user, uint256 amount, uint256 userTokenSeconds);
    event ArenaFeeReceiverSet(address indexed receiver);
    event HookSet(address indexed hook);
    event ActiveArenaOpened(address indexed arena, uint256 participantCount);
    event ActiveArenaFinished(address indexed arena);
    event TokenAssignedToArena(uint256 indexed tokenId, address indexed arena);
    event DirectEthReceived(address indexed from, uint256 amount);
    event NftActionLockChecked(bool locked);

    error BadFee();
    error NotStakeOwner();
    error AlreadyStaked();
    error NotStaked();
    error ArenaFull();
    error ArenaLocked();
    error ZeroAmount();
    error TransferFailed();
    error AlreadyClaimed();
    error BadEpoch();
    error ZeroAddress();
    error HookAlreadySet();
    error HookNotSet();
    error NotArenaController();
    error NotActiveArena();
    error ArenaInProgress();
    error BadParticipantList();
    error InvalidArenaParticipant();
    error InvalidNftTransfer();

    constructor(address initialOwner, IERC20 ghv_, IGoldhavenNFT nft_, IGoldhavenPriceOracle oracle_)
        Ownable(initialOwner)
    {
        if (address(ghv_) == address(0) || address(nft_) == address(0) || address(oracle_) == address(0)) {
            revert ZeroAddress();
        }
        ghv = ghv_;
        nft = nft_;
        oracle = oracle_;
        lastCheckpointTime = uint64(block.timestamp);
        observations.push(Observation(uint64(block.timestamp), 0, 0));
    }

    receive() external payable {
        if (msg.value == 0) return;
        pendingUndistributedDividends += msg.value;
        emit DirectEthReceived(msg.sender, msg.value);
        emit DividendRolledOver(msg.value, uint64(block.timestamp), uint64(block.timestamp));
    }

    /// @notice Locks the Hook address exactly once. NFT arena entry fees are sent to this Hook.
    function setHook(IArenaFeeReceiver newHook) public onlyOwner {
        if (address(arenaFeeReceiver) != address(0)) revert HookAlreadySet();
        if (address(newHook) == address(0)) revert ZeroAddress();
        arenaFeeReceiver = newHook;
        emit HookSet(address(newHook));
        emit ArenaFeeReceiverSet(address(newHook));
    }

    /// @dev Backwards-compatible alias. Semantically this is the one-time Hook setter.
    function setArenaFeeReceiver(IArenaFeeReceiver receiver) external onlyOwner {
        setHook(receiver);
    }

    modifier onlyArenaController() {
        IArenaFeeReceiver receiver = arenaFeeReceiver;
        if (address(receiver) == address(0)) revert HookNotSet();
        if (msg.sender != receiver.arenaController()) revert NotArenaController();
        _;
    }

    /// @notice Locks an NFT for arena participation only. This is not the dividend stake.
    function stakeNftForArena(uint256 tokenId) public payable nonReentrant returns (uint256 stakeId) {
        if (isNftActionLocked()) revert ArenaLocked();
        if (msg.value != NFT_STAKE_FEE) revert BadFee();
        if (stakeIdOfToken[tokenId] != 0) revert AlreadyStaked();
        if (arenaParticipantTokenIds.length >= MAX_ARENA_PARTICIPANTS) revert ArenaFull();
        stakeId = nextStakeId++;
        stakeIdOfToken[tokenId] = stakeId;
        nftStakes[stakeId] = NftStake(msg.sender, tokenId, uint64(block.timestamp), true);
        _addArenaParticipant(tokenId);
        receivingArenaStake = true;
        IERC721(address(nft)).safeTransferFrom(msg.sender, address(this), tokenId);
        receivingArenaStake = false;
        nft.setStakeMeta(tokenId, stakeId, uint64(block.timestamp));
        IArenaFeeReceiver receiver = arenaFeeReceiver;
        if (address(receiver) == address(0)) revert HookNotSet();
        receiver.depositArenaFee{value: msg.value}();
        emit NftStakedForArena(msg.sender, tokenId, stakeId);
        emit ArenaParticipantAdded(tokenId, stakeId, msg.sender);
    }

    /// @dev Backwards-compatible alias for old frontends. Semantics are arena participation only.
    function stakeNft(uint256 tokenId) external payable returns (uint256 stakeId) {
        return stakeNftForArena(tokenId);
    }

    function unstakeNftFromArena(uint256 stakeId) public nonReentrant {
        if (isNftActionLocked()) revert ArenaLocked();
        NftStake storage s = nftStakes[stakeId];
        if (!s.active) revert NotStaked();
        if (s.owner != msg.sender) revert NotStakeOwner();
        if (lockedInActiveArena[s.tokenId]) revert ArenaInProgress();
        s.active = false;
        _removeArenaParticipant(s.tokenId);
        stakeIdOfToken[s.tokenId] = 0;
        delete arenaOfToken[s.tokenId];
        delete arenaFinishedAtOfToken[s.tokenId];
        nft.clearStakeMeta(s.tokenId);
        IERC721(address(nft)).safeTransferFrom(address(this), msg.sender, s.tokenId);
        emit NftUnstakedFromArena(msg.sender, s.tokenId, stakeId);
        emit ArenaParticipantRemoved(s.tokenId, stakeId, msg.sender);
    }

    /// @dev Backwards-compatible alias for old frontends. Semantics are arena participation only.
    function unstakeNft(uint256 stakeId) external {
        unstakeNftFromArena(stakeId);
    }

    /// @notice Stakes Goldhaven Token. This stake controls dividends, validator rights, and mint defense bonus.
    function stakeToken(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _checkpoint();
        _checkpointUser(msg.sender);

        tokenStakeOf[msg.sender] += amount;
        totalTokenStaked += amount;

        observations.push(Observation(uint64(block.timestamp), cumulativeTokenSeconds, totalTokenStaked));
        userObservations[msg.sender].push(Observation(uint64(block.timestamp), userCumulativeTokenSeconds[msg.sender], tokenStakeOf[msg.sender]));

        bool ok = ghv.transferFrom(msg.sender, address(this), amount);
        if (!ok) revert TransferFailed();
        emit TokenStaked(msg.sender, amount);
    }

    function unstakeToken(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _checkpoint();
        _checkpointUser(msg.sender);

        tokenStakeOf[msg.sender] -= amount;
        totalTokenStaked -= amount;

        observations.push(Observation(uint64(block.timestamp), cumulativeTokenSeconds, totalTokenStaked));
        userObservations[msg.sender].push(Observation(uint64(block.timestamp), userCumulativeTokenSeconds[msg.sender], tokenStakeOf[msg.sender]));

        bool ok = ghv.transfer(msg.sender, amount);
        if (!ok) revert TransferFailed();
        emit TokenUnstaked(msg.sender, amount);
    }

    /// @notice Arena deposits the 20% dividend pool here at settlement time.
    /// @dev Shares are calculated by token-seconds in the last 24h window.
    ///      If no GHV tokens were staked in the window, the funds roll into the next dividend epoch.
    function depositDividendForLast24h() external payable nonReentrant returns (uint256 epochId) {
        if (msg.value == 0) revert ZeroAmount();
        _checkpoint();

        uint64 end = uint64(block.timestamp);
        uint64 start = end > WINDOW ? uint64(end - WINDOW) : uint64(0);
        uint256 totalSeconds = cumulativeAt(end) - cumulativeAt(start);

        if (totalSeconds == 0) {
            pendingUndistributedDividends += msg.value;
            emit DividendRolledOver(msg.value, start, end);
            return 0;
        }

        uint256 amount = msg.value + pendingUndistributedDividends;
        pendingUndistributedDividends = 0;
        epochId = nextDividendEpochId++;
        dividendEpochs[epochId] = DividendEpoch(start, end, amount, totalSeconds, 0);
        emit DividendDeposited(epochId, start, end, amount, totalSeconds);
    }

    function claimDividend(uint256 epochId) public nonReentrant returns (uint256 amount) {
        return _claimDividend(epochId, msg.sender);
    }

    function _claimDividend(uint256 epochId, address user) internal returns (uint256 amount) {
        DividendEpoch storage e = dividendEpochs[epochId];
        if (e.amount == 0) revert BadEpoch();
        if (dividendClaimed[epochId][user]) revert AlreadyClaimed();
        dividendClaimed[epochId][user] = true;

        uint256 userSeconds = userCumulativeAt(user, e.end) - userCumulativeAt(user, e.start);
        if (userSeconds == 0) {
            emit DividendClaimed(epochId, user, 0, 0);
            return 0;
        }

        amount = (e.amount * userSeconds) / e.totalTokenSeconds;
        e.claimed += amount;
        _sendEth(payable(user), amount);
        emit DividendClaimed(epochId, user, amount, userSeconds);
    }

    function claimDividends(uint256[] calldata epochIds) external nonReentrant returns (uint256 total) {
        for (uint256 i = 0; i < epochIds.length; i++) {
            total += _claimDividend(epochIds[i], msg.sender);
        }
    }

    function previewDividend(uint256 epochId, address user) external view returns (uint256 amount, uint256 userTokenSeconds) {
        DividendEpoch memory e = dividendEpochs[epochId];
        if (e.amount == 0 || dividendClaimed[epochId][user]) return (0, 0);
        userTokenSeconds = userCumulativeAt(user, e.end) - userCumulativeAt(user, e.start);
        amount = e.totalTokenSeconds == 0 ? 0 : (e.amount * userTokenSeconds) / e.totalTokenSeconds;
    }



    /// @notice Called by ArenaFactory when an arena is opened.
    /// @dev Locks the exact current participant queue for this Arena and removes it from the pending queue.
    ///      After the Arena finishes, NFTs can be redeemed, but they are not automatically re-entered for the next Arena.
    function markArenaOpened(address arena, uint256[] calldata participants) external nonReentrant onlyArenaController {
        if (arenaInProgress) revert ArenaInProgress();
        if (arena == address(0)) revert ZeroAddress();
        if (participants.length == 0 || participants.length != arenaParticipantTokenIds.length) revert BadParticipantList();

        for (uint256 i = 0; i < participants.length; i++) {
            uint256 tokenId = participants[i];
            if (arenaParticipantIndexPlusOne[tokenId] == 0) revert InvalidArenaParticipant();
            uint256 stakeId = stakeIdOfToken[tokenId];
            if (stakeId == 0 || !nftStakes[stakeId].active) revert InvalidArenaParticipant();
            if (lockedInActiveArena[tokenId]) revert ArenaInProgress();
            lockedInActiveArena[tokenId] = true;
            arenaOfToken[tokenId] = arena;
            delete arenaFinishedAtOfToken[tokenId];
            activeArenaLockedTokenIds.push(tokenId);
            emit TokenAssignedToArena(tokenId, arena);
        }

        // The pending queue is consumed by this arena. To join the next arena, the user must unstake and stake again.
        for (uint256 i = 0; i < participants.length; i++) {
            _removeArenaParticipant(participants[i]);
        }

        activeArena = arena;
        arenaInProgress = true;
        emit ActiveArenaOpened(arena, participants.length);
    }

    /// @notice Called by the active Arena after final settlement.
    function markArenaFinished() external nonReentrant {
        if (!arenaInProgress || msg.sender != activeArena) revert NotActiveArena();
        address arena = activeArena;
        for (uint256 i = 0; i < activeArenaLockedTokenIds.length; i++) {
            delete lockedInActiveArena[activeArenaLockedTokenIds[i]];
            arenaFinishedAtOfToken[activeArenaLockedTokenIds[i]] = block.timestamp;
        }
        delete activeArenaLockedTokenIds;
        activeArena = address(0);
        arenaInProgress = false;
        emit ActiveArenaFinished(arena);
    }

    function activeArenaLockedCount() external view returns (uint256) {
        return activeArenaLockedTokenIds.length;
    }

    function activeArenaLockedTokenAt(uint256 index) external view returns (uint256) {
        return activeArenaLockedTokenIds[index];
    }

    function arenaParticipantCount() external view returns (uint256) {
        return arenaParticipantTokenIds.length;
    }

    function arenaParticipantAt(uint256 index) external view returns (uint256) {
        return arenaParticipantTokenIds[index];
    }

    function getArenaParticipants() external view returns (uint256[] memory participants) {
        participants = new uint256[](arenaParticipantTokenIds.length);
        for (uint256 i = 0; i < arenaParticipantTokenIds.length; i++) {
            participants[i] = arenaParticipantTokenIds[i];
        }
    }

    function isArenaParticipant(uint256 tokenId) external view returns (bool) {
        return arenaParticipantIndexPlusOne[tokenId] != 0;
    }

    function stakeOwnerOfToken(uint256 tokenId) external view returns (address) {
        uint256 stakeId = stakeIdOfToken[tokenId];
        if (stakeId == 0) return address(0);
        return nftStakes[stakeId].owner;
    }

    function isValidator(address user) external view returns (bool) {
        return oracle.ghvToUsdWad(tokenStakeOf[user]) >= VALIDATOR_THRESHOLD_USD_WAD;
    }

    /// @notice Global 24h average GHV token stake, converted to USD. Used for NFT defense bonus at mint time.
    function averageLockUsdWad24h() external view returns (uint256) {
        uint256 avgTokenAmount = averageTokenAmount24h();
        return oracle.ghvToUsdWad(avgTokenAmount);
    }

    function averageTokenAmount24h() public view returns (uint256) {
        uint256 nowTs = block.timestamp;
        uint256 currentCum = cumulativeTokenSeconds + totalTokenStaked * (nowTs - lastCheckpointTime);
        uint256 start = nowTs > WINDOW ? nowTs - WINDOW : 0;
        uint256 startCum = cumulativeAt(start);
        uint256 elapsed = nowTs - start;
        if (elapsed == 0) return totalTokenStaked;
        return (currentCum - startCum) / elapsed;
    }

    function userAverageTokenAmount24h(address user) external view returns (uint256) {
        uint256 nowTs = block.timestamp;
        uint256 start = nowTs > WINDOW ? nowTs - WINDOW : 0;
        uint256 elapsed = nowTs - start;
        if (elapsed == 0) return tokenStakeOf[user];
        return (userCumulativeAt(user, nowTs) - userCumulativeAt(user, start)) / elapsed;
    }

    function userObservationCount(address user) external view returns (uint256) {
        return userObservations[user].length;
    }

    function userObservationAt(address user, uint256 index) external view returns (Observation memory) {
        return userObservations[user][index];
    }

    /// @notice Returns true when NFT arena staking/unstaking is disabled.
    /// @dev Production rules:
    ///      - active arena always locks NFT stake/unstake;
    ///      - UTC 11:50-12:10 locks NFT stake/unstake while today's arena has not finished,
    ///        including the not-yet-opened case;
    ///      - after today's arena finishes, NFT stake/unstake is open again.
    ///      Test mode, controlled by ArenaFactory, removes time/day restrictions but still respects active arena locks.
    function isArenaLockWindow() public view returns (bool) {
        return isNftActionLocked();
    }

    function isNftActionLocked() public view returns (bool) {
        if (arenaInProgress) return true;
        if (_factoryTestMode()) return false;

        uint256 secondsOfDay = block.timestamp % 1 days;
        if (secondsOfDay < NFT_ACTION_LOCK_START || secondsOfDay >= NFT_ACTION_LOCK_END) return false;

        address controller = _arenaControllerOrZero();
        if (controller == address(0)) return true;

        uint256 dayId = block.timestamp / 1 days;
        address todayArena;
        try IArenaControllerSchedule(controller).arenaOfDay(dayId) returns (address arena) {
            todayArena = arena;
        } catch {
            return true;
        }

        // Within 11:50-12:10, no arena yet means today's arena is not finished, so NFT actions are locked.
        if (todayArena == address(0)) return true;

        try IArenaFinishedView(todayArena).finished() returns (bool done) {
            return !done;
        } catch {
            return true;
        }
    }

    function _factoryTestMode() internal view returns (bool) {
        address controller = _arenaControllerOrZero();
        if (controller == address(0)) return false;
        try IArenaControllerSchedule(controller).testMode() returns (bool enabled) {
            return enabled;
        } catch {
            return false;
        }
    }

    function _arenaControllerOrZero() internal view returns (address controller) {
        IArenaFeeReceiver receiver = arenaFeeReceiver;
        if (address(receiver) == address(0)) return address(0);
        try receiver.arenaController() returns (address c) {
            return c;
        } catch {
            return address(0);
        }
    }

    function _addArenaParticipant(uint256 tokenId) internal {
        if (arenaParticipantIndexPlusOne[tokenId] != 0) revert AlreadyStaked();
        arenaParticipantTokenIds.push(tokenId);
        arenaParticipantIndexPlusOne[tokenId] = arenaParticipantTokenIds.length;
    }

    function _removeArenaParticipant(uint256 tokenId) internal {
        uint256 indexPlusOne = arenaParticipantIndexPlusOne[tokenId];
        if (indexPlusOne == 0) return;

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = arenaParticipantTokenIds.length - 1;
        if (index != lastIndex) {
            uint256 lastTokenId = arenaParticipantTokenIds[lastIndex];
            arenaParticipantTokenIds[index] = lastTokenId;
            arenaParticipantIndexPlusOne[lastTokenId] = indexPlusOne;
        }
        arenaParticipantTokenIds.pop();
        delete arenaParticipantIndexPlusOne[tokenId];
    }

    function _checkpoint() internal {
        uint64 nowTs = uint64(block.timestamp);
        if (nowTs == lastCheckpointTime) return;
        cumulativeTokenSeconds += totalTokenStaked * (nowTs - lastCheckpointTime);
        lastCheckpointTime = nowTs;
        observations.push(Observation(nowTs, cumulativeTokenSeconds, totalTokenStaked));
    }

    function _checkpointUser(address user) internal {
        uint64 nowTs = uint64(block.timestamp);
        uint64 last = userLastCheckpointTime[user];
        if (last == 0) {
            userLastCheckpointTime[user] = nowTs;
            userObservations[user].push(Observation(nowTs, 0, tokenStakeOf[user]));
            return;
        }
        if (nowTs == last) return;
        userCumulativeTokenSeconds[user] += tokenStakeOf[user] * (nowTs - last);
        userLastCheckpointTime[user] = nowTs;
        userObservations[user].push(Observation(nowTs, userCumulativeTokenSeconds[user], tokenStakeOf[user]));
    }

    function cumulativeAt(uint256 timestamp_) public view returns (uint256) {
        if (observations.length == 0 || timestamp_ <= observations[0].timestamp) return 0;
        Observation memory latest = observations[observations.length - 1];
        if (timestamp_ >= block.timestamp) return cumulativeTokenSeconds + totalTokenStaked * (timestamp_ - lastCheckpointTime);
        if (timestamp_ >= latest.timestamp) return latest.cumulativeTokenSeconds + latest.tokenAmount * (timestamp_ - latest.timestamp);

        for (uint256 i = observations.length; i > 0; i--) {
            Observation memory o = observations[i - 1];
            if (o.timestamp <= timestamp_) {
                return o.cumulativeTokenSeconds + o.tokenAmount * (timestamp_ - o.timestamp);
            }
        }
        return 0;
    }

    function userCumulativeAt(address user, uint256 timestamp_) public view returns (uint256) {
        Observation[] storage obs = userObservations[user];
        if (obs.length == 0 || timestamp_ <= obs[0].timestamp) return 0;
        Observation memory latest = obs[obs.length - 1];
        if (timestamp_ >= block.timestamp) {
            uint64 last = userLastCheckpointTime[user];
            if (last == 0) return 0;
            return userCumulativeTokenSeconds[user] + tokenStakeOf[user] * (timestamp_ - last);
        }
        if (timestamp_ >= latest.timestamp) return latest.cumulativeTokenSeconds + latest.tokenAmount * (timestamp_ - latest.timestamp);

        for (uint256 i = obs.length; i > 0; i--) {
            Observation memory o = obs[i - 1];
            if (o.timestamp <= timestamp_) {
                return o.cumulativeTokenSeconds + o.tokenAmount * (timestamp_ - o.timestamp);
            }
        }
        return 0;
    }

    function _sendEth(address payable to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(nft) || !receivingArenaStake) revert InvalidNftTransfer();
        return IERC721Receiver.onERC721Received.selector;
    }
}
