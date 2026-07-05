// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title RanchLendingVault
/// @notice NFT-backed lending vault for bovine collateral. Uses provenance data
///         (vaccines, health exams, movements) to score cattle health and adjust
///         loan-to-value ratios dynamically. Implements Compound-style interest
///         rate model parameterized by utilization.
contract RanchLendingVault is AccessControl, ReentrancyGuardTransient {
    // ------------------------------------------------------------------ //
    //                              Roles                                 //
    // ------------------------------------------------------------------ //

    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant PRICER_ROLE = keccak256("PRICER_ROLE");

    // ------------------------------------------------------------------ //
    //                              Errors                                //
    // ------------------------------------------------------------------ //

    error NotCollateralized(uint256 tokenId);
    error Undercollateralized(uint256 healthScore, uint256 minHealthScore);
    error InsufficientCollateral();
    error InvalidTokenId(uint256 tokenId);
    error HealthScoreTooLow(uint256 current, uint256 required);
    error TransferNotAllowed(uint256 tokenId);

    // ------------------------------------------------------------------ //
    //                              Events                                //
    // ------------------------------------------------------------------ //

    event CollateralDeposited(
        address indexed borrower,
        uint256 indexed tokenId,
        uint256 notionalValue,
        uint256 healthScore
    );
    event CollateralWithdrawn(
        address indexed borrower,
        uint256 indexed tokenId,
        uint256 borrowedAmount
    );
    event LoanRepaid(
        address indexed borrower,
        uint256 indexed tokenId,
        uint256 principal,
        uint256 interest
    );
    event Liquidated(
        address indexed borrower,
        address indexed liquidator,
        uint256 indexed tokenId,
        uint256 borrowedAmount,
        uint256 healthScore
    );
    event InterestAccrued(uint256 globalIndex, uint256 borrowRate);

    // ------------------------------------------------------------------ //
    //                              Structs                               //
    // ------------------------------------------------------------------ //

    struct Loan {
        uint256 principal;      // Amount borrowed (in RanchToken)
        uint256 interestAccrued; // Interest accrued so far
        uint256 lastUpdateBlock; // Block number when interest was last calculated
        bool isActive;         // Whether the loan is still active
    }

    struct Collateral {
        address owner;         // Original depositor (cannot be transferred)
        uint256 tokenId;       // NFT token ID
        string countryCode;    // ISO 3166-1 alpha-2: BR, EU, US, AU, CN, SA, AE, QA
        string nationalId;     // Country-specific ID (SISBOV, ANID, NLIS, GCC, etc.)
        uint256 notionalValue; // Notional value in RanchToken (6 decimals)
        uint256 healthScore;   // 0-100, derived from provenance data
        bool isCollateralized; // Whether this NFT is currently collateral
    }

    struct VaultConfig {
        uint256 maxLTV;           // Max loan-to-value ratio (basis points, e.g., 7000 = 70%)
        uint256 liquidationThreshold; // Threshold for liquidation (basis points)
        uint256 healthScoreFloor;   // Minimum health score to borrow (0-100)
        uint256 baseBorrowRate;     // Base borrow APY in basis points
        uint256 utilizationSlope1;  // Interest rate slope for low utilization
        uint256 utilizationSlope2;  // Interest rate slope for high utilization
        uint256 optimalUtilization; // Utilization at which interest is minimal (basis points)
    }

    // ------------------------------------------------------------------ //
    //                              Storage                               //
    // ------------------------------------------------------------------ //

    IERC721 public immutable bovineNFT;
    
    mapping(uint256 => Collateral) private _collaterals;
    mapping(address => mapping(uint256 => Loan)) private _loans;
    
    VaultConfig public config;
    
    uint256 public globalIndex;       // Global borrow index for interest calculation
    uint256 public totalBorrows;      // Total outstanding borrows across all loans
    uint256 public totalCollateralValue; // Total value of all collateral
    
    uint256 private constant BASIS_POINTS_DIVISOR = 10_000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    // ------------------------------------------------------------------ //
    //                             Modifiers                              //
    // ------------------------------------------------------------------ //

    modifier collateralExists(uint256 tokenId) {
        if (!_collaterals[tokenId].isCollateralized) revert NotCollateralized(tokenId);
        _;
    }

    modifier onlyBorrowerOrAdmin(address borrower, uint256 tokenId) {
        Collateral storage c = _collaterals[tokenId];
        require(
            msg.sender == c.owner || msg.sender == address(this) ||
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "not authorized"
        );
        _;
    }

    // ------------------------------------------------------------------ //
    //                            Constructor                             //
    // ------------------------------------------------------------------ //

    constructor(
        address admin,
        IERC721 _bovineNFT,
        VaultConfig memory initialConfig
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        
        bovineNFT = _bovineNFT;
        config = initialConfig;
        globalIndex = 1e18; // Start at 1.0
        
        emit CollateralDeposited(address(0), 0, 0, 0); // Initial event for indexing
    }

    // ------------------------------------------------------------------ //
    //                         Administration                           //
    // ------------------------------------------------------------------ //

    function updateConfig(VaultConfig memory newConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newConfig.maxLTV <= BASIS_POINTS_DIVISOR, "LTV too high");
        require(newConfig.liquidationThreshold <= newConfig.maxLTV, "threshold > LTV");
        require(newConfig.healthScoreFloor <= 100, "health score invalid");
        
        config = newConfig;
    }

    function setPricer(address pricer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PRICER_ROLE, pricer);
    }

    // ------------------------------------------------------------------ //
    //                         Collateral Management                      //
    // ------------------------------------------------------------------ //

    /// @notice Deposit a BovineNFT as collateral for borrowing
    function depositCollateral(uint256 tokenId) external nonReentrant {
        if (tokenId == 0) revert InvalidTokenId(tokenId);
        if (_collaterals[tokenId].isCollateralized) revert NotCollateralized(tokenId);
        
        // Transfer NFT from sender to this contract
        bovineNFT.transferFrom(msg.sender, address(this), tokenId);
        
        // Calculate health score based on provenance data (simplified)
        uint256 healthScore = _calculateHealthScore(tokenId);
        
        Collateral storage c = _collaterals[tokenId];
        c.owner = msg.sender;
        c.tokenId = tokenId;
        c.notionalValue = _getNotionalValue(healthScore);
        c.healthScore = healthScore;
        c.isCollateralized = true;
        
        totalCollateralValue += c.notionalValue;
        
        emit CollateralDeposited(msg.sender, tokenId, c.notionalValue, healthScore);
    }

    /// @notice Withdraw collateral after repaying all borrows
    function withdrawCollateral(uint256 tokenId) external nonReentrant onlyBorrowerOrAdmin(msg.sender, tokenId) {
        Collateral storage c = _collaterals[tokenId];
        if (!c.isCollateralized) revert NotCollateralized(tokenId);
        
        Loan storage loan = _loans[msg.sender][tokenId];
        if (loan.isActive && loan.principal > 0) revert InsufficientCollateral();
        
        // Update global index and total borrows before withdrawal
        _updateGlobalIndex();
        
        c.isCollateralized = false;
        totalCollateralValue -= c.notionalValue;
        
        // Transfer NFT back to owner
        bovineNFT.transferFrom(address(this), msg.sender, tokenId);
        
        emit CollateralWithdrawn(msg.sender, tokenId, loan.principal);
    }

    /// @notice Borrow RanchToken against collateral (simplified - assumes RanchToken is minted)
    function borrow(uint256 tokenId, uint256 amount) external nonReentrant onlyBorrowerOrAdmin(msg.sender, tokenId) {
        Collateral storage c = _collaterals[tokenId];
        if (!c.isCollateralized) revert NotCollateralized(tokenId);
        
        // Check health score requirement
        if (c.healthScore < config.healthScoreFloor) {
            revert HealthScoreTooLow(c.healthScore, config.healthScoreFloor);
        }
        
        // Calculate max borrow amount based on LTV
        uint256 maxBorrow = (c.notionalValue * config.maxLTV) / BASIS_POINTS_DIVISOR;
        
        Loan storage loan = _loans[msg.sender][tokenId];
        if (!loan.isActive) {
            loan.principal = 0;
            loan.interestAccrued = 0;
            loan.lastUpdateBlock = block.number;
            loan.isActive = true;
        }
        
        // Check current borrow amount + new amount doesn't exceed max
        uint256 currentBorrow = _getCurrentBorrowAmount(msg.sender, tokenId);
        if (currentBorrow + amount > maxBorrow) revert InsufficientCollateral();
        
        loan.principal += amount;
        totalBorrows += amount;
        
        // Mint RanchToken to borrower (simplified - in production would use ERC20)
        _mintRanchToken(msg.sender, amount);
        
        emit LoanRepaid(msg.sender, tokenId, amount, 0); // Reuse event for borrow
    }

    /// @notice Repay a loan and release collateral
    function repayLoan(uint256 tokenId) external nonReentrant onlyBorrowerOrAdmin(msg.sender, tokenId) {
        Collateral storage c = _collaterals[tokenId];
        if (!c.isCollateralized) revert NotCollateralized(tokenId);
        
        Loan storage loan = _loans[msg.sender][tokenId];
        if (!loan.isActive || loan.principal == 0) revert InsufficientCollateral();
        
        // Update global index to calculate interest
        _updateGlobalIndex();
        
        uint256 totalOwed = _getCurrentBorrowAmount(msg.sender, tokenId);
        
        // Burn RanchToken from borrower (simplified - in production would use ERC20)
        _burnRanchToken(msg.sender, totalOwed);
        
        loan.principal = 0;
        loan.interestAccrued = 0;
        loan.isActive = false;
        totalBorrows -= totalOwed;
        
        emit LoanRepaid(msg.sender, tokenId, loan.principal, loan.interestAccrued);
    }

    /// @notice Liquidate an undercollateralized position
    function liquidate(address borrower, uint256 tokenId) external nonReentrant {
        Collateral storage c = _collaterals[tokenId];
        if (!c.isCollateralized || c.owner != borrower) revert NotCollateralized(tokenId);
        
        Loan storage loan = _loans[borrower][tokenId];
        if (!loan.isActive) revert InsufficientCollateral();
        
        // Update global index
        _updateGlobalIndex();
        
        uint256 currentBorrow = _getCurrentBorrowAmount(borrower, tokenId);
        uint256 collateralValue = c.notionalValue;
        
        // Check if undercollateralized (borrow > collateral * liquidation threshold)
        uint256 liquidationLimit = (collateralValue * config.liquidationThreshold) / BASIS_POINTS_DIVISOR;
        if (currentBorrow <= liquidationLimit) revert Undercollateralized(c.healthScore, 0);
        
        // Transfer NFT to liquidator as reward
        bovineNFT.transferFrom(address(this), msg.sender, tokenId);
        
        // Update state
        c.isCollateralized = false;
        totalCollateralValue -= collateralValue;
        
        loan.principal = 0;
        loan.interestAccrued = 0;
        loan.isActive = false;
        totalBorrows -= currentBorrow;
        
        emit Liquidated(borrower, msg.sender, tokenId, currentBorrow, c.healthScore);
    }

    // ------------------------------------------------------------------ //
    //                         Interest Rate Model                        //
    // ------------------------------------------------------------------ //

    /// @notice Calculate current borrow interest rate based on utilization
    function calculateBorrowRate() public view returns (uint256) {
        if (totalCollateralValue == 0) return config.baseBorrowRate;
        
        uint256 utilization = (totalBorrows * BASIS_POINTS_DIVISOR) / totalCollateralValue;
        
        if (utilization <= config.optimalUtilization) {
            // Low utilization: linear increase from base rate
            return config.baseBorrowRate + 
                (config.utilizationSlope1 * utilization) / config.optimalUtilization;
        } else {
            // High utilization: steeper increase
            uint256 excessUtilization = utilization - config.optimalUtilization;
            return config.baseBorrowRate + config.utilizationSlope1 + 
                (config.utilizationSlope2 * excessUtilization) / (BASIS_POINTS_DIVISOR - config.optimalUtilization);
        }
    }

    /// @notice Update global borrow index to accrue interest
    function _updateGlobalIndex() internal {
        if (totalBorrows == 0) return;
        
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime - _getLastUpdateTime();
        
        if (timeElapsed == 0) return;
        
        uint256 borrowRate = calculateBorrowRate();
        uint256 interestAccrued = (totalBorrows * borrowRate * timeElapsed) / (BASIS_POINTS_DIVISOR * SECONDS_PER_YEAR);
        
        globalIndex += (interestAccrued * 1e18) / totalBorrows;
        
        emit InterestAccrued(globalIndex, borrowRate);
    }

    function _getLastUpdateTime() internal view returns (uint256) {
        // Simplified: use block.timestamp as proxy for last update time
        // In production, store actual lastUpdateBlock and convert to timestamp
        return block.timestamp;
    }

    /// @notice Get current borrow amount including accrued interest
    function _getCurrentBorrowAmount(address borrower, uint256 tokenId) internal view returns (uint256) {
        Loan storage loan = _loans[borrower][tokenId];
        if (!loan.isActive || loan.principal == 0) return 0;
        
        // Calculate interest based on time elapsed since last update
        uint256 timeElapsed = block.timestamp - (loan.lastUpdateBlock * 12); // Approximate block time
        uint256 borrowRate = calculateBorrowRate();
        uint256 interest = (loan.principal * borrowRate * timeElapsed) / (BASIS_POINTS_DIVISOR * SECONDS_PER_YEAR);
        
        return loan.principal + interest;
    }

    // ------------------------------------------------------------------ //
    //                         Health Score Calculation                   //
    // ------------------------------------------------------------------ //

    /// @notice Calculate health score for a bovine NFT based on provenance data
    function _calculateHealthScore(uint256 tokenId) internal view returns (uint256) {
        // Simplified health score calculation
        // In production, this would query BovineTracking contract for:
        // - Number of vaccines administered
        // - Recent health exams and results
        // - Movement history (fewer movements = healthier)
        // - Feed quality and consistency
        
        uint256 score = 70; // Base score
        
        // Bonus for recent activity (simplified)
        if (tokenId % 3 == 0) score += 10;
        if (tokenId % 5 == 0) score += 5;
        
        return score > 100 ? 100 : score;
    }

    /// @notice Get notional value based on health score
    function _getNotionalValue(uint256 healthScore) internal pure returns (uint256) {
        // Base value: 1000 RanchToken (6 decimals = 1000e6)
        uint256 baseValue = 1000e6;
        
        // Adjust by health score (0-100 maps to 50%-150% of base value)
        uint256 multiplier = 50 + healthScore; // 50 to 150
        return (baseValue * multiplier) / 100;
    }

    /// @notice Mint RanchToken (simplified - in production would use ERC20)
    function _mintRanchToken(address to, uint256 amount) internal {
        // In production: IERC20(ranchToken).mint(to, amount);
        // For now, just emit an event for tracking
        emit LoanRepaid(to, 0, amount, 0);
    }

    /// @notice Burn RanchToken (simplified - in production would use ERC20)
    function _burnRanchToken(address from, uint256 amount) internal {
        // In production: IERC20(ranchToken).burnFrom(from, amount);
        emit LoanRepaid(from, 0, amount, 0);
    }

    // ------------------------------------------------------------------ //
    //                              View Functions                        //
    // ------------------------------------------------------------------ //

    function getCollateral(uint256 tokenId) external view returns (Collateral memory) {
        return _collaterals[tokenId];
    }

    function getLoan(address borrower, uint256 tokenId) external view returns (Loan memory) {
        return _loans[borrower][tokenId];
    }

    function getCurrentBorrowAmount(address borrower, uint256 tokenId) external view returns (uint256) {
        return _getCurrentBorrowAmount(borrower, tokenId);
    }

    function getVaultUtilization() external view returns (uint256) {
        if (totalCollateralValue == 0) return 0;
        return (totalBorrows * BASIS_POINTS_DIVISOR) / totalCollateralValue;
    }
}
