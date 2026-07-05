# DAO Governance Design — RanchLendingVault

**Status:** Design Phase  
**Priority:** P3 (Low)  
**Effort:** L (1-3 weeks)  
**Dependencies:** R-12 (RanchLendingVault), R-09 (UUPS decision)

---

## Overview

This document outlines the DAO governance framework for the RanchLendingVault, enabling decentralized parameter updates through RanchToken holder voting. The design uses OpenZeppelin v5's Governor + TimelockController pattern with a 7-day timelock for safety.

**Key Design Decisions:**
- **Governance Token:** RanchToken (ERC-20) — holders vote on vault parameters
- **Voting Mechanism:** Quadratic voting to prevent whale dominance
- **Timelock:** 7 days for all parameter changes (allows exit before adverse changes)
- **Proposal Types:** Parameter updates, collateral type additions, fee structure changes

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Governance Layer                          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              GovernorRanch                               ││
│  │  • Create proposals                                     ││
│  │  • Vote (quadratic)                                    ││
│  │  • Execute after timelock                              ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │              TimelockController                          ││
│  │  • 7-day delay for all state changes                   ││
│  │  • Cancel proposals during timelock                    ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    RanchLendingVault                         │
│  • Liquidation threshold (40-80%)                          │
│  • Supported collateral types                              │
│  • Interest rate parameters                                │
│  • Fee structure                                           │
└─────────────────────────────────────────────────────────────┘
```

## Smart Contract Implementation

### GovernorRanch.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GovernorRanch is Governor, Votes, EIP712 {
    using SafeCast for *;
    
    // ── Proposal Types ──────────────────────────────────────────
    
    enum ProposalType {
        UPDATE_LIQUIDATION_THRESHOLD,  // Change liquidation LTV (40-80%)
        ADD_COLLATERAL_TYPE,           // Add new NFT type as collateral
        REMOVE_COLLATERAL_TYPE,        // Remove supported collateral type
        UPDATE_INTEREST_RATES,         // Change base rate + slopes
        UPDATE_FEE_STRUCTURE,          // Modify protocol fees
        UPGRADE_VAULT                  // Upgrade RanchLendingVault implementation
    }

    struct ProposalDetails {
        ProposalType proposalType;
        uint256 parameterId;      // Which parameter to update
        uint256 newValue;         // New value (e.g., new LTV percentage)
        address targetContract;   // Contract to call
        bytes calldataData;       // Encoded function call data
    }

    // ── State Variables ─────────────────────────────────────────
    
    uint256 public constant PROPOSAL_THRESHOLD = 100e18;  // 100 RANCH tokens to create proposal
    uint256 public constant VOTING_PERIOD = 3 days;       // 3-day voting window
    uint256 public constant TIMELock_DELAY = 7 days;      // 7-day execution delay
    
    mapping(uint256 => ProposalDetails) public proposals;
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address proposer,
        ProposalType proposalType,
        uint256 parameterId,
        uint256 newValue
    );
    
    event VoteCast(
        uint256 indexed proposalId,
        address voter,
        uint256 weight,
        bool support,
        string reason
    );

    // ── Constructor ─────────────────────────────────────────────
    
    constructor(
        ERC20Votes _token,
        address timelock_,
        string memory name_,
        string memory version_
    ) Governor(name_) EIP712(name_, version_) {
        __VotesInit(_token);
        __GovernorInit(timelock_);
    }

    // ── Governor Configuration ──────────────────────────────────
    
    function votingDelay() public view override returns (uint256) {
        return 1; // 1 block delay before voting starts
    }

    function votingPeriod() public view override returns (uint256) {
        return VOTING_PERIOD;
    }

    function proposalThreshold() public view override returns (uint256) {
        return PROPOSAL_THRESHOLD;
    }

    // ── Proposal Creation ───────────────────────────────────────
    
    function createProposal(
        address proposer,
        ProposalDetails memory details
    ) external returns (uint256 proposalId) {
        _checkGovernance();
        
        proposalId = _propose(
            new address[](0),      // No target contracts yet
            new bytes[](0),        // No calldata yet
            "",                    // No description
            proposer,
            details.proposalType,
            details.parameterId,
            details.newValue
        );
        
        emit ProposalCreated(
            proposalId,
            proposer,
            details.proposalType,
            details.parameterId,
            details.newValue
        );
    }

    // ── Voting ──────────────────────────────────────────────────
    
    function castVote(
        uint256 proposalId,
        bool support,
        string calldata reason
    ) external returns (uint256) {
        _checkGovernance();
        
        uint256 weight = getVotes(msg.sender, block.number - 1);
        
        _castVote(proposalId, support, weight, reason);
        
        emit VoteCast(proposalId, msg.sender, weight, support, reason);
    }

    // ── Quadratic Voting Weight Calculation ─────────────────────
    
    function getQuadraticWeight(uint256 rawVotes) internal pure returns (uint256) {
        // Quadratic voting: weight = sqrt(rawVotes)
        // This prevents whale dominance while still allowing large holders influence
        return uint256(sqrt(rawVotes));
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = (y + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    // ── Execution ───────────────────────────────────────────────
    
    function executeProposal(uint256 proposalId) external payable {
        _checkGovernance();
        
        ProposalDetails memory details = proposals[proposalId];
        
        // Execute based on proposal type
        if (details.proposalType == ProposalType.UPDATE_LIQUIDATION_THRESHOLD) {
            _updateLiquidationThreshold(details.newValue);
        } else if (details.proposalType == ProposalType.ADD_COLLATERAL_TYPE) {
            _addCollateralType(details.targetContract, details.calldataData);
        } else if (details.proposalType == ProposalType.UPDATE_INTEREST_RATES) {
            _updateInterestRates(details.newValue);
        }
        
        // Mark proposal as executed
        _setProposalExecuted(proposalId);
    }

    // ── Internal Functions ──────────────────────────────────────
    
    function _updateLiquidationThreshold(uint256 newLTV) internal {
        require(newLTV >= 40 && newLTV <= 80, "LTV must be between 40-80%");
        // Call RanchLendingVault.setLiquidationThreshold(newLTV)
    }

    function _addCollateralType(address nftContract, bytes memory data) internal {
        // Call RanchLendingVault.addCollateralType(nftContract)
    }

    function _updateInterestRates(uint256 newBaseRate) internal {
        require(newBaseRate <= 30e18, "Base rate cannot exceed 30%");
        // Call RanchLendingVault.setBaseInterestRate(newBaseRate)
    }

    function _checkGovernance() internal view {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Must be governor to perform this action"
        );
    }
}
```

### TimelockController Integration

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice Timelock for RanchLendingVault governance proposals
contract RanchTimelock is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}

    // Override to add Ranch-specific validation if needed
}
```

## Proposal Workflow

### 1. Create Proposal

```bash
# Rancher holds 500 RANCH tokens (above threshold of 100)
cast send <GovernorRanch> "createProposal(address,(uint8,uint256,uint256,address,bytes))" \
  0xProposer \
  '(1, 0, 65, 0xVaultAddress, hex"")' \
  --private-key $PRIVATE_KEY

# Proposal #42 created: Update liquidation threshold to 65%
```

### 2. Vote on Proposal

```bash
# Vote YES (support = true) with reason
cast send <GovernorRanch> "castVote(uint256,bool,string)" \
  42 true "Healthy cattle should support higher LTV" \
  --private-key $VOTER_PRIVATE_KEY

# Vote NO (support = false) with reason
cast send <GovernorRanch> "castVote(uint256,bool,string)" \
  42 false "Too risky for current market conditions" \
  --private-key $SKEPTIC_PRIVATE_KEY
```

### 3. Wait for Timelock (7 days)

During this period:
- Anyone can monitor the proposal
- Opponents can rally against it
- Proponents can gather more support

### 4. Execute Proposal

```bash
# After 7-day timelock expires, execute
cast send <GovernorRanch> "executeProposal(uint256)" \
  42 --private-key $EXECUTOR_PRIVATE_KEY

# Liquidation threshold updated from 70% to 65%
```

## Parameter Update Examples

### Example 1: Adjust Liquidation Threshold

**Scenario:** Market conditions improve, healthy cattle can support higher LTV.

```solidity
ProposalDetails memory proposal = ProposalDetails({
    proposalType: ProposalType.UPDATE_LIQUIDATION_THRESHOLD,
    parameterId: 0,  // Liquidation threshold parameter
    newValue: 75,    // Increase from 70% to 75%
    targetContract: address(vault),
    calldataData: abi.encodeWithSignature("setLiquidationThreshold(uint256)", 75)
});

governor.createProposal(proposer, proposal);
```

**Impact:**
- Healthy cattle (score > 80): LTV increases from 69.5% to ~74%
- Ranchers can borrow more against same collateral
- Increases capital efficiency for healthy herds

### Example 2: Add New Collateral Type

**Scenario:** Carbon credit NFTs become widely adopted and want to accept as collateral.

```solidity
ProposalDetails memory proposal = ProposalDetails({
    proposalType: ProposalType.ADD_COLLATERAL_TYPE,
    parameterId: 1,  // Collateral types registry
    newValue: 0,     // N/A for this type
    targetContract: address(carbonCreditNFT),
    calldataData: abi.encodeWithSignature("addCollateralType(address)", address(carbonCreditNFT))
});

governor.createProposal(proposer, proposal);
```

**Impact:**
- Ranchers can use carbon credit NFTs as additional collateral
- Incentivizes sustainable farming practices
- Diversifies collateral base

### Example 3: Update Interest Rate Model

**Scenario:** Protocol needs more liquidity, raises base interest rate.

```solidity
ProposalDetails memory proposal = ProposalDetails({
    proposalType: ProposalType.UPDATE_INTEREST_RATES,
    parameterId: 2,  // Base interest rate
    newValue: 12e18, // Increase from 10% to 12% APR
    targetContract: address(vault),
    calldataData: abi.encodeWithSignature("setBaseInterestRate(uint256)", 12e18)
});

governor.createProposal(proposer, proposal);
```

**Impact:**
- Borrowers pay higher interest (10% → 12%)
- Lenders earn more yield
- Attracts more liquidity providers

## Governance Token Economics

### RanchToken Distribution for Governance

| Recipient | Allocation | Purpose |
|-----------|-----------|---------|
| Protocol Treasury | 20% | Future development, grants |
| Early Users (airdrop) | 15% | Reward early adopters |
| Liquidity Providers | 15% | Incentivize vault liquidity |
| Team & Advisors | 20% | Vesting over 4 years |
| Community Reserve | 30% | Grants, marketing, partnerships |

### Voting Power Calculation

```solidity
function getVotes(address account) public view returns (uint256) {
    return _balances[account]; // Simple ERC20Votes: 1 token = 1 vote
}

// With quadratic voting (optional enhancement):
function getQuadraticVotes(address account) public view returns (uint256) {
    uint256 rawVotes = _balances[account];
    return sqrt(rawVotes); // Prevents whale dominance
}
```

### Proposal Threshold

- **Minimum tokens to create proposal:** 100 RANCH (~$100 at current price)
- **Quorum requirement:** 4% of total supply must vote YES for proposal to pass
- **Voting period:** 3 days (72 hours)
- **Timelock delay:** 7 days before execution

## Security Considerations

### 1. Timelock Protection

The 7-day timelock prevents:
- Rush decisions without community review
- Malicious parameter changes
- Flash loan attacks on voting power

During timelock, anyone can:
- Monitor the proposal
- Rally opposition
- Prepare exit strategies if parameters change unfavorably

### 2. Quadratic Voting

Prevents whale dominance by making voting power sublinear:
- 1 token = 1 vote
- 100 tokens = 10 votes (not 100)
- 10,000 tokens = 100 votes (not 10,000)

This ensures smaller holders have proportional influence.

### 3. Proposal Validation

All proposals must:
- Pass through `createProposal()` with valid parameters
- Be executable within the contract's parameter constraints
- Not exceed maximum allowed values (e.g., LTV ≤ 80%)

### 4. Emergency Pause

The DEFAULT_ADMIN_ROLE holder can pause governance during crises:

```solidity
function emergencyPause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _pause();
}

function emergencyUnpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
}
```

**Use cases:**
- Smart contract bug discovered
- Oracle manipulation detected
- Market crash requiring immediate parameter adjustment

## Testing Strategy

### Unit Tests (Foundry)

1. **Proposal Creation:**
   - Verify proposal ID increments correctly
   - Check event emission with all parameters
   - Test threshold enforcement (below 100 RANCH fails)

2. **Voting:**
   - Quadratic weight calculation correctness
   - Vote counting (YES vs NO)
   - Quorum requirement enforcement

3. **Timelock:**
   - Cannot execute before delay expires
   - Can cancel during timelock
   - State changes only after execution

4. **Parameter Updates:**
   - LTV updates within 40-80% range
   - Interest rates cannot exceed 30%
   - Collateral type additions require valid NFT contract

### Integration Tests

```bash
# Full governance flow test
forge script test/GovernanceFlow.t.sol --broadcast

# Test scenario: Update liquidation threshold from 70% to 75%
1. Deploy GovernorRanch + TimelockController
2. Airdrop 10,000 RANCH to 100 test users
3. User A creates proposal (holds 500 RANCH)
4. Users B-J vote YES (total: 6,000 RANCH = 60% of supply)
5. Wait 7 days for timelock
6. Execute proposal
7. Verify vault liquidation threshold is now 75%
```

## Deployment Strategy

### Phase 1: Testnet Governance

1. Deploy GovernorRanch + TimelockController to Polygon Amoy
2. Airdrop test RANCH tokens to beta testers
3. Run mock proposals (no real parameter changes)
4. Gather feedback on UX and voting mechanics

### Phase 2: Mainnet Pilot

1. Deploy to Polygon PoS mainnet
2. Airdrop 5% of total supply to early users
3. Start with conservative proposals (parameter tweaks only)
4. Monitor for governance attacks or manipulation

### Phase 3: Full DAO Launch

1. Distribute remaining tokens via liquidity mining + airdrops
2. Enable all proposal types including collateral additions
3. Consider delegating voting power to specialized delegates
4. Integrate with Snapshot for off-chain signaling

## Future Enhancements

1. **Delegation:** Allow token holders to delegate voting power to experts
2. **Multisig Integration:** Require 3-of-5 multisig approval for critical changes
3. **Reputation System:** Track proposal success rate, reward good governance participants
4. **SubDAOs:** Create specialized committees (risk, technical, community)
5. **Cross-chain Governance:** Extend to Base, Arbitrum deployments

## Metrics & KPIs

Track these metrics post-launch:

1. **Participation Rate:** % of supply voting on proposals
   - Target: > 20% (healthy governance)
   
2. **Proposal Success Rate:** Proposals executed / proposals created
   - Target: 60-80% (not too easy, not too hard)
   
3. **Average Voting Time:** Days from creation to execution
   - Target: 10-14 days (7-day timelock + 3-day vote + buffer)
   
4. **Governance Attacks:** Failed malicious proposals
   - Target: 0 (design should prevent these)
   
5. **Delegate Concentration:** % of votes held by top 10 delegates
   - Target: < 50% (decentralized voting power)

---

**Next Steps:**
1. Implement GovernorRanch.sol with basic proposal creation/voting
2. Deploy to Polygon Amoy testnet for beta testing
3. Run mock governance cycles to validate UX
4. Integrate with RanchLendingVault parameter update functions

**Estimated Timeline:** 3-4 weeks from design approval to mainnet pilot launch
