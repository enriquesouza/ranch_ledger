// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {RanchLendingVault} from "../src/RanchLendingVault.sol";
import {BovineNFT} from "../src/BovineNFT.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract RanchLendingVaultTest is Test {
    RanchLendingVault internal vault;
    BovineNFT internal nft;
    address internal admin = address(this);
    address internal borrower;
    address internal liquidator;

    function setUp() public {
        nft = new BovineNFT(admin, "ipfs://bovine/");
        borrower = makeAddr("borrower");
        liquidator = makeAddr("liquidator");

        RanchLendingVault.VaultConfig memory config = RanchLendingVault.VaultConfig({
            maxLTV: 7000,
            liquidationThreshold: 8000,
            healthScoreFloor: 50,
            baseBorrowRate: 500,
            utilizationSlope1: 2000,
            utilizationSlope2: 8000,
            optimalUtilization: 8000
        });

        vault = new RanchLendingVault(admin, IERC721(address(nft)), config);
        vault.grantRole(vault.LIQUIDATOR_ROLE(), liquidator);
        nft.grantRole(nft.MINTER_ROLE(), admin);
    }

    // ---------------------------------------------------------------- //
    //                       Helper utilities                          //
    // ---------------------------------------------------------------- //

    /// @dev Mint tokenId to borrower, approve vault, and deposit as borrower.
    function _mintApproveAndDeposit(uint256 bovineId) internal returns (uint256 tokenId) {
        tokenId = nft.mintForBovine(borrower, bovineId);
        vm.startPrank(borrower);
        nft.approve(address(vault), tokenId);
        vault.depositCollateral(tokenId);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- //
    //                         Collateral tests                        //
    // ---------------------------------------------------------------- //

    function test_DepositCollateral() public {
        uint256 tokenId = nft.mintForBovine(borrower, 1);

        // tokenId 1 → healthScore 70, notionalValue = 1000e6 * (50+70)/100 = 1200e6
        uint256 expectedHealth = 70;
        uint256 expectedNotional = 1200e6;

        vm.startPrank(borrower);
        nft.approve(address(vault), tokenId);

        vm.expectEmit(true, true, false, false);
        emit RanchLendingVault.CollateralDeposited(borrower, tokenId, expectedNotional, expectedHealth);

        vault.depositCollateral(tokenId);
        vm.stopPrank();

        // NFT should now be held by the vault
        assertEq(nft.ownerOf(tokenId), address(vault));

        // totalCollateralValue should reflect the deposit
        assertEq(vault.totalCollateralValue(), expectedNotional);

        // Collateral record should be marked collateralized
        RanchLendingVault.Collateral memory c = vault.getCollateral(tokenId);
        assertTrue(c.isCollateralized);
        assertEq(c.owner, borrower);
        assertEq(c.healthScore, expectedHealth);
        assertEq(c.notionalValue, expectedNotional);
    }

    function test_RevertDepositInvalidToken() public {
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(RanchLendingVault.InvalidTokenId.selector, 0));
        vault.depositCollateral(0);
    }

    function test_RevertDoubleDeposit() public {
        uint256 tokenId = _mintApproveAndDeposit(1);

        // Second deposit of the same tokenId should revert NotCollateralized
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(RanchLendingVault.NotCollateralized.selector, tokenId));
        vault.depositCollateral(tokenId);
    }

    function test_WithdrawCollateral() public {
        uint256 tokenId = _mintApproveAndDeposit(1);

        // Before withdrawal the vault holds the NFT
        assertEq(nft.ownerOf(tokenId), address(vault));

        vm.startPrank(borrower);
        // CollateralWithdrawn(borrower, tokenId, borrowedAmount=0) since no loan
        vm.expectEmit(true, true, false, false);
        emit RanchLendingVault.CollateralWithdrawn(borrower, tokenId, 0);

        vault.withdrawCollateral(tokenId);
        vm.stopPrank();

        // NFT returned to borrower
        assertEq(nft.ownerOf(tokenId), borrower);

        // totalCollateralValue reduced
        assertEq(vault.totalCollateralValue(), 0);

        // Collateral record no longer collateralized
        RanchLendingVault.Collateral memory c = vault.getCollateral(tokenId);
        assertFalse(c.isCollateralized);
    }

    function test_RevertWithdrawWithActiveLoan() public {
        uint256 tokenId = _mintApproveAndDeposit(1);

        // Borrow against the collateral (max borrow = 1200e6 * 7000/10000 = 840e6)
        vm.prank(borrower);
        vault.borrow(tokenId, 840e6);

        // Attempting to withdraw with an active loan should revert
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(RanchLendingVault.InsufficientCollateral.selector));
        vault.withdrawCollateral(tokenId);
    }

    // ---------------------------------------------------------------- //
    //                            Borrow tests                         //
    // ---------------------------------------------------------------- //

    function test_Borrow() public {
        uint256 tokenId = _mintApproveAndDeposit(1);

        uint256 borrowAmount = 500e6; // well within maxLTV (840e6)

        vm.prank(borrower);
        vault.borrow(tokenId, borrowAmount);

        // totalBorrows should increase
        assertEq(vault.totalBorrows(), borrowAmount);

        // Loan should be active
        RanchLendingVault.Loan memory loan = vault.getLoan(borrower, tokenId);
        assertTrue(loan.isActive);
        assertEq(loan.principal, borrowAmount);
    }

    function test_RevertBorrowExceedsLTV() public {
        uint256 tokenId = _mintApproveAndDeposit(1);

        // maxBorrow = 1200e6 * 7000 / 10000 = 840e6
        // Attempting to borrow 841e6 should revert
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(RanchLendingVault.InsufficientCollateral.selector));
        vault.borrow(tokenId, 841e6);
    }

    // ---------------------------------------------------------------- //
    //                            Repay tests                          //
    // ---------------------------------------------------------------- //

    function test_RepayLoan() public {
        uint256 tokenId = _mintApproveAndDeposit(1);

        vm.prank(borrower);
        vault.borrow(tokenId, 500e6);

        // Repay the loan
        vm.prank(borrower);
        vault.repayLoan(tokenId);

        // Loan should be inactive
        RanchLendingVault.Loan memory loan = vault.getLoan(borrower, tokenId);
        assertFalse(loan.isActive);
        assertEq(loan.principal, 0);

        // totalBorrows should be reduced (interest may leave a small residual
        // but with no time advance the principal portion is fully repaid)
        assertEq(vault.totalBorrows(), 0);
    }

    // ---------------------------------------------------------------- //
    //                         Liquidation tests                       //
    // ---------------------------------------------------------------- //

    function test_Liquidate() public {
        uint256 tokenId = _mintApproveAndDeposit(1);

        // Borrow the maximum allowed (840e6)
        vm.prank(borrower);
        vault.borrow(tokenId, 840e6);

        // Advance time ~2 years so interest accrues past the liquidation
        // threshold (960e6 = 1200e6 * 8000/10000).
        vm.warp(block.timestamp + 2 * 365 days);

        // Liquidator calls liquidate
        vm.prank(liquidator);
        vm.expectEmit(true, true, true, false);
        emit RanchLendingVault.Liquidated(borrower, liquidator, tokenId, 0, 0);
        vault.liquidate(borrower, tokenId);

        // NFT should be transferred to the liquidator
        assertEq(nft.ownerOf(tokenId), liquidator);

        // Collateral no longer active
        RanchLendingVault.Collateral memory c = vault.getCollateral(tokenId);
        assertFalse(c.isCollateralized);

        // Loan should be closed
        RanchLendingVault.Loan memory loan = vault.getLoan(borrower, tokenId);
        assertFalse(loan.isActive);

        // totalBorrows and totalCollateralValue should be zeroed
        assertEq(vault.totalBorrows(), 0);
        assertEq(vault.totalCollateralValue(), 0);
    }

    // ---------------------------------------------------------------- //
    //                       Administration tests                       //
    // ---------------------------------------------------------------- //

    function test_UpdateConfig() public {
        RanchLendingVault.VaultConfig memory newConfig = RanchLendingVault.VaultConfig({
            maxLTV: 7500,
            liquidationThreshold: 7000,
            healthScoreFloor: 60,
            baseBorrowRate: 400,
            utilizationSlope1: 1500,
            utilizationSlope2: 7000,
            optimalUtilization: 7500
        });

        vault.updateConfig(newConfig);

        // config is a public state variable; the auto-generated getter returns
        // the struct fields as a tuple.
        (
            uint256 maxLTV,
            uint256 liquidationThreshold,
            uint256 healthScoreFloor,
            uint256 baseBorrowRate,
            uint256 utilizationSlope1,
            uint256 utilizationSlope2,
            uint256 optimalUtilization
        ) = vault.config();
        assertEq(maxLTV, 7500);
        assertEq(liquidationThreshold, 7000);
        assertEq(healthScoreFloor, 60);
        assertEq(baseBorrowRate, 400);
        assertEq(utilizationSlope1, 1500);
        assertEq(utilizationSlope2, 7000);
        assertEq(optimalUtilization, 7500);
    }

    function test_RevertUpdateConfigNonAdmin() public {
        address nonAdmin = makeAddr("nonAdmin");

        RanchLendingVault.VaultConfig memory newConfig = RanchLendingVault.VaultConfig({
            maxLTV: 7500,
            liquidationThreshold: 7000,
            healthScoreFloor: 60,
            baseBorrowRate: 400,
            utilizationSlope1: 1500,
            utilizationSlope2: 7000,
            optimalUtilization: 7500
        });

        // Cache the role before prank so vm.prank applies to updateConfig only.
        bytes32 adminRole = vault.DEFAULT_ADMIN_ROLE();

        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                nonAdmin,
                adminRole
            )
        );
        vault.updateConfig(newConfig);
    }

    // ---------------------------------------------------------------- //
    //                    Interest rate / pricer tests                  //
    // ---------------------------------------------------------------- //

    function test_CalculateBorrowRate() public {
        // With no utilization the borrow rate should equal the base rate
        assertEq(vault.calculateBorrowRate(), 500);
    }

    function test_SetPricer() public {
        address pricer = makeAddr("pricer");

        assertFalse(vault.hasRole(vault.PRICER_ROLE(), pricer));

        vault.setPricer(pricer);

        assertTrue(vault.hasRole(vault.PRICER_ROLE(), pricer));
    }
}