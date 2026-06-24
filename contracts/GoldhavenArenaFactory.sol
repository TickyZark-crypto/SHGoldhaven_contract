// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGoldhavenNFT} from "./interfaces/IGoldhavenNFT.sol";
import {IGoldhavenBattleEngine} from "./interfaces/IGoldhavenBattleEngine.sol";
import {IGoldhavenVault} from "./interfaces/IGoldhavenVault.sol";

interface IGoldhavenHookArenaFunding {
    function arenaVaultEth() external view returns (uint256);
    function pullArenaFunding(address payable to, uint256 amount) external;
    function depositArenaFee() external payable;
}

interface IGoldhavenArenaStatus {
    function finished() external view returns (bool);
}

interface IGoldhavenArenaSingleEntrant {
    function finishSingleEntrant() external;
}

interface IGoldhavenArenaDeployer {
    function deployArena(
        uint256 dayId,
        address nft,
        address vault,
        address battleEngine,
        address rolloverReceiver,
        address opener,
        uint256[] calldata participants
    ) external returns (address arena);
}

/// @notice Opens Goldhaven arenas. Production enforces UTC 12:00-12:10 and one arena per day; owner test mode disables time/day limits.
/// @dev The Factory calls a clone deployer so Arena creation bytecode is not embedded here.
contract GoldhavenArenaFactory is Ownable {
    uint256 public constant OPEN_START = 12 hours;
    uint256 public constant OPEN_END = 12 hours + 10 minutes;

    IGoldhavenNFT public immutable nft;
    IGoldhavenVault public immutable vault;
    IGoldhavenBattleEngine public immutable battleEngine;
    IGoldhavenArenaDeployer public immutable arenaDeployer;
    IGoldhavenHookArenaFunding public hook;

    mapping(uint256 => address) public arenaOfDay;
    mapping(uint256 => address) public arenaOfId;
    uint256 public arenaCount;
    address public activeArena;
    address public latestArena;
    address public latestFinishedArena;
    bool public testMode;

    event ArenaOpened(uint256 indexed dayId, address indexed arena, address indexed opener, uint256 funding);
    event ArenaOpenedV2(uint256 indexed arenaId, uint256 indexed dayId, address indexed arena, address opener, uint256 funding);
    event ArenaStatusSynced(address indexed activeArena, address indexed latestFinishedArena);
    event DailyLimitEnabledSet(bool enabled);
    event TestModeSet(bool enabled);
    event HookSet(address indexed hook);

    error NotOpenWindow();
    error AlreadyOpened();
    error ArenaActive();
    error NotValidator();
    error ZeroAddress();
    error HookAlreadySet();
    error HookNotSet();

    constructor(
        address initialOwner,
        IGoldhavenNFT nft_,
        IGoldhavenVault vault_,
        IGoldhavenBattleEngine battleEngine_,
        IGoldhavenArenaDeployer arenaDeployer_
    ) Ownable(initialOwner) {
        if (
            address(nft_) == address(0)
                || address(vault_) == address(0)
                || address(battleEngine_) == address(0)
                || address(arenaDeployer_) == address(0)
        ) {
            revert ZeroAddress();
        }
        nft = nft_;
        vault = vault_;
        battleEngine = battleEngine_;
        arenaDeployer = arenaDeployer_;
    }

    function setHook(IGoldhavenHookArenaFunding newHook) external onlyOwner {
        if (address(hook) != address(0)) revert HookAlreadySet();
        if (address(newHook) == address(0)) revert ZeroAddress();
        hook = newHook;
        emit HookSet(address(newHook));
    }

    /// @notice Owner test mode. Production default is false.
    /// @dev When enabled, openDailyArena ignores UTC window and one-per-day checks.
    ///      Active arena locking still applies, so NFT stake/unstake remains blocked while an arena is running.
    function setTestMode(bool enabled) external onlyOwner {
        testMode = enabled;
        emit TestModeSet(enabled);
        emit DailyLimitEnabledSet(!enabled);
    }

    /// @dev Backwards-compatible helper. Setting daily limit disabled is equivalent to enabling test mode.
    function setDailyLimitEnabled(bool enabled) external onlyOwner {
        testMode = !enabled;
        emit TestModeSet(!enabled);
        emit DailyLimitEnabledSet(enabled);
    }

    function dailyLimitEnabled() external view returns (bool) {
        return !testMode;
    }

    /// @notice Syncs active/latest-finished pointers after an arena finishes.
    function syncArenaStatus() public {
        address arena = activeArena;
        if (arena != address(0) && IGoldhavenArenaStatus(arena).finished()) {
            latestFinishedArena = arena;
            activeArena = address(0);
            emit ArenaStatusSynced(address(0), latestFinishedArena);
        }
    }

    /// @notice Opens the arena using the active NFT participant queue from Vault.
    /// @dev Validators no longer provide arbitrary participantTokenIds.
    function openDailyArena() public returns (address arena) {
        syncArenaStatus();
        if (!testMode && !isOpenWindow()) revert NotOpenWindow();
        if (!vault.isValidator(msg.sender)) revert NotValidator();
        if (activeArena != address(0)) revert ArenaActive();

        uint256 dayId = block.timestamp / 1 days;
        if (!testMode && arenaOfDay[dayId] != address(0)) revert AlreadyOpened();

        IGoldhavenHookArenaFunding arenaHook = hook;
        if (address(arenaHook) == address(0)) revert HookNotSet();

        uint256[] memory participantTokenIds = vault.getArenaParticipants();
        arena = arenaDeployer.deployArena(
            dayId,
            address(nft),
            address(vault),
            address(battleEngine),
            address(arenaHook),
            msg.sender,
            participantTokenIds
        );

        arenaCount++;
        arenaOfId[arenaCount] = arena;
        arenaOfDay[dayId] = arena;
        activeArena = arena;
        latestArena = arena;

        vault.markArenaOpened(arena, participantTokenIds);

        uint256 funding = (arenaHook.arenaVaultEth() * 70) / 100;
        if (funding > 0) arenaHook.pullArenaFunding(payable(arena), funding);
        if (participantTokenIds.length == 1) {
            IGoldhavenArenaSingleEntrant(arena).finishSingleEntrant();
            syncArenaStatus();
        }
        emit ArenaOpened(dayId, arena, msg.sender, funding);
        emit ArenaOpenedV2(arenaCount, dayId, arena, msg.sender, funding);
    }

    /// @dev Backwards-compatible alias. The calldata list is intentionally ignored.
    function openDailyArena(uint256[] calldata) external returns (address arena) {
        return openDailyArena();
    }

    /// @dev Alias for frontends/tests. Same validation as openDailyArena().
    function openArena() external returns (address arena) {
        return openDailyArena();
    }

    function isOpenWindow() public view returns (bool) {
        if (testMode) return true;
        uint256 secondsOfDay = block.timestamp % 1 days;
        return secondsOfDay >= OPEN_START && secondsOfDay < OPEN_END;
    }
}
