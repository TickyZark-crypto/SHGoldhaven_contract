// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GoldhavenTypes as T} from "../lib/GoldhavenTypes.sol";

interface IGoldhavenNFT {
    function mintFromHook(address to, uint256 buyUsdWad, uint256 vaultAvgUsdWad, bytes32 seed)
        external
        returns (uint256 tokenId);
    function cardOf(uint256 tokenId) external view returns (T.Card memory);
    function setStakeMeta(uint256 tokenId, uint256 stakeId, uint64 stakeTime) external;
    function clearStakeMeta(uint256 tokenId) external;
    function imageURI(uint256 tokenId) external view returns (string memory);
}
