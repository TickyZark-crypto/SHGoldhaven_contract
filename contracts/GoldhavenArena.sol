// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {GoldhavenTypes as T} from "./lib/GoldhavenTypes.sol";
import {IGoldhavenNFT} from "./interfaces/IGoldhavenNFT.sol";
import {IGoldhavenBattleEngine} from "./interfaces/IGoldhavenBattleEngine.sol";

interface IGoldhavenArenaVault {
    function isValidator(address user) external view returns (bool);
    function stakeOwnerOfToken(uint256 tokenId) external view returns (address);
    function getArenaParticipants() external view returns (uint256[] memory);
    function depositDividendForLast24h() external payable returns (uint256 epochId);
    function markArenaOpened(address arena, uint256[] calldata participants) external;
    function markArenaFinished() external;
}

interface IGoldhavenArenaRolloverReceiver {
    function depositArenaFee() external payable;
}

/// @notice 1v1 elimination arena. Full skill settlement is delegated to GoldhavenBattleEngine.
/// @dev Current round matches can be verified concurrently by index. Validators should call verifyMatch(matchIndex)
///      for different match indexes to avoid mempool races. verifyNextMatch() remains as a compatibility helper.
contract GoldhavenArena is ReentrancyGuard {
    uint256 public constant MAX_PARTICIPANTS = 32;
    uint256 public constant BPS = 10_000;

    struct MatchRecord {
        uint256 tokenA;
        uint256 tokenB;
        uint256 winner;
        uint256 loser;
        address validator;
        bool verified;
    }

    IGoldhavenNFT public nft;
    IGoldhavenArenaVault public vault;
    IGoldhavenBattleEngine public battleEngine;
    IGoldhavenArenaRolloverReceiver public rolloverReceiver;
    uint256 public dayId;
    bool private _initialized;

    uint256[] public currentRound;
    uint256[] public nextRound;
    uint256[] public entrantTokenIds;
    mapping(uint256 => address) public entrantOwnerAtOpen;
    mapping(uint8 => uint256) public matchCountOfRound;
    mapping(uint8 => mapping(uint256 => MatchRecord)) internal _matchRecords;
    uint8 public currentRoundNumber = 1;
    uint8 public finalRoundNumber;

    /// @notice Compatibility pointer to the first unverified match pair in currentRound.
    uint256 public nextMatchIndex;
    uint256 public currentRoundMatchCount;
    uint256 public currentRoundVerifiedMatches;
    uint256 public nextRoundBaseLength;

    bool public finished;
    uint256 public championTokenId;

    mapping(uint8 => uint256[]) public eliminatedByRound;
    mapping(uint8 => mapping(uint256 => bool)) public matchVerified;
    mapping(uint8 => mapping(uint256 => uint256)) public matchWinner;
    mapping(uint8 => mapping(uint256 => uint256)) public matchLoser;

    mapping(address => uint256) public validatorVerifications;
    address[] public validatorList;
    uint256 public totalVerifications;

    mapping(address => uint256) public pendingBattleRewards;
    mapping(address => uint256) public pendingValidatorRewards;
    uint256 public totalPendingBattleRewards;
    uint256 public totalPendingValidatorRewards;
    uint256 public totalPendingRewards;

    event MatchVerified(uint8 indexed round, uint256 indexed tokenA, uint256 indexed tokenB, uint256 winner, address validator);
    event MatchVerifiedByIndex(uint8 indexed round, uint256 indexed matchIndex, uint256 indexed winner, uint256 loser, address validator);
    event ArenaEntrantSnapshot(uint256 indexed tokenId, address indexed owner);
    event Top32Snapshot(uint256 indexed rank, uint256 indexed tokenId, address indexed owner);
    event RoundAdvanced(uint8 indexed round);
    event ArenaFinished(uint256 indexed championTokenId, uint256 pot);
    event BattleRewardCredited(address indexed account, uint256 amount);
    event ValidatorRewardCredited(address indexed account, uint256 amount);
    event BattleRewardClaimed(address indexed account, uint256 amount);
    event ValidatorRewardClaimed(address indexed account, uint256 amount);
    event RewardClaimed(address indexed account, uint256 battleAmount, uint256 validatorAmount);
    event ExcessEthRolledOver(uint256 amount);

    error NotValidator();
    error BadParticipantCount();
    error Finished();
    error NoMatchReady();
    error MatchAlreadyVerified();
    error BadMatchIndex();
    error TransferFailed();
    error ZeroAmount();
    error InvalidParticipant();
    error DuplicateParticipant();
    error NotFinished();
    error AlreadyInitialized();
    error ZeroAddress();

    /// @dev Implementation constructor. Clones use initialize(); this locks the implementation itself.
    constructor() {
        _initialized = true;
    }

    /// @notice Initializes a freshly cloned arena.
    /// @dev Called by GoldhavenArenaDeployer immediately after EIP-1167 clone creation.
    function initialize(
        uint256 dayId_,
        IGoldhavenNFT nft_,
        IGoldhavenArenaVault vault_,
        IGoldhavenBattleEngine battleEngine_,
        IGoldhavenArenaRolloverReceiver rolloverReceiver_,
        address opener,
        uint256[] calldata participants
    ) external {
        if (_initialized) revert AlreadyInitialized();
        if (
            address(nft_) == address(0)
                || address(vault_) == address(0)
                || address(battleEngine_) == address(0)
                || address(rolloverReceiver_) == address(0)
        ) {
            revert ZeroAddress();
        }
        if (participants.length < 1 || participants.length > MAX_PARTICIPANTS) revert BadParticipantCount();
        _initialized = true;
        nft = nft_;
        vault = vault_;
        battleEngine = battleEngine_;
        rolloverReceiver = rolloverReceiver_;
        dayId = dayId_;
        currentRoundNumber = 1;
        uint256[] memory participantsMem = new uint256[](participants.length);
        for (uint256 i = 0; i < participants.length; i++) {
            participantsMem[i] = participants[i];
        }
        _validateParticipants(participantsMem);
        _snapshotParticipants(participantsMem);
        _buildFirstRound(participantsMem);
        _prepareRoundSlots();
        if (opener != address(0)) {
            validatorVerifications[opener] = 2;
            validatorList.push(opener);
            totalVerifications = 2;
        }
    }

    receive() external payable {
        if (finished && msg.value > 0) {
            _rollover(msg.value);
            emit ExcessEthRolledOver(msg.value);
        }
    }

    function pendingRewards(address account) public view returns (uint256) {
        return pendingBattleRewards[account] + pendingValidatorRewards[account];
    }

    function claimBattleReward() external nonReentrant returns (uint256 amount) {
        amount = pendingBattleRewards[msg.sender];
        if (amount == 0) revert ZeroAmount();
        pendingBattleRewards[msg.sender] = 0;
        totalPendingBattleRewards -= amount;
        totalPendingRewards -= amount;
        _sendEth(payable(msg.sender), amount);
        emit BattleRewardClaimed(msg.sender, amount);
    }

    function claimValidatorReward() external nonReentrant returns (uint256 amount) {
        amount = pendingValidatorRewards[msg.sender];
        if (amount == 0) revert ZeroAmount();
        pendingValidatorRewards[msg.sender] = 0;
        totalPendingValidatorRewards -= amount;
        totalPendingRewards -= amount;
        _sendEth(payable(msg.sender), amount);
        emit ValidatorRewardClaimed(msg.sender, amount);
    }

    /// @dev Backwards-compatible helper. Claims both battle and validator rewards in one transaction.
    function claimReward() external nonReentrant returns (uint256 battleAmount, uint256 validatorAmount) {
        battleAmount = pendingBattleRewards[msg.sender];
        validatorAmount = pendingValidatorRewards[msg.sender];
        uint256 amount = battleAmount + validatorAmount;
        if (amount == 0) revert ZeroAmount();
        if (battleAmount > 0) {
            pendingBattleRewards[msg.sender] = 0;
            totalPendingBattleRewards -= battleAmount;
        }
        if (validatorAmount > 0) {
            pendingValidatorRewards[msg.sender] = 0;
            totalPendingValidatorRewards -= validatorAmount;
        }
        totalPendingRewards -= amount;
        _sendEth(payable(msg.sender), amount);
        emit RewardClaimed(msg.sender, battleAmount, validatorAmount);
    }

    function sweepExcessToRollover() external nonReentrant returns (uint256 amount) {
        if (!finished) revert NotFinished();
        uint256 balance = address(this).balance;
        if (balance <= totalPendingRewards) revert ZeroAmount();
        amount = balance - totalPendingRewards;
        _rollover(amount);
        emit ExcessEthRolledOver(amount);
    }

    function finishSingleEntrant() external nonReentrant {
        if (finished) revert Finished();
        if (currentRound.length != 0 || nextRound.length != 1) revert NoMatchReady();
        _finish(nextRound[0]);
    }

    /// @notice Compatibility helper. Verifies the first currently unverified match.
    /// @dev For concurrent validation, prefer verifyMatch(matchIndex) with different match indexes.
    function verifyNextMatch() external nonReentrant {
        uint256 matchIndex = _firstUnverifiedMatchIndex();
        _verifyMatch(matchIndex, msg.sender);
    }

    /// @notice Verifies a specific match in the current round. Different matchIndex values can be verified concurrently.
    function verifyMatch(uint256 matchIndex) external nonReentrant {
        _verifyMatch(matchIndex, msg.sender);
    }

    function getCurrentRound() external view returns (uint256[] memory out) {
        out = currentRound;
    }

    function getNextRound() external view returns (uint256[] memory out) {
        out = nextRound;
    }

    function getEliminatedByRound(uint8 round) external view returns (uint256[] memory out) {
        out = eliminatedByRound[round];
    }

    function currentRoundRemaining() external view returns (uint256) {
        if (finished) return 0;
        return currentRound.length - (currentRoundVerifiedMatches * 2);
    }

    function currentRoundProgress() external view returns (uint256 verified, uint256 total) {
        return (currentRoundVerifiedMatches, currentRoundMatchCount);
    }

    function matchTokens(uint256 matchIndex) external view returns (uint256 tokenA, uint256 tokenB, bool verified, uint256 winner) {
        if (matchIndex >= currentRoundMatchCount) revert BadMatchIndex();
        MatchRecord storage m = _matchRecords[currentRoundNumber][matchIndex];
        tokenA = m.tokenA;
        tokenB = m.tokenB;
        verified = m.verified;
        winner = m.winner;
    }

    function matchCount(uint8 round) external view returns (uint256) {
        return matchCountOfRound[round];
    }

    function getMatch(uint8 round, uint256 matchIndex)
        external
        view
        returns (
            uint8 round_,
            uint256 matchIndex_,
            uint256 tokenA,
            uint256 tokenB,
            uint256 winner,
            uint256 loser,
            bool verified,
            address validator
        )
    {
        if (matchIndex >= matchCountOfRound[round]) revert BadMatchIndex();
        MatchRecord storage m = _matchRecords[round][matchIndex];
        return (round, matchIndex, m.tokenA, m.tokenB, m.winner, m.loser, m.verified, m.validator);
    }

    function entrantCount() external view returns (uint256) {
        return entrantTokenIds.length;
    }

    function entrantAt(uint256 index) external view returns (uint256 tokenId, address owner) {
        tokenId = entrantTokenIds[index];
        owner = entrantOwnerAtOpen[tokenId];
    }

    function top32Count() public view returns (uint256) {
        return finished ? entrantTokenIds.length : 0;
    }

    function top32At(uint256 index) external view returns (uint256 rank, uint256 tokenId, address owner) {
        uint256 count = top32Count();
        if (index >= count) revert BadMatchIndex();
        rank = index + 1;
        if (index == 0) {
            tokenId = championTokenId;
            owner = entrantOwnerAtOpen[tokenId];
            return (rank, tokenId, owner);
        }

        uint256 remainingIndex = index - 1;
        uint8 r = finalRoundNumber;
        while (r > 0) {
            uint256[] storage group = eliminatedByRound[r];
            if (remainingIndex < group.length) {
                tokenId = group[remainingIndex];
                owner = entrantOwnerAtOpen[tokenId];
                return (rank, tokenId, owner);
            }
            remainingIndex -= group.length;
            r--;
        }

        revert BadMatchIndex();
    }

    function _verifyMatch(uint256 matchIndex, address validator) internal {
        if (finished) revert Finished();
        if (!vault.isValidator(validator)) revert NotValidator();
        if (currentRoundMatchCount == 0 || matchIndex >= currentRoundMatchCount) revert BadMatchIndex();
        if (matchVerified[currentRoundNumber][matchIndex]) revert MatchAlreadyVerified();

        uint256 pairIndex = matchIndex * 2;
        uint256 tokenA = currentRound[pairIndex];
        uint256 tokenB = currentRound[pairIndex + 1];
        if (tokenA == 0 || tokenB == 0) revert NoMatchReady();

        matchVerified[currentRoundNumber][matchIndex] = true;

        T.BattleResult memory br = battleEngine.resolve(nft.cardOf(tokenA), nft.cardOf(tokenB));
        uint256 winner = br.winnerSide == 0 ? tokenA : tokenB;
        uint256 loser = br.winnerSide == 0 ? tokenB : tokenA;

        matchWinner[currentRoundNumber][matchIndex] = winner;
        matchLoser[currentRoundNumber][matchIndex] = loser;
        MatchRecord storage mr = _matchRecords[currentRoundNumber][matchIndex];
        mr.winner = winner;
        mr.loser = loser;
        mr.validator = validator;
        mr.verified = true;
        nextRound[nextRoundBaseLength + matchIndex] = winner;
        eliminatedByRound[currentRoundNumber].push(loser);
        currentRoundVerifiedMatches++;
        _creditValidator(validator, 1);
        _updateNextMatchIndex();

        emit MatchVerified(currentRoundNumber, tokenA, tokenB, winner, validator);
        emit MatchVerifiedByIndex(currentRoundNumber, matchIndex, winner, loser, validator);

        if (currentRoundVerifiedMatches >= currentRoundMatchCount) {
            if (nextRound.length == 1) _finish(nextRound[0]);
            else {
                currentRound = nextRound;
                delete nextRound;
                currentRoundNumber++;
                emit RoundAdvanced(currentRoundNumber);
                _prepareRoundSlots();
            }
        }
    }

    function _validateParticipants(uint256[] memory participants) internal view {
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i] == 0 || vault.stakeOwnerOfToken(participants[i]) == address(0)) revert InvalidParticipant();
            for (uint256 j = 0; j < i; j++) {
                if (participants[i] == participants[j]) revert DuplicateParticipant();
            }
        }
    }

    function _snapshotParticipants(uint256[] memory participants) internal {
        for (uint256 i = 0; i < participants.length; i++) {
            uint256 tokenId = participants[i];
            address owner = vault.stakeOwnerOfToken(tokenId);
            entrantTokenIds.push(tokenId);
            entrantOwnerAtOpen[tokenId] = owner;
            emit ArenaEntrantSnapshot(tokenId, owner);
        }
    }

    function _buildFirstRound(uint256[] memory participants) internal {
        for (uint256 i = 1; i < participants.length; i++) {
            uint256 key = participants[i];
            uint256 j = i;
            while (j > 0 && _higherByePriority(key, participants[j - 1])) {
                participants[j] = participants[j - 1];
                j--;
            }
            participants[j] = key;
        }
        uint256 bracketSize = _nextPowerOfTwo(participants.length);
        uint256 byeCount = bracketSize - participants.length;
        if (participants.length == 1) {
            nextRound.push(participants[0]);
            return;
        }
        for (uint256 i = 0; i < participants.length; i++) {
            if (i < byeCount) nextRound.push(participants[i]);
            else currentRound.push(participants[i]);
        }
    }

    function _prepareRoundSlots() internal {
        currentRoundMatchCount = currentRound.length / 2;
        currentRoundVerifiedMatches = 0;
        nextRoundBaseLength = nextRound.length;
        matchCountOfRound[currentRoundNumber] = currentRoundMatchCount;
        for (uint256 i = 0; i < currentRoundMatchCount; i++) {
            uint256 tokenA = currentRound[i * 2];
            uint256 tokenB = currentRound[i * 2 + 1];
            _matchRecords[currentRoundNumber][i] = MatchRecord(tokenA, tokenB, 0, 0, address(0), false);
            nextRound.push(0);
        }
        _updateNextMatchIndex();
    }

    function _firstUnverifiedMatchIndex() internal view returns (uint256) {
        if (currentRoundMatchCount == 0) revert NoMatchReady();
        for (uint256 i = 0; i < currentRoundMatchCount; i++) {
            if (!matchVerified[currentRoundNumber][i]) return i;
        }
        revert NoMatchReady();
    }

    function _updateNextMatchIndex() internal {
        if (finished || currentRoundMatchCount == 0) {
            nextMatchIndex = 0;
            return;
        }
        for (uint256 i = 0; i < currentRoundMatchCount; i++) {
            if (!matchVerified[currentRoundNumber][i]) {
                nextMatchIndex = i * 2;
                return;
            }
        }
        nextMatchIndex = currentRound.length;
    }

    function _higherByePriority(uint256 a, uint256 b) internal view returns (bool) {
        T.Card memory ca = nft.cardOf(a);
        T.Card memory cb = nft.cardOf(b);
        uint256 sa = uint256(ca.attack) + ca.defense;
        uint256 sb = uint256(cb.attack) + cb.defense;
        if (sa != sb) return sa > sb;
        if (ca.stakeTime != cb.stakeTime) return ca.stakeTime < cb.stakeTime;
        if (ca.stakeId != cb.stakeId) return ca.stakeId < cb.stakeId;
        return ca.tokenId < cb.tokenId;
    }

    function _nextPowerOfTwo(uint256 x) internal pure returns (uint256 p) {
        p = 1;
        while (p < x) p <<= 1;
    }

    function _creditValidator(address validator, uint256 count) internal {
        if (validatorVerifications[validator] == 0) validatorList.push(validator);
        validatorVerifications[validator] += count;
        totalVerifications += count;
    }

    function _finish(uint256 champion) internal {
        finished = true;
        championTokenId = champion;
        uint256 pot = address(this).balance;
        finalRoundNumber = currentRoundNumber;
        _depositTokenStakeDividend((pot * 2000) / BPS);
        _payValidators((pot * 1000) / BPS);
        _payToken(champion, (pot * 2000) / BPS);

        uint8 finalRound = currentRoundNumber;
        _payRankSlots(eliminatedByRound[finalRound], (pot * 1000) / BPS, 1);
        if (finalRound >= 2) _payRankSlots(eliminatedByRound[finalRound - 1], (pot * 1000) / BPS, 2);
        else _rollover((pot * 1000) / BPS);
        if (finalRound >= 3) _payRankSlots(eliminatedByRound[finalRound - 2], (pot * 1000) / BPS, 4);
        else _rollover((pot * 1000) / BPS);
        if (finalRound >= 4) _payRankSlots(eliminatedByRound[finalRound - 3], (pot * 1000) / BPS, 8);
        else _rollover((pot * 1000) / BPS);
        if (finalRound >= 5) _payRankSlots(eliminatedByRound[finalRound - 4], (pot * 1000) / BPS, 16);
        else _rollover((pot * 1000) / BPS);

        uint256 balance = address(this).balance;
        if (balance > totalPendingRewards) _rollover(balance - totalPendingRewards);

        _emitTop32Snapshot();

        delete currentRound;
        delete nextRound;
        currentRoundMatchCount = 0;
        currentRoundVerifiedMatches = 0;
        nextRoundBaseLength = 0;
        nextMatchIndex = 0;

        vault.markArenaFinished();
        emit ArenaFinished(champion, pot);
    }

    function _emitTop32Snapshot() internal {
        uint256 count = top32Count();
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId;
            if (i == 0) tokenId = championTokenId;
            else {
                uint256 remainingIndex = i - 1;
                uint8 r = finalRoundNumber;
                while (r > 0) {
                    uint256[] storage group = eliminatedByRound[r];
                    if (remainingIndex < group.length) {
                        tokenId = group[remainingIndex];
                        break;
                    }
                    remainingIndex -= group.length;
                    r--;
                }
            }
            if (tokenId != 0) emit Top32Snapshot(i + 1, tokenId, entrantOwnerAtOpen[tokenId]);
        }
    }

    function _payValidators(uint256 amount) internal {
        if (amount == 0) return;
        if (totalVerifications == 0 || validatorList.length == 0) {
            _rollover(amount);
            return;
        }
        uint256 paid;
        for (uint256 i = 0; i < validatorList.length; i++) {
            address v = validatorList[i];
            uint256 share = amount * validatorVerifications[v] / totalVerifications;
            paid += share;
            _creditValidatorReward(v, share);
        }
        if (amount > paid) _rollover(amount - paid);
    }

    function _payRankSlots(uint256[] storage tokens, uint256 amount, uint256 slotCount) internal {
        if (amount == 0) return;
        if (slotCount == 0) {
            _rollover(amount);
            return;
        }
        uint256 each = amount / slotCount;
        uint256 paid;
        uint256 n = tokens.length < slotCount ? tokens.length : slotCount;
        for (uint256 i = 0; i < n; i++) {
            paid += each;
            _payToken(tokens[i], each);
        }
        if (amount > paid) _rollover(amount - paid);
    }

    function _payToken(uint256 tokenId, uint256 amount) internal {
        address recipient = vault.stakeOwnerOfToken(tokenId);
        if (recipient == address(0)) {
            _rollover(amount);
            return;
        }
        _creditBattleReward(recipient, amount);
    }

    function _depositTokenStakeDividend(uint256 amount) internal {
        if (amount == 0) return;
        vault.depositDividendForLast24h{value: amount}();
    }

    function _rollover(uint256 amount) internal {
        if (amount == 0) return;
        rolloverReceiver.depositArenaFee{value: amount}();
    }

    function _creditBattleReward(address to, uint256 amount) internal {
        if (amount == 0) return;
        if (to == address(0)) {
            _rollover(amount);
            return;
        }
        pendingBattleRewards[to] += amount;
        totalPendingBattleRewards += amount;
        totalPendingRewards += amount;
        emit BattleRewardCredited(to, amount);
    }

    function _creditValidatorReward(address to, uint256 amount) internal {
        if (amount == 0) return;
        if (to == address(0)) {
            _rollover(amount);
            return;
        }
        pendingValidatorRewards[to] += amount;
        totalPendingValidatorRewards += amount;
        totalPendingRewards += amount;
        emit ValidatorRewardCredited(to, amount);
    }

    function _sendEth(address payable to, uint256 amount) internal {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
