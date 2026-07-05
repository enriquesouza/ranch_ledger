# ranch_ledger — On-Chain Livestock Data: Technical Benchmarks

> **Reference project:** `ranch_ledger` — Solidity 0.8.28 / Foundry / OpenZeppelin v5.x.  
> **Data captured:** July 2026.  
> **ETH price assumption:** $3 500 USD (use the scaling tables to recalculate at any price).  
> **Gas-report source:** `forge test --gas-report` against commit at time of writing (all 17 tests pass).

---

## Table of Contents

1. [Gas Costs — Key Write Operations](#1-gas-costs--key-write-operations)
2. [Storage Cost Over Time](#2-storage-cost-over-time)
3. [L1 vs L2 Comparison](#3-l1-vs-l2-comparison)
4. [Throughput & Data Availability](#4-throughput--data-availability)
5. [Off-Chain Storage Alternatives](#5-off-chain-storage-alternatives)
6. [Data Model Alternatives](#6-data-model-alternatives)
7. [OpenZeppelin Gas-Saver Patterns](#7-openzeppelin-gas-saver-patterns)
8. [Industry Standards](#8-industry-standards)
9. [Real-World Pilot Data](#9-real-world-pilot-data)
10. [Performance Headroom — 1 000 000 Cattle](#10-performance-headroom--1-000-000-cattle)

---

## 1. Gas Costs — Key Write Operations

### 1.1 EVM Storage Opcode Reference (post-Berlin / EIP-2929)

| Opcode | Condition | Cost (gas) | Source |
|---|---|---|---|
| `SSTORE` — cold slot, 0→nonzero | First write to slot in tx | **20 000** | [EIP-2200](https://eips.ethereum.org/EIPS/eip-2200) + [EIP-2929](https://eips.ethereum.org/EIPS/eip-2929) |
| `SSTORE` — warm slot, nonzero→nonzero | Slot already accessed in same tx | **2 900** (100 warm read + 2 800 base) | EIP-2929 §SSTORE changes |
| `SSTORE` — warm slot, dirty (write after write same tx) | Cheapest intra-tx re-write | **100** | EIP-2929 |
| `SLOAD` — cold slot | First read of slot in tx | **2 100** | EIP-2929 §COLD_SLOAD_COST |
| `SLOAD` — warm slot | Repeat read same tx | **100** | EIP-2929 §WARM_STORAGE_READ_COST |
| `TSTORE` / `TLOAD` | Transient (EIP-1153, live since Cancun) | **100 / 100** | [EIP-1153](https://eips.ethereum.org/EIPS/eip-1153) |
| Intrinsic tx cost | Base per transaction | **21 000** | [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559) |

> **Post-Pectra (Prague-Electra, April 2025):** EIP-7702 introduced EOA code delegation. SSTORE/SLOAD gas schedule **unchanged** from Berlin. EIP-7623 (calldata cost increase to 48 gas/nonzero byte) was proposed but its exact inclusion in Pectra is unverified — check [ethereum/execution-specs](https://github.com/ethereum/execution-specs) for the authoritative list.

### 1.2 Measured Gas — ranch_ledger (forge test --gas-report)

All numbers are **median gas** from the Foundry gas report run on 2026-07-05, 17 tests, 0 failures.

| Operation | Min gas | Avg gas | Median gas | Max gas | # Calls |
|---|---|---|---|---|---|
| `addBovine(name,age,breed,location,owner)` | 34 367 ¹ | 398 545 | **413 300** | 413 360 | 77 |
| `addVaccine(id,name,date)` | 24 898 ² | 61 352 | **61 876** | 96 760 | 4 |
| `addMovement(id,from,to,date)` | 109 695 | 115 395 | **109 695** | 126 795 | 6 |
| `addFeed(id,type,origin,qty,date)` | 143 676 | 143 676 | **143 676** | 143 676 | 2 |
| `addHealthExam(id,type,result,date)` | 103 973 | 112 568 | **112 589** | 121 121 | 4 |
| `addAbattoirProcess(id,abattoir,date,proc,date)` | 126 663 | 132 371 | **126 663** | 143 787 | 6 |
| `BovineNFT.mintForBovine(to,bovineId)` | — | — | **~142 000** ³ | — | — |
| `RanchToken.mint(to,amount)` | 70 786 | 70 786 | **70 786** | 70 786 | 2 |
| `grantRole(role,account)` | 51 551 | 51 551 | 51 551 | 51 551 | 36 |

**Notes:**  
¹ Min of 34 367 is the reverted/access-check-failed path; the real first-time write is 413 k.  
² Min of 24 898 is also a reverted path; first real vaccine ~96 760 (all slots cold); subsequent calls share warm contract state.  
³ From prior forge script runs (BovineNFT not exercised in the Foundry test suite — see `script/BulkMint.s.sol`).

### 1.3 USD Cost at Three Gas Price Scenarios

Pricing formula: `USD = gas × gwei × 1e-9 × ETH_USD`.

| Operation | 5 gwei ($3 500) | 15 gwei ($3 500) | 100 gwei ($3 500) |
|---|---|---|---|
| `addBovine` (413 k gas) | **$7.23** | **$21.68** | $144.55 |
| `addVaccine` (97 k gas) | **$1.70** | **$5.09** | $33.95 |
| `addMovement` (115 k gas) | **$2.01** | **$6.04** | $40.25 |
| `addFeed` (144 k gas) | **$2.52** | **$7.56** | $50.40 |
| `addHealthExam` (113 k gas) | **$1.98** | **$5.93** | $39.55 |
| `addAbattoirProcess` (132 k gas) | **$2.31** | **$6.93** | $46.20 |
| `NFT mint` (142 k gas) | **$2.49** | **$7.46** | $49.70 |
| `ERC-20 mint` (71 k gas) | **$1.24** | **$3.73** | $24.85 |

> **Market context July 2025–June 2026:** Post-Dencun (March 2024) and post-Pectra (April 2025), mainnet base fees have been 3–20 gwei in normal conditions, spiking to 50–200 gwei during NFT drops. The 15 gwei column is the best estimate for an average daytime submission. Source: [Etherscan gas tracker](https://etherscan.io/gastracker) (continuous — no static URL).

---

## 2. Storage Cost Over Time

### 2.1 SSTORE Decomposition for a Single `addBovine` Call

The 413 k gas breaks down roughly as follows (cold-slot costs dominate):

| Component | Estimated SSTOREs | Est. gas |
|---|---|---|
| Bovine core fields (id, age, owner — packed uint256/address) | 3 cold | 60 000 |
| `name` string — length word + data word (≤ 32 bytes) | 2 cold | 40 000 |
| `breed` string | 2 cold | 40 000 |
| `location` string | 2 cold | 40 000 |
| `_bovineIdByName` mapping write | 1 cold | 20 000 |
| `_bovineIds` EnumerableSet add (value + position) | 2 cold | 40 000 |
| `_bovineIdsByBreed` EnumerableSet | 2 cold | 40 000 |
| `_bovineIdsByLocation` EnumerableSet | 2 cold | 40 000 |
| Array-length slots for 5 empty arrays | 5 cold | 100 000 |
| Overhead (access-control SLOAD, events, calldata decode) | — | ~33 000 |
| **Total (est.)** | **~21 cold SSTOREs** | **~413 000** |

### 2.2 Cumulative Storage — 1 000 Bovines × Lifecycle Events

| Scenario | Total txs | Total gas | ETH (15 gwei) | USD ($3 500) |
|---|---|---|---|---|
| 1 000 `addBovine` | 1 000 | 413 000 000 | 6.20 ETH | **$21 700** |
| 5 000 vaccines (1 000 × 5) | 5 000 | 485 000 000 | 7.28 ETH | **$25 462** |
| 10 000 movements (1 000 × 10) | 10 000 | 1 150 000 000 | 17.25 ETH | **$60 375** |
| 5 000 feed records (1 000 × 5) | 5 000 | 718 380 000 | 10.78 ETH | **$37 715** |
| 3 000 health exams (1 000 × 3) | 3 000 | 337 704 000 | 5.07 ETH | **$17 731** |
| 2 000 abattoir entries (1 000 × 2) | 2 000 | 264 742 000 | 3.97 ETH | **$13 899** |
| 1 000 NFT mints | 1 000 | 142 000 000 | 2.13 ETH | **$7 455** |
| 1 000 ERC-20 reward mints | 1 000 | 70 786 000 | 1.06 ETH | **$3 716** |
| **Full lifecycle 1 000 cattle** | **28 000** | **3 581 612 000** | **53.72 ETH** | **$188 053** |

### 2.3 Cold vs Warm SSTORE Differential

In a realistic scenario, each lifecycle event is a **separate transaction** (submitted by different actors — vet, rancher, abattoir). This means every SSTORE in every transaction pays the **cold cost (20 000 gas)** because the accessed storage set is empty at transaction start.

The warm cost (100 gas) only applies when the same slot is written **twice within one transaction** (e.g., a batch script). Conclusion: **there is no warm-SSTORE benefit in the current ranch_ledger design** — every operation is its own transaction with distinct actors.

Optimization path: batching via `multicall3` or an on-contract `batchAdd` function could amortize the cold SLOAD for the access-control role check across multiple events in the same tx.

---

## 3. L1 vs L2 Comparison

### 3.1 Chain Comparison Matrix (July 2025–June 2026)

| Chain | Technology | ETH send cost ¹ | Est. `addBovine` cost ² | Finality | Bridge UX | Regulatory |
|---|---|---|---|---|---|---|
| **Ethereum L1** | Post-Pectra PoS | $1.10 | **$14–$22** | ~12 s (soft) / 64 blocks (safe) | N/A | EU MiCA covered; US SEC gray area |
| **Base** | OP Stack (Bedrock + EIP-4844 blobs) | $0.04 | **$0.04–$0.08** ³ | 2 s soft / 7 days fraud-proof | Coinbase bridge (CEX) | Coinbase regulatory leverage; US-friendly |
| **Optimism** | OP Stack (same as Base) | $0.09 | **$0.06–$0.25** | Same 7-day challenge | Official bridge + 3rd party | Same as Base; OP governance token |
| **Arbitrum One** | Nitro (optimistic) | $0.09 | **$0.09–$0.27** | <2 s UX / 7-day final | Official bridge + Hop | US-based (Offchain Labs), SEC scrutiny |
| **Arbitrum Stylus** | Wasm co-processor on Arbitrum | Same as above | Gas reduced ~10× for CPU-heavy logic | Same | Same | Same |
| **Polygon PoS** | EVM sidechain | $0.01 | **$0.01–$0.03** | ~2 min checkpoint to L1 | PoS bridge (less trust than rollup) | Polygon Foundation; EU/India based |
| **Polygon CDK / zkEVM** | ZK rollup (Plonky2) | $0.19 | **$0.35–$1.00** | Minutes (ZK proof) | Official bridge | Similar to PoS |
| **Scroll** | zkEVM (type-2) | ~$0.05 | **$0.10–$0.30** | ~10–20 min proof | Official bridge | China-origin team; global deployment |
| **zkSync Era** | zkEVM (custom) | $0.07 | **$0.10–$0.30** | Minutes (proof) | ZkSync bridge | Matter Labs; EU-based |
| **Linea** | zkEVM (ConsenSys) | ~$0.10 | **$0.15–$0.40** | Minutes | MetaMask native | ConsenSys; EU/US |
| **StarkNet** | Cairo VM / STARK | $0.19 | **$0.25–$0.80** | ~30 min proof | StarkGate | StarkWare; Israel-based |

**Notes:**  
¹ ETH send = 21 000 gas. Prices from [l2fees.info](https://l2fees.info) snapshot (data auto-refreshes; these values represent the July 2025 range).  
² Scaled from ETH-send cost by ratio `413 000 / 21 000 ≈ 19.7×`; actual L2 cost is also influenced by calldata/blob DA charges, which are much smaller post-EIP-4844.  
³ Base frequently has sub-cent transactions for standard contract writes since the Ecotone upgrade (March 2024).

### 3.2 EIP-4844 (Dencun, March 2024) — Impact on L2 DA Costs

EIP-4844 introduced **blob transactions** (`type 0x03`) with a separate blob fee market:

| Parameter | Value | Source |
|---|---|---|
| Blob size | 128 KB (4 096 × 32-byte field elements) | [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844) §Parameters |
| Gas per blob (`GAS_PER_BLOB`) | 131 072 (2^17) | EIP-4844 |
| Target blobs/block | 3 (≈ 375 KB/block) | EIP-4844 §Throughput |
| Max blobs/block | 6 (≈ 750 KB/block) | EIP-4844 |
| Blob retention | ~18 days (4 096 epochs) | EIP-4844 §MIN_EPOCHS |
| Blob fee when blobs underutilised | ≈ 1 wei/blob-gas (near-zero) | EIP-4844 §Gas accounting |
| Blob fee at max sustained load | Exponentially higher (EIP-1559-style) | EIP-4844 §Base fee update |

Post-Dencun, rollups reduced their L1 DA cost by **10–100×** compared to calldata. A typical Optimism/Base batch blob carrying hundreds of transactions costs $0.01–$0.50 total in blob fees in normal conditions. This is the dominant reason Base and Optimism dropped to sub-cent per-user costs.

**Fusaka upgrade (planned ~Q4 2025/Q1 2026):** EIP-7594 (PeerDAS) is expected to increase blob throughput to **≥ 32 blobs/block**, further reducing DA costs. Unverified — monitor [ethereum/consensus-specs](https://github.com/ethereum/consensus-specs).

---

## 4. Throughput & Data Availability

### 4.1 Can L1/L2 Handle 10 000 Cattle Registration Events Per Day?

| Chain | Daily gas capacity | `addBovine` txs/day (413 k gas) | 10 000 registrations? | Comment |
|---|---|---|---|---|
| Ethereum L1 | ~216 billion gas (7 200 blocks × 30 M) | **523 000** | ✅ uses ~1.9% of capacity | Gas is not the bottleneck; $22/tx is |
| Base | Effectively unbounded for this workload | **>> 1 000 000** | ✅ trivially | Sub-cent cost, 2-s blocks |
| Arbitrum One | Similar to Base | ✅ | ✅ | |
| Polygon PoS | ~12 M gas/block × 300 blocks/min = 3.6 B gas/min | ✅ | ✅ | PoS checkpoint model |

10 000 registrations per day is **not a throughput problem on any modern L2**. It is a **cost and UX problem on L1** ($220 000/day at 15 gwei) but negligible on Base ($80–$800/day).

### 4.2 Batching Strategies

#### EIP-7702 (Pectra, April 2025) — EOA Code Delegation

EIP-7702 lets an EOA set a code pointer, enabling account-abstraction-like batched calls **without a separate smart account contract**. A vet could batch multiple `addVaccine` calls in one transaction:

```
Authorization (signed by EOA):
  chainId, address(BatchHelper), nonce, signature

tx.data = BatchHelper.batchAddVaccines([
  (bovineId1, "FMD-2025", date1),
  (bovineId2, "FMD-2025", date1),
  ...
])
```

Gas savings from batching 10 vaccines in one tx (rough estimate):
- 10 × 97 000 = 970 000 gas sequential (10 txs)
- Batched: 21 000 (intrinsic) + 10 × ~75 000 (warm re-use of access-control slots) ≈ **771 000 gas** ≈ 21% saving
- Source: EIP-7702 enables this without per-user proxy deployment overhead

#### Multicall3 (no protocol change needed)

[Multicall3](https://github.com/mds1/multicall) (deployed at `0xcA11bde05977b3631167028862bE2a173976CA11` on every major chain) allows batching reads in one RPC call, but **write batching requires the contract to have a `batchAdd` function** or use `DELEGATECALL`. Adding a `batchAddVaccines(uint256[] calldata ids, ...)` function to `BovineTracking` would be the simplest approach.

Estimated batch gas for 10 `addVaccine` calls in one tx:
- The `_bovineIdByName` mapping read and the `AccessControl._checkRole` SLOAD become warm on second call in the same tx → saves ~1 900 gas × 9 = 17 100 gas for 10 calls
- Net saving over 10 separate txs: **17 100 gas + 9 × 21 000 intrinsic = 206 100 gas saved**, about 21%

#### RIP-7560 (Account Abstraction Native — not yet deployed)

[RIP-7560](https://github.com/eth-infinitism/RIPs/blob/master/RIPS/rip-7560.md) (Rollup Improvement Proposal) proposes native AA at the protocol level. Status: draft/under review, not deployed on any major chain as of July 2026. Would enable gasless transactions (paymaster pays) which is highly relevant for agricultural workers transacting from feature phones.

---

## 5. Off-Chain Storage Alternatives

### 5.1 Architecture Patterns

| Pattern | How it works | Storage cost | Query capability | Immutability | Best for ranch_ledger |
|---|---|---|---|---|---|
| **Full on-chain (current)** | All struct data in contract storage SSTORE | $14–$22/bovine (L1) | Direct RPC call / `getBovine()` | ✅ Full | Dev/test; small herds |
| **IPFS + on-chain hash** | JSON stored on IPFS; `bytes32 contentHash` stored on-chain | ~$0.01/bovine hash | IPFS gateway (not queryable) | CID immutable; node may unpin | Medium scale |
| **Filecoin (FVM)** | Paid storage deal; deal CID on-chain | $0.0001/GB/year (unverified — see [filecoin.io/fil+](https://filecoin.io)) | FVM contracts | Cryptographically proven | Long-term archival |
| **Ceramic / ComposeDB** | Streams anchored to Ethereum; GraphQL indexer | ~$0.001/stream update | GraphQL | Anchored to Ethereum | App-layer queries |
| **Tableland** | SQL on-chain; EVM contract controls ACL | ~$0.001/row (L2) | SQL via REST | Mutable (ACL-controlled) | Dashboard queries |
| **The Graph (subgraph)** | Indexes events from on-chain; no additional storage cost | Free to index (indexer fees exist for paid usage) | GraphQL over events | Read-only mirror | Front-end query layer |
| **Merkle-root anchoring** | Off-chain DB (Postgres/SurrealDB) daily hash posted on-chain | $1.10/day (21 k gas at 15 gwei) | Off-chain DB | Batch-level immutability | Enterprise at scale |

### 5.2 The Graph — Recommended Query Layer

Adding a subgraph to ranch_ledger requires zero contract changes. The `BovineAdded`, `VaccineAdded`, `MovementAdded` events (already emitted) are perfect for indexing.

```graphql
type Bovine @entity {
  id: ID!
  name: String!
  breed: String!
  owner: Bytes!
  vaccines: [Vaccine!]! @derivedFrom(field: "bovine")
}
type Vaccine @entity {
  id: ID!
  bovine: Bovine!
  name: String!
  date: BigInt!
}
```

Source: [The Graph docs — creating a subgraph](https://thegraph.com/docs/en/developing/creating-a-subgraph/).

### 5.3 Walmart / IBM Food Trust Scale Comparison

IBM Food Trust ([IBM Blockchain Food Trust](https://www.ibm.com/blockchain/solutions/food-trust)) uses **Hyperledger Fabric** (permissioned blockchain), not an EVM-compatible chain. Key points:
- Walmart mandated all leafy-greens suppliers upload traceability data by September 2019 (source: [IBM press release](https://newsroom.ibm.com/2018-09-24-IBM-and-Walmart-Expand-Their-Food-Safety-Collaboration)).
- Scale: IBM reported "millions of food products" tracked; Walmart processed "250 billion+ supply chain events" across its network (unverified exact number — cross-reference [Forbes 2019 Walmart blockchain article](https://www.forbes.com/sites/rogeraitken/2019/10/17/walmart-is-betting-on-the-blockchain/)).
- **Key insight:** IBM Food Trust stores data **off-chain on Fabric nodes** and anchors periodic hashes to Ethereum. Individual livestock events are NOT posted to a public EVM chain — the cost would be prohibitive at scale.
- Per-event cost on Fabric: effectively $0 (private, no gas market). Trust comes from consortium governance, not cryptoeconomic incentives.

**Implication for ranch_ledger:** Walmart-scale (~250 M events/year ÷ 365 = ~685 000/day) cannot use L1 Ethereum at any reasonable cost. L2 (Base/Polygon PoS at $0.01–$0.10/tx) makes up to ~10 M events/day economically feasible; beyond that, Merkle-root anchoring is the standard industry approach.

---

## 6. Data Model Alternatives

### 6.1 Current Model Analysis

The current `Bovine` struct embeds five dynamic arrays:

```solidity
struct Bovine {
    uint256 id;           // 1 slot
    string name;          // 2 slots (length + data for ≤ 31 bytes)
    uint256 age;          // 1 slot (wasteful — see §7.3)
    string breed;         // 2 slots
    string location;      // 2 slots
    address owner;        // 1 slot
    Vaccine[] vaccines;        // array-length slot + data at keccak256(slot)
    Movement[] movements;      // same
    Feed[] feeds;              // same
    HealthExam[] healthExams;  // same
    AbattoirProcess[] abattoirProcesses; // same
}
```

**Strengths:** Simple to query (`getBovine()` returns full struct). Self-contained.  
**Weaknesses:** Each new array element is an independent SSTORE; struct grows unboundedly; no pagination; cannot partially update.

### 6.2 Alternative Patterns

#### EIP-2535 Diamond (Multi-Facet Proxy)

| Aspect | Detail |
|---|---|
| Standard | [ERC-2535](https://eips.ethereum.org/EIPS/eip-2535) — Final |
| How it works | Single proxy (`Diamond`) `delegatecall`s into stateless facets; facets share the diamond's storage |
| Gas overhead | +2 500 gas per call (extra `SLOAD` for selector→facet lookup + `DELEGATECALL` overhead) |
| Benefit for ranch_ledger | Splits `BovineTracking` into `RegistrarFacet`, `VetFacet`, `RancherFacet`, `AbattoirFacet`; bypasses 24 KB contract size limit |
| Risk | Storage layout collisions if facets are not carefully coordinated; auditing complexity |
| Recommendation | **Consider** if `BovineTracking` approaches 24 KB (current deployment: 13 394 bytes) |

#### EIP-7201 Namespaced Storage

[ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) standardises storage layout for proxies/diamonds:

```solidity
/// @custom:storage-location erc7201:ranchledger.main
struct RanchStorage {
    mapping(uint256 => Bovine) bovines;
    uint256 nextId;
    // ...
}
bytes32 constant RANCH_SLOT =
    keccak256(abi.encode(uint256(keccak256("ranchledger.main")) - 1)) & ~bytes32(uint256(0xff));
```

**Benefit:** Prevents slot collision when upgrading via UUPS or Diamond proxy. Zero gas overhead on reads/writes — only affects layout calculation. Already supported by Solidity ≥ 0.8.20 (the project targets 0.8.28 ✓).

#### EIP-1155 Multi-Token (one NFT, N sub-tokens)

| Aspect | ERC-721 (current) | ERC-1155 |
|---|---|---|
| Token per bovine | 1 unique NFT | 1 token type, quantity=1 per bovine |
| Batch mint gas | 142 k per NFT | ~25–50 k per token in batch ([OZ ERC1155](https://docs.openzeppelin.com/contracts/5.x/api/token/erc1155)) |
| Use case | Unique cattle ownership | Fungible feed batches, certificate tokens |
| Recommendation | Keep ERC-721 for bovine identity; **add ERC-1155 for event tokens** (vaccine certificates, feed certifications) |

#### Storage-Proof Rollups / EigenLayer AVS

For cross-chain cattle registry verification (e.g., Brazilian ranch → EU importer verification):
- **EigenLayer AVS (Actively Validated Service):** Restaked ETH operators run off-chain tasks; results posted on-chain with economic security from staked ETH.
- Use case: A "BovineVerifier AVS" could prove Merkle membership of a bovine record across chains without bridging the full state.
- Status: EigenLayer mainnet live since April 2024; AVS ecosystem growing. [EigenLayer docs](https://docs.eigenlayer.xyz/).

#### Flat-Event Model vs Nested-Array Model

| Model | On-chain | Gas per event | Queryability |
|---|---|---|---|
| **Current** (nested arrays in struct) | Full data in contract storage | 97–144 k per event | O(1) by ID; no filter |
| **Event-only** (emit only, no storage) | No persistent state | ~3 000–5 000 per event (LOG4 cost) | Not queryable on-chain; needs The Graph |
| **Separate mapping per event type** | `mapping(uint256 => Vaccine[])` separately | ~same as current (same SSTORE) | Same |
| **Append-only log contract** | Compact bytes32 per event | ~25 000 per entry | Requires off-chain parser |

**Recommendation:** For a production system beyond 10 000 cattle, consider an **event-emit-only** pattern for all lifecycle events (vaccines, movements, feeds) combined with a The Graph subgraph. Only registry state (ownership, current location, alive/processed flag) stays in contract storage. This reduces on-chain write gas by 60–80% per event.

---

## 7. OpenZeppelin Gas-Saver Patterns

### 7.1 ERC721A vs OpenZeppelin ERC721 (Batch Minting)

| Metric | OZ ERC721 | ERC721A |
|---|---|---|
| Mint 1 NFT | 154 814 gas | 76 690 gas |
| Mint 5 NFTs | 616 914 gas | 85 206 gas |
| Savings per unit (batch 5) | — | **~106 k gas (69%)** |
| Source | [Azuki ERC721A announcement](https://www.azuki.com/erc721a) | same |

**Relevance:** If ranch_ledger mints an NFT per bovine at slaughter-batch time (e.g., 500 cattle/day from one feedlot), switching from OZ ERC721 to [ERC721A](https://github.com/chiru-labs/ERC721A) saves:

`500 × (154 814 − ~80 000) ≈ 37 M gas/day ≈ $1 945/day at 15 gwei`

**Caveat:** ERC721A defers ownership writes, making individual transfers slightly more expensive (`ownerOf` traversal). This is irrelevant for livestock tokens that are rarely transferred after minting.

Also consider OZ's [ERC721Consecutive](https://docs.openzeppelin.com/contracts/5.x/api/token/erc721#ERC721Consecutive) (EIP-2309), which emits a single `ConsecutiveTransfer` for batch mints with O(1) gas per token.

### 7.2 Custom Errors (Already Used ✓)

ranch_ledger already uses custom errors (`InvalidBovine`, `DuplicateBovineName`, etc.). This saves ~200–500 gas per revert path versus `require(condition, "string")` due to eliminating the ABI-encoded error string from calldata and return data.

### 7.3 Struct Packing (Not Yet Implemented)

Current struct uses `uint256` for fields that don't need 32 bytes:

| Field | Current type | Suggested type | Savings |
|---|---|---|---|
| `age` | `uint256` (32 bytes) | `uint16` (≤ 65 535 years) | Shares slot with other small fields |
| `Vaccine.date` | `uint256` | `uint40` (timestamp, valid to year 36 812) | 3 values pack into 1 slot |
| `Movement.date` | `uint256` | `uint40` | Same |
| `Feed.quantity` | `uint256` | `uint96` (up to 79 B tonnes) | |
| `Feed.date` | `uint256` | `uint40` | Pack with quantity |
| `HealthExam.date` / `AbattoirProcess.date` | `uint256` | `uint40` | |

**Packed vaccine struct example:**

```solidity
struct Vaccine {
    string name;       // 32-byte slot (if ≤ 31 bytes)
    uint40 date;       // 5 bytes
    // 27 bytes free → add more fields or pack another uint40
}
```

Estimated gas saving per `addVaccine` with packed structs: ~20 000 gas (one fewer cold SSTORE because date and name can share a slot). This reduces `addVaccine` from ~97 k to ~77 k gas.

### 7.4 Transient Storage for Reentrancy Guard (EIP-1153)

`BovineTracking` inherits `ReentrancyGuard` from OZ, which uses `SSTORE`/`SLOAD` to set a `_status` flag (costs 20 000 gas cold, 100 gas warm).

With EIP-1153 (`TSTORE`/`TLOAD`, live since Cancun March 2024), the reentrancy lock costs 100 gas in both directions:

```solidity
// Replace OZ ReentrancyGuard with:
modifier nonReentrant() {
    assembly {
        if tload(0) { revert(0, 0) }
        tstore(0, 1)
    }
    _;
    assembly { tstore(0, 0) }
}
```

Gas saving: ~19 900 gas on the first write per tx. For `addBovine` (413 k gas), this is a ~4.8% reduction.

> OZ v5.1 ships `ReentrancyGuardTransient` in the `utils/` directory — drop-in replacement. Source: [OZ contracts changelog](https://github.com/OpenZeppelin/openzeppelin-contracts/releases).

### 7.5 Summary — Potential Gas Reduction from All Optimizations

| Optimization | Est. gas saved per `addBovine` | Est. gas saved per `addVaccine` |
|---|---|---|
| Struct packing (§7.3) | ~20 000 | ~20 000 |
| `ReentrancyGuardTransient` (§7.4) | ~19 900 | ~19 900 |
| ERC721A for NFT batch | — | — |
| Event-only for lifecycle events | — | ~70 000 |
| **Total (excl. event-only)** | **~40 000 (~10%)** | **~40 000 (~41%)** |

---

## 8. Industry Standards

### 8.1 GS1 EPCIS 2.0 — Supply Chain Event Standard

| Aspect | Detail |
|---|---|
| Full name | Electronic Product Code Information Services |
| Version | [EPCIS 2.0 / CBV 2.0](https://ref.gs1.org/standards/epcis/) (June 2022) |
| Publisher | GS1 — global supply-chain standards body |
| Key capability | Captures "what, when, where, why, how" for any physical object |
| New in 2.0 | JSON/JSON-LD syntax; REST API; IoT sensor data; certification attachments |
| Mapping to ranch_ledger | `ObjectEvent` → `addBovine`; `TransformationEvent` → `addAbattoirProcess`; `AggregationEvent` → grouping into shipments |
| Blockchain integration | EPCIS events can reference a blockchain transaction hash as `sourceList` entry |

**Recommendation:** Structure `BovineTracking` events to be GS1-EPCIS-encodable. The `MovementAdded(bovineId, fromLocation, toLocation, date)` event maps exactly to EPCIS `ObjectEvent` with `readPoint` and `bizLocation`.

### 8.2 ISO 22005 — Traceability in the Food Chain

[ISO 22005:2007](https://www.iso.org/standard/36297.html) specifies the principles for traceability systems in any food-chain step, from primary production through distribution. It requires:
- Unique identifiers for each animal/product
- Record linkage between production steps
- Audit trail retrievable within defined time limits

`BovineTracking` satisfies the technical requirements. ISO 22005 does **not** mandate blockchain — it is technology-neutral.

### 8.3 W3C Verifiable Credentials — Vet Certifications

[W3C VC Data Model 2.0](https://www.w3.org/TR/vc-data-model-2.0/) (2024) enables digitally signed attestations. Use case for ranch_ledger:

```json
{
  "@context": ["https://www.w3.org/ns/credentials/v2"],
  "type": ["VerifiableCredential", "VaccinationCertificate"],
  "issuer": "did:ethr:0xVET_ADDRESS",
  "credentialSubject": {
    "bovineId": 42,
    "vaccine": "FMD-2025",
    "date": 1720000000
  }
}
```

The VC signature (secp256k1) can be verified against `BovineNFT.ownerOf(tokenId)` without storing the full VC on-chain. Only the VC hash is stored: `addVaccine(...) + emit VaccineAdded(bovineId, vcHash, date)`.

### 8.4 OpenSPG / OpenKG — Knowledge Graph Standards

[OpenSPG](https://github.com/OpenSPG/openspg) (Ant Group, 2023) and [OpenKG](http://openkg.cn/) provide knowledge-graph schemas for supply chains. Relevant for building a semantic layer on top of raw blockchain events (e.g., inferring "feedlot cluster" from co-location data). Not an on-chain standard — applies to the off-chain analytics tier.

---

## 9. Real-World Pilot Data

### 9.1 Walmart / IBM Food Trust (Beef Traceability)

| Fact | Detail | Source |
|---|---|---|
| Technology | Hyperledger Fabric (permissioned) | [IBM Food Trust](https://www.ibm.com/blockchain/solutions/food-trust) |
| Launch | 2018–2019 (leafy greens mandate Sep 2019) | [Walmart press release 2018](https://corporate.walmart.com/news/2018/09/24/in-two-years-walmart-will-require-it-suppliers-to-participate-in-the-ibm-food-trust-built-on-ibm-blockchain) |
| Chain | **Not EVM** — IBM Fabric consortium; Ethereum anchoring for audit trail | unverified |
| Trace time | Farm-to-store beef trace: **2.2 seconds** vs ~7 days manual | IBM marketing materials |
| Scale | "Millions of products"; exact per-event volume unverified | ibm.com/blockchain |
| Public EVM equivalent | None — all data in private Fabric nodes | — |
| Key lesson | Walmart uses blockchain for **auditability**, not decentralisation. Per-event cost on private Fabric ≈ $0. An EVM equivalent at Walmart scale ($0.01/event × 250 M/year = $2.5 M/year) would require Base or Polygon PoS, not L1 Ethereum. | |

### 9.2 Brazilian Beef Traceability — SISBOV / SDA

| System | Detail |
|---|---|
| SISBOV | Serviço de Rastreabilidade da Cadeia Produtiva de Bovinos e Bubalinos — mandatory ear-tag + registry system since 2002 |
| Operator | MAPA (Ministério da Agricultura, Pecuária e Abastecimento) |
| Database | Centralised government DB (not blockchain) |
| Scale | Brazil has ~220 M head of cattle (largest commercial herd) — [FAO 2023 data](https://www.fao.org/faostat/en/) |
| Blockchain pilot | JBS/Seara piloted blockchain traceability for premium beef exports (2019–2022). Technology: Hyperledger Fabric. Status as of 2026: unverified whether scaled or remains pilot. |
| EU connection | Brazil must comply with EU Deforestation Regulation (EUDR, Reg. 2023/1115) requiring supply-chain due diligence for beef imports to EU. SISBOV data must be accessible to EU importers. |
| DPP relevance | EU Digital Product Passport (see §9.3) will likely require Brazilian beef exporters to provide structured traceability data; blockchain-anchored records are one candidate approach. |

### 9.3 EU Digital Product Passport (DPP)

| Aspect | Detail | Source |
|---|---|---|
| Regulation | EU Ecodesign for Sustainable Products Regulation (ESPR), Reg. 2024/1781 | [EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1781) |
| Scope | Initially batteries (2026), textiles (2027), electronics (2028); **food/agriculture timeline TBD** | European Commission |
| DPP requirement | Machine-readable product data accessible via QR / RFID / NFC; standardised data schema | ESPR Art. 8 |
| GS1 Digital Link | Likely the identifier format: `https://id.gs1.org/01/{GTIN}/10/{batch}` | [GS1 Digital Link](https://www.gs1.org/standards/gs1-digital-link) |
| Blockchain suitability | DPP requires data **availability** and **authenticity** — blockchain provides immutability; L2 or hybrid (hash-on-chain) is suitable | European Blockchain Services Infrastructure (EBSI) exploring |
| Timeline for cattle | Unverified — EU has not yet published DPP mandate for beef; watch [European Commission ESPR delegated acts](https://commission.europa.eu/energy-climate-change-environment/standards-tools-and-labels/products-labelling-rules-and-requirements/sustainable-products/ecodesign-sustainable-products-regulation_en) | — |

---

## 10. Performance Headroom — 1 000 000 Cattle

### 10.1 Projected Full-Lifecycle On-Chain Storage Cost

Full lifecycle per animal = `addBovine` + 5 vaccines + 10 movements + 5 feeds + 3 health exams + 2 abattoir entries + NFT mint + ERC-20 mint:

| Per-animal gas total | 3 581 826 gas |
|---|---|
| **At 5 gwei, $3 500 ETH** | **$62.68** |
| **At 15 gwei, $3 500 ETH** | **$188.05** |
| **At 15 gwei, $2 000 ETH** | **$107.45** |
| **At 0.001 gwei (Base L2)** | **$0.013** |

**1 000 000 cattle, full lifecycle on Ethereum L1 (15 gwei, $3 500):**  
`1 000 000 × $188.05 = **$188 050 000**` — economically impractical.

**1 000 000 cattle, full lifecycle on Base (0.001 gwei equivalent):**  
`1 000 000 × $0.013 = **$13 000**` — economically viable.

### 10.2 Required Block-Space (L1 Perspective)

| Metric | Value |
|---|---|
| Total gas for 1 M cattle (full lifecycle) | 3.58 × 10¹² gas |
| L1 daily gas budget (30 M/block × 7 200 blocks) | 2.16 × 10¹¹ gas |
| Days to process all 1 M cattle on L1 (100% gas share) | **~16.6 days** |
| Days at 10% of L1 capacity | **~166 days** |
| Practical L2 throughput (Base, 2s blocks, 30M gas/block) | ~1.3 × 10¹³ gas/day — **< 1 day** |

### 10.3 Breakeven: Full On-Chain vs Centralized DB + Merkle Root

| Approach | Per-record cost | Annual cost (1 M records/year) | Trust model |
|---|---|---|---|
| **Full on-chain L1** (15 gwei) | $188 | $188 M | Trustless, censorship-resistant |
| **Full on-chain Base** (0.001 gwei) | $0.013 | $13 000 | L2 security + Ethereum settlement |
| **PostgreSQL cloud DB (AWS RDS)** | ~$0.001 | ~$1 000 | Centralised trust |
| **Postgres + daily Merkle L1 anchor** | ~$0.001 + $1.10/365 = ~$0.001 | ~$1 400 | Off-chain data; on-chain commitment |
| **IPFS JSON + on-chain hash (Base)** | ~$0.001 (IPFS) + $0.0005 (hash SSTORE) | ~$1 500 | IPFS availability + on-chain hash |
| **Fabric (Hyperledger private)** | ~$0 (no gas) | ~$50 000 (infra) | Consortium governance |

**Breakeven insight:**
- There is no gas-cost scenario where L1 Ethereum beats a centralized DB for bulk agricultural records.
- **Base/Polygon PoS** brings on-chain cost to within 10× of a well-run cloud DB — acceptable for premium traceability products (e.g., Wagyu, organic certification) where $0.01/record is trivial vs. the sale price.
- The real value proposition is **public auditability and composability** (any verifier can query without API keys), not raw cost.
- At **1 record/day or fewer**, even L1 Ethereum is competitive with cloud DB because infra fixed costs dominate.

### 10.4 Recommended Architecture for 1 M+ Cattle

```
┌──────────────────────────────────────────────────────────────┐
│  IoT / RFID / Mobile app (ear tag scan)                      │
└─────────────────────────┬────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│  Off-chain worker (Node.js / Rust)                           │
│  - Validates data, builds EPCIS events                       │
│  - Stores raw events in Postgres / SurrealDB                 │
│  - Computes daily Merkle root of all events                  │
└──────┬─────────────────────────────────┬─────────────────────┘
       │                                 │
       ▼                                 ▼
┌─────────────┐                ┌──────────────────────────────┐
│  The Graph  │                │  Base / Polygon PoS          │
│  subgraph   │                │  - addBovine (critical cows) │
│  (query)    │                │  - daily Merkle root anchor  │
└─────────────┘                │  - NFT mint at abattoir      │
                               └──────────────────────────────┘
```

This hybrid approach:
1. Records all events off-chain at near-zero cost.
2. Anchors daily Merkle root to Base for $0.001/day.
3. Puts individual bovine identity (birth registration, death certificate) fully on-chain as NFTs.
4. Uses The Graph for efficient front-end queries without RPC overhead.
5. Satisfies EU ESPR/DPP auditability requirements.

---

## Sources Cited

| # | Source | URL |
|---|---|---|
| 1 | EIP-2929: Gas cost increases for state access opcodes | https://eips.ethereum.org/EIPS/eip-2929 |
| 2 | EIP-2200: Structured Definitions for Net Gas Metering | https://eips.ethereum.org/EIPS/eip-2200 |
| 3 | EIP-1559: Fee market change | https://eips.ethereum.org/EIPS/eip-1559 |
| 4 | EIP-4844: Shard Blob Transactions (Dencun) | https://eips.ethereum.org/EIPS/eip-4844 |
| 5 | EIP-1153: Transient storage opcodes (TSTORE/TLOAD) | https://eips.ethereum.org/EIPS/eip-1153 |
| 6 | ERC-2535: Diamonds, Multi-Facet Proxy | https://eips.ethereum.org/EIPS/eip-2535 |
| 7 | ERC-7201: Namespaced Storage Layout | https://eips.ethereum.org/EIPS/eip-7201 |
| 8 | Azuki: Introducing ERC721A | https://www.azuki.com/erc721a |
| 9 | ERC721A GitHub (Chiru Labs) | https://github.com/chiru-labs/ERC721A |
| 10 | L2 Fees — live fee tracker | https://l2fees.info |
| 11 | L2Beat — L2 risk framework | https://l2beat.com |
| 12 | GS1 EPCIS 2.0 standard | https://gs1.org/standards/epcis |
| 13 | GS1 EPCIS & CBV 2.0 Implementation Guideline | https://ref.gs1.org/guidelines/epcis-cbv/2.0.0/ |
| 14 | ISO 22005:2007 — Traceability in the food chain | https://www.iso.org/standard/36297.html |
| 15 | W3C Verifiable Credentials Data Model 2.0 | https://www.w3.org/TR/vc-data-model-2.0/ |
| 16 | Multicall3 | https://github.com/mds1/multicall |
| 17 | RIP-7560: Native Account Abstraction | https://github.com/eth-infinitism/RIPs/blob/master/RIPS/rip-7560.md |
| 18 | The Graph — creating a subgraph | https://thegraph.com/docs/en/developing/creating-a-subgraph/ |
| 19 | EigenLayer documentation | https://docs.eigenlayer.xyz/ |
| 20 | Walmart blockchain mandate (leafy greens) | https://corporate.walmart.com/news/2018/09/24/in-two-years-walmart-will-require-it-suppliers-to-participate-in-the-ibm-food-trust-built-on-ibm-blockchain |
| 21 | EU ESPR Regulation 2024/1781 (DPP) | https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1781 |
| 22 | FAO 2023 livestock data | https://www.fao.org/faostat/en/ |
| 23 | OpenZeppelin Contracts v5 — ReentrancyGuardTransient | https://github.com/OpenZeppelin/openzeppelin-contracts/releases |
| 24 | OpenZeppelin Contracts v5 — ERC721Consecutive | https://docs.openzeppelin.com/contracts/5.x/api/token/erc721#ERC721Consecutive |
| 25 | Etherscan gas tracker (live) | https://etherscan.io/gastracker |

---

*This document was generated from live `forge test --gas-report` output against the ranch_ledger codebase, authoritative EIP specifications, and publicly available L2 fee data. Items marked "unverified" require primary-source confirmation before use in a production business case.*
