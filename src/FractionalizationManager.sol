// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {BovineShareToken} from "./BovineShareToken.sol";

/// @title FractionalizationManager
/// @notice Manages NFT fractionalization - holds BovineNFTs and mints ERC20 shares
contract FractionalizationManager is AccessControl, ReentrancyGuardTransient {
    // ------------------------------------------------------------------ //
    //                              Roles                                 //
    // ------------------------------------------------------------------ //

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    // ------------------------------------------------------------------ //
    //                              Errors                                //
    // ------------------------------------------------------------------ //

    error NFTNotOwnedByManager(uint256 tokenId);
    error AlreadyFractionalized(uint256 tokenId);
    error NotFractionalized(uint256 tokenId);
    error InsufficientShares(address investor, uint256 requested, uint256 available);
    error InvalidSalePrice(uint256 price);
    error SaleNotComplete();

    // ------------------------------------------------------------------ //
    //                              Events                                //
    // ------------------------------------------------------------------ //

    event Fractionalized(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 totalShares,
        uint256 initialPrice
    );
    event SharesPurchased(
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 sharesBought,
        uint256 pricePaid
    );
    event SharesRedeemed(
        address indexed investor,
        uint256 indexed tokenId,
        uint256 sharesRedeemed,
        uint256 proceedsReceived
    );
    event SaleComplete(
        uint256 indexed tokenId,
        uint256 salePrice,
        uint256 totalProceeds
    );

    // ------------------------------------------------------------------ //
    //                              Structs                               //
    // ------------------------------------------------------------------ //

    struct Fractionalization {
        address owner;              // Original NFT owner who fractionalized
        uint256 totalShares;        // Total shares minted for this cow
        uint256 initialPrice;       // Initial price per share (in ETH, 18 decimals)
        bool isFractionalized;      // Whether this NFT has been fractionalized
        uint256 salePrice;          // Final sale price when slaughtered/sold
        bool isSold;                // Whether the cow has been sold/slaughtered
    }

    // ------------------------------------------------------------------ //
    //                              Storage                               //
    // ------------------------------------------------------------------ //

    mapping(uint256 => Fractionalization) private _fractionalizations;
    
    /// @notice Mapping: tokenId => shareToken contract address
    mapping(uint256 => address) public tokenToShareContract;
    
    /// @notice Mapping: shareToken => underlying NFT tokenId
    mapping(address => uint256) public shareContractToTokenId;

    // ------------------------------------------------------------------ //
    //                            Constructor                             //
    // ------------------------------------------------------------------ //

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ------------------------------------------------------------------ //
    //                         Fractionalization                          //
    // ------------------------------------------------------------------ //

    /// @notice Fractionalize a bovine NFT by depositing it into the manager
    function fractionalize(
        address nftContract,
        uint256 tokenId,
        uint256 totalShares,
        uint256 initialPricePerShare
    ) external nonReentrant {
        if (totalShares == 0 || initialPricePerShare == 0) revert InvalidSalePrice(0);
        
        // Transfer NFT from sender to this contract
        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        
        // Create share token contract with deterministic name based on tokenId
        string memory shareName = _formatShareName(tokenId);
        string memory shareSymbol = _formatShareSymbol(tokenId);
        BovineShareToken shareToken = new BovineShareToken(
            shareName, 
            shareSymbol, 
            nftContract, 
            tokenId
        );
        
        _fractionalizations[tokenId] = Fractionalization({
            owner: msg.sender,
            totalShares: totalShares,
            initialPrice: initialPricePerShare,
            isFractionalized: true,
            salePrice: 0,
            isSold: false
        });
        
        tokenToShareContract[tokenId] = address(shareToken);
        shareContractToTokenId[address(shareToken)] = tokenId;
        
        // Mint all shares to the original owner (they can then sell/distribute)
        shareToken.mint(msg.sender, totalShares);
        
        emit Fractionalized(tokenId, msg.sender, totalShares, initialPricePerShare);
    }

    /// @notice Buy shares of a fractionalized cow
    function buyShares(
        address nftContract,
        uint256 tokenId,
        uint256 sharesToBuy
    ) external payable nonReentrant {
        Fractionalization storage frac = _fractionalizations[tokenId];
        if (!frac.isFractionalized) revert NotFractionalized(tokenId);
        
        address shareTokenAddr = tokenToShareContract[tokenId];
        BovineShareToken shareToken = BovineShareToken(shareTokenAddr);
        
        uint256 cost = sharesToBuy * frac.initialPrice;
        if (msg.value < cost) revert InsufficientShares(msg.sender, cost, msg.value);
        
        // Transfer NFT from buyer to vault (if not already owned by vault)
        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        
        // Transfer shares from original owner to buyer
        shareToken.transferFrom(frac.owner, msg.sender, sharesToBuy);
        
        // Pay the original owner
        payable(frac.owner).transfer(cost);
        
        emit SharesPurchased(msg.sender, tokenId, sharesToBuy, cost);
    }

    /// @notice Redeem shares after the cow has been sold/slaughtered
    function redeemShares(uint256 tokenId) external nonReentrant {
        Fractionalization storage frac = _fractionalizations[tokenId];
        if (!frac.isFractionalized) revert NotFractionalized(tokenId);
        if (!frac.isSold) revert SaleNotComplete();
        
        address shareTokenAddr = tokenToShareContract[tokenId];
        BovineShareToken shareToken = BovineShareToken(shareTokenAddr);
        
        uint256 sharesOwned = shareToken.balanceOf(msg.sender);
        if (sharesOwned == 0) revert InsufficientShares(msg.sender, 1, 0);
        
        // Calculate proportional proceeds
        uint256 proceedsPerShare = frac.salePrice / frac.totalShares;
        uint256 totalProceeds = sharesOwned * proceedsPerShare;
        
        // Burn shares from investor
        shareToken.burnFrom(msg.sender, sharesOwned);
        
        // Transfer proceeds to investor
        payable(msg.sender).transfer(totalProceeds);
        
        emit SharesRedeemed(msg.sender, tokenId, sharesOwned, totalProceeds);
    }

    /// @notice Mark a cow as sold/slaughtered and set the sale price
    function markAsSold(
        uint256 tokenId,
        uint256 salePrice
    ) external onlyRole(LIQUIDATOR_ROLE) nonReentrant {
        Fractionalization storage frac = _fractionalizations[tokenId];
        if (!frac.isFractionalized) revert NotFractionalized(tokenId);
        if (frac.isSold) revert SaleNotComplete();
        
        frac.salePrice = salePrice;
        frac.isSold = true;
        
        emit SaleComplete(tokenId, salePrice, salePrice * frac.totalShares);
    }

    // ------------------------------------------------------------------ //
    //                              View Functions                        //
    // ------------------------------------------------------------------ //

    function getFractionalization(uint256 tokenId) external view returns (Fractionalization memory) {
        return _fractionalizations[tokenId];
    }

    function isFractionalized(uint256 tokenId) external view returns (bool) {
        return _fractionalizations[tokenId].isFractionalized;
    }

    function getShareTokenAddress(uint256 tokenId) external view returns (address) {
        return tokenToShareContract[tokenId];
    }

    // ------------------------------------------------------------------ //
    //                         Helper Functions                           //
    // ------------------------------------------------------------------ //

    /// @notice Convert uint256 to string (simple implementation)
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }

    /// @notice Format share name as "Bovine Share #<tokenId>"
    function _formatShareName(uint256 tokenId) internal pure returns (string memory) {
        return string.concat("Bovine Share #", _uintToString(tokenId));
    }

    /// @notice Format share symbol as "BOVN-<tokenId>"
    function _formatShareSymbol(uint256 tokenId) internal pure returns (string memory) {
        return string.concat("BOVN-", _uintToString(tokenId));
    }
}
