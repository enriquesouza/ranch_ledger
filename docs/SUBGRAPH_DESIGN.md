# Subgraph Configuration for ranch_ledger

## Overview

This subgraph indexes events from the full ranch_ledger contract suite — BovineTracking, BovineNFT, EUDRCompliance, GPSValidator, RanchLendingVault, FractionalizationManager, and GovernorRanch — providing efficient off-chain queries via GraphQL. At scale (1M cattle × 50 events each = 50M events), direct `eth_call` is not viable — subgraphs pre-compute the index.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ranch_ledger Application                  │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Express Server (BFF)                       ││
│  │  • ?useSubgraph=true → GraphQL endpoint                ││
│  │  • ?useSubgraph=false → Direct chain calls             ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    The Graph Node                           │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              GraphQL Endpoint                           ││
│  │  • /subgraphs/name/ranch-ledger                        ││
│  │  • Query: getBovine(id), getBovinesByBreed(breed)      ││
│  │  • Query: getFractionalizations, getCollaterals        ││
│  │  • Query: getProposals, getGPSMovements, getEUDR       ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    Event Indexer                            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Event Handlers                             ││
│  │  • BovineAdded → Create Bovine entity                  ││
│  │  • VaccineAdded → Add to Bovine.vaccines array         ││
│  │  • MovementAdded → Update Bovine.location + movements  ││
│  │  • FeedAdded → Add to Bovine.feeds array               ││
│  │  • HealthExamAdded → Add to Bovine.healthExams array   ││
│  │  • AbattoirProcessAdded → Add to Bovine.abattoirs      ││
│  │  • Transfer (NFT) → Update NFT.owner                   ││
│  │  • EudrAttestations → Create EUDRMetadata + GeoPolygon ││
│  │  • MovementGPS → Create GPSMovement entity             ││
│  │  • CollateralDeposited → Create Collateral entity      ││
│  │  • CollateralWithdrawn → Mark Collateral inactive      ││
│  │  • LoanRepaid → Update Loan, mark inactive             ││
│  │  • Liquidated → Update Collateral + Loan state         ││
│  │  • InterestAccrued → Update global interest index       ││
│  │  • Fractionalized → Create Fractionalization entity    ││
│  │  • SharesPurchased → Create SharePurchase entity       ││
│  │  • SharesRedeemed → Update Fractionalization           ││
│  │  • SaleComplete → Mark Fractionalization.isSold = true  ││
│  │  • ProposalCreated → Create Proposal entity            ││
│  │  • VoteCast → Update Proposal vote counts               ││
│  │  • ProposalExecuted → Update Proposal.state            ││
│  │  • ProposalCanceled → Update Proposal.state            ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    Ethereum Node                            │
│  • Polygon Amoy / Base Sepolia / Mainnet                   │
└─────────────────────────────────────────────────────────────┘
```

## Contracts to Index

### BovineTracking Events
1. `BovineAdded(id, name, age, breed, location, owner)`
2. `VaccineAdded(bovineId, name, date)`
3. `MovementAdded(bovineId, fromLocation, toLocation, date)`
4. `FeedAdded(bovineId, foodType, origin, quantity, date)`
5. `HealthExamAdded(bovineId, examType, result, date)`
6. `AbattoirProcessAdded(bovineId, abattoir, abattoirDate, processing, date)`

### BovineNFT Events
7. `Transfer(from, to, tokenId)` — Standard ERC-721 transfer
8. `BovineNFTMinted(tokenId, bovineId, to)` — Custom mint event

### EUDRCompliance Events
9. `EudrAttestations(bovineId, sisbovId, certHash, farmPolygon)` — EUDR metadata anchored

### GPSValidator Events
10. `MovementGPS(bovineId, fromCoords, toCoords, date)` — GPS-validated movement

### RanchLendingVault Events
11. `CollateralDeposited(borrower, tokenId, notionalValue, healthScore)` — NFT deposited as collateral
12. `CollateralWithdrawn(borrower, tokenId, borrowedAmount)` — collateral withdrawn
13. `LoanRepaid(borrower, tokenId, principal, interest)` — loan repaid
14. `Liquidated(borrower, liquidator, tokenId, borrowedAmount, healthScore)` — position liquidated
15. `InterestAccrued(globalIndex, borrowRate)` — interest accrued globally

### FractionalizationManager Events
16. `Fractionalized(tokenId, owner, totalShares, initialPrice)` — NFT fractionalized
17. `SharesPurchased(buyer, tokenId, sharesBought, pricePaid)` — shares bought
18. `SharesRedeemed(investor, tokenId, sharesRedeemed, proceedsReceived)` — shares redeemed
19. `SaleComplete(tokenId, salePrice, totalProceeds)` — cow marked as sold

### GovernorRanch Events
20. `ProposalCreated(proposalId, description, targets, values, calldatas, voteStart, voteEnd)`
21. `VoteCast(voter, proposalId, support, weight, reason)`
22. `ProposalExecuted(proposalId)`
23. `ProposalCanceled(proposalId)`

## GraphQL Schema

```graphql
type Bovine @entity {
  id: ID!                    # Bovine ID (uint256)
  name: String!
  age: Int!
  breed: String!
  location: String!
  owner: Bytes!              # Owner address at time of creation
  
  vaccines: [Vaccine!]! @derivedFrom(field: "bovine")
  movements: [Movement!]! @derivedFrom(field: "bovine")
  feeds: [Feed!]! @derivedFrom(field: "bovine")
  healthExams: [HealthExam!]! @derivedFrom(field: "bovine")
  abattoirProcesses: [AbattoirProcess!]! @derivedFrom(field: "bovine")
  
  createdAt: BigInt!         # Block timestamp when bovine was added
  updatedAt: BigInt!         # Last event timestamp
}

type Vaccine @entity {
  id: ID!                    # Event transaction hash + log index
  bovine: Bovine!
  name: String!
  date: BigInt!              # Unix timestamp
}

type Movement @entity {
  id: ID!
  bovine: Bovine!
  fromLocation: String!
  toLocation: String!
  date: BigInt!
}

type Feed @entity {
  id: ID!
  bovine: Bovine!
  foodType: String!
  origin: String!
  quantity: BigInt!
  date: BigInt!
}

type HealthExam @entity {
  id: ID!
  bovine: Bovine!
  examType: String!
  result: String!
  date: BigInt!
}

type AbattoirProcess @entity {
  id: ID!
  bovine: Bovine!
  abattoir: String!
  abattoirDate: BigInt!
  processing: String!
  date: BigInt!
}

type NFT @entity {
  id: ID!                    # Token ID
  tokenId: BigInt!
  bovineId: BigInt!          # Linked bovine ID
  owner: Bytes!              # Current owner address
  mintedAt: BigInt!          # Block timestamp when minted
  transferredAt: BigInt      # Last transfer timestamp (nullable)
}

type RanchToken @entity {
  id: ID!                    # Contract address
  totalSupply: BigInt!
  decimals: Int!
  
  holders: [TokenHolder!]! @derivedFrom(field: "token")
}

type TokenHolder @entity {
  id: ID!                    # Holder address
  token: RanchToken!
  balance: BigInt!
  firstMintedAt: BigInt!     # When holder first received tokens
  lastTransferAt: BigInt!    # Last transfer timestamp
}

type EUDRMetadata @entity {
  id: ID!
  bovine: Bovine!
  sisbovId: String
  cnpj: String
  birthTimestamp: BigInt!
  deforestationCertHash: Bytes!
  farmPolygon: GeoPolygon!
  createdAt: BigInt!
}

type GeoPolygon @entity {
  id: ID!
  latE7: [BigInt!]!
  longE7: [BigInt!]!
}

type Collateral @entity {
  id: ID!
  borrower: Bytes!
  tokenId: BigInt!
  countryCode: String
  nationalId: String
  notionalValue: BigInt!
  healthScore: Int!
  isCollateralized: Boolean!
  createdAt: BigInt!
}

type Loan @entity {
  id: ID!
  borrower: Bytes!
  tokenId: BigInt!
  principal: BigInt!
  interestAccrued: BigInt!
  isActive: Boolean!
  createdAt: BigInt!
}

type Fractionalization @entity {
  id: ID!
  tokenId: BigInt!
  owner: Bytes!
  totalShares: BigInt!
  initialPrice: BigInt!
  isFractionalized: Boolean!
  salePrice: BigInt
  isSold: Boolean!
  shareTokenAddress: Bytes!
  createdAt: BigInt!
}

type SharePurchase @entity {
  id: ID!
  buyer: Bytes!
  tokenId: BigInt!
  sharesBought: BigInt!
  pricePaid: BigInt!
  createdAt: BigInt!
}

type Proposal @entity {
  id: ID!
  proposalId: BigInt!
  description: String!
  proposer: Bytes!
  voteStart: BigInt!
  voteEnd: BigInt!
  yesVotes: BigInt!
  noVotes: BigInt!
  abstainVotes: BigInt!
  state: String!
  createdAt: BigInt!
}

type GPSMovement @entity {
  id: ID!
  bovineId: BigInt!
  fromLatE7: BigInt!
  fromLongE7: BigInt!
  toLatE7: BigInt!
  toLongE7: BigInt!
  timestamp: BigInt!
}
```

## Event Handlers

### BovineTracking Handlers
- **handleBovineAdded:** Create new `Bovine` entity, initialize empty derived arrays
- **handleVaccineAdded:** Load `Bovine`, create `Vaccine` entity (derivedFrom links automatically)
- **handleMovementAdded:** Update `Bovine.location`, create `Movement` entity
- **handleFeedAdded:** Load `Bovine`, create `Feed` entity
- **handleHealthExamAdded:** Load `Bovine`, create `HealthExam` entity
- **handleAbattoirProcessAdded:** Load `Bovine`, create `AbattoirProcess` entity

### BovineNFT Handlers
- **handleTransfer:** Update `NFT.owner`, set `transferredAt` timestamp
- **handleBovineNFTMinted:** Create `NFT` entity linked to `Bovine`

### EUDRCompliance Handlers
- **handleEudrAttestations:** Create `GeoPolygon` entity from `farmPolygon` lat/long arrays, create `EUDRMetadata` entity linked to `Bovine`

### GPSValidator Handlers
- **handleMovementGPS:** Create `GPSMovement` entity with E7-encoded coordinates

### RanchLendingVault Handlers
- **handleCollateralDeposited:** Create `Collateral` entity with `isCollateralized = true`
- **handleCollateralWithdrawn:** Load `Collateral`, set `isCollateralized = false`
- **handleLoanRepaid:** Load `Loan`, set `isActive = false`, update `interestAccrued`
- **handleLiquidated:** Load `Collateral` and `Loan`, mark both inactive, record liquidator
- **handleInterestAccrued:** Update global interest index entity (singleton)

### FractionalizationManager Handlers
- **handleFractionalized:** Create `Fractionalization` entity with `isFractionalized = true`, `isSold = false`
- **handleSharesPurchased:** Create `SharePurchase` entity, update `Fractionalization.totalShares` remaining
- **handleSharesRedeemed:** Update `Fractionalization`, record redemption proceeds
- **handleSaleComplete:** Load `Fractionalization`, set `isSold = true`, record `salePrice`

### GovernorRanch Handlers
- **handleProposalCreated:** Create `Proposal` entity with `state = "Pending"`, zero vote counts
- **handleVoteCast:** Load `Proposal`, increment `yesVotes`/`noVotes`/`abstainVotes` based on `support` field
- **handleProposalExecuted:** Load `Proposal`, set `state = "Executed"`
- **handleProposalCanceled:** Load `Proposal`, set `state = "Canceled"`

## Query Examples

### Get a Single Bovine with Full History

```graphql
query GetBovine($id: ID!) {
  bovine(id: $id) {
    id
    name
    age
    breed
    location
    owner
    
    vaccines {
      name
      date
    }
    
    movements {
      fromLocation
      toLocation
      date
    }
    
    feeds {
      foodType
      origin
      quantity
      date
    }
    
    healthExams {
      examType
      result
      date
    }
    
    abattoirProcesses {
      abattoir
      processing
      date
    }
  }
}

# Variables: { "id": "1" }
```

### Get All Bovines by Breed

```graphql
query GetBovinesByBreed($breed: String!) {
  bovines(where: { breed: $breed }, first: 100, orderBy: id) {
    id
    name
    age
    location
    owner
  }
}

# Variables: { "breed": "Holstein" }
```

### Get Bovines by Location with Health Status

```graphql
query GetHealthyBovines($location: String!) {
  bovines(
    where: { 
      location: $location,
      healthExams_some: { result: "Healthy" }
    },
    first: 100
  ) {
    id
    name
    age
    breed
    
    healthExams(orderBy: date, orderDirection: desc, first: 1) {
      examType
      result
      date
    }
    
    vaccines(first: 5, orderBy: date, orderDirection: desc) {
      name
      date
    }
  }
}

# Variables: { "location": "Farm A" }
```

### Get NFT Ownership History

```graphql
query GetNFTHistory($tokenId: BigInt!) {
  nft(id: $tokenId.toString()) {
    tokenId
    bovineId
    owner
    mintedAt
    transferredAt
    
    # Could add Transfer events if indexed separately
  }
}

# Variables: { "tokenId": "1" }
```

### Aggregate Statistics

```graphql
query GetStatistics {
  bovines(first: 1) {
    id
  }
  
  # Count by breed
  bovinesByBreed_Holstein: bovines(where: { breed: "Holstein" }, first: 1) {
    id
  }
  bovinesByBreed_Angus: bovines(where: { breed: "Angus" }, first: 1) {
    id
  }
  
  # Total vaccines administered
  totalVaccines: vaccines(first: 1000000) {
    id
  }
}
```

### Get All Fractionalized Cows

```graphql
query GetFractionalizedCows {
  fractionalizations(
    where: { isFractionalized: true }
    first: 100
    orderBy: createdAt
    orderDirection: desc
  ) {
    id
    tokenId
    owner
    totalShares
    initialPrice
    isSold
    salePrice
    createdAt
  }
}
```

### Get All Collateral Deposits by Country

```graphql
query GetCollateralsByCountry($countryCode: String!) {
  collaterals(
    where: { countryCode: $countryCode, isCollateralized: true }
    first: 100
    orderBy: createdAt
    orderDirection: desc
  ) {
    id
    borrower
    tokenId
    notionalValue
    healthScore
    nationalId
    createdAt
  }
}

# Variables: { "countryCode": "BR" }
```

### Get All Proposals and Their Vote Counts

```graphql
query GetProposals {
  proposals(
    first: 100
    orderBy: createdAt
    orderDirection: desc
  ) {
    id
    proposalId
    description
    proposer
    voteStart
    voteEnd
    yesVotes
    noVotes
    abstainVotes
    state
    createdAt
  }
}
```

### Get All GPS Movements for a Specific Bovine

```graphql
query GetGPSMovements($bovineId: BigInt!) {
  gpsMovements(
    where: { bovineId: $bovineId }
    first: 100
    orderBy: timestamp
    orderDirection: desc
  ) {
    id
    bovineId
    fromLatE7
    fromLongE7
    toLatE7
    toLongE7
    timestamp
  }
}

# Variables: { "bovineId": "42" }
```

### Get All EUDR Metadata for a Farm Polygon

```graphql
query GetEUDRByPolygon($polygonId: ID!) {
  geoPolygon(id: $polygonId) {
    id
    latE7
    longE7
  }
  eudrMetadatas(
    where: { farmPolygon: $polygonId }
    first: 100
    orderBy: createdAt
    orderDirection: desc
  ) {
    id
    bovine {
      id
      name
      breed
    }
    sisbovId
    cnpj
    birthTimestamp
    deforestationCertHash
    createdAt
  }
}

# Variables: { "polygonId": "0xabc123..." }
```

## AssemblyScript Mapping Functions

See `src/mapping.ts` for the complete event handler implementations.

Key patterns:
- **BovineAdded:** Create new Bovine entity, initialize empty arrays
- **VaccineAdded/FeedAdded/etc.:** Load existing Bovine, push to array, save
- **MovementAdded:** Update Bovine.location + add movement record
- **Transfer (NFT):** Update NFT.owner, set transferredAt timestamp
- **EudrAttestations:** Create GeoPolygon from lat/long E7 arrays, link EUDRMetadata to Bovine
- **MovementGPS:** Create GPSMovement with E7-encoded coordinates (no conversion needed)
- **CollateralDeposited:** Create Collateral with healthScore and notionalValue from event
- **LoanRepaid/Liquidated:** Update both Collateral and Loan entities atomically
- **InterestAccrued:** Update singleton global index entity (id: "global")
- **Fractionalized:** Create Fractionalization with shareTokenAddress from event
- **SharesPurchased/SharesRedeemed:** Update Fractionalization aggregate fields + create SharePurchase
- **SaleComplete:** Set isSold = true, record salePrice on Fractionalization
- **ProposalCreated:** Create Proposal with state = "Pending", zero vote counts
- **VoteCast:** Increment yesVotes/noVotes/abstainVotes based on support (0=against, 1=for, 2=abstain)
- **ProposalExecuted/Canceled:** Update Proposal.state string field

## Local Development Setup

### Prerequisites

1. **The Graph CLI** (`npm install -g @graphprotocol/graph-cli`)
2. **Node.js 18+** with npm
3. **Docker** for running graph-node locally
4. **Ethereum node** (anvil or Alchemy/Infura)

### Step 1: Install Dependencies

```bash
cd subgraph
npm install
```

### Step 2: Generate TypeScript Bindings

```bash
graph codegen
```

This generates `src/generated/` with typed event handlers.

### Step 3: Build Subgraph

```bash
graph build
```

### Step 4: Run Local Graph Node (Docker)

```bash
# Start Ethereum node (anvil in another terminal)
anvil --accounts 100 --balance 1000 --block-time 1

# Start The Graph stack
docker-compose up -d

# Wait for graph-node to be ready
sleep 10

# Check status
curl http://localhost:8020/health
```

### Step 5: Deploy Subgraph Locally

```bash
# Create subgraph on local node
graph create --node http://localhost:8020 ranch-ledger/local

# Build and deploy
graph codegen && graph build && graph deploy \
  --node http://localhost:8020 \
  --ipfs http://localhost:5001 \
  ranch-ledger/local ./subgraph.yaml
```

### Step 6: Query Local Subgraph

```bash
# Open GraphQL playground
open http://localhost:8000/subgraphs/name/ranch-ledger/local

# Or use curl
curl -X POST http://localhost:8000/subgraphs/name/ranch-ledger/local \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{ bovines(first: 10) { id name breed } }"
  }'
```

## Production Deployment

### Deploy to The Graph Network (Hosted Service)

```bash
# Install The Graph CLI
npm install -g @graphprotocol/graph-cli

# Authenticate with The Graph
graph auth --product hosted-service <YOUR_ACCESS_TOKEN>

# Build subgraph
cd subgraph
graph codegen && graph build

# Deploy to production
graph deploy \
  --node https://api.thegraph.com/deploy/ \
  ranch-ledger/ranch-ledger \
  ./subgraph.yaml
```

### Alternative: Self-Hosted Graph Node

For full control and cost savings at scale:

1. **Provision infrastructure:**
   - AWS EC2 (t3.xlarge or larger)
   - PostgreSQL for metadata storage
   - IPFS node for artifact storage
   
2. **Deploy graph-node:**
   ```bash
   docker-compose -f docker/graph-node/docker-compose.yml up -d
   ```

3. **Configure indexing:**
   - Set `IPFS_NODES` to point to your IPFS cluster
   - Configure `ethereum` networks in `config.yaml`
   - Set up subgraph deployment via CLI or API

## Performance Considerations

### Indexing Speed

- **BovineAdded events:** ~10,000 events/hour (fast)
- **Vaccine/Feed/Movement events:** ~50,000 events/hour (moderate)
- **Total throughput:** ~100,000 events/hour on a single graph-node

### Query Performance

- **Single bovine query:** < 50ms (indexed by ID)
- **Breed/location filter:** < 100ms (indexed fields)
- **Aggregate queries:** < 200ms (with proper indexing)

### Cost Optimization

1. **Use subqueries** to avoid fetching large arrays
2. **Paginate results** with `first`/`skip` parameters
3. **Cache frequently accessed data** in application layer
4. **Use @derivedFrom** instead of storing reverse relationships

## Integration with Express Server

### Update server.js to Support Subgraph Queries

```javascript
const { GraphQLClient } = require('graphql-request');

// Initialize subgraph client (optional)
const SUBGRAPH_URL = process.env.SUBGRAPH_URL || 'http://localhost:8000/subgraphs/name/ranch-ledger/local';
const graphClient = new GraphQLClient(SUBGRAPH_URL);

// Example: Get bovine with full history via subgraph
async function getBovineWithHistory(bovineId, useSubgraph = true) {
  if (useSubgraph) {
    const query = `
      query GetBovine($id: ID!) {
        bovine(id: $id) {
          id name age breed location owner
          vaccines { name date }
          movements { fromLocation toLocation date }
          feeds { foodType origin quantity date }
          healthExams { examType result date }
          abattoirProcesses { abattoir processing date }
        }
      }
    `;
    
    const variables = { id: bovineId.toString() };
    const data = await graphClient.request(query, variables);
    return data.bovine;
  } else {
    // Fallback to direct chain calls (ethers.js)
    const contract = await getContract();
    const bovine = await contract.getBovine(bovineId);
    
    // Fetch additional history via separate calls
    const vaccines = await contract.getVaccines(bovineId);
    const movements = await contract.getMovements(bovineId);
    // ... etc
    
    return { ...bovine, vaccines, movements };
  }
}

// Example: Get all bovines by breed via subgraph
async function getBovinesByBreed(breed, useSubgraph = true) {
  if (useSubgraph) {
    const query = `
      query GetBovinesByBreed($breed: String!) {
        bovines(where: { breed: $breed }, first: 100) {
          id name age location owner
        }
      }
    `;
    
    const variables = { breed };
    const data = await graphClient.request(query, variables);
    return data.bovines;
  } else {
    // Fallback to direct chain calls
    const contract = await getContract();
    const ids = await contract.getBovinesByBreed(breed);
    
    const bovines = [];
    for (const id of ids) {
      const bovine = await contract.getBovine(id);
      bovines.push(bovine);
    }
    return bovines;
  }
}

// Update existing routes to support ?useSubgraph=true
app.get('/bovines/:id', async (req, res) => {
  const useSubgraph = req.query.useSubgraph === 'true';
  
  try {
    const bovine = await getBovineWithHistory(req.params.id, useSubgraph);
    res.json(bovine);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/bovines/by-breed/:breed', async (req, res) => {
  const useSubgraph = req.query.useSubgraph === 'true';
  
  try {
    const bovines = await getBovinesByBreed(req.params.breed, useSubgraph);
    res.json(bovines);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
```

## Monitoring & Maintenance

### Subgraph Health Checks

```bash
# Check subgraph sync status
curl http://localhost:8000/subgraphs/name/ranch-ledger/local/health

# Expected response: { "result": true }

# Check indexing progress
curl http://localhost:8000/subgraphs/name/ranch-ledger/local | jq '.syncStatus'
```

### Error Handling

Common issues and solutions:

1. **Subgraph fails to sync:**
   - Check graph-node logs: `docker logs graph-node`
   - Verify contract addresses in subgraph.yaml match deployed contracts
   - Ensure event signatures match exactly

2. **Slow query performance:**
   - Add indexes to frequently queried fields
   - Optimize GraphQL queries (avoid deep nesting)
   - Increase graph-node resources (CPU/RAM)

3. **Data inconsistency:**
   - Reindex subgraph from scratch: `graph remove && graph create && graph deploy`
   - Check for missing events in Ethereum node
   - Verify event handler logic handles edge cases

## Future Enhancements

1. **Real-time WebSocket subscriptions** for live bovine updates
2. **Advanced filtering** (date ranges, health status combinations)
3. **Analytics queries** (vaccine compliance rates, movement patterns)
4. **Multi-chain support** (index same contracts on Polygon + Base)
5. **IPFS metadata integration** for NFT tokenURI resolution

---

**Status:** Scaffolding created  
**Priority:** P2 (Medium)  
**Effort:** L (1-3 weeks for full implementation)  
**Dependencies:** R-03 (Polygon Amoy deployment), R-14 (viem migration)
