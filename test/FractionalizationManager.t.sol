// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {FractionalizationManager} from "../src/FractionalizationManager.sol";
import {BovineShareToken} from "../src/BovineShareToken.sol";
import {BovineNFT} from "../src/BovineNFT.sol";

contract FractionalizationManagerTest is Test {
    FractionalizationManager internal manager;
    BovineNFT internal nft;
    address internal admin = address(this);
    address internal owner;
    address internal investor;
    address internal liquidator;

    function setUp() public {
        manager = new FractionalizationManager();
        nft = new BovineNFT(admin, "ipfs://bovine/");
        owner = makeAddr("owner");
        investor = makeAddr("investor");
        liquidator = makeAddr("liquidator");

        manager.grantRole(manager.LIQUIDATOR_ROLE(), liquidator);
        nft.grantRole(nft.MINTER_ROLE(), admin);
    }

    function test_Fractionalize() public {
        vm.prank(admin);
        nft.mintForBovine(owner, 1);

        vm.startPrank(owner);
        nft.approve(address(manager), 1);
        manager.fractionalize(address(nft), 1, 1000, 0.01 ether);
        vm.stopPrank();

        assertTrue(manager.isFractionalized(1));
        address shareAddr = manager.getShareTokenAddress(1);
        assertTrue(shareAddr != address(0));

        BovineShareToken shareToken = BovineShareToken(shareAddr);
        assertEq(shareToken.balanceOf(owner), 1000);
    }

    function test_RevertFractionalizeZeroShares() public {
        vm.prank(admin);
        nft.mintForBovine(owner, 1);
        vm.startPrank(owner);
        nft.approve(address(manager), 1);
        vm.expectRevert();
        manager.fractionalize(address(nft), 1, 0, 0.01 ether);
        vm.stopPrank();
    }

    function test_MarkAsSold() public {
        _setupFractionalized();

        vm.prank(liquidator);
        manager.markAsSold(1, 5 ether);

        FractionalizationManager.Fractionalization memory frac = manager.getFractionalization(1);
        assertEq(frac.salePrice, 5 ether);
        assertTrue(frac.isSold);
    }

    function test_RevertMarkAsSoldNotLiquidator() public {
        _setupFractionalized();
        vm.prank(owner);
        vm.expectRevert();
        manager.markAsSold(1, 5 ether);
    }

    function test_RedeemShares() public {
        _setupFractionalized();

        // Fund the manager contract with ETH for payouts
        vm.deal(address(manager), 10 ether);

        // Mark as sold
        vm.prank(liquidator);
        manager.markAsSold(1, 10 ether);

        // Transfer shares from owner to investor
        address shareAddr = manager.getShareTokenAddress(1);
        BovineShareToken shareToken = BovineShareToken(shareAddr);

        // Owner approves investor to transfer shares
        vm.prank(owner);
        shareToken.approve(investor, 500);

        // Investor transfers shares from owner to self
        vm.prank(investor);
        shareToken.transferFrom(owner, investor, 500);

        // Verify investor has shares
        assertEq(shareToken.balanceOf(investor), 500);

        // Investor must approve the FractionalizationManager to burn their shares
        vm.prank(investor);
        shareToken.approve(address(manager), 500);

        // Investor redeems
        uint256 balanceBefore = investor.balance;
        vm.prank(investor);
        manager.redeemShares(1);

        // Check investor received ETH (500 shares * (10 ether / 1000) = 5 ether)
        assertGt(investor.balance, balanceBefore);
    }

    function test_RevertRedeemBeforeSale() public {
        _setupFractionalized();
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(FractionalizationManager.SaleNotComplete.selector));
        manager.redeemShares(1);
    }

    function test_GetFractionalization() public {
        _setupFractionalized();
        FractionalizationManager.Fractionalization memory frac = manager.getFractionalization(1);
        assertEq(frac.totalShares, 1000);
        assertEq(frac.initialPrice, 0.01 ether);
        assertTrue(frac.isFractionalized);
        assertFalse(frac.isSold);
    }

    function test_IsFractionalized_False() public view {
        assertFalse(manager.isFractionalized(999));
    }

    function _setupFractionalized() internal {
        vm.prank(admin);
        nft.mintForBovine(owner, 1);
        vm.startPrank(owner);
        nft.approve(address(manager), 1);
        manager.fractionalize(address(nft), 1, 1000, 0.01 ether);
        vm.stopPrank();
    }
}