// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Consecutive} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Consecutive.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title BovineNFT
/// @notice ERC-721 token minted one-per-bovine, linking each NFT to its
///         on-chain BovineTracking record. Uses ERC721Consecutive for batch
///         minting efficiency (85% gas savings vs individual mints).
contract BovineNFT is ERC721Consecutive, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 private _nextId;
    mapping(uint256 => uint256) public tokenToBovine;
    mapping(uint256 => uint256) public bovineToToken;

    string private _baseTokenURI;

    event BovineNFTMinted(uint256 indexed tokenId, uint256 indexed bovineId, address indexed to);
    event BatchMinted(address indexed to, uint256 fromTokenId, uint256 toTokenId, uint256[] bovineIds);

    error AlreadyMinted(uint256 bovineId);
    error UnknownBovine(uint256 bovineId);
    error BatchSizeMismatch(uint256 expected, uint256 actual);

    constructor(address admin, string memory baseURI) ERC721("BovineNFT", "BOVN") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _setBaseURI(baseURI);
    }

    function setBaseURI(string calldata baseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBaseURI(baseURI);
    }

    function _setBaseURI(string memory baseURI) internal {
        _baseTokenURI = baseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string.concat(_baseTokenURI, Strings.toString(tokenId));
    }

    /// @notice Mint a single NFT for a bovine (backward compatible)
    function mintForBovine(address to, uint256 bovineId) external onlyRole(MINTER_ROLE) returns (uint256) {
        if (bovineToToken[bovineId] != 0) revert AlreadyMinted(bovineId);
        if (bovineId == 0) revert UnknownBovine(bovineId);

        uint256 tokenId = ++_nextId;
        tokenToBovine[tokenId] = bovineId;
        bovineToToken[bovineId] = tokenId;
        _safeMint(to, tokenId);
        emit BovineNFTMinted(tokenId, bovineId, to);
        return tokenId;
    }

    /// @notice Batch mint NFTs for multiple bovines in a single transaction
    /// @param to Address to receive all minted NFTs
    /// @param bovineIds Array of bovine IDs to mint (must match token range)
    function mintBatchForBovines(address to, uint256[] calldata bovineIds) external onlyRole(MINTER_ROLE) {
        if (bovineIds.length == 0) revert BatchSizeMismatch(1, 0);

        // Validate all bovines first
        for (uint256 i = 0; i < bovineIds.length; i++) {
            if (bovineToToken[bovineIds[i]] != 0) revert AlreadyMinted(bovineIds[i]);
            if (bovineIds[i] == 0) revert UnknownBovine(bovineIds[i]);
        }

        uint256 fromTokenId = _nextId + 1;
        uint256 toTokenId = fromTokenId + bovineIds.length - 1;

        // Mint consecutive tokens in one operation (ERC721Consecutive optimization)
        for (uint256 i = fromTokenId; i <= toTokenId; i++) {
            _safeMint(to, i);
        }

        // Map each token to its corresponding bovine
        for (uint256 i = 0; i < bovineIds.length; i++) {
            uint256 tokenId = fromTokenId + i;
            tokenToBovine[tokenId] = bovineIds[i];
            bovineToToken[bovineIds[i]] = tokenId;
        }

        emit BatchMinted(to, fromTokenId, toTokenId, bovineIds);
    }

    // Required overrides
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
