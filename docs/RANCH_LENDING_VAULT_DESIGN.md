# RanchLendingVault — Architecture & Design Document

**Status:** Implemented  
**Priority:** P2 (Medium)  
**Effort:** XL (1+ month)  
**Dependencies:** R-09 (no-upgradeability decision, see ADR-001), R-11 (EUDR compliance)

---

## Overview

The RanchLendingVault is a decentralized lending protocol that uses BovineNFTs as collateral for rural credit. It enables ranchers worldwide to access affordable loans backed by proven cattle assets, addressing the critical gap in rural financing in the global agribusiness sector.

**Key Innovation:** Risk scoring based on on-chain bovine health data (vaccines, feed, movements) rather than traditional credit scores.

**Global Livestock ID Support:** The vault's `Collateral` struct includes `countryCode` and `nationalId` fields, enabling cross-jurisdiction collateral. A Brazilian rancher can deposit a cow with its SISBOV ID, while a US rancher can deposit with a USDA ANID — both in the same vault. Supported registries include:

- 🇧🇷 **Brazil** — SISBOV
- 🇪🇺 **EU** — ISO 1166 / animal passport
- 🇺🇸 **US** — USDA ANID
- 🇦🇺 **Australia** — NLIS
- 🇨🇳 **China** — MARA
- 🇸🇦🇦🇪🇶🇦 **GCC** — Saudi Arabia, UAE, Qatar national IDs

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
│  │  • Global livestock ID (countryCode + nationalId)       ││
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
│                                                             │
│  Non-upgradeable (per ADR-001) — AccessControl +            │
│  ReentrancyGuardTransient                                   │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  BovineNFT (ERC-721)  ←  BovineTracking (provenance)         │
│  • tokenId → bovineId                                       │
│  • countryCode / nationalId stored on NFT                   │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Rancher deposits BovineNFT** → Vault locks NFT, calculates health score
2. **Health score determines LTV** → Healthy cattle (score > 80): 70% LTV, Sick cattle (score < 50): 40% LTV
3. **Rancher borrows against collateral** → Receives stablecoins at variable interest rate
4. **Repayment or liquidation** → Loan repaid: NFT released; Default: NFT auctioned

## Smart Contract Design

### RanchLendingVault.sol

> **Note:** Per [ADR-001-no-upgradeability.md](./ADR-001-no-upgradeability.md), the vault uses **non-upgradeable** contracts with `AccessControl` and `ReentrancyGuardTransient` (transient storage reentrancy guard, cheaper than storage-based). No proxy pattern is used.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract RanchLendingVault is AccessControl, ReentrancyGuardTransient {
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant PRICER_ROLE = keccak256("PRICER_ROLE");

    struct Collateral {
        address owner;
        uint256 tokenId;
        string countryCode;    // ISO 3166-1 alpha-2: BR, EU, US, AU, CN, SA, AE, QA
        string nationalId;     // Country-specific ID (SISBOV, ANID, NLIS, GCC, etc.)
        uint256 notionalValue;
        uint256 healthScore;
        bool isCollateralized;
    }

    struct Loan {
        uint256 principal;
        uint256 interestAccrued;
        uint256 lastUpdateBlock;
        bool isActive;
    }

    struct VaultConfig {
        uint256 maxLTV;
        uint256 liquidationThreshold;
        uint256 healthScoreFloor;
        uint256 baseBorrowRate;
        uint256 utilizationSlope1;
        uint256 utilizationSlope2;
        uint256 optimalUtilization;
    }
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

## Global Livestock ID Integration

The `Collateral` struct now includes `countryCode` and `nationalId` fields, enabling **cross-jurisdiction collateral** within a single vault. This means:

- A **Brazilian rancher** can deposit a cow with its SISBOV ID (`countryCode = "BR"`, `nationalId = "BR-SISBOV-123456"`)
- A **US rancher** can deposit with a USDA ANID (`countryCode = "US"`, `nationalId = "USDA-ANID-840-..."`)
- An **Australian rancher** can deposit with an NLIS tag (`countryCode = "AU"`, `nationalId = "NLIS-..."`)

All three deposits coexist in the same vault, with health scores derived from each jurisdiction's BovineTracking provenance data. The `countryCode` follows ISO 3166-1 alpha-2 format, while `nationalId` is a free-form string that accommodates each country's identification scheme:

| Country | Code | Registry | ID Format Example |
|---------|------|----------|------------------|
| Brazil | BR | SISBOV | `BR-SISBOV-123456` |
| EU | EU | ISO 1166 | `EU-PASS-DE-...` |
| US | US | USDA ANID | `USDA-ANID-840-...` |
| Australia | AU | NLIS | `NLIS-123456789` |
| China | CN | MARA | `MARA-CN-...` |
| Saudi Arabia | SA | GCC | `GCC-SA-...` |
| UAE | AE | GCC | `GCC-AE-...` |
| Qatar | QA | GCC | `GCC-QA-...` |

This design enables a globally diversified collateral pool, reducing geographic concentration risk and allowing lenders to access cattle-backed yield across multiple regulatory frameworks.

## Health Score Derivation

Health scores (0–100) are derived from BovineTracking provenance data. The score is a composite of multiple on-chain signals:

| Signal | Weight | Source | Max Points |
|--------|--------|--------|------------|
| **Vaccine history completeness** | +2/vaccine | `Bovine.vaccines[]` | +20 |
| **Feed quality & origin verification** | +3/organic feed | `Bovine.feeds[]` | +9 |
| **Movement pattern analysis** | +1/movement | `Bovine.movements[]` | +10 |
| **Health exam results** | +5/"Healthy" | `Bovine.healthExams[]` | +15 |
| **Base score** | — | — | 50 |

**Risk-adjusted LTV mapping:**

$$\text{LTV} = 40 + \frac{\text{healthScore} \times 30}{100}$$

- **Higher scores → lower risk → higher LTV** (e.g., score 90 → LTV 67%)
- **Lower scores → higher risk → lower LTV** (e.g., score 30 → LTV 49%)
- Scores below `healthScoreFloor` (configurable, default 30) trigger liquidation

## Interest Rate Model

The vault uses a **Compound-style** interest rate model with a kink at `optimalUtilization`:

```
        rate
         │
         │              ╱  utilizationSlope2 (steep)
         │            ╱
         │          ╱
  base──┤────────╱  ← kink (optimalUtilization)
  +slope1╲      ╱
         │    ╱  utilizationSlope1 (gentle)
         │  ╱
         ╱
         └──────────────────────────────── utilization
          0%       optimalUtilization      100%
```

- **Global index** tracks accrued interest across all loans
- **`baseBorrowRate`** — floor rate applied at 0% utilization
- **`utilizationSlope1`** — gentle slope below the kink (low utilization regime)
- **`utilizationSlope2`** — steep slope above the kink (high utilization regime, incentivizes repayment)
- **`optimalUtilization`** — the kink point (e.g., 80%)

```solidity
function calculateInterestRate(uint256 utilization) public view returns (uint256 rate) {
    VaultConfig memory cfg = config;
    if (utilization <= cfg.optimalUtilization) {
        rate = cfg.baseBorrowRate
            + (utilization * cfg.utilizationSlope1) / cfg.optimalUtilization;
    } else {
        uint256 excess = utilization - cfg.optimalUtilization;
        rate = cfg.baseBorrowRate + cfg.utilizationSlope1
            + (excess * cfg.utilizationSlope2) / (100 - cfg.optimalUtilization);
    }
}
```

## Liquidation Flow

Liquidation is triggered by `LIQUIDATOR_ROLE` holders when any of the following conditions are met:

1. **Health score drops below `healthScoreFloor`** — cattle health deteriorates (disease, missing vaccines)
2. **LTV exceeds `liquidationThreshold`** — debt grows beyond safe collateral coverage
3. **NFT transferred out of vault without repayment** — collateral theft attempt

**Liquidation process:**

```
┌──────────────┐    LIQUIDATOR_ROLE    ┌──────────────────┐
│  Liquidator  │ ───────────────────► │  RanchLendingVault │
└──────────────┘    liquidate(tokenId) └────────┬─────────┘
                                               │
                    ┌──────────────────────────┘
                    ▼
        ┌───────────────────────┐
        │  Verify trigger:      │
        │  • health < floor OR  │
        │  • LTV > threshold    │
        └───────────┬───────────┘
                    │ pass
                    ▼
        ┌───────────────────────┐
        │  Transfer BovineNFT    │
        │  to liquidator         │
        └───────────┬───────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │  Forgive remaining     │
        │  debt (loan.isActive   │
        │  = false)              │
        └───────────────────────┘
```

- The NFT is transferred to the liquidator as compensation
- Remaining debt is **forgiven** (no further obligation on the borrower)
- The loan is marked `isActive = false`

## Key Functions

| Function | Access | Description |
|----------|--------|-------------|
| `depositCollateral(uint256 tokenId)` | External | Deposit a BovineNFT as collateral; locks NFT in vault |
| `withdrawCollateral(uint256 tokenId)` | External | Withdraw NFT after loan is fully repaid |
| `borrow(uint256 tokenId, uint256 amount)` | External | Borrow RanchToken against deposited collateral |
| `repayLoan(uint256 tokenId)` | External | Repay outstanding loan and release collateral |
| `updateConfig(VaultConfig)` | `DEFAULT_ADMIN_ROLE` | Update vault parameters (LTV, thresholds, rates) |
| `setPricer(address)` | `DEFAULT_ADMIN_ROLE` | Set the address authorized to update notional values (`PRICER_ROLE`) |

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

1. **FractionalizationManager Integration:** Allow `FractionalizationVault` share tokens (BovineShareToken ERC-20) to be used as collateral, enabling fractional ownership of high-value cattle to participate in lending
2. **GovernorRanch DAO Governance:** Move parameter updates (`updateConfig`, `setPricer`) from admin-only to DAO-governed proposals via `GovernorRanch`, letting RanchToken holders vote on interest rates and LTV thresholds
3. **Chainlink Price Oracle:** Replace admin-set notional values with Chainlink price feeds for real-time, tamper-resistant cattle market valuations
4. **Multi-Currency Support:** Beyond RanchToken, support borrowing in multiple stablecoins (USDC, DAI, USDT) with cross-rate conversion
5. **Insurance Integration:** Partner with parametric insurance providers for disease outbreaks
6. **Carbon Credits:** Allow ranchers to use carbon credit NFTs as additional collateral
7. **Cross-Chain Lending:** Support lending across multiple L2s (Base, Arbitrum, Optimism)
8. **AI Risk Scoring:** Integrate ML models for more accurate health predictions

---

**Implementation Status:** ✅ Core contract implemented in `src/RanchLendingVault.sol`. See [ARCHITECTURE.md](./ARCHITECTURE.md) for deployment details.
