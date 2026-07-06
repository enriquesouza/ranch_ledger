# EIP-7201 Namespaced Storage Implementation Guide

## Overview

This document provides a reference implementation for migrating BovineTracking to use EIP-7201 namespaced storage slots. This is a prerequisite for future upgradeability (UUPS proxy pattern).

**Why EIP-7201?**
- Prevents storage collisions between contract versions
- Enables safe upgrades without data migration
- Required for UUPS proxy pattern compatibility
- Makes storage layout auditable and predictable

## Current Status

**⚠️ Attempted and Reverted — Using Simple Storage**

The EIP-7201 namespaced storage migration was attempted but reverted to simple storage variables. The namespace constants (`BOVINES_SLOT`, `ID_BY_NAME_SLOT`, etc.) remain in `BovineTracking.sol` as unused constants for future reference, but the actual storage uses simple `mapping` and `uint256` declarations.

**Why it was reverted:**

The `assembly { $.slot := NAMESPACE_SLOT }` pattern works for mappings, structs, and arrays, but **fails for value types** (uint256, address, bool). When we tried to move `totalBovines` (uint256) and `nftReceiver` (address) to namespaced slots, the Solidity compiler rejected the assembly slot assignment for value types.

Specifically:
```solidity
// ✅ Works for mappings:
function _getBovinesMapping() internal pure returns (mapping(uint256 => Bovine) storage $) {
    assembly { $.slot := BOVINES_SLOT }
}

// ❌ Fails for value types:
function _getTotalBovines() internal pure returns (uint256 storage $) {
    assembly { $.slot := TOTAL_BOVINES_SLOT }  // Error: uint256 is not a storage reference type
}
```

The `StorageSlot` library from OpenZeppelin provides `getUint256Slot()` and `getAddressSlot()`, but these require a different access pattern that would make the code less readable and more error-prone for simple value types.

**Decision:** Keep simple storage variables for v1. The namespace constants remain as documentation of the intended slot locations for a future migration. When EIP-7201 tooling matures (or when we need upgradeability via UUPS), we can revisit this.

## Implementation Strategy

### Step 1: Add StorageSlot Library Dependency

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-commit
# Already installed, but verify StorageSlot is available
ls lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol
```

### Step 2: Compute Namespaced Slots

> **Note:** Steps 2–4 were attempted during implementation. The value-type limitation described in the "Current Status" section above was discovered during Step 3/4 when trying to apply the pattern to `totalBovines` (uint256) and `nftReceiver` (address). The migration was reverted as a result.

Use `keccak256(abi.encodePacked("ranch_ledger.storage.", <namespace>))` to generate deterministic slots.

**Current Storage Layout (BovineTracking):**
```solidity
// Slot 0: _bovines mapping
mapping(uint256 => Bovine) private _bovines;

// Slot 1: _bovineIdByName mapping  
mapping(string => uint256) private _bovineIdByName;

// Slot 2-3: _bovineIdsByBreed/_bovineIdsByLocation mappings
mapping(string => EnumerableSet.UintSet) private _bovineIdsByBreed;
mapping(string => EnumerableSet.UintSet) private _bovineIdsByLocation;

// Slot 4: _bovineIds set
EnumerableSet.UintSet private _bovineIds;

// Slot 5: totalBovines counter
uint256 public totalBovines;

// Slot 6: nftReceiver address
address public nftReceiver;
```

**Proposed Namespaced Layout:**
```solidity
bytes32 constant BOVINES_SLOT = keccak256(abi.encodePacked("ranch_ledger.storage.bovines"));
bytes32 constant ID_BY_NAME_SLOT = keccak256(abi.encodePacked("ranch_ledger.storage.idByName"));
bytes32 constant IDS_BY_BREED_SLOT = keccak256(abi.encodePacked("ranch_ledger.storage.idsByBreed"));
bytes32 constant IDS_BY_LOCATION_SLOT = keccak256(abi.encodePacked("ranch_ledger.storage.idsByLocation"));
bytes32 constant ALL_IDS_SLOT = keccak256(abi.encodePacked("ranch_ledger.storage.allIds"));
bytes32 constant TOTAL_BOVINES_SLOT = keccak256(abi.encodePacked("ranch_ledger.storage.totalBovines"));
bytes32 constant NFT_RECEIVER_SLOT = keccak256(abi.encodePacked("ranch_ledger.storage.nftReceiver"));
```

### Step 3: Refactor Storage Access

Replace direct storage access with `StorageSlot` library calls:

**Before:**
```solidity
mapping(uint256 => Bovine) private _bovines;

function getBovine(uint256 id) external view returns (Bovine memory) {
    return _bovines[id];
}
```

**After:**
```solidity
function _getBoivnesMapping() internal pure returns (mapping(uint256 => Bovine) storage $) {
    $.slot = BOVINES_SLOT;
}

function getBovine(uint256 id) external view returns (Bovine memory) {
    return _getBoivnesMapping()[id];
}
```

### Step 4: Update All Storage Operations

Apply the same pattern to:
- `_bovineIdByName` → `ID_BY_NAME_SLOT`
- `_bovineIdsByBreed` → `IDS_BY_BREED_SLOT`
- `_bovineIdsByLocation` → `IDS_BY_LOCATION_SLOT`
- `_bovineIds` → `ALL_IDS_SLOT`
- `totalBovines` → `TOTAL_BOVINES_SLOT`
- `nftReceiver` → `NFT_RECEIVER_SLOT`

### Step 5: Verify Zero Storage Collisions

Run Foundry state-diff snapshots to ensure no collisions:

```bash
# Deploy V1 (current implementation)
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

# Take snapshot
cast storage <contract_address> 0
cast storage <contract_address> 1
# ... continue for all slots

# Deploy V2 (namespaced implementation)
forge script script/DeployNamespaced.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

# Compare snapshots - should be identical layout
```

### Step 6: Write StorageLayout.md

Create `docs/StorageLayout.md` documenting each slot's purpose and namespace.

## Lessons Learned

1. **EIP-7201 works well for complex types (mappings, structs, arrays) but not for value types (uint256, address, bool).** The `assembly { $.slot := ... }` pattern requires a storage reference type, which value types are not.

2. **The `StorageSlot` library is a workaround but adds complexity.** Using `StorageSlot.getUint256Slot(slot).value` for every access to `totalBovines` would make the code harder to read and maintain.

3. **Namespace constants are still useful as documentation.** Even though they're not used in assembly, they document the intended storage layout for future migration.

4. **Consider EIP-7201 for new contracts from the start.** For new contracts (like RanchLendingVault, FractionalizationManager), we could design with EIP-7201 from the beginning, using only complex types in namespaced storage and keeping value types in simple storage.

5. **OpenZeppelin v5.1.0's StorageSlot library provides:** `getBooleanSlot()`, `getBytes32Slot()`, `getUint256Slot()`, `getInt256Slot()`, `getAddressSlot()`, `getStringSlot()`, `getBytesSlot()`. These can be used for value types but require a different access pattern.

## Migration Path

### Option A: In-Place Refactor (Recommended for New Deployments)

1. Implement namespaced storage in a new contract version
2. Deploy to testnet/mainnet
3. Migrate existing data via upgrade function or manual transfer
4. Deprecate old contract

**Pros:** Clean implementation, no legacy code
**Cons:** Requires migration strategy for existing deployments

### Option B: Dual-Storage (For Existing Deployments)

1. Keep current storage layout unchanged
2. Add namespaced storage as parallel structure
3. Migrate data on first write to each bovine
4. Deprecate old storage after full migration

**Pros:** No breaking changes, gradual migration
**Cons:** Double storage costs during migration period

## Testing Requirements

1. **Unit Tests:** All existing tests must pass with namespaced storage
2. **State Diff Tests:** Verify slot assignments match expected layout
3. **Upgrade Tests:** Ensure V1 → V2 upgrade preserves all data
4. **Gas Tests:** Confirm no significant gas overhead from indirection

## Gas Impact

EIP-7201 adds one SLOAD per storage access (to compute the slot). Expected impact:
- Read operations: +5,000 gas (one extra SLOAD)
- Write operations: +5,000 gas (one extra SLOAD)
- **Net effect:** Minimal for most use cases

## Security Considerations

1. **Slot Computation:** Use constant expressions for slot hashes (compile-time evaluation)
2. **Namespace Collisions:** Ensure no overlap with OpenZeppelin library slots
3. **Upgrade Safety:** Verify proxy pattern compatibility before mainnet deployment

## Next Steps

1. Implement namespaced storage in a feature branch
2. Run full test suite to verify correctness
3. Create ADR-001 documenting the upgradeability decision (R-09)
4. If approved, deploy UUPS proxy with V2 implementation (R-09)

---

**Status:** Attempted and reverted — using simple storage (see Current Status)  
**Priority:** P2 (Medium)  
**Effort:** M (1-5 days)  
**Dependencies:** R-09 (UUPS upgradeability decision)
