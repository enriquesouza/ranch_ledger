# RanchLendingVault — Architecture & Design Document

**Status:** Design Phase  
**Priority:** P2 (Medium)  
**Effort:** XL (1+ month)  
**Dependencies:** R-09 (UUPS decision), R-11 (EUDR compliance)

---

## Overview

The RanchLendingVault is a decentralized lending protocol that uses BovineNFTs as collateral for rural credit. It enables Brazilian ranchers to access affordable loans backed by proven cattle assets, addressing the critical gap in rural financing in Brazil's $2 trillion agribusiness sector.

**Key Innovation:** Risk scoring based on on-chain bovine health data (vaccines, feed, movements) rather than traditional credit scores.

## Problem Statement

Brazilian ranchers face:
- **High interest rates:** 15-30% APR from traditional banks
- **Limited collateral acceptance:** Banks don't accept live cattle as collateral
- **Credit exclusion:** 40% of smallholder ranchers lack access to formal credit
- **Slow approval:** 2-6 weeks for loan approval

**Solution:** NFT-per-cattle lending vault that uses provenance data for dynamic risk scoring.

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    RanchLendingVault                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Collateral Management                      ││
│  │  • Deposit/Withdraw BovineNFTs                          ││
│  │  • Calculate LTV (Loan-to-Value)                        ││
│  │  • Monitor NFT transfers & health status                ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Risk Scoring Engine                        ││
│  │  • Analyze vaccine history                              ││
│  │  • Check feed quality & origin                          ││
│  │  • Verify movement patterns                             ││
│  │  • Calculate health score (0-100)                       ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Lending Pool                               ││
│  │  • Compound-style interest rate model                   ││
│  │  • Parameterized by cattle health data                  ││
│  │  • Automated liquidation on default                     ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Rancher deposits BovineNFT** → Vault locks NFT, calculates health score
2. **Health score determines LTV** → Healthy cattle (score > 80): 70% LTV, Sick cattle (score < 50): 40% LTV
3. **Rancher borrows against collateral** → Receives stablecoins at variable interest rate
4. **Repayment or liquidation** → Loan repaid: NFT released; Default: NFT auctioned

## Smart Contract Design

### RanchLendingVault.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract RanchLendingVault is 
    UUPSUpgradeable, 
    AccessControlUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    struct Loan {
        address borrower;
        uint256[] collateralNftIds;  // Array of BovineNFT token IDs
        uint256 principal;           // Borrowed amount
        uint256 interestAccrued;     // Accrued interest
        uint256 lastInterestUpdate;  // Last interest calculation timestamp
        bool isActive;               // Loan status
    }

    struct Collateral {
        uint256 nftId;
        address owner;
        uint256 healthScore;       // 0-100, calculated from on-chain data
        uint256 value;             // Notional value in stablecoins (e.g., USDC)
        bool isLocked;             // Locked during loan period
    }

    mapping(uint256 => Loan) public loans;
    mapping(address => Collateral[]) public userCollateral;
    
    uint256 public totalLiquidity;     // Total deposited liquidity
    uint256 public totalBorrowed;      // Total outstanding loans
    uint256 public baseInterestRate;   // Base APR (e.g., 10%)
    uint256 public liquidationThreshold; // LTV threshold for liquidation (e.g., 70%)
    
    address public nftContract;        // BovineNFT contract address
    
    event LoanTaken(uint256 indexed loanId, address indexed borrower, uint256 amount);
    event LoanRepaid(uint256 indexed loanId, address indexed borrower);
    event CollateralDeposited(address indexed user, uint256 nftId);
    event CollateralWithdrawn(address indexed user, uint256 nftId);
    event Liquidated(uint256 indexed loanId, address indexed liquidator);
}
```

### Risk Scoring Algorithm

```solidity
function calculateHealthScore(uint256 bovineId) public view returns (uint256 score) {
    Bovine memory b = BovineTracking(nftContract).getBovine(bovineId);
    
    // Base score: 50 points
    score = 50;
    
    // Vaccine history: +2 points per vaccine (max +20)
    uint256 vaccineCount = b.vaccines.length;
    if (vaccineCount > 10) vaccineCount = 10;
    score += vaccineCount * 2;
    
    // Feed quality: +3 points for organic/natural feed (max +9)
    for (uint256 i = 0; i < b.feeds.length && i < 3; i++) {
        if (keccak256(abi.encodePacked(b.feeds[i].foodType)) == keccak256("Organic")) {
            score += 3;
        }
    }
    
    // Movement history: +1 point per movement (max +10)
    uint256 movementCount = b.movements.length;
    if (movementCount > 10) movementCount = 10;
    score += movementCount;
    
    // Health exams: +5 points for "Healthy" result (max +15)
    for (uint256 i = 0; i < b.healthExams.length && i < 3; i++) {
        if (keccak256(abi.encodePacked(b.healthExams[i].result)) == keccak256("Healthy")) {
            score += 5;
        }
    }
    
    // Cap at 100
    if (score > 100) score = 100;
}

function calculateLTV(uint256 healthScore) public pure returns (uint256 ltv) {
    // Linear mapping: score 0-100 → LTV 40%-70%
    ltv = 40 + (healthScore * 30) / 100;
}
```

### Interest Rate Model

```solidity
function calculateInterestRate(uint256 utilizationRatio) public view returns (uint256 rate) {
    // Compound-style model:
    // - Below 80% utilization: base rate + small slope
    // - Above 80% utilization: steep increase to incentivize repayment
    
    uint256 optimalUtilization = 80;
    
    if (utilizationRatio <= optimalUtilization) {
        rate = baseInterestRate + (utilizationRatio * 10) / optimalUtilization;
    } else {
        uint256 excessUtilization = utilizationRatio - optimalUtilization;
        rate = baseInterestRate + 10 + (excessUtilization * 50) / (100 - optimalUtilization);
    }
}

function accrueInterest(uint256 loanId) public {
    Loan storage loan = loans[loanId];
    uint256 timeElapsed = block.timestamp - loan.lastInterestUpdate;
    
    // Calculate utilization ratio
    uint256 utilization = totalBorrowed == 0 ? 0 : (loan.principal * 1e18) / totalLiquidity;
    
    uint256 rate = calculateInterestRate(utilization);
    loan.interestAccrued += (loan.principal * rate * timeElapsed) / (365 days * 1e18);
    loan.lastInterestUpdate = block.timestamp;
}

function isUnderwater(uint256 loanId) public view returns (bool) {
    Loan storage loan = loans[loanId];
    
    // Calculate total collateral value
    uint256 totalCollateralValue = 0;
    for (uint256 i = 0; i < loan.collateralNftIds.length; i++) {
        Collateral memory coll = userCollateral[loan.borrower][i];
        if (coll.isLocked && coll.nftId == loan.collateralNftIds[i]) {
            totalCollateralValue += coll.value;
        }
    }
    
    uint256 debt = loan.principal + loan.interestAccrued;
    return (debt * 100) / totalCollateralValue > liquidationThreshold;
}
```

## Integration with BovineTracking

### Health Score Oracle

The vault queries BovineTracking for real-time health data:

```solidity
function updateCollateralHealth(uint256 nftId) external {
    uint256 bovineId = BovineNFT(nftContract).tokenToBovine(nftId);
    uint256 healthScore = calculateHealthScore(bovineId);
    
    // Update collateral record
    for (uint256 i = 0; i < userCollateral[msg.sender].length; i++) {
        if (userCollateral[msg.sender][i].nftId == nftId) {
            userCollateral[msg.sender][i].healthScore = healthScore;
            
            // Recalculate LTV and check for liquidation
            uint256 ltv = calculateLTV(healthScore);
            if (ltv < liquidationThreshold) {
                // Trigger liquidation warning or automatic liquidation
                emit LiquidationWarning(nftId, healthScore);
            }
        }
    }
}
```

### NFT Transfer Monitoring

The vault must monitor NFT transfers to prevent collateral theft:

```solidity
modifier onlyVault(address nftContract) {
    require(msg.sender == nftContract || msg.sender == IERC721(nftContract).getApproved(msg.sender), "Not authorized");
    _;
}

function onTransferSingle(
    address operator,
    address from,
    address to,
    uint256 id,
    uint256 value
) external override onlyVault(msg.sender) {
    if (from == address(this)) {
        // NFT withdrawn by vault (loan repaid or liquidated)
        _removeCollateral(from, id);
    } else if (to == address(this)) {
        // NFT deposited as collateral
        _addCollateral(to, id);
    }
}
```

## Liquidation Mechanism

### Automatic Liquidation Trigger

Liquidation occurs when:
1. Loan is underwater (debt > LTV threshold × collateral value)
2. Health score drops below critical threshold (< 30)
3. NFT is transferred out of vault without repayment

### Liquidation Process

```solidity
function liquidateLoan(uint256 loanId) external onlyRole(LIQUIDATOR_ROLE) {
    Loan storage loan = loans[loanId];
    
    require(isUnderwater(loanId), "Loan not underwater");
    require(!loan.isActive, "Loan already closed");
    
    // Calculate liquidation bonus (10% discount for liquidator)
    uint256 debt = loan.principal + loan.interestAccrued;
    uint256 liquidationBonus = debt / 10;
    
    // Transfer collateral to liquidator
    for (uint256 i = 0; i < loan.collateralNftIds.length; i++) {
        IERC721(nftContract).transferFrom(address(this), msg.sender, loan.collateralNftIds[i]);
    }
    
    // Distribute repayment to lenders (proportional to their share)
    uint256 totalCollateralValue = 0;
    for (uint256 i = 0; i < loan.collateralNftIds.length; i++) {
        Collateral memory coll = userCollateral[loan.borrower][i];
        totalCollateralValue += coll.value;
    }
    
    uint256 liquidatorReceives = totalCollateralValue - liquidationBonus;
    // Update liquidity pool
    
    loan.isActive = false;
    emit Liquidated(loanId, msg.sender);
}
```

## Testing Strategy

### Unit Tests (Foundry)

1. **Loan Lifecycle:**
   - Deposit collateral → Take loan → Repay loan → Withdraw collateral
   - Test with multiple NFTs per loan
   - Test partial repayments

2. **Risk Scoring:**
   - Vaccinated cattle: score > 70, LTV = 65%
   - Unvaccinated cattle: score < 50, LTV = 45%
   - Sick cattle (health exam "Sick"): automatic liquidation trigger

3. **Interest Accrual:**
   - Verify interest compounds correctly over time
   - Test with different utilization ratios
   - Ensure rate increases above 80% utilization

4. **Liquidation:**
   - Underwater loan triggers liquidation
   - Liquidator receives NFTs at discount
   - Repayment distributed to lenders

### Integration Tests

1. **End-to-End Flow:**
   ```bash
   # Deploy contracts
   forge script script/DeployLendingVault.s.sol --broadcast
   
   # Rancher deposits 10 healthy NFTs (score > 80)
   cast send <vault> "depositCollateral(uint256[])" '[1,2,3,...,10]'
   
   # Calculate health scores and LTV
   # Score: 85 → LTV: 69.5%
   # Collateral value: 10 × $2,000 = $20,000
   # Max loan: $20,000 × 69.5% = $13,900
   
   # Rancher borrows $10,000 USDC
   cast send <vault> "takeLoan(uint256[],uint256)" '[1,2,...,10]', 10000
   
   # Wait 30 days, interest accrues
   # Interest: $10,000 × 12% APR × 30/365 = $98.63
   
   # Rancher repays loan + interest
   cast send <vault> "repayLoan(uint256)" '[loanId]', 10098.63
   
   # NFTs released back to rancher
   ```

2. **Liquidation Scenario:**
   ```bash
   # Rancher deposits 5 sick NFTs (score < 40)
   cast send <vault> "depositCollateral(uint256[])" '[11,12,13,14,15]'
   
   # Health score: 35 → LTV: 44.5%
   # Collateral value: 5 × $1,500 = $7,500
   # Max loan: $7,500 × 44.5% = $3,337
   
   # Rancher borrows $3,000 (close to max)
   
   # Health score drops to 25 after disease outbreak
   # LTV recalculated: 38%
   # New max loan: $7,500 × 38% = $2,850
   
   # Loan is now underwater ($3,000 > $2,850)
   
   # Liquidator calls liquidateLoan(loanId)
   cast send <vault> "liquidateLoan(uint256)" '[loanId]' --from 0xLiquidator
   
   # NFTs transferred to liquidator at 10% discount
   # Repayment distributed to lenders
   ```

## Gas Optimization

### Batch Operations

```solidity
function depositCollateralBatch(uint256[] calldata nftIds) external nonReentrant {
    for (uint256 i = 0; i < nftIds.length; i++) {
        _addCollateral(msg.sender, nftIds[i]);
    }
}

function withdrawCollateralBatch(uint256[] calldata nftIds) external nonReentrant {
    for (uint256 i = 0; i < nftIds.length; i++) {
        _removeCollateral(msg.sender, nftIds[i]);
    }
}
```

### Storage Packing

```solidity
struct Collateral {
    uint256 nftId;           // Slot 1
    address owner;           // Slot 2 (packed with nftId if possible)
    uint8 healthScore;       // Slot 3 (0-100 fits in uint8)
    uint16 value;            // Slot 4 (value in thousands of USDC)
    bool isLocked;           // Packed into existing slot
}
```

## Security Considerations

### Reentrancy Protection

All external calls use `nonReentrant` modifier and checks-effects-interactions pattern.

### NFT Ownership Verification

Before accepting NFTs as collateral, verify:
1. NFT is owned by the depositor
2. NFT is not already locked in another loan
3. NFT transfer is approved to vault contract

### Oracle Manipulation Resistance

Health scores are calculated from on-chain data (BovineTracking events), making them resistant to oracle manipulation. However, consider:
- Rate-limit health score updates (max 1 per hour per bovine)
- Allow risk managers to override scores in extreme cases

### Liquidation Incentives

Ensure liquidators are incentivized:
- 10% discount on collateral value
- Gas compensation for liquidation tx
- Automated liquidation bots can operate profitably

## Deployment Strategy

### Phase 1: Testnet (Polygon Amoy)

1. Deploy RanchLendingVault with mock NFT contract
2. Run full test suite
3. Deploy to Polygon Amoy testnet
4. Invite beta testers (5-10 ranchers)
5. Monitor for issues over 30 days

### Phase 2: Mainnet Pilot

1. Deploy to Polygon PoS mainnet
2. Partner with 2-3 Brazilian cattle cooperatives
3. Onboard 50-100 ranchers
4. Start with conservative LTV (50%) and high liquidation threshold (80%)
5. Gradually adjust parameters based on real-world data

### Phase 3: Full Launch

1. Optimize interest rate model based on pilot data
2. Expand to 1,000+ ranchers
3. Integrate with DeFi protocols for liquidity provision
4. Consider DAO governance for parameter updates (R-20)

## Metrics & KPIs

Track these metrics post-launch:

1. **Utilization Rate:** Total borrowed / Total deposited
   - Target: 60-80% (optimal for interest revenue)
   
2. **Default Rate:** Loans not repaid / Total loans
   - Target: < 5% (healthy lending portfolio)
   
3. **Average Loan Size:** Total borrowed / Number of loans
   - Target: $5,000-$15,000 (accessible to smallholders)
   
4. **Liquidation Rate:** Liquidated loans / Total loans
   - Target: < 2% (indicates good risk assessment)
   
5. **Rancher Retention:** Ranchers with active loans after 6 months
   - Target: > 70% (indicates product-market fit)

## Future Enhancements

1. **Insurance Integration:** Partner with parametric insurance providers for disease outbreaks
2. **Carbon Credits:** Allow ranchers to use carbon credit NFTs as additional collateral
3. **Cross-Chain Lending:** Support lending across multiple L2s (Base, Arbitrum)
4. **AI Risk Scoring:** Integrate ML models for more accurate health predictions
5. **DAO Governance:** Let RanchToken holders vote on interest rates and LTV parameters

---

**Next Steps:**
1. Implement core contract structure (RanchLendingVault.sol)
2. Add risk scoring engine with BovineTracking integration
3. Write comprehensive test suite
4. Deploy to Polygon Amoy testnet for beta testing

**Estimated Timeline:** 6-8 weeks from design approval to mainnet pilot launch
