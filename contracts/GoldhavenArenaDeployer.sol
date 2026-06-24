// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {GoldhavenArena, IGoldhavenArenaVault, IGoldhavenArenaRolloverReceiver} from "./GoldhavenArena.sol";
import {IGoldhavenNFT} from "./interfaces/IGoldhavenNFT.sol";
import {IGoldhavenBattleEngine} from "./interfaces/IGoldhavenBattleEngine.sol";

/// @notice Deploys lightweight EIP-1167 GoldhavenArena clones.
/// @dev The Arena implementation is deployed once. This deployer only stores its address and clones it,
///      so GoldhavenArena creation bytecode is not embedded in this contract's runtime bytecode.
contract GoldhavenArenaDeployer {
    using Clones for address;

    address public immutable implementation;

    event ArenaDeployed(address indexed factory, address indexed arena, address indexed implementation, uint256 dayId);

    error ZeroAddress();

    constructor(address implementation_) {
        if (implementation_ == address(0)) revert ZeroAddress();
        implementation = implementation_;
    }

    function deployArena(
        uint256 dayId,
        address nft,
        address vault,
        address battleEngine,
        address rolloverReceiver,
        address opener,
        uint256[] calldata participants
    ) external returns (address arena) {
        if (nft == address(0) || vault == address(0) || battleEngine == address(0) || rolloverReceiver == address(0)) {
            revert ZeroAddress();
        }

        arena = implementation.clone();
        GoldhavenArena(payable(arena)).initialize(
            dayId,
            IGoldhavenNFT(nft),
            IGoldhavenArenaVault(vault),
            IGoldhavenBattleEngine(battleEngine),
            IGoldhavenArenaRolloverReceiver(rolloverReceiver),
            opener,
            participants
        );

        emit ArenaDeployed(msg.sender, arena, implementation, dayId);
    }
}
