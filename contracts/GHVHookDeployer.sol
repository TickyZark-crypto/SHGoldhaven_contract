// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core-main/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core-main/src/libraries/Hooks.sol";

import {GHVHook} from "./GHVHook.sol";
import {GHVToken} from "./GHVToken.sol";
import {IGoldhavenNFT} from "./interfaces/IGoldhavenNFT.sol";
import {IGoldhavenVault} from "./interfaces/IGoldhavenVault.sol";
import {IGoldhavenPriceOracle} from "./interfaces/IGoldhavenPriceOracle.sol";

/// @notice CREATE2 helper for deploying GHVHook at a Uniswap V4-compatible hook address.
/// @dev initCodeHash and deploy arguments MUST match GHVHook.constructor exactly.
///      The arena controller is locked in GHVHook at deployment; there is no later setArenaController step.
contract GHVHookDeployer {
    uint160 public constant GHV_HOOK_FLAGS = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

    error HookAddressMismatch(address predicted, address actual);
    error SaltNotFound();

    function initCodeHash(
        IPoolManager poolManager,
        GHVToken ghvToken,
        IGoldhavenNFT ghvNFT,
        IGoldhavenVault ghvVault,
        IGoldhavenPriceOracle priceOracle,
        uint256 nftThresholdUsdWad,
        address arenaController_
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                type(GHVHook).creationCode,
                abi.encode(
                    poolManager,
                    ghvToken,
                    ghvNFT,
                    ghvVault,
                    priceOracle,
                    nftThresholdUsdWad,
                    arenaController_
                )
            )
        );
    }

    function computeAddress(bytes32 salt, bytes32 initHash) public view returns (address) {
        bytes32 digest = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initHash));
        return address(uint160(uint256(digest)));
    }

    function isValidHookAddress(address hook) public pure returns (bool) {
        return (uint160(hook) & Hooks.ALL_HOOK_MASK) == GHV_HOOK_FLAGS;
    }

    function mineSalt(bytes32 seed, bytes32 initHash) public view returns (bytes32 salt, address hook) {
        for (uint256 i = 0; i < 1_000_000; ++i) {
            salt = keccak256(abi.encodePacked(seed, i));
            hook = computeAddress(salt, initHash);
            if (isValidHookAddress(hook)) return (salt, hook);
        }
        revert SaltNotFound();
    }

    function deploy(
        bytes32 salt,
        IPoolManager poolManager,
        GHVToken ghvToken,
        IGoldhavenNFT ghvNFT,
        IGoldhavenVault ghvVault,
        IGoldhavenPriceOracle priceOracle,
        uint256 nftThresholdUsdWad,
        address arenaController_
    ) external returns (GHVHook hook) {
        bytes32 initHash = initCodeHash(
            poolManager,
            ghvToken,
            ghvNFT,
            ghvVault,
            priceOracle,
            nftThresholdUsdWad,
            arenaController_
        );
        address predicted = computeAddress(salt, initHash);
        hook = new GHVHook{salt: salt}(
            poolManager,
            ghvToken,
            ghvNFT,
            ghvVault,
            priceOracle,
            nftThresholdUsdWad,
            arenaController_
        );
        if (address(hook) != predicted) revert HookAddressMismatch(predicted, address(hook));
    }
}
