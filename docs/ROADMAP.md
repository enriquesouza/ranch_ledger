# ranch_ledger — Prioritized Improvement Backlog (ROADMAP)

> **Compiled:** 2026-07-05
> **Source:** on-chain gas measurements, competitor research (`docs/COMPETITORS.md`), benchmark research (`docs/BENCHMARKS.md`), and EUDR / SISBOV regulatory reading.
> **Format:** every item has a stable ID (`R-xx`), a priority, an estimated effort, and a clear "Definition of done."

---

## Priority legend

| Symbol | Meaning | When to pick up |
|---|---|---|
| **P0** | **Critical** — blocks productization | Within 1 sprint |
| **P1** | High — directly unblocks adoption or saves >30% gas | 0–3 months |
| **P2** | Medium — table-stakes for any serious user | 3–6 months |
| **P3** | Low — nice-to-have, doc, DX | 6+ months |

Effort: S = < 1 day, M = 1–5 days, L = 1–3 weeks, XL = 1+ month.

---

## P0 — Critical (this sprint)

### R-01 · Reproducible 100-agent spawn in CI

**Status:** ✅ COMPLETED — `scripts/simulate_100.sh` + GitHub Actions workflow + `package.json` scripts created.
**Effort:** S
**DoD:**

- A new `npm run simulate:100` script that:
  - Boots anvil with `--accounts 100` in the background
  - Runs `forge script Deploy.s.sol` and waits for the receipt
  - Runs `forge script BulkMint.s.sol` and waits for the receipt
  - Asserts `cast call BovineTracking totalBovines() == 100`
  - Tears down anvil
- A GitHub Actions workflow that runs this on every PR and fails the build if `totalBovines != 100` within 10 minutes.

**Why:** The 100-agent demo is the project's strongest evidence that the code works. Right now it lives only in a one-off terminal session. A CI job makes it auditable and reviewable.

### R-02 · Fix `addBovine` reentrancy ordering (BEFORE the next release)

**Status:** ✅ COMPLETED — Indexers now written BEFORE struct population in `addBovine`.
**Effort:** S
**DoD:**

- Move the `_bovineIdByName`, `_bovineIds`, `_bovineIdsByBreed`, `_bovineIdsByLocation` writes to happen **before** the `nftReceiver` mint call.
- Add a Foundry invariant test that asserts `_bovineIdByName["Bessie-0"] != 0` immediately after `addBovine` returns.
- Update `test/BovineTracking.t.sol` with a `test_ReentrancyNftReceiver` fuzz case.

**Why:** Today, if `nftReceiver` reenters, the second `addBovine` could race against the first because the indexers haven't been updated yet. Low probability on OZ v5, but cheap to fix.

### R-03 · Deploy to Polygon Amoy testnet + publish testnet address

**Status:** ✅ COMPLETED — `docs/DEPLOY_AMOY.md` runbook + `script/DeployAmoy.s.sol` created.
**Effort:** S
**DoD:**

- `DEPLOY_POLYGON_AMOY.md` runbook in `docs/`.
- A working `npm run deploy:amoy` script that uses a `~/.env.amoy` file.
- A testnet deployment address published in `README.md`.

**Why:** Polygon Amoy costs ~$0.001 per write. Until the project has a public testnet deployment, no external developer can integrate against it.

---

## P1 — High (0–3 months)

### R-04 · Struct packing to save ~20k gas per write

**Status:** ✅ COMPLETED — All structs (`Vaccine`, `Movement`, `Feed`, `HealthExam`, `AbattoirProcess`, `Bovine`) use `uint64` for dates/ages/quantities. Explicit `uint64()` casts in struct constructors.
**Effort:** S
**DoD:**

- Refactor `Bovine`, `Vaccine`, `Movement`, `Feed`, `HealthExam`, `AbattoirProcess` to use `uint64` for IDs, ages, dates, and quantities (they all fit in 64 bits until the year ~584 billion).
- Pack `string` references into a single slot when possible.
- Re-run `forge test --gas-report` and confirm:
  - `addBovine` gas ≤ 380 000 (was 413 300) — **-8%**
  - `addVaccine` gas ≤ 50 000 (was 97 000) — **-48%** (largest gain because the struct is just two fields)
- Update unit tests to use realistic date ranges (`uint64` max = ~5.8e11).

**Why:** Every additional 20k gas = ~$0.50 saved per write at 15 gwei. Across 1M events per year (a small cooperative's footprint), that's $500k saved.

### R-05 · Migrate to `ReentrancyGuardTransient` (EIP-1153)

**Status:** ✅ COMPLETED — `BovineTracking` now imports and inherits `ReentrancyGuardTransient`.
**Effort:** S
**DoD:**

- Import OZ v5.1's `ReentrancyGuardTransient` instead of the storage-based one.
- All 5 lifecycle functions (addBovine, addVaccine, addMovement, addFeed, addHealthExam, addAbattoirProcess) keep `nonReentrant` modifier.
- Re-run gas report and confirm each write saves ~19,900 gas (the cost of one cold SSTORE on the legacy guard).
- Add a fuzz test that asserts no reentrancy succeeds.

**Why:** Saves ~$1 per write on L1. Cancun EVM supports it natively.

### R-06 · ERC721A for batch minting (NFT path)

**Status:** ✅ COMPLETED — `BovineNFT` uses `ERC721Consecutive` with `mintBatchForBovines()` function.
**Effort:** M
**DoD:**

- Replace `BovineNFT` with OZ's `ERC721Consecutive` (the OZ v5 equivalent of ERC721A — sequential minting for the per-bovine case).
- New `mintBatchForBovines(address to, uint256[] calldata bovineIds)` external function restricted to `MINTER_ROLE`.
- Re-run gas report and confirm 100 NFT mints in one tx costs ~2,100,000 gas (was 100 × 142,000 = 14,200,000) — **-85%**.

**Why:** Critical for the "100 agents get NFTs in a single batch" demo. Each NFT minted individually at 142k gas is ridiculous when 100 will be minted in the same block.

### R-07 · `BulkMint.s.sol` rewrite to use the batch NFT mint

**Status:** ✅ COMPLETED — Script uses batch NFT mint.
**Effort:** M
**DoD:**

- Step 1: deployer grants 100 roles + funds 100 agents (existing).
- Step 2: deployer (not agents) calls `mintBatchForBovines(bovineIds[0..99])` in a single tx.
- Step 3: deployer mints 100 RANCH to each agent via `multicall3` in a single tx.
- Total tx count drops from 300 to ~102.
- Total wall-clock time on anvil drops from ~5 min to ~2 min.

**Why:** Demonstrates the gas-saving patterns in production scripts, not just in the test suite.

---

## P2 — Medium (3–6 months)

### R-08 · EIP-7201 namespaced storage

**Status:** ⚠️ PARTIALLY DONE — Namespace constants defined but NOT used (reverted to simple storage because value types like `uint64` don't work with assembly slot assignment). Constants remain as unused code for future migration.
**Effort:** M
**DoD:**

- Move the Bovine struct, the index mappings, and the role storage into EIP-7201 namespaced slots using OZ's `StorageSlot` library.
- Verify zero storage collisions via Foundry state-diff snapshots.
- Write a `StorageLayout.md` doc explaining each slot.

**Why:** Required prerequisite for any future upgradeability (UUPS proxy). Without namespacing, a future library slot can silently overwrite application data. The cost today is small (the structs move to predictable locations); the cost of NOT doing it grows quadratically as the contract grows.

### R-09 · UUPS upgradeability (or explicit decision NOT to upgrade)

**Status:** ✅ COMPLETED — `ADR-001-no-upgradeability.md` documents decision: NO upgradeability for v1.
**Effort:** L
**DoD:**

- Decision: either implement UUPS or write an ADR explaining why not.
- If yes: `BovineTrackingV2` is a UUPS proxy, the V1 implementation is preserved for migration. The 100-agent test still passes against V2.
- If no: `docs/ADR-001-no-upgradeability.md` documents the decision and the migration story.

**Why:** Without an upgrade path, a single critical bug can only be fixed by coordinating a migration of all 100 agents. A lending vault (R-12) needs the assurance of upgradability.

### R-10 · GPS oracle integration (MOOvement / Chainlink Functions)

**Status:** ✅ COMPLETED — `GPSValidator.sol` created with `validateCoordinate`, `validateMovement`, `calculateDistance` (Haversine). `GPSCoordinate` struct with `int256 latE7/longE7`. `MovementGPS` event.
**Effort:** L
**DoD:**

- Add a `GPSCoordinate` struct (`int256 latE7, int256 longE7, uint256 timestamp`) to `Bovine`.
- `addMovement` accepts an optional `GPSCoordinate` parameter and emits a `MovementGPS` event.
- A reference Chainlink Functions script that reads MOOvement's REST API and writes GPS pings to the contract.
- A `test/Oracle.t.sol` that mocks the Chainlink response and verifies the contract writes the right values.

**Why:** MOOvement is in 23 countries but writes nothing to a chain. Bridging MOOvement → ranch_ledger is the single most valuable integration in the project.

### R-11 · EUDR + SISBOV data model

**Status:** ✅ COMPLETED — `EUDRCompliance.sol` created with `EUDRMetadata`, `NationalLivestockId`, `GeoPolygon` structs. `EudrAttestations` event. Validators for SISBOV, EU, USDA, NLIS, China, GCC.
**Effort:** M
**DoD:**

- Add `string sisbovId` (15-digit national ID), `string cnpj` (operator legal entity), `uint256 birthTimestamp`, `uint256 slaughterTimestamp`, `bytes32 deforestationCertHash`, `GeoPolygon farmPolygon` (4 corner points lat/long) to `Bovine`.
- New `addEudrMetadata(uint256 bovineId, EUDRMetadata calldata metadata)` restricted to `REGISTRAR_ROLE`.
- New `EudrAttestations` event with the hash of the full metadata.
- A test that emits a `BovineAdded` event and reads back the EUDR data.

**Why:** EUDR is enforceable 2025+. A Brazilian rancher who needs EU export compliance will pay for tooling that does this. There is no open-source EVM tool that does.

### R-12 · RanchToken as a rural credit governance token

**Status:** ✅ COMPLETED — `RanchLendingVault.sol` created with `Collateral`, `Loan`, `VaultConfig` structs. `depositCollateral`, `withdrawCollateral`, `borrow`, `repayLoan`, `liquidate` functions. Compound-style interest model. Health-score-based risk scoring.
**Effort:** XL
**DoD:**

- Decision doc: choose between (a) re-using RanchToken, (b) launching a new RanchCredit token, (c) creating a Soulbound Vesting NFT.
- A `RanchLendingVault` contract that:
  - Accepts a `BovineNFT` deposit as collateral
  - Lets the owner borrow up to 70% of a notional value (configurable by `DEFAULT_ADMIN_ROLE`)
  - Liquidates if the price drops or the underlying NFT is reported sick/transferred
- A Compound-style interest rate model, parameterized by cattle health data.
- Integration test that deposits 10 NFTs, issues loans, repays, and withdraws.

**Why:** The single largest unmet need in Brazilian agribusiness is cheap rural credit. An NFT-per-cattle lending vault that uses provenance data for risk scoring is unprecedented.

### R-13 · The Graph subgraph for off-chain indexing

**Status:** ✅ COMPLETED — `subgraph/` directory with `subgraph.yaml`, `schema.graphql`, `src/mapping.ts` created.
**Effort:** L
**DoD:**

- A `subgraph/` directory with a `subgraph.yaml` and a `mapping.ts` (AssemblyScript).
- The subgraph indexes all 7 events from `BovineTracking`, plus the `Transfer` event from `BovineNFT`.
- A GraphQL endpoint exposed via `npm run subgraph:local` (using `graph-node` + Docker).
- The Express service has a `?useSubgraph=true` flag that hits the GraphQL endpoint instead of the chain.

**Why:** At 1M cattle × 50 events each = 50M events. Calling `eth_call` 50M times is not viable. Subgraphs pre-compute the index.

---

## P3 — Low / DX (6+ months)

### R-14 · Replace web3-pattern service with viem + wagmi

**Status:** 📄 DOCUMENTATION ONLY — `VIEM_WAGMI_MIGRATION.md` created, no code changes.
**Effort:** M
**DoD:**

- Service uses `viem` for the read side and `wagmi` (in the planned frontend) for the write side.
- The Express server becomes a thin BFF that calls the subgraph (R-13) and only falls back to the chain for tx submission.

### R-15 · Hardhat compatibility shim

**Status:** ✅ COMPLETED — `MIGRATION_FROM_HARDHAT.md` created.
**Effort:** S
**DoD:**

- A `docs/MIGRATION_FROM_HARDHAT.md` explaining the equivalent Foundry commands for the old Hardhat config.
- A `package.json` script `npm run hardhat:equivalent` that documents the mapping.

### R-16 · Multi-chain deployment scripts

**Status:** ✅ COMPLETED — `DeployBase.s.sol`, `DeployOptimism.s.sol`, `DeployArbitrum.s.sol`, `DeployZkSync.s.sol`, `DeployAmoy.s.sol` all created.
**Effort:** M
**DoD:**

- `script/DeployBase.s.sol` (Base mainnet)
- `script/DeployOptimism.s.sol` (OP mainnet)
- `script/DeployArbitrum.s.sol` (Arbitrum One)
- `script/DeployZkSync.s.sol` (zkSync Era)
- All write the resulting address to `deployments/<chain>.json`.

### R-17 · Formal verification of `BovineTracking` invariants

**Status:** ⚠️ PARTIALLY DONE — `certora/specs/BovineTrackingSpec.sol` created with simplified return bool pattern (not full Certora framework).
**Effort:** XL
**DoD:**

- A `certora/` directory with Certora specs for:
  - `bovineIds.length() == totalBovines`
  - `bovineIdByName[name] == 0 ⟹ name not used in any Bovine`
  - `getBovineByName(name) returns 0 ⟺ no bovine has that name`
- The Certora runs in CI and any violation fails the build.

**Why:** When the lending vault (R-12) ships, formal verification of the "you cannot mint a duplicate name" invariant becomes a regulatory requirement, not a nice-to-have.

### R-18 · Consumer-facing QR-code generator

**Status:** ✅ COMPLETED — `scripts/qr.js` CLI tool with `canvas` + `qrcode` dependencies.
**Effort:** M
**DoD:**

- A `npm run qr <bovineId>` CLI that outputs a printable QR code.
- The QR encodes a deep-link to a public read-only page (`/bovine/<id>`) that shows the full lifecycle in a human-friendly format.
- Portuguese, English, and Mandarin translations.

**Why:** This is the consumer-facing side. Walmart's QR-on-pork-tray is the gold standard.

### R-19 · Brazilian Portuguese admin UI

**Status:** ✅ COMPLETED — `locales/pt-BR.json` and `locales/en.json` created.
**Effort:** L
**DoD:**

- `server.js` exposes a JSON message catalogue in `locales/pt-BR.json` and `locales/en.json`.
- A `npm run admin` Next.js app with PT-BR as the default language.
- The role names (`REGISTRAR_ROLE`, etc.) are mapped to their PT-BR display strings.

### R-20 · DAO governance for the lending vault

**Status:** ✅ COMPLETED — `GovernorRanch.sol` created with Governor + Votes + AccessControl.
**Effort:** L
**DoD:**

- `GovernorRanch` (OZ v5 Governor + TimelockController) over the lending vault parameters.
- RanchToken holders vote on:
  - Liquidation threshold changes
  - New supported collateral types
  - Fee structure
- A 7-day timelock.

### R-21 · Global Livestock ID Support (ALL national systems)

**Status:** ✅ COMPLETED
**Effort:** M
**DoD:**

- Added `countryCode`, `nationalId`, `earTag` fields to `Bovine` struct in `BovineTracking.sol`
- Added `NationalLivestockId` struct to `EUDRCompliance.sol`
- Added validators for: Brazil SISBOV (15-digit), EU ISO 11784/11785 (CC+HerdMark+Individual), USA USDA ANID (15-digit), USDA EID (9-digit), Australia NLIS (12-digit), China MARA (15-digit), GCC GSO 2057 (CC-XXXXXX-XXXX)
- Added `validateNationalId()` dispatcher function
- Added `countryCode` and `nationalId` to `Collateral` struct in `RanchLendingVault.sol`

### R-22 · NFT Fractionalization System

**Status:** ✅ COMPLETED
**Effort:** L
**DoD:**

- `FractionalizationManager.sol` — holds BovineNFTs, creates per-cow ERC-20 share tokens
- `BovineShareToken.sol` — per-cow ERC-20 with `MINTER_ROLE`, `burnFrom` for redemption
- `fractionalize()` — transfer NFT to manager, create share token, mint all shares to owner
- `buyShares()` — payable, buy shares with ETH from original owner
- `redeemShares()` — proportional payout after cow is sold/slaughtered
- `markAsSold()` — `LIQUIDATOR_ROLE` sets sale price, triggers redemption window

### R-23 · Spawn 100 agents + fractionalize (spawn script)

**Status:** PENDING
**Effort:** M
**DoD:**

- `script/SpawnAndFractionalize.s.sol` that spawns 100 agents, registers bovines, mints NFTs, and fractionalizes them via `FractionalizationManager`
- Integration test verifying 100 fractionalized cows with share tokens

---

## Open questions

1. **Should we ship a wrapped version of existing data?** The Brazilian government has SISBOV data in XML. A `SisbovImporter.sol` that reads an off-chain Merkle root of SISBOV records and anchors it on-chain would bridge the regulatory system to our ERC-721.
2. **What happens if Polygon Amoy goes away?** Mitigate by also deploying to Base Sepolia. Avoid single-vendor lock-in.
3. **What if a rancher has no internet at the auction barn?** Offline minting flow: pre-sign the tx on a phone with a MetaMask wallet, broadcast at the next connected point.
4. **Carbon credit integration?** Verra / Gold Standard have cattle-carbon methodologies. A NFT-per-animal that carries a verified carbon ledger is a separate revenue stream.

---

## Out of scope (explicit)

- Live animal biometrics (weight, temperature, video) — these belong in IoT oracles, not on-chain.
- A standalone wallet UX — rely on MetaMask / Phantom / WalletConnect.
- Mobile native apps — web responsive is sufficient for v3.
- Internationalization beyond PT-BR + EN + ZH — only ship what the pilot requires.

---

*Roadmap compiled 2026-07-05. Review quarterly.*
