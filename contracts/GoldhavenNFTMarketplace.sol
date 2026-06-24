// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Simple GHV-denominated marketplace for unstaked Goldhaven NFTs.
contract GoldhavenNFTMarketplace is ReentrancyGuard {
    IERC20 public immutable ghv;
    IERC721 public immutable nft;

    struct Listing {
        address seller;
        uint256 price;
    }

    mapping(uint256 => Listing) public listings;

    event Listed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event Cancelled(address indexed seller, uint256 indexed tokenId);
    event Bought(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 price);

    error NotOwner();
    error BadPrice();
    error NotListed();
    error NotSeller();
    error TransferFailed();

    constructor(IERC20 ghv_, IERC721 nft_) {
        ghv = ghv_;
        nft = nft_;
    }

    function list(uint256 tokenId, uint256 price) external {
        if (price == 0) revert BadPrice();
        if (nft.ownerOf(tokenId) != msg.sender) revert NotOwner();
        listings[tokenId] = Listing(msg.sender, price);
        emit Listed(msg.sender, tokenId, price);
    }

    function cancel(uint256 tokenId) external {
        Listing memory l = listings[tokenId];
        if (l.seller == address(0)) revert NotListed();
        if (l.seller != msg.sender) revert NotSeller();
        delete listings[tokenId];
        emit Cancelled(msg.sender, tokenId);
    }

    function buy(uint256 tokenId) external nonReentrant {
        Listing memory l = listings[tokenId];
        if (l.seller == address(0)) revert NotListed();
        delete listings[tokenId];
        bool ok = ghv.transferFrom(msg.sender, l.seller, l.price);
        if (!ok) revert TransferFailed();
        nft.safeTransferFrom(l.seller, msg.sender, tokenId);
        emit Bought(msg.sender, l.seller, tokenId, l.price);
    }
}
