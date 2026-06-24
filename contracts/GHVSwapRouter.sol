// SPDX-License-Identifier: MIT
// https://www.GHV.io/
pragma solidity 0.8.26;

import {IUnlockCallback} from "v4-core-main/src/interfaces/callback/IUnlockCallback.sol";
import {IERC20Minimal} from "v4-core-main/src/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core-main/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core-main/src/libraries/TickMath.sol";
import {PoolKey} from "v4-core-main/src/types/PoolKey.sol";
import {Currency} from "v4-core-main/src/types/Currency.sol";
import {BalanceDelta} from "v4-core-main/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core-main/src/types/PoolOperation.sol";

/// @notice Minimal exact-input router for GHV's SATO-style V4 hook swaps.
contract GHVSwapRouter is IUnlockCallback {
    IPoolManager public immutable POOL_MANAGER;

    error NotPoolManager();
    error ZeroInput();
    error ExactOutputUnsupported();
    error InvalidNativePayment();
    error InsufficientOutput(uint256 actual, uint256 minimum);
    error TransferFailed();

    struct CallbackData {
        address payer;
        address recipient;
        PoolKey key;
        SwapParams params;
    }

    constructor(IPoolManager poolManager) {
        POOL_MANAGER = poolManager;
    }

    function buy(PoolKey calldata key, uint256 minGHVOut) external payable returns (BalanceDelta delta) {
        if (msg.value == 0) revert ZeroInput();

        SwapParams memory params = SwapParams({
            zeroForOne: true, amountSpecified: -int256(msg.value), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        delta = _swap(key, params, msg.sender, msg.sender);
        uint256 GHVOut = uint128(delta.amount1());
        if (GHVOut < minGHVOut) revert InsufficientOutput(GHVOut, minGHVOut);
    }

    function sell(PoolKey calldata key, uint256 GHVIn, uint256 minEthOut) external returns (BalanceDelta delta) {
        if (GHVIn == 0) revert ZeroInput();

        SwapParams memory params = SwapParams({
            zeroForOne: false, amountSpecified: -int256(GHVIn), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        delta = _swap(key, params, msg.sender, msg.sender);
        uint256 ethOut = uint128(delta.amount0());
        if (ethOut < minEthOut) revert InsufficientOutput(ethOut, minEthOut);
    }

    function swap(PoolKey calldata key, SwapParams calldata params, address recipient)
        external
        payable
        returns (BalanceDelta delta)
    {
        if (params.amountSpecified >= 0) revert ExactOutputUnsupported();
        if (params.zeroForOne) {
            if (msg.value != uint256(-params.amountSpecified)) revert InvalidNativePayment();
        } else if (msg.value != 0) {
            revert InvalidNativePayment();
        }

        delta = _swap(key, params, msg.sender, recipient);
    }

    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) revert NotPoolManager();

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        uint256 amountIn = uint256(-data.params.amountSpecified);
        Currency inputCurrency = data.params.zeroForOne ? data.key.currency0 : data.key.currency1;

        // SATO-mode hooks take the exact input in beforeSwap, so the router must fund
        // PoolManager before swap accounting enters the hook.
        _settle(inputCurrency, data.payer, amountIn);

        BalanceDelta delta = POOL_MANAGER.swap(data.key, data.params, abi.encode(data.payer));

        if (delta.amount0() > 0) {
            POOL_MANAGER.take(data.key.currency0, data.recipient, uint256(uint128(delta.amount0())));
        }
        if (delta.amount1() > 0) {
            POOL_MANAGER.take(data.key.currency1, data.recipient, uint256(uint128(delta.amount1())));
        }

        return abi.encode(delta);
    }

    function _swap(PoolKey memory key, SwapParams memory params, address payer, address recipient)
        internal
        returns (BalanceDelta delta)
    {
        delta = abi.decode(POOL_MANAGER.unlock(abi.encode(CallbackData(payer, recipient, key, params))), (BalanceDelta));
    }

    function _settle(Currency currency, address payer, uint256 amount) internal {
        if (Currency.unwrap(currency) == address(0)) {
            POOL_MANAGER.settle{value: amount}();
            return;
        }

        POOL_MANAGER.sync(currency);
        _safeTransferFrom(Currency.unwrap(currency), payer, address(POOL_MANAGER), amount);
        POOL_MANAGER.settle();
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeCall(IERC20Minimal.transferFrom, (from, to, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    receive() external payable {}
}
