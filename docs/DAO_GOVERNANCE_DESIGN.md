# DAO Governance Design — RanchLendingVault

**Status:** Implemented  
**Priority:** P3 (Low)  
**Effort:** L (1-3 weeks)  
**Dependencies:** R-12 (RanchLendingVault), R-09 (UUPS decision)

---

## Overview

This document describes the DAO governance framework for the RanchLendingVault, enabling decentralized parameter updates through RanchToken holder voting. The implementation uses OpenZeppelin v5.1's Governor pattern with role-based access control (AccessControl). The TimelockController originally planned was removed due to API incompatibility with Governor in OZ v5.1.0 (see [Key Design Decisions](#key-design-decisions)).

**Key Design Decisions:**
- **Governance Token:** RanchToken (plain ERC-20) — holders vote on vault parameters
- **Voting Mechanism:** Simple token-weighted voting (1 token = 1 vote)
- **Timelock:** None in v1 (TimelockController removed — see [Key Design Decisions](#key-design-decisions))
- **Proposal Types:** Arbitrary target/calldata proposals via Governor's standard `propose()`

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Governance Layer                          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              GovernorRanch                               ││
│  │  • Create proposals (PROPOSER_ROLE)                      ││
│  │  • Vote (VOTER_ROLE, 1 token = 1 vote)                   ││
│  │  • Execute after voting period                           ││
│  │  • AccessControl for role management                     ││
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

> **Note:** The TimelockController shown in the original design has been removed. See [Key Design Decisions](#key-design-decisions) for rationale.

## Smart Contract Implementation

### GovernorRanch.sol

The actual implementation lives in `src/GovernorRanch.sol`. The contract inherits `Governor`, `Votes`, and `AccessControl` — note that it does **not** inherit `ERC20Votes` (RanchToken is a plain ERC-20) and does **not** use a `TimelockController`.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract GovernorRanch is Governor, Votes, AccessControl {
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant VOTER_ROLE = keccak256("VOTER_ROLE");

    ERC20 public immutable token;
    uint256 private immutable _votingDelay;
    uint256 private immutable _votingPeriod;

    uint256 private constant MIN_PROPOSAL_THRESHOLD = 1e18;

    mapping(uint256 => mapping(address => bool)) private _votesCast;
    mapping(uint256 => ProposalDetails) private _proposals;

    struct ProposalDetails {
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
        uint256 proposalSnapshot;
        uint256 proposalDeadline;
    }

    constructor(ERC20 _token, string memory name_, uint256 votingDelay_, uint256 votingPeriod_)
        Governor(name_) Votes(_token.name())
    {
        token = _token;
        _votingDelay = votingDelay_;
        _votingPeriod = votingPeriod_;
        _grantRole(DEFAULT_ADMIN_ROLE, address(this));
        _grantRole(PROPOSER_ROLE, msg.sender);
    }

    // ── Governor configuration (immutable, set at deploy time) ──

    function votingDelay() public view override returns (uint256) {
        return _votingDelay;
    }

    function votingPeriod() public view override returns (uint256) {
        return _votingPeriod;
    }

    function quorum(uint256 blockNumber) public view override returns (uint256) {
        return token.totalSupply() / 10; // 10% quorum based on total supply
    }

    function proposalThreshold() public view override returns (uint256) {
        return MIN_PROPOSAL_THRESHOLD;
    }

    // ── Voting power: balanceOf (simplified for v1) ──

    function getVotes(address account, uint256 blockNumber) public view override returns (uint256) {
        return token.balanceOf(account);
    }

    // ── Custom hasVoted (no _getReceipt in OZ v5.1.0) ──

    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return _votesCast[proposalId][account];
    }

    // ── supportsInterface: resolve Governor + AccessControl conflict ──

    function supportsInterface(bytes4 interfaceId)
        public view virtual override(Governor, AccessControl) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ── Vote counting ──

    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal virtual override {
        ProposalDetails storage details = _proposals[proposalId];
        if (support == 0) {
            details.noVotes += weight;
        } else if (support == 1) {
            details.yesVotes += weight;
        } else if (support == 2) {
            details.abstainVotes += weight;
        }
        _votesCast[proposalId][account] = true;
    }

    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool) {
        ProposalDetails memory details = _proposals[proposalId];
        return details.yesVotes > details.noVotes && _quorumReached(proposalId);
    }

    function _quorumReached(uint256 proposalId) internal view virtual override returns (bool) {
        ProposalDetails memory details = _proposals[proposalId];
        uint256 quorumVotes = quorum(details.proposalSnapshot);
        return details.yesVotes + details.abstainVotes >= quorumVotes;
    }
}
```

### Key differences from the original design

| Aspect | Original Design | Actual Implementation |
|--------|-----------------|----------------------|
| Timelock | TimelockController, 7-day delay | None (removed — see below) |
| Voting | Quadratic voting | Simple token-weighted (1 token = 1 vote) |
| Token | ERC20Votes | Plain ERC20 (RanchToken) |
| Voting power source | `getPastVotes()` snapshot | `balanceOf()` (current balance) |
| Voting params | Constants, settable | Immutable, set at deploy time |
| hasVoted | `_getReceipt()` | Custom `_votesCast` mapping |
| Quorum | 4% of supply | 10% of total supply (`token.totalSupply() / 10`) |
| Proposal threshold | 100e18 | 1e18 (`MIN_PROPOSAL_THRESHOLD`) |
| Roles | DEFAULT_ADMIN_ROLE only | PROPOSER_ROLE + VOTER_ROLE + DEFAULT_ADMIN_ROLE |
| Inheritance | Governor, Votes, EIP712 | Governor, Votes, AccessControl |

## Proposal Lifecycle

1. **Proposer creates proposal** — A holder with at least `MIN_PROPOSAL_THRESHOLD` (1e18) tokens and the `PROPOSER_ROLE` calls `propose(targets, values, calldatas, description)`.
2. **Voting delay passes** — The immutable `_votingDelay` (in blocks) must elapse before voting opens.
3. **Voting period opens** — The immutable `_votingPeriod` (in blocks) window begins; token holders with `VOTER_ROLE` may cast votes.
4. **Token holders cast votes** — `castVote(proposalId, support)` or `castVoteWithReason(...)`. `support` values: `0` = Against, `1` = For, `2` = Abstain. Weight = `token.balanceOf(voter)`.
5. **Voting period ends** — No more votes are accepted.
6. **Quorum & success check** — Proposal succeeds if quorum is reached (10% of `token.totalSupply()` in For + Abstain votes) **and** `yesVotes > noVotes`.
7. **Execution** — Anyone calls `execute(targets, values, calldatas, descriptionHash)`, which triggers `_execute()` and emits `ProposalExecuted`.

## Proposal Workflow

### 1. Create Proposal

```bash
# Proposer holds >= 1 RANCH token and has PROPOSER_ROLE
cast send <GovernorRanch> "propose(address[],uint256[],bytes[],string)" \
  '[<VaultAddress>]' '[0]' '["0x...encoded calldata..."]' "Update liquidation threshold to 75%" \
  --private-key $PROPOSER_PRIVATE_KEY
```

### 2. Vote on Proposal

```bash
# Vote FOR (support = 1) with reason
cast send <GovernorRanch> "castVoteWithReason(uint256,uint8,string)" \
  <proposalId> 1 "Healthy cattle should support higher LTV" \
  --private-key $VOTER_PRIVATE_KEY

# Vote AGAINST (support = 0)
cast send <GovernorRanch> "castVote(uint256,uint8)" \
  <proposalId> 0 \
  --private-key $SKEPTIC_PRIVATE_KEY
```

### 3. Wait for Voting Period

During the voting period (immutable `_votingPeriod` blocks):
- Token holders cast votes (For / Against / Abstain)
- Quorum (10% of total supply) must be met in For + Abstain votes
- For votes must exceed Against votes

### 4. Execute Proposal

```bash
# After voting period ends and proposal succeeded
cast send <GovernorRanch> "execute(address[],uint256[],bytes[],bytes32)" \
  '[<VaultAddress>]' '[0]' '["0x...encoded calldata..."]' <descriptionHash> \
  --private-key $EXECUTOR_PRIVATE_KEY
```

## Parameter Update Examples

The actual implementation uses Governor's standard `propose(targets, values, calldatas, description)` interface. There is no typed `ProposalType` enum — the calldata encodes the target contract call directly.

### Example 1: Adjust Liquidation Threshold

**Scenario:** Market conditions improve, healthy cattle can support higher LTV.

```solidity
address[] memory targets = new address[](1);
targets[0] = address(vault);

uint256[] memory values = new uint256[](1);
values[0] = 0;

bytes[] memory calldatas = new bytes[](1);
calldatas[0] = abi.encodeWithSignature("setLiquidationThreshold(uint256)", 75);

governor.propose(targets, values, calldatas, "Update liquidation threshold to 75%");
```

**Impact:**
- Healthy cattle (score > 80): LTV increases from 69.5% to ~74%
- Ranchers can borrow more against same collateral
- Increases capital efficiency for healthy herds

### Example 2: Add New Collateral Type

**Scenario:** Carbon credit NFTs become widely adopted and want to accept as collateral.

```solidity
address[] memory targets = new address[](1);
targets[0] = address(vault);

uint256[] memory values = new uint256[](1);
values[0] = 0;

bytes[] memory calldatas = new bytes[](1);
calldatas[0] = abi.encodeWithSignature("addCollateralType(address)", address(carbonCreditNFT));

governor.propose(targets, values, calldatas, "Add carbon credit NFT as collateral");
```

**Impact:**
- Ranchers can use carbon credit NFTs as additional collateral
- Incentivizes sustainable farming practices
- Diversifies collateral base

### Example 3: Update Interest Rate Model

**Scenario:** Protocol needs more liquidity, raises base interest rate.

```solidity
address[] memory targets = new address[](1);
targets[0] = address(vault);

uint256[] memory values = new uint256[](1);
values[0] = 0;

bytes[] memory calldatas = new bytes[](1);
calldatas[0] = abi.encodeWithSignature("setBaseInterestRate(uint256)", 12e18);

governor.propose(targets, values, calldatas, "Raise base interest rate to 12% APR");
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

The implementation uses simple token-weighted voting (1 token = 1 vote). Voting power is derived from `token.balanceOf(account)` rather than a checkpointed `getPastVotes()` snapshot — this is a v1 simplification (see [Future Enhancements](#future-enhancements)).

```solidity
function getVotes(address account, uint256 blockNumber) public view override returns (uint256) {
    return token.balanceOf(account); // Simplified: current balance, not historical
}
```

### Proposal Threshold

- **Minimum tokens to create proposal:** 1 RANCH (`MIN_PROPOSAL_THRESHOLD = 1e18`)
- **Quorum requirement:** 10% of total supply (`token.totalSupply() / 10`) in For + Abstain votes
- **Voting period:** Immutable `_votingPeriod` (set at deploy time, in blocks)
- **Voting delay:** Immutable `_votingDelay` (set at deploy time, in blocks)
- **Timelock delay:** None (TimelockController removed — see [Key Design Decisions](#key-design-decisions))

## Security Considerations

### 1. No Timelock in v1

The original design called for a 7-day `TimelockController` delay before execution. This was **removed** because the `TimelockController` API in OpenZeppelin v5.1.0 is incompatible with the `Governor` base contract's expected interface. Without a timelock, approved proposals execute immediately after the voting period ends.

**Mitigations in v1:**
- The voting period itself provides a review window (immutable `_votingPeriod` blocks)
- `PROPOSER_ROLE` is gated — only authorized accounts can create proposals
- `VOTER_ROLE` is gated — only authorized accounts can vote
- Quorum (10% of supply) must be reached

**Future:** Re-add a timelock when OZ v5.2+ resolves the Governor compatibility issue (see [Future Enhancements](#future-enhancements)).

### 2. Simple Token-Weighted Voting

The implementation uses **simple token-weighted voting** (1 token = 1 vote), not quadratic voting. This means larger holders have proportionally more influence. The original design's quadratic voting was not implemented in v1.

**Mitigations:**
- Quorum requirement (10% of supply) ensures broad participation
- `VOTER_ROLE` gating limits who can participate
- Future versions may add quadratic voting as an option

### 3. Proposal Validation

All proposals must:
- Be submitted by an account holding `PROPOSER_ROLE`
- Include `targets`, `values`, and `calldatas` arrays of equal length
- Be backed by at least `MIN_PROPOSAL_THRESHOLD` (1e18) tokens
- Pass quorum (10% of supply) and `yesVotes > noVotes` to succeed

### 4. Role-Based Access Control

The contract uses OpenZeppelin `AccessControl` with three roles:

| Role | Permission |
|------|-----------|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke roles, manage voters |
| `PROPOSER_ROLE` | Create proposals |
| `VOTER_ROLE` | Cast votes on proposals |

The deployer receives `PROPOSER_ROLE` at construction. `DEFAULT_ADMIN_ROLE` is granted to the contract itself. Voters are added/removed via `grantVoterRole()` / `revokeVoterRole()` by admins.

## Testing Strategy

### Unit Tests (Foundry)

1. **Proposal Creation:**
   - Verify proposal ID is derived from `hashProposal(targets, values, calldatas, descriptionHash)`
   - Check `ProposalCreated` event emission
   - Test threshold enforcement (below `MIN_PROPOSAL_THRESHOLD` fails)
   - Verify `PROPOSER_ROLE` is required

2. **Voting:**
   - Token-weighted vote counting (yes / no / abstain)
   - `VOTER_ROLE` enforcement
   - Double-vote prevention via `_votesCast` mapping
   - Quorum (10% of `totalSupply`) enforcement

3. **Execution:**
   - Cannot execute before voting period ends
   - `_voteSucceeded` checks `yesVotes > noVotes` and quorum
   - `ProposalExecuted` event emitted

4. **Role Management:**
   - `grantVoterRole` / `revokeVoterRole` (admin only)
   - `PROPOSER_ROLE` granted to deployer at construction

### Integration Tests

```bash
# Full governance flow test
forge script test/GovernanceFlow.t.sol --broadcast

# Test scenario: Update liquidation threshold from 70% to 75%
1. Deploy GovernorRanch (no TimelockController)
2. Distribute RANCH tokens to test voters
3. Grant VOTER_ROLE to test accounts
4. Proposer creates proposal (holds >= 1 RANCH + PROPOSER_ROLE)
5. Voters cast FOR votes (>= 10% of total supply)
6. Wait for voting period to end
7. Execute proposal
8. Verify vault liquidation threshold is now 75%
```

## Deployment Strategy

### Phase 1: Testnet Governance

1. Deploy GovernorRanch to Polygon Amoy (no TimelockController needed)
2. Distribute test RANCH tokens to beta testers
3. Grant `VOTER_ROLE` to test accounts
4. Run mock proposals (no real parameter changes)
5. Gather feedback on UX and voting mechanics

### Phase 2: Mainnet Pilot

1. Deploy to Polygon PoS mainnet
2. Distribute a portion of total supply to early users
3. Start with conservative proposals (parameter tweaks only)
4. Monitor for governance attacks or manipulation

### Phase 3: Full DAO Launch

1. Distribute remaining tokens via liquidity mining + airdrops
2. Open `PROPOSER_ROLE` to broader community
3. Consider delegating voting power to specialized delegates
4. Integrate with Snapshot for off-chain signaling

## Key Design Decisions

This section explains the significant deviations from the original design doc, all driven by constraints in OpenZeppelin v5.1.0.

### 1. Why TimelockController was removed

The original design specified a `TimelockController` with a 7-day execution delay. In OpenZeppelin v5.1.0, the `Governor` base contract's constructor and internal API changed such that integrating `TimelockController` cleanly is not possible without significant custom plumbing. Rather than ship a fragile integration, the timelock was removed for v1. The voting period (immutable `_votingPeriod`) provides the primary review window. A timelock will be re-added when OZ v5.2+ resolves the compatibility issue.

### 2. Why voting parameters are immutable

OpenZeppelin v5.1.0's `Governor` does not expose `_setVotingDelay()` / `_setVotingPeriod()` setter functions. The only way to configure `votingDelay()` and `votingPeriod()` is to override them and return a stored value. Since there are no setters, the values are set once in the constructor and stored in `immutable` variables. This means voting delay and period **cannot be changed after deployment** — a new Governor deployment would be required to change them.

### 3. Why `balanceOf` instead of `getPastVotes`

The original design used `ERC20Votes` with checkpointed `getPastVotes()` for snapshot-based voting. The actual implementation uses plain `ERC20` (RanchToken) and `getVotes()` returns `token.balanceOf(account)` — the **current** balance, not a historical snapshot. This is a v1 simplification:

- **Trade-off:** Simpler token contract, no checkpointing overhead, but voting power can change during the voting period (e.g., if tokens are transferred).
- **Future:** Switch to `getPastVotes()` for proper snapshot-based voting when RanchToken is upgraded to `ERC20Votes`.

### 4. Why a custom `_votesCast` mapping

OpenZeppelin v5.1.0's `Governor` does not expose `_getReceipt()` (the function that tracks whether an account has voted on a proposal). To implement `hasVoted()`, the contract maintains a custom `mapping(uint256 => mapping(address => bool)) _votesCast` that is updated in `_countVote()`. This is the standard workaround for OZ v5.1.0 Governor.

### 5. Why `supportsInterface` needs an explicit override

Both `Governor` and `AccessControl` declare `supportsInterface(bytes4)`. When a contract inherits both, the Solidity compiler requires an explicit override that resolves the conflict. The implementation uses:

```solidity
function supportsInterface(bytes4 interfaceId)
    public view virtual override(Governor, AccessControl) returns (bool)
{
    return super.supportsInterface(interfaceId);
}
```

Without this, compilation fails with "Two or more functions have the same name and parameter types."

## Future Enhancements

1. **Re-add TimelockController** when OpenZeppelin v5.2+ resolves the Governor compatibility issue — restores the safety window between approval and execution.
2. **Switch from `balanceOf` to `getPastVotes`** for snapshot-based voting — requires upgrading RanchToken to `ERC20Votes` with checkpointing.
3. **Add quadratic voting option** — the original design's `sqrt(weight)` approach to prevent whale dominance; could be added as a counting mode.
4. **Add proposal types enum** — structured governance with typed proposals (parameter updates, collateral additions, fee changes, vault upgrades) for better UX and validation.
5. **Integration with FractionalizationManager** — allow fractional shareholders to vote on cow management decisions (e.g., breeding, veterinary care, sale timing).
6. **Delegation:** Allow token holders to delegate voting power to experts.
7. **Multisig Integration:** Require 3-of-5 multisig approval for critical changes.
8. **Reputation System:** Track proposal success rate, reward good governance participants.
9. **SubDAOs:** Create specialized committees (risk, technical, community).
10. **Cross-chain Governance:** Extend to Base, Arbitrum deployments.

## Metrics & KPIs

Track these metrics post-launch:

1. **Participation Rate:** % of supply voting on proposals
   - Target: > 20% (healthy governance)
   
2. **Proposal Success Rate:** Proposals executed / proposals created
   - Target: 60-80% (not too easy, not too hard)
   
3. **Average Voting Time:** Days from creation to execution
   - Target: 3-7 days (voting delay + voting period, no timelock in v1)
   
4. **Governance Attacks:** Failed malicious proposals
   - Target: 0 (design should prevent these)
   
5. **Delegate Concentration:** % of votes held by top 10 delegates
   - Target: < 50% (decentralized voting power)

---

**Next Steps:**
1. ✅ GovernorRanch.sol implemented in `src/GovernorRanch.sol`
2. Deploy to Polygon Amoy testnet for beta testing
3. Run mock governance cycles to validate UX
4. Integrate with RanchLendingVault parameter update functions
5. Re-add TimelockController when OZ v5.2+ is available

**Estimated Timeline:** 1-2 weeks for testnet pilot (implementation complete)
