// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GoldhavenTypes as T} from "./lib/GoldhavenTypes.sol";
import {GoldhavenBattle} from "./lib/GoldhavenBattle.sol";

/// @notice Goldhaven NFT with fully on-chain generated battle attributes.
/// @dev tokenURI/imageURI is intentionally resolved by classId + beast mapping. Empty string is valid until metadata is configured.
contract GoldhavenNFT is ERC721, ERC721Burnable, Ownable {
    using GoldhavenBattle for uint256;

    error NotHook();
    error NotVault();
    error MissingToken();
    error ZeroAddress();
    error HookAlreadySet();
    error VaultAlreadySet();

    address public hook;
    address public vault;
    bool public hookLocked;
    bool public vaultLocked;
    uint256 public nextTokenId = 1;

    mapping(uint256 => T.Card) internal _cards;
    mapping(T.ClassId => mapping(T.Beast => string)) internal _comboImageURIs;

    event HookSet(address indexed hook);
    event VaultSet(address indexed vault);
    event CardMinted(address indexed to, uint256 indexed tokenId, T.Card card);
    event ComboImageURISet(T.ClassId indexed classId, T.Beast indexed beast, string imageURI);

    modifier onlyHook() {
        if (msg.sender != hook) revert NotHook();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    constructor(address initialOwner) ERC721("Goldhaven NFT", "GHVNFT") Ownable(initialOwner) {}

    function _setComboImageURI(T.ClassId classId, T.Beast beast, string memory newImageURI) internal {
        _comboImageURIs[classId][beast] = newImageURI;
        emit ComboImageURISet(classId, beast, newImageURI);
    }

    /// @notice Locks the Hook address exactly once. Only this Hook can mint NFTs forever.
    /// @dev This lock is independent from the Vault lock. Setting hook must not block setVault().
    function setHook(address newHook) public onlyOwner {
        if (hookLocked) revert HookAlreadySet();
        if (newHook == address(0)) revert ZeroAddress();
        hook = newHook;
        hookLocked = true;
        emit HookSet(newHook);
    }

    /// @notice Locks the Vault address exactly once. Only this Vault can update arena stake metadata.
    /// @dev This lock is independent from the Hook lock. Setting vault must not block setHook().
    function setVault(address newVault) public onlyOwner {
        if (vaultLocked) revert VaultAlreadySet();
        if (newVault == address(0)) revert ZeroAddress();
        vault = newVault;
        vaultLocked = true;
        emit VaultSet(newVault);
    }

    /// @notice Convenience initializer for deployment scripts. Locks both addresses in one tx.
    /// @dev Optional. You can still call setHook() and setVault() separately in either order.
    function setHookAndVault(address newHook, address newVault) external onlyOwner {
        setHook(newHook);
        setVault(newVault);
    }

    /// @notice Set the image/metadata URI for one class + beast combination.
    /// @dev Passing an empty string is allowed and clears the mapping entry.
    function setComboImageURI(T.ClassId classId, T.Beast beast, string calldata newImageURI) external onlyOwner {
        _setComboImageURI(classId, beast, newImageURI);
    }

    /// @notice Batch setter for the later off-chain/on-chain image mapping table.
    function setComboImageURIs(T.ClassId[] calldata classIds, T.Beast[] calldata beasts, string[] calldata imageURIs_) external onlyOwner {
        uint256 len = classIds.length;
        require(len == beasts.length && len == imageURIs_.length, "LEN");
        for (uint256 i; i < len; ++i) {
            _setComboImageURI(classIds[i], beasts[i], imageURIs_[i]);
        }
    }

    function comboImageURI(T.ClassId classId, T.Beast beast) public view returns (string memory) {
        return _comboImageURIs[classId][beast];
    }

    function mintFromHook(address to, uint256 buyUsdWad, uint256 vaultAvgUsdWad, bytes32 seed)
        external
        onlyHook
        returns (uint256 tokenId)
    {
        tokenId = nextTokenId++;
        _mint(to, tokenId);
        T.Card memory card = GoldhavenBattle.makeCard(tokenId, buyUsdWad, vaultAvgUsdWad, seed);
        _cards[tokenId] = card;
        emit CardMinted(to, tokenId, card);
    }

    function cardOf(uint256 tokenId) external view returns (T.Card memory card) {
        if (_ownerOf(tokenId) == address(0)) revert MissingToken();
        return _cards[tokenId];
    }

    /// @notice Returns URI based on the NFT's generated classId + beast. May return empty string until configured.
    function imageURI(uint256 tokenId) public view returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert MissingToken();
        T.Card storage card = _cards[tokenId];
        return _comboImageURIs[card.classId][card.beast];
    }

    /// @dev For now this returns the image URI directly. If you later use metadata JSON, put the metadata URI in the combo mapping.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return imageURI(tokenId);
    }

    function setStakeMeta(uint256 tokenId, uint256 stakeId, uint64 stakeTime) external onlyVault {
        if (_ownerOf(tokenId) == address(0)) revert MissingToken();
        _cards[tokenId].stakeId = stakeId;
        _cards[tokenId].stakeTime = stakeTime;
    }

    function clearStakeMeta(uint256 tokenId) external onlyVault {
        if (_ownerOf(tokenId) == address(0)) revert MissingToken();
        _cards[tokenId].stakeId = 0;
        _cards[tokenId].stakeTime = 0;
    }
}
