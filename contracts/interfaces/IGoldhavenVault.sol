// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IGoldhavenVault {
    function averageLockUsdWad24h() external view returns (uint256);
    function depositDividendForLast24h() external payable returns (uint256 epochId);
    function isValidator(address user) external view returns (bool);
    function stakeOwnerOfToken(uint256 tokenId) external view returns (address);
    function getArenaParticipants() external view returns (uint256[] memory);
    function arenaParticipantCount() external view returns (uint256);
    function arenaParticipantAt(uint256 index) external view returns (uint256);
    function markArenaOpened(address arena, uint256[] calldata participants) external;
    function markArenaFinished() external;
    function arenaInProgress() external view returns (bool);
    function isArenaLockWindow() external view returns (bool);
    function isNftActionLocked() external view returns (bool);
    function activeArena() external view returns (address);
    function lockedInActiveArena(uint256 tokenId) external view returns (bool);
    function arenaOfToken(uint256 tokenId) external view returns (address);
    function arenaFinishedAtOfToken(uint256 tokenId) external view returns (uint256);
}
