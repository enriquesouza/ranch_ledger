# ranch_ledger — Architecture

> **Status:** `v2.0.0` (Solidity 0.8.28, Foundry, OpenZeppelin v5.1)
> **Last updated:** 2026-07-05
> **Audience:** Solidity / DevOps / rancher-developers onboarding to the project.

---

## 1. What this project does

`ranch_ledger` is a **permissionless, EVM-native cattle lifecycle ledger**. Every animal is represented as a unique on-chain entity that can be:

- identified uniquely (an ERC-721 NFT)
- enriched with a full life history (vaccines, movements, feed, health exams, abattoir processing)
- rewarded via an ERC-20 utility token for completing lifecycle events
- queried by any third party (consumer, regulator, banker) without asking the original registry

The goal is to give smallholder ranchers in jurisdictions like Brazil a **public, composable, EUDR-ready provenance record** for each animal they raise — without paying for an enterprise contract, without a SaaS lock-in, and without trusting a centralized database.

---

## 2. Why it exists

The on-chain ledger is the system of record. The off-chain Express + MongoDB service is a **CRUD index** over the same data, with rollback on chain failure. This split mirrors how Walmart + IBM Food Trust operated, but with two crucial differences:

1. **No permissioning.** Anyone with a wallet can query, fork, and run their own copy.
2. **No per-record fee at the user layer.** The on-chain fee is paid by the actor (the rancher) when they call a function. The off-chain API is free.

The current release (`v2.0.0`) is a working Foundry + Solidity 0.8.28 codebase with:

- 17 Solidity tests, all passing
- 100 simulated agents that each registered one bovine on a local anvil chain
- A REST API (Express + mongoose + ethers v6) that bridges the on-chain data with a familiar CRUD interface

---

## 3. Smart contract surface

### 3.1 `BovineTracking.sol` — the ledger

**Roles (OpenZeppelin AccessControl):**

| Role constant | Granted to | Can call |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Deployer (multi-sig in production) | Grant/revoke other roles, set NFT receiver |
| `REGISTRAR_ROLE` | Farm / cooperative | `addBovine` |
| `VET_ROLE` | Veterinarian | `addVaccine`, `addHealthExam` |
| `RANCHER_ROLE` | Ranch hand | `addMovement`, `addFeed` |
| `ABBATTOIR_ROLE` | Slaughterhouse | `addAbattoirProcess` |

**Storage layout** (EIP-7201 namespaced in the next release — see `docs/ROADMAP.md` §3):

```
Bovine struct:
  uint256 id
  string  name
  uint256 age
  string  breed
  string  location
  address owner
  Vaccine[]           vaccines
  Movement[]          movements
  Feed[]              feeds
  HealthExam[]        healthExams
  AbattoirProcess[]   abattoirProcesses

Mappings:
  uint256 => Bovine                  _bovines
  string  => uint256                 _bovineIdByName
  string  => EnumerableSet.UintSet   _bovineIdsByBreed
  string  => EnumerableSet.UintSet   _bovineIdsByLocation
  EnumerableSet.UintSet              _bovineIds
  uint256                            totalBovines
  address                            nftReceiver
```

**Errors (custom, gas-efficient):**

```solidity
error InvalidBovine(uint256 id);
error DuplicateBovineName(string name);
error EmptyString(string field);
error InvalidAge(uint256 age);
```

**Events:**

```solidity
event BovineAdded(uint256 indexed id, string name, uint256 age, string breed, string location, address indexed owner);
event VaccineAdded(uint256 indexed bovineId, string name, uint256 date);
event MovementAdded(uint256 indexed bovineId, string fromLocation, string toLocation, uint256 date);
event FeedAdded(uint256 indexed bovineId, string foodType, string origin, uint256 quantity, uint256 date);
event HealthExamAdded(uint256 indexed bovineId, string examType, string result, uint256 date);
event AbattoirProcessAdded(uint256 indexed bovineId, string abattoir, uint256 abattoirDate, string processing, uint256 date);
```

### 3.2 `BovineNFT.sol` — the per-animal identity

Standard `ERC721` from OpenZeppelin v5.1 with:

- `mintForBovine(address to, uint256 bovineId)` — only `MINTER_ROLE` can call
- `bovineToToken[uint256] => uint256` (1:1 mapping to enforce one NFT per animal)
- `tokenToBovine[uint256] => uint256` (reverse lookup)
- `setBaseURI(string)` — admin-only, points to metadata (default `ipfs://bovine/`)
- `tokenURI(uint256) => string` — returns `baseURI + tokenId`

The NFT is intentionally minimal: it links an on-chain token to a bovine id, and the actual lifecycle data lives in `BovineTracking`. This separation means the NFT stays cheap (ERC-721) while the rich data structure can be upgraded without redeploying the NFT.

### 3.3 `RanchToken.sol` — the reward / utility ERC-20

Standard `ERC20` from OpenZeppelin v5.1 with:

- `mint(address to, uint256 amount)` — `MINTER_ROLE` only
- `burn(uint256 amount)` — anyone can burn their own
- Custom `decimals()` (6, by design — for sub-cent rewards)
- AccessControl inheritance (so the same admin that governs `BovineTracking` can govern the token)

In the roadmap this token is repurposed from "reward" to "rural credit governance" — see `docs/ROADMAP.md` §6.

---

## 4. Off-chain service

```
Express server (server.js)
  ├── /POST   /bovines              addBovine (Mongo first, then chain; rollback on chain fail)
  ├── /POST   /bovines/:id/vaccine addVaccine
  ├── /POST   /bovines/:id/movement addMovement
  ├── /GET    /bovines/:id          getBovine (chain only)
  └── /GET    /health               contract address sanity check

services/bovineService.js
  └── reads ABIs from out/BovineTracking.sol/BovineTracking.json
      (canonical ABI source - never hand-write tuple types)
```

Key invariants:

1. The on-chain contract is the **source of truth**. The Mongo write is a cache.
2. If the chain call fails, the Mongo write is rolled back. (Best-effort; if the process dies between the two, the cache drifts — see `ROADMAP.md` §8.)
3. ABIs are loaded from the Foundry build artifact (`out/`), not hand-written. This avoids the `tuple` ABI parsing trap.

---

## 5. Deployment topology

### 5.1 Local development

```
+--------------------+      +-------------------+      +------------------+
|  Foundry forge     | ---> |  Anvil (100 acct) | <--- |  ethers v6       |
|  (build / script)  |      |  block-time 1s    |      |  (server + CLI)  |
+--------------------+      +-------------------+      +------------------+
                                      ^
                                      |
                          deployments/local.json
                              (written by Deploy.s.sol)
```

### 5.2 Target production

The recommended L2 for production deployment is **Polygon PoS** (or **Base** for the OP-stack alternative). See `docs/BENCHMARKS.md` §3 for the per-tx cost comparison.

```
                  +-------------------+
                  |   Public RPC      |
                  |   (Polygon / Base)|
                  +-------------------+
                            ^
       +--------------------+--------------------+
       |                                         |
+--------------+                          +--------------+
|  Frontend    |  <---- wagmi / viem ---> |  Server     |
|  Next.js     |                          |  (Express)  |
+--------------+                          +--------------+
                                                  |
                                                  v
                                          +--------------+
                                          |  MongoDB     |
                                          |  (cache)     |
                                          +--------------+
```

---

## 6. The 100-agent simulation

`script/BulkMint.s.sol` is a Foundry script that:

1. Reads the deployed `BovineTracking` address from `deployments/local.json`
2. For `i` in `0..99`:
   - Derives a deterministic private key `keccak256("agent-" + i)`
   - Derives the agent address from that key
   - Pre-funds the agent with 1 ETH from the deployer
   - Grants `REGISTRAR_ROLE` to the agent (still under the deployer's broadcast)
3. For `i` in `0..99`:
   - The agent signs a transaction that calls `addBovine` with a unique name (`Bessie-0`, `Daisy-1`, `Molly-2`, …)
   - The agent is recorded as the `owner` of the new bovine

**What this exercises:**

- `AccessControl` for 100 distinct accounts
- `EnumerableSet` lookup performance at 100+ entries
- Role-grant ordering (the script must grant roles *before* the agents try to call)
- Deterministic key derivation (no real wallets required)
- Anvil's behavior under 300 sequential transactions

**Known caveat:** the script runs against anvil's 1-second block time, so the on-chain execution takes ~5 minutes end-to-end. Use `--block-time 1` for a faster local dev loop, or a faster anvil fork for production-scale testing.

---

## 7. File layout

```
src/                  Solidity 0.8.28 sources
  BovineTracking.sol  Lifecycle ledger
  BovineNFT.sol       ERC-721 per-animal identity
  RanchToken.sol      ERC-20 reward / future governance

test/                 Foundry tests (forge test)
  BovineTracking.t.sol  12 tests: add / revert / fuzz / aggregate
  Tokens.t.sol          5 tests: NFT mint + RANCH mint/burn

script/               Foundry scripts
  Deploy.s.sol       Deploys all 3 contracts, writes deployments/local.json
  BulkMint.s.sol     100-agent spawn

services/
  bovineService.js   ethers v6 wrapper, lazy-loads ABI from out/

server.js             Express + MongoDB API

foundry.toml          Solc 0.8.28, optimizer, gas reports
remappings.txt        @openzeppelin/, forge-std/

deployments/          Generated by Deploy.s.sol (gitignored)
lib/                  forge-std + OpenZeppelin v5.1
docs/                 Architecture, benchmarks, competitors, roadmap
```

---

## 8. Security model

The current release assumes:

- The deployer (anvil[0] = `0xf39F…92266` in dev) is trusted at the admin level
- Each role-holder is independent (no collusion risk assumed for the unit tests)
- The `nftReceiver` hook is set by `DEFAULT_ADMIN_ROLE` to the `BovineNFT` contract

Threats not yet mitigated (and addressed in `ROADMAP.md`):

- No upgrade path — `BovineTracking` is non-upgradeable. A bug fix requires a full migration.
- No reentrancy on `addBovine` etc. — currently `nonReentrant` is in place, but `_bovineIdsByBreed` / `_bovineIdsByLocation` writes happen *after* the storage write; if the `nftReceiver` hook reenters, the second `addBovine` would not see the first. See ROADMAP §3.
- No rate-limit on the off-chain API — any caller can spam the chain.
- No on-chain price oracle for the future lending vault.
- No formal verification.

---

## 9. Where to read next

- `docs/BENCHMARKS.md` — gas, L1 vs L2, throughput, what the numbers actually mean
- `docs/COMPETITORS.md` — what IBM Food Trust, VeChain, TE-FOOD, BeefLedger, MOOvement, and 10+ others are doing
- `docs/ROADMAP.md` — prioritized improvement backlog with concrete next steps
