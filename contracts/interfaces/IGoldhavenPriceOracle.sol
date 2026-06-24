// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Project-level oracle adapter. Implement this with Chainlink, TWAP, or your own guarded oracle.
interface IGoldhavenPriceOracle {
    function ethToUsdWad(uint256 ethWei) external view returns (uint256 usdWad);
    function ghvToUsdWad(uint256 ghvAmount) external view returns (uint256 usdWad);
}
