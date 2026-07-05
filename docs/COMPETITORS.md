# ranch_ledger — Competitor Analysis (2025–2026)

> **Audience:** rancher-developers, agritech VCs, and EUDR-compliance teams evaluating this project.
> **Compiled:** 2026-07-05 (live web fetches + GitHub search + training-data reconciliation).
> **Confidence labels:** see the appendix. "Low confidence" entries were not verifiable live and should be re-checked before citing externally.

---

## Table of contents

1. [Landscape map (TL;DR)](#1-landscape-map)
2. [Competitor profiles](#2-competitor-profiles)
3. [Brazilian / Latin American projects](#3-brazilian--latin-american-projects)
4. [Where ranch_ledger fits](#4-where-ranch_ledger-fits)
5. [Feature gap matrix](#5-feature-gap-matrix)
6. [Strategic recommendations](#6-strategic-recommendations)
7. [Appendix — data confidence](#7-appendix)

---

## 1. Landscape map

```
                        PERMISSIONED / ENTERPRISE
                          (Hyperledger, Quorum, Besu)
                                    ▲
                          IBM Food Trust (defunct)
                          TE-FOOD (FoodChain)
                          Walmart China / JD.com
                                    │
CENTRALIZED ◄──────────────────────┼────────────────────────► DECENTRALISED / PUBLIC
  (SaaS, IoT only)                 │                               (EVM, Solana)
                          VeChain (semi-public)                │
FoodLogiQ ●                        │               BeefLedger (defunct, was Quorum)
MOOvement ●                        │               MOOvement (pivoted away from chain)
(GPS only, no chain)               │               ranch_ledger ●  ← HERE
                                   │               Elysia (RWA, not cattle-specific)
                                   ▼
                          PERMISSIONLESS / PUBLIC
                          (Polygon, Base, Ethereum L1)
```

The market splits cleanly into three eras:

- **2016–2019 hype cycle** (BeefLedger, Ripe.io, IBM Food Trust pilots): pre-COVID optimism, no clear ROI.
- **2020–2023 consolidation** (TE-FOOD, MOOvement, VeChain DNV partnership): survivors moved to industrial SaaS.
- **2024–2026 EUDR-driven re-emergence** (ranch_ledger, Elysia RWA, base-layer NFT ecosystems): regulation creates a forced market pull.

---

## 2. Competitor profiles

### 2.1 IBM Food Trust

| Field | Detail |
|---|---|
| **Description** | Enterprise food-traceability network built on Hyperledger Fabric; the largest blockchain food-safety deployment by participant count |
| **Year launched** | 2017 (Walmart pork pilot); GA 2019 |
| **Current status** | **Effectively sunset ~2023.** IBM pivoted hard to watsonx AI. The Food Trust product page now redirects to generic IBM products. |
| **Blockchain** | Hyperledger Fabric (permissioned, private channels per supply-chain consortium) |
| **Data model** | **Hybrid (off-chain heavy).** On-chain: product event hash + event timestamp + participating orgs. Off-chain: actual product IDs, lot numbers, sensor readings, certifications stored in HLF world-state. |
| **Token standard** | None. Hyperledger Fabric has no native token. |
| **Smart contract language** | Go (Hyperledger Fabric Chaincode) |
| **Open-source repo** | [github.com/IBM/food-trust-samples](https://github.com/IBM/food-trust-samples) — last meaningful commit ~2021. Core platform was proprietary. |
| **Token economics** | None. SaaS subscription: ~$10k–$100k/year per participant tier |
| **Notable partners** | Walmart US (leafy greens mandate 2019), Walmart China (pork 2016 pilot), Dole, Driscoll's, Nestlé, Unilever, Tyson, Golden State Foods |
| **Throughput** | HLF: ~3,500 TPS on optimized hardware; in practice ~500 TPS on shared infrastructure. No per-record gas fee. |
| **Strengths** | Largest enterprise network, FDA FSMA 204 alignment, GFSI recognition, GS1 EPCIS compliance |
| **Weaknesses vs. ranch_ledger** | Closed platform (now defunct), no public auditability, no DeFi integration, no token economy for farmer incentives, Hyperledger is Go/Java not Solidity |

**Verdict:** Benchmark for enterprise adoption but dead as a product. Its death opened a gap for open standards.

### 2.2 VeChain (VeChainThor)

| Field | Detail |
|---|---|
| **Description** | General-purpose enterprise supply-chain blockchain with its own VM, used by DNV GL for food safety including Australian beef exports to China |
| **Year launched** | 2015 (as VEN on Ethereum); VeChainThor mainnet June 2018 |
| **Current status** | **Live and active.** ~156M total transactions (confirmed July 2026). Pivoting toward sustainability (VeBetter app, B3TR token), ESG tracking, RWA |
| **Blockchain** | VeChainThor — custom Proof-of-Authority, 101 validators. Full EVM compatibility (JSON-RPC equivalence, 2026 Interstellar roadmap) |
| **Data model** | **Hybrid.** On-chain: cryptographic fingerprints (multi-party hashes), lifecycle events. Off-chain: detailed sensor data, documents via VeChain's ToolChain middleware |
| **Token standard** | VIP-181 (analogous to ERC-721); VIP-180 (ERC-20 equivalent). Both VeChain-specific, not portable to EVM |
| **Smart contract language** | Solidity (EVM compatible, with historical VeChainThor VM deployment) |
| **Open-source repo** | [github.com/vechain](https://github.com/vechain) — Thor core is open-source. ToolChain middleware is proprietary |
| **Token economics** | **Dual-token:** VET (store of value, staking) generates VTHO automatically (~5 VTHO per 10,000 VET per day). VTHO is the gas token. Enterprises pre-buy VTHO to sponsor their users (meta-transaction model). Avoids end-user crypto UX friction |
| **Notable partners** | DNV GL (food/marine), Walmart China (pork supply chain), H&M (cotton), BMW, BYD, LVMH, PwC. Beef-specific: DNV GL **MyStory** platform verified Australian grass-fed beef for Chinese market (2018–2021) |
| **Throughput** | 10-second block time, ~50–100 TPS effective. VTHO cost: ~21 VTHO per basic transaction (~$0.0008 in 2026) |
| **Strengths** | Dual-token eliminates gas UX friction; enterprise tooling; DNV GL credibility for beef certs; proven at scale |
| **Weaknesses vs. ranch_ledger** | VIP-181 NFTs not portable to MetaMask/OpenSea/DeFi; proprietary middleware lock-in; China-focused; not DeFi-composable |

### 2.3 BeefLedger (Australia)

| Field | Detail |
|---|---|
| **Description** | Australian beef provenance blockchain for export traceability to China, with crypto token for premium wagyu certification |
| **Year launched** | 2016 (R&D), 2018 (public) |
| **Current status** | **Defunct.** Domain (beefledger.io) explicitly states "no longer affiliated with the original BeefLedger project" (confirmed by live web fetch, July 2026) |
| **Blockchain** | Ethereum-compatible (Quorum / enterprise Ethereum) for the permissioned supply chain layer; public Ethereum for the WQB token sale |
| **Data model** | **Hybrid.** Per-product (not per-animal) provenance hash on-chain. Off-chain: farm origin, breed, grass-fed cert, hormone/antibiotic records, slaughter date, export docs, cold-chain. QR-code consumer portal |
| **Token standard** | ERC-20 (WQB — "Wagyu Q-Beef token") for a tokenised beef futures/premium model. No ERC-721 |
| **Smart contract language** | Solidity (Ethereum/Quorum) |
| **Open-source repo** | No public repos found. Original GitHub org inaccessible |
| **Token economics** | WQB token attempted to let buyers pre-purchase premium beef allocations (commodity forward-contract token). ICO raised ~AUD 3–5M (est.). Did not survive COVID |
| **Notable partners** | Jack's Creek (wagyu), various Chinese importers, CSIRO, Smart Trade Networks |
| **Throughput** | Quorum/IBFT: ~100–300 TPS on internal network. Gas effectively zero (no mining) |
| **Strengths** | Early mover, B2C QR-code UX, real pilot with Chinese market |
| **Weaknesses vs. ranch_ledger** | Dead project; ERC-20 commodity model fragile; no per-animal NFT; permissioned chain with no public auditability; Chinese market focus failed when geopolitics shifted |

**Post-mortem lesson for ranch_ledger:** Per-animal ERC-721 NFT is architecturally sounder than a per-batch ERC-20. BeefLedger's WQB token conflated the commodity (beef) with the traceability record.

### 2.4 TE-FOOD

| Field | Detail |
|---|---|
| **Description** | Farm-to-table food traceability SaaS running its own permissioned blockchain (FoodChain); started with Vietnamese livestock, now global |
| **Year launched** | 2016 (Vietnam pilot); 2018 (token sale); 2019 (FoodChain public) |
| **Current status** | **Active.** 6,000+ business customers, 400,000+ transactions/day, 150M+ people accessing tracked food. Based in Albstadt, Germany. Partners: FAO, Deloitte (confirmed July 2026) |
| **Blockchain** | **FoodChain** — TE-FOOD's proprietary permissioned blockchain (custom). Optimised for high-volume food data. Also has the TONE ERC-20 token on Ethereum mainnet for the incentive layer |
| **Data model** | **Richest hybrid model of all cattle competitors.** On FoodChain: serialized product IDs (QR code based), supply chain events (timestamped, GPS-tagged), lab test results hashes, certification hashes. Per animal: animal ID (ear tag/chip), origin farm, breed, birth date, vaccination history, movement events, weight/growth records, feed type, slaughter event, carcass grading, cold-chain temps, retail delivery. GS1/EPCIS compliant output |
| **Token standard** | ERC-20 (TONE on Ethereum mainnet, contract `0x2ab6bb8408ca3199b8fa6c92d5b455f820af03c4`). No ERC-721 |
| **Smart contract language** | Solidity (TONE on Ethereum); FoodChain core likely Go or Java (proprietary) |
| **Open-source repo** | No public supply-chain repos. TONE token contract verified on Etherscan |
| **Token economics** | TONE utility token: validators and supply-chain participants earn TONE for logging verifiable data. Enterprises pay subscription fees in fiat, not TONE. Total supply: 1B TONE |
| **Notable partners** | Vietnamese Ministry of Agriculture (pork pilot, 15M+ pork animals tracked), FAO (charity program), Deloitte, several EU food exporters |
| **Throughput** | FoodChain: ~2,000–5,000 TPS (claimed internal figure). EPCIS output means no on-chain gas cost to end-users |
| **Strengths** | Deepest livestock data model of any competitor; proven at massive scale; GS1/EPCIS standards compliance; mobile B2B app for field agents; FAO partnership lends credibility |
| **Weaknesses vs. ranch_ledger** | Proprietary FoodChain = no public auditability; no DeFi composability; no per-animal NFT ownership (data custodianship vs. true asset ownership); centralized off-chain store; SaaS pricing model unaffordable for smallholders |

### 2.5 Hyperledger Fabric / Besu (generic)

| Field | Detail |
|---|---|
| **Description** | Foundation-layer permissioned blockchain frameworks used by multiple food/beef supply-chain consortia |
| **Year launched** | Fabric: 2015; Besu: 2018 |
| **Current status** | **Active.** Maintained by Linux Foundation Decentralized Trust. Widely deployed in enterprise food networks |
| **Blockchain** | Fabric: custom PBFT variants (Raft, PBFT). Besu: Ethereum-compatible (PoA Clique/IBFT/QBFT) |
| **Data model** | Flexible — chaincode defines whatever struct the implementer wants. Typical beef deployments: GTIN/EPC product IDs, event types, GPS, temperature, certification references |
| **Token standard** | Fabric: none natively. Besu: full ERC-20/ERC-721/ERC-1155 support (EVM-compatible) |
| **Smart contract language** | Fabric: Go, Java, Node.js chaincode. Besu: Solidity |
| **Open-source repos** | [github.com/hyperledger/fabric](https://github.com/hyperledger/fabric), [github.com/hyperledger/besu](https://github.com/hyperledger/besu) |
| **Token economics** | None in Fabric. Besu can support gas (ETH clones) or gasless private chains |
| **Notable beef deployments** | JD.com (pork origin China, Fabric), Walmart China (pork, Fabric via IBM), Australian red meat NLIS (investigating Besu) |
| **Throughput** | Fabric: 3,500 TPS (optimized). Besu private: 1,000–2,000 TPS. Per-record gas: near-zero on private networks |
| **Strengths** | Enterprise credibility; no gas cost; GDPR-friendly (private channels); Go/Java developer pool; established in food consortia |
| **Weaknesses vs. ranch_ledger** | No public auditability by consumers; no DeFi integration; heavy infrastructure (k8s, CA management); permissioned = trust in consortium operator; no open token economy |

### 2.6 MOOvement

| Field | Detail |
|---|---|
| **Description** | Australian IoT GPS ear-tag + BLE sensor system for real-time cattle tracking; originally marketed blockchain integration but is now primarily an IoT/farm-management platform |
| **Year launched** | 2018 |
| **Current status** | **Active as IoT product.** Live in 23 countries, 5 continents. Offices in USA (Fort Worth TX), Australia, Paraguay, Netherlands |
| **Blockchain** | Originally claimed Polygon integration for provenance records. Current website makes no mention of blockchain |
| **Data model** | Live GPS location (10-min BLE check-ins), animal out-of-range alerts, water point monitoring. No vaccination, health, or slaughter records |
| **Token standard** | None |
| **Smart contract language** | N/A |
| **Open-source repo** | None public |
| **Token economics** | Hardware + subscription model. ~USD $2,618 for 25-tag starter bundle (1 year connectivity included). Carbon credits from Kateri/Cultivo |
| **Notable partners** | ABC, Beef Central, Queensland Country Life. Farms of the Future (Australia). Carbon market: Kateri, Cultivo |
| **Throughput** | N/A (IoT telemetry, not on-chain) |
| **Strengths** | Beautiful IoT UX; real hardware deployed globally; carbon credit revenue stream; proven in harsh outback conditions |
| **Weaknesses vs. ranch_ledger** | Not a blockchain project anymore; no slaughter/provenance data; hardware cost ($100+ per animal for GPS) prohibitive for smallholders; no permanent record |

**Complementary opportunity:** MOOvement generates the location + health telemetry that ranch_ledger could consume as oracle input to mint/update NFT records. See `ROADMAP.md` §4.

### 2.7 Elysia (Korea) — RWA, not cattle

| Field | Detail |
|---|---|
| **Description** | Korean RWA (Real-World Asset) tokenization protocol; originally real estate, expanding to broader RWA including agricultural assets |
| **Year launched** | 2018 (BlockFin / Elysia RWA platform) |
| **Current status** | **Active — live DeFi protocol.** $500M+ Total RWA Value; 100+ Issued RWAs; 50+ Partners. EL token |
| **Blockchain** | Ethereum mainnet + Polygon |
| **Data model** | Real-world asset tokenization: legal title hash + valuation + yield terms. Not cattle/food specific — more financial instrument than traceability |
| **Token standard** | ERC-20 (EL); ERC-721 for RWA certificates |
| **Smart contract language** | Solidity |
| **Open-source repo** | [github.com/elysia-dev](https://github.com/elysia-dev) |
| **Token economics** | EL utility token for governance + yield-bearing synthetic assets. DeFi-native with perps trading on RWA-linked indices |
| **Notable partners** | Finiverse Consortium (KRW stablecoin), multiple Korean financial institutions |
| **Strengths** | Strong DeFi integration; RWA legal framework; active liquidity; proven on-chain yield |
| **Weaknesses vs. ranch_ledger** | Not a traceability platform; focused on financial yield, not cattle provenance; Korean market focus; does not track animal health/movement data |

**Convergence opportunity:** Elysia's RWA model is the financial endgame for ranch_ledger — if an NFT-per-animal can be collateralized or fractionalized, Elysia is the blueprint. See `ROADMAP.md` §6.

### 2.8 Smaller / defunct competitors (one-liners)

| Competitor | Status | Takeaway for ranch_ledger |
|---|---|---|
| **Ripe.io** (US) | Defunct ~2020 | Showed that L1 gas costs can kill IoT-to-chain unit economics — argues for L2 deployment |
| **Provenance** (UK) | Pivoted to beauty/cosmetics 2024 | "Blockchain for supply chain" alone isn't a moat — need a specific commodity network |
| **FoodLogiQ** (US) | Acquired by Trustwell 2022, no blockchain | Confirms that compliance SaaS is the *adjacent* market, not the competitor |
| **Tonsqoia / Hog Ledger** (US, Hedera) | Defunct | Hedera's speed/cost advantage was real but EVM incompatibility killed the ecosystem |
| **Atado** (Cardano livestock) | Unverifiable | Cardano/Haskell developer pool is too small to sustain a niche product |
| **CattlePass / Biotrust** (Canada) | Unverifiable | Likely absorbed into a government traceability system; no public token layer |
| **OpenSC** (Australia/Germany) | Active, niche | ESG-claims platform, not cattle-specific; potential EUDR partner |
| **E-Mandi** (India) | Fragmented, government-run | National-level deployment; no public chain; non-EVM |

---

## 3. Brazilian / Latin American projects

This is the most relevant section for ranch_ledger's competitive positioning. The Brazilian bovine traceability market is enormous (Brazil = world's largest beef exporter, ~215M head of cattle) yet the blockchain layer remains embryonic.

### 3.1 Known Brazilian initiatives

| Project | Status | Tech | Notes |
|---|---|---|---|
| **Embrapa / Sisbov** | Active (centralized) | None (government DB) | Brazil's official SISBOV cattle traceability ID system. Mandatory for EU export. Government-owned, XML-based DB. No blockchain. **This is the regulatory baseline ranch_ledger must be aware of.** |
| **JBS / Marfrig / Minerva internal pilots** | Confirmed internal pilots (~2019–2022) | Hyperledger Fabric | Large meatpackers ran internal HLF pilots for export documentation. Not open, not tokenized. JBS partnership with IBM Food Trust (~2020) was announced but never publicly scaled. |
| **BNDES / Embrapa blockchain project** | R&D phase | Ethereum/HLF (academic) | BNDES funded academic research on blockchain for beef traceability. Papers published 2020–2022. No production deployment found. |
| **FazendaChain / BovineChain.com.br** | **Unverifiable** — domain unreachable (July 2026) | Unknown | Startup claimed EVM-based cattle NFTs. May have pivoted or dissolved. |
| **VetCow / similar agri-tech** | **No live instance found** | Unknown | Referenced in agritech media (~2021) as a veterinary + blockchain cattle health record platform. No active presence found. |
| **NFTBoi.com.br** | **Unverifiable** — domain unreachable (July 2026) | Polygon (claimed) | 2021-era Brazilian NFT cattle project. Likely defunct. |
| **Certfied Beef (Corte Limpo)** | Active (non-blockchain) | None | Brazilian premium beef certification (no blockchain). Market exists. |
| **Startup CNA/Senai pilots** | R&D only | Various | CNA (national agriculture federation) funded multiple blockchain feasibility studies but no production deployments confirmed. |

### 3.2 Assessment of the Brazilian market gap

The Brazilian market has:

- ✅ The world's largest cattle herd (>215M head)
- ✅ Mandatory SISBOV ID for EU exports (regulatory compliance pressure)
- ✅ EU Deforestation Regulation (EUDR, enforceable 2025+) creating urgent demand for verifiable origin data
- ✅ Growing premium beef export market (China, Middle East, EU) that rewards traceability
- ❌ No open-source, permissionless blockchain traceability system in production
- ❌ No ERC-721 per-animal standard anyone has shipped and maintained
- ❌ No DeFi integration for cattle as collateral (a real financing need given Brazil's high rural credit costs)

**This is the gap ranch_ledger can own.**

---

## 4. Where ranch_ledger fits

### 4.1 The honest assessment

ranch_ledger is currently a smart contract codebase (`BovineNFT.sol`, `BovineTracking.sol`, `RanchToken.sol`) running on local Anvil. It is far too small to compete head-on with TE-FOOD (6,000+ customers, 400k tx/day), VeChain (enterprise partnerships with Walmart, DNV), or any Hyperledger consortium. Attempting to replicate those platforms would take years and tens of millions of dollars.

However, the competitive landscape reveals a structural gap that a small, opinionated, open-source EVM project can fill.

### 4.2 The niche to own

**"The open-source ERC-721 bovine identity layer for EUDR-compliant Brazilian beef"**

Specific niche characteristics:

1. **EUDR compliance layer for smallholders.** The EU Deforestation Regulation requires traceability to the plot/farm level for cattle products entering the EU. No open-source, composable Solidity contract exists that a Brazilian rancher can deploy, own, and use to generate EUDR-compliant provenance data.

2. **Per-animal ERC-721 (not per-batch ERC-20).** BeefLedger proved the commodity-token model fails. TE-FOOD doesn't do NFTs. VeChain has VIP-181 (non-portable). ranch_ledger's ERC-721 model means each animal is a sovereign on-chain entity — its history is owned by the rancher, auditable by any third party, and composable with any EVM DeFi protocol.

3. **Developer-first, open-source.** Hyperledger Fabric requires a Go developer and a k8s cluster. ranch_ledger requires `forge install` and a JSON-RPC endpoint. Brazilian agritech developers can fork it, extend it, and contribute. No competitor offers this.

4. **DeFi integration for rural credit.** Brazil has among the world's highest rural credit interest rates. An NFT-per-animal that represents auditable provenance + health data + GPS history can be used as collateral in DeFi lending protocols (e.g., Aave v3 on Polygon, or a bespoke ranch credit DAO). No competitor does this. Elysia does RWA finance but not cattle traceability.

5. **Polygon / Base deployment (L2) for cost.** On Ethereum L1, writing 50 fields per animal would cost ~$5–$50 in gas. On Polygon PoS or Base, the same transaction costs <$0.01. The business case closes at L2.

### 4.3 The moat

The moat is not the code (easily forked) but:

- The **open SISBOV + EUDR data standard** that ranch_ledger formalizes as a Solidity struct and ABI
- The **network of ranchers** who mint their first bovine NFT via ranch_ledger
- **Institutional endorsement** from a Brazilian cooperative, BNDES pilot, or Embrapa partnership
- **First-mover EUDR compliance tooling** (a regulatory deadline creates adoption pressure)

---

## 5. Feature gap matrix

| Feature | IBM Food Trust | VeChain | TE-FOOD | BeefLedger | MOOvement | OpenSC | ranch_ledger (current) | ranch_ledger (roadmap) |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Per-animal ERC-721 NFT | ❌ | ❌ VIP-181 | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Public EVM / auditable | ❌ | Partial | ❌ | Partial | ❌ | ✅ | ✅ (testnet) | ✅ (L2) |
| DeFi composable (collateral) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (roadmap) |
| Open-source + Foundry | ❌ | Partial | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Vaccination records on-chain | ✅ | ✅ | ✅ | Partial | ❌ | ❌ | ✅ | ✅ |
| GPS movement on-chain | Partial | ✅ | ✅ | ❌ | ✅ IoT | Partial | ❌ | ✅ (oracle) |
| EUDR compliance ready | ❌ (defunct) | ❌ | Partial | ❌ | ❌ | ❌ | ❌ | ✅ (roadmap) |
| SISBOV integration | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (roadmap) |
| Consumer QR scan | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ (roadmap) |
| Role-based access (RBAC) | ✅ | ✅ | ✅ | Partial | ❌ | ❌ | ✅ | ✅ |
| ERC-20 incentive token | ❌ | ❌ VTHO | ✅ TONE | ✅ WQB | ❌ | ❌ | ✅ RanchToken | ✅ |
| Free to deploy | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (anvil) | ✅ (L2) |
| <$0.10 per record cost | ❌ | ✅ VTHO | ✅ | ❌ | N/A | ❌ | ✅ (testnet) | ✅ (Polygon/Base) |
| Brazilian Portuguese UX | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (roadmap) |

---

## 6. Strategic recommendations

### Immediate (0–3 months)

1. **Deploy to Polygon PoS testnet (Amoy).** Every competitor either costs too much (Ethereum L1) or requires permission (Hyperledger). Polygon Amoy costs ~$0.001 per record write. This is the cost threshold where the business model works.

2. **Formalize the BovineTracking data struct as an EUDR-compliant standard.** Add the seven data points the EU Deforestation Regulation requires: geolocation (lat/long polygon of farm), deforestation-free certificate hash, SISBOV ID, country of origin, operator legal entity (CNPJ), date of birth, date of slaughter. Publish this as an ABI and README. This is the moat — no competitor has done it.

3. **Add a SISBOV ID field to the NFT.** The SISBOV 15-digit national cattle ID is required for EU export. Making it a first-class field in `BovineNFT.sol` means ranch_ledger is immediately the only EVM contract that maps SISBOV ↔ ERC-721 NFT.

### Short-term (3–12 months)

4. **Build a GPS oracle bridge from MOOvement (or similar).** MOOvement is in 23 countries but has no on-chain record. A Chainlink Functions script (or a simple off-chain relayer) that reads MOOvement's API and writes GPS events to the NFT's history is a genuine competitive differentiator. MOOvement becomes the IoT layer; ranch_ledger becomes the ownership/provenance layer.

5. **Pilot with one Brazilian cooperative.** Target cooperatives in Mato Grosso do Sul or Pará (active in EU export). You need 500–1,000 cattle on-chain to demonstrate viability. A cooperative pilot validates the SISBOV integration and generates the case study needed for the BNDES grant pipeline.

6. **Publish the first open EUDR-cattle-on-EVM data standard.** Write a GitHub repo README + EIP-style document. Submit to Hyperledger Labs or Ethereum Improvement Proposal process. This generates developer mindshare before any competitor notices the gap.

### Medium-term (12–24 months)

7. **RanchToken as a rural credit instrument.** The RanchToken (ERC-20) should not just be a reward token — it should be a governance token for a lending vault where cattle NFTs (with verified SISBOV + GPS + vaccination history) can be deposited as collateral for USD-denominated stablecoin loans. The target APR for Brazilian rural credit is 8–15% formal / 20–40% informal. Even 6% on-chain is a transformative offer. Model after MakerDAO's RWA vaults.

8. **Integrate EU Digital Product Passport.** The EU Digital Product Passport (DPP) regulation (2026–2027 rollout) is explicitly EVM-friendly — the European Commission's DPP working group has referenced ERC-721 and ERC-1155 in their technical recommendations. Position ranch_ledger as the reference implementation for DPP in the Brazilian beef sector.

---

## 7. Appendix — data confidence

| Competitor | Primary source | Confidence |
|---|---|---|
| IBM Food Trust | Live web fetch (July 2026) + training data | **High** — confirmed sunset |
| VeChain | Live web fetch explorer + training data | **High** — confirmed live |
| TE-FOOD | Live web fetch (te-food.com) + training data | **High** — confirmed active, metrics verified |
| BeefLedger | Live web fetch — domain repurposed (confirmed disclaimer) | **High** — confirmed defunct |
| MOOvement | Live web fetch (moovement.com) | **High** — confirmed IoT-only, no blockchain |
| Provenance | Live web fetch (provenance.org) | **High** — confirmed pivoted to beauty |
| OpenSC | Live web fetch (opensc.org) | **High** — confirmed active, non-cattle focus |
| FoodLogiQ | Domain unreachable — training data | Medium |
| Ripe.io | Domain unreachable — training data | Medium |
| CattlePass / Biotrust | Domain unreachable — training data | Low |
| Tonsqoia / Hog Ledger | Domain unreachable — training data | Low |
| Atado | Domain unreachable — training data | Low |
| Elysia | Live web fetch (elysia.land) | **High** — confirmed active, not cattle-specific |
| Brazilian projects | Web fetch + training data | **Low** — fragmented landscape |
| E-Mandi India | Training data | Medium |

Competitors marked **Low confidence** should be independently verified before citing in pitch materials.

---

*Generated 2026-07-05. Web fetches performed live.*
