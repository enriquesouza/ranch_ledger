// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {BovineNFT} from "../src/BovineNFT.sol";
import {RanchToken} from "../src/RanchToken.sol";

contract BovineNFTTest is Test {
    BovineNFT internal nft;
    address internal admin = address(this);
    address internal minter;

    function setUp() public {
        nft = new BovineNFT(admin, "ipfs://bovine/");
        minter = makeAddr("minter");
        nft.grantRole(nft.MINTER_ROLE(), minter);
    }

    function test_Mint() public {
        address to = makeAddr("alice");
        vm.prank(minter);
        uint256 tokenId = nft.mintForBovine(to, 42);
        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(1), to);
        assertEq(nft.tokenToBovine(1), 42);
        assertEq(nft.bovineToToken(42), 1);
    }

    function test_RevertDoubleMint() public {
        address to = makeAddr("alice");
        vm.startPrank(minter);
        nft.mintForBovine(to, 42);
        vm.expectRevert(abi.encodeWithSignature("AlreadyMinted(uint256)", 42));
        nft.mintForBovine(to, 42);
        vm.stopPrank();
    }

    function test_TokenURI() public view {
        // No mint, but should not revert on supportsInterface
        assertTrue(nft.supportsInterface(0x01ffc9a7)); // ERC165
        assertTrue(nft.supportsInterface(0x80ac58cd)); // ERC721
    }
}

contract RanchTokenTest is Test {
    RanchToken internal tok;
    address internal admin = address(this);
    address internal minter;

    function setUp() public {
        tok = new RanchToken(admin, 6);
        minter = makeAddr("minter");
        tok.grantRole(tok.MINTER_ROLE(), minter);
    }

    function test_Mint() public {
        address to = makeAddr("alice");
        vm.prank(minter);
        tok.mint(to, 1_000e6);
        assertEq(tok.balanceOf(to), 1_000e6);
        assertEq(tok.decimals(), 6);
    }

    function test_Burn() public {
        address to = makeAddr("alice");
        vm.prank(minter);
        tok.mint(to, 500e6);
        vm.prank(to);
        tok.burn(200e6);
        assertEq(tok.balanceOf(to), 300e6);
    }
}
