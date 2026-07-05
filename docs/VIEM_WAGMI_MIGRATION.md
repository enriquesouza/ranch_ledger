# viem + wagmi Migration Guide

**Status:** Design Phase  
**Priority:** P3 (Low / DX)  
**Effort:** M (1-5 days)  
**Dependencies:** R-13 (Subgraph), R-06 (ERC721Consecutive)

---

## Overview

Migrate the off-chain service layer from `ethers v6` to `viem` + `wagmi` for:
- **Smaller bundle size:** viem is tree-shakeable (~30KB vs ethers ~500KB)
- **TypeScript-first:** Native TS types, no `@types/ethers` needed
- ** wagmi hooks:** React components get `useReadContract`, `useWriteContract` out of the box
- **Future-proof:** viem is the recommended library for new Ethereum projects

## Current Architecture (ethers v6)

```
┌─────────────────────────────────────────────────────────────┐
│                    Express Server                           │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              bovineService.js                           ││
│  │  • getContract() — lazy-loads ABI from out/             ││
│  │  • addVaccine(id, name, date) — ethers Contract.write   ││
│  │  • getBovine(id) — ethers Contract.read                 ││
│  │  • getBovinesByBreed(breed) — ethers Contract.read      ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Target Architecture (viem + wagmi)

```
┌─────────────────────────────────────────────────────────────┐
│                    Express Server                           │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              bovineService.ts                           ││
│  │  • createBovineClient() — viem createPublicClient       ││
│  │  • addVaccine(id, name, date) — viem writeContract      ││
│  │  • getBovine(id) — viem readContract                    ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                            ↓ (future frontend)
┌─────────────────────────────────────────────────────────────┐
│                    Next.js Frontend                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              wagmi hooks                                ││
│  │  • useReadContract({ abi, functionName: 'getBovine' })  ││
│  │  • useWriteContract() → writeContract(...)              ││
│  │  • useAccount(), useConnect(), useDisconnect()          ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Migration Steps

### Step 1: Install Dependencies

```bash
npm install viem wagmi @tanstack/react-query
npm install -D typescript @types/node ts-node
```

### Step 2: Create TypeScript Configuration

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### Step 3: Define Contract ABIs as TypeScript Constants

```typescript
// src/abis.ts
export const BOVINE_TRACKING_ABI = [
  {
    type: 'function',
    name: 'addBovine',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'name', type: 'string' },
      { name: 'age', type: 'uint256' },
      { name: 'breed', type: 'string' },
      { name: 'location', type: 'string' },
      { name: 'owner', type: 'address' }
    ],
    outputs: []
  },
  {
    type: 'function',
    name: 'addVaccine',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'bovineId', type: 'uint256' },
      { name: 'name', type: 'string' },
      { name: 'date', type: 'uint64' }
    ],
    outputs: []
  },
  {
    type: 'function',
    name: 'getBovine',
    stateMutability: 'view',
    inputs: [{ name: 'id', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'id', type: 'uint64' },
          { name: 'name', type: 'string' },
          { name: 'age', type: 'uint64' },
          { name: 'breed', type: 'string' },
          { name: 'location', type: 'string' },
          { name: 'owner', type: 'address' }
        ]
      }
    ]
  },
  // ... other functions
] as const;

export const BOVINE_NFT_ABI = [
  {
    type: 'function',
    name: 'mintBatchForBovines',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'bovineIds', type: 'uint256[]' }
    ],
    outputs: []
  },
  // ... other functions
] as const;

export const RANCH_TOKEN_ABI = [
  {
    type: 'function',
    name: 'mint',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    outputs: []
  },
  // ... other functions
] as const;
```

### Step 4: Create viem Client Configuration

```typescript
// src/client.ts
import { createPublicClient, createWalletClient, http } from 'viem';
import { mainnet, polygonAmoy, anvil } from 'viem/chains';
import type { Chain } from 'viem/chains';

export const chains: Record<string, Chain> = {
  mainnet,
  polygonAmoy,
  anvil
};

let currentChain: Chain = anvil;

export function setChain(chainName: string) {
  currentChain = chains[chainName] || anvil;
}

// Public client (read-only, no private key needed)
export function createPublicClient() {
  return createPublicClient({
    chain: currentChain,
    transport: http(process.env.RPC_URL || 'http://127.0.0.1:8545')
  });
}

// Wallet client (for writing transactions)
export function createWalletClient(privateKey: string) {
  return createWalletClient({
    chain: currentChain,
    transport: http(process.env.RPC_URL || 'http://127.0.0.1:8545'),
    account: privateKey
  });
}

// Get contract address based on environment
export function getContractAddress(contractName: string): `0x${string}` {
  const deployments = JSON.parse(
    require('fs').readFileSync(`deployments/${currentChain.id}.json`, 'utf-8')
  );
  
  return deployments[contractName] as `0x${string}`;
}
```

### Step 5: Rewrite bovineService.ts

```typescript
// src/bovineService.ts
import { readContract, writeContract } from 'viem/actions';
import { createPublicClient, createWalletClient } from './client';
import { BOVINE_TRACKING_ABI, BOVINE_NFT_ABI, RANCH_TOKEN_ABI } from './abis';

const TRACKING_ADDRESS = getContractAddress('BovineTracking');
const NFT_ADDRESS = getContractAddress('BovineNFT');
const TOKEN_ADDRESS = getContractAddress('RanchToken');

// ── Read Operations (public client) ──────────────────────────

async function getPublicClient() {
  return createPublicClient();
}

export async function getBovine(bovineId: bigint) {
  const client = await getPublicClient();
  
  const bovine = await readContract(client, {
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'getBovine',
    args: [bovineId]
  });
  
  return {
    id: Number(bovine.id),
    name: bovine.name,
    age: Number(bovine.age),
    breed: bovine.breed,
    location: bovine.location,
    owner: bovine.owner
  };
}

export async function getBovinesByBreed(breed: string) {
  const client = await getPublicClient();
  
  const ids = await readContract(client, {
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'getBovinesByBreed',
    args: [breed]
  });
  
  return Promise.all(ids.map(id => getBovine(BigInt(id))));
}

export async function getAllBovineIds() {
  const client = await getPublicClient();
  
  return readContract(client, {
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'getAllBovineIds'
  });
}

export async function getTotalBovines() {
  const client = await getPublicClient();
  
  const total = await readContract(client, {
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'totalBovines'
  });
  
  return Number(total);
}

// ── Write Operations (wallet client) ─────────────────────────

async function getWalletClient(privateKey: string) {
  return createWalletClient(privateKey);
}

export async function addVaccine(
  privateKey: string,
  bovineId: bigint,
  name: string,
  date: bigint
) {
  const client = await getWalletClient(privateKey);
  
  const hash = await writeContract(client, {
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'addVaccine',
    args: [bovineId, name, date]
  });
  
  return hash;
}

export async function addMovement(
  privateKey: string,
  bovineId: bigint,
  fromLocation: string,
  toLocation: string,
  date: bigint
) {
  const client = await getWalletClient(privateKey);
  
  const hash = await writeContract(client, {
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'addMovement',
    args: [bovineId, fromLocation, toLocation, date]
  });
  
  return hash;
}

export async function addFeed(
  privateKey: string,
  bovineId: bigint,
  foodType: string,
  origin: string,
  quantity: bigint,
  date: bigint
) {
  const client = await getWalletClient(privateKey);
  
  const hash = await writeContract(client, {
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'addFeed',
    args: [bovineId, foodType, origin, quantity, date]
  });
  
  return hash;
}

export async function addHealthExam(
  privateKey: string,
  bovineId: bigint,
  examType: string,
  result: string,
  date: bigint
) {
  const client = await getWalletClient(privateKey);
  
  const hash = await writeContract(client, {
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'addHealthExam',
    args: [bovineId, examType, result, date]
  });
  
  return hash;
}

export async function addAbattoirProcess(
  privateKey: string,
  bovineId: bigint,
  abattoir: string,
  abattoirDate: bigint,
  processing: string,
  date: bigint
) {
  const client = await getWalletClient(privateKey);
  
  const hash = await writeContract(client, {
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'addAbattoirProcess',
    args: [bovineId, abattoir, abattoirDate, processing, date]
  });
  
  return hash;
}

// ── NFT Operations ───────────────────────────────────────────

export async function mintBatchForBovines(
  privateKey: string,
  to: `0x${string}`,
  bovineIds: bigint[]
) {
  const client = await getWalletClient(privateKey);
  
  const hash = await writeContract(client, {
    address: NFT_ADDRESS,
    abi: BOVINE_NFT_ABI,
    functionName: 'mintBatchForBovines',
    args: [to, bovineIds]
  });
  
  return hash;
}

// ── Token Operations ─────────────────────────────────────────

export async function mintToken(
  privateKey: string,
  to: `0x${string}`,
  amount: bigint
) {
  const client = await getWalletClient(privateKey);
  
  const hash = await writeContract(client, {
    address: TOKEN_ADDRESS,
    abi: RANCH_TOKEN_ABI,
    functionName: 'mint',
    args: [to, amount]
  });
  
  return hash;
}

export async function getTokenBalance(user: `0x${string}`) {
  const client = await getPublicClient();
  
  const balance = await readContract(client, {
    address: TOKEN_ADDRESS,
    abi: RANCH_TOKEN_ABI,
    functionName: 'balanceOf',
    args: [user]
  });
  
  return balance;
}
```

### Step 6: Update Express Server to Use viem

```typescript
// server.js (updated)
import express from 'express';
import { 
  getBovine, 
  getBovinesByBreed, 
  addVaccine,
  getTotalBovines 
} from './bovineService.ts';

const app = express();
app.use(express.json());

// GET /bovines/:id — Get a single bovine with full history
app.get('/bovines/:id', async (req, res) => {
  try {
    const bovineId = BigInt(req.params.id);
    const bovine = await getBovine(bovineId);
    
    // Fetch additional history via separate calls
    const contract = await getContract();
    const vaccines = await contract.getVaccines(bovineId);
    const movements = await contract.getMovements(bovineId);
    const feeds = await contract.getFeeds(bovineId);
    const healthExams = await contract.getHealthExams(bovineId);
    const abattoirProcesses = await contract.getAbattoirProcesses(bovineId);
    
    res.json({
      ...bovine,
      vaccines,
      movements,
      feeds,
      healthExams,
      abattoirProcesses
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// POST /bovines — Register a new bovine
app.post('/bovines', async (req, res) => {
  try {
    const { name, age, breed, location, owner } = req.body;
    
    // Validate inputs
    if (!name || !breed) {
      return res.status(400).json({ error: 'Name and breed are required' });
    }
    if (age <= 0 || age > 40) {
      return res.status(400).json({ error: 'Age must be between 1 and 40' });
    }
    
    const hash = await addBovine(req.body.privateKey, name, age, breed, location, owner);
    
    res.json({ 
      message: 'Bovine registered successfully',
      transactionHash: hash
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /bovines/by-breed/:breed — Get all bovines of a breed
app.get('/bovines/by-breed/:breed', async (req, res) => {
  try {
    const bovines = await getBovinesByBreed(req.params.breed);
    res.json(bovines);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /stats — Get aggregate statistics
app.get('/stats', async (req, res) => {
  try {
    const totalBovines = await getTotalBovines();
    
    // Get breed distribution
    const breeds = ['Holstein', 'Angus', 'Hereford', 'Jersey', 'Brahman'];
    const breedCounts = {};
    
    for (const breed of breeds) {
      const ids = await getBovinesByBreed(breed);
      breedCounts[breed] = ids.length;
    }
    
    res.json({
      totalBovines,
      breedDistribution: breedCounts
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`RPC URL: ${process.env.RPC_URL || 'http://127.0.0.1:8545'}`);
});

export default app;
```

### Step 7: wagmi Configuration for Frontend (Future)

```typescript
// src/wagmiConfig.ts
import { http, createConfig } from 'wagmi';
import { anvil, polygonAmoy, mainnet } from 'wagmi/chains';
import { metaMask, walletConnect } from 'wagmi/connectors';

export const wagmiConfig = createConfig({
  chains: [anvil, polygonAmoy, mainnet],
  connectors: [
    metaMask(),
    walletConnect({ projectId: process.env.WC_PROJECT_ID! })
  ],
  transports: {
    [anvil.id]: http('http://127.0.0.1:8545'),
    [polygonAmoy.id]: http(`https://rpc-amoy.polygon.technology`),
    [mainnet.id]: http(`https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`)
  }
});
```

### Step 8: React Components with wagmi Hooks (Future)

```tsx
// src/components/BovineList.tsx
import { useReadContract, useWriteContract } from 'wagmi';
import { BOVINE_TRACKING_ABI } from '../abis';
import { TRACKING_ADDRESS } from '../config';

export function BovineList({ breed }: { breed: string }) {
  const { data: bovineIds, isLoading } = useReadContract({
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'getBovinesByBreed',
    args: [breed]
  });

  if (isLoading) return <div>Loading...</div>;

  return (
    <ul>
      {bovineIds?.map((id: bigint) => (
        <BovineItem key={id.toString()} bovineId={id} />
      ))}
    </ul>
  );
}

function BovineItem({ bovineId }: { bovineId: bigint }) {
  const { data: bovine } = useReadContract({
    address: TRACKING_ADDRESS,
    abi: BOVINE_TRACKING_ABI,
    functionName: 'getBovine',
    args: [bovineId]
  });

  return (
    <li>
      <h3>{bovine?.name}</h3>
      <p>Breed: {bovine?.breed}</p>
      <p>Location: {bovine?.location}</p>
    </li>
  );
}
```

## Migration Checklist

- [ ] Install viem, wagmi, @tanstack/react-query
- [ ] Create tsconfig.json
- [ ] Define contract ABIs as TypeScript constants (abis.ts)
- [ ] Create viem client configuration (client.ts)
- [ ] Rewrite bovineService.js → bovineService.ts
- [ ] Update Express server to use new service
- [ ] Add TypeScript compilation to build script
- [ ] Test all read/write operations against anvil
- [ ] Deploy to Polygon Amoy and verify
- [ ] (Future) Create Next.js frontend with wagmi hooks

## Benefits of Migration

| Metric | ethers v6 | viem + wagmi | Improvement |
|--------|-----------|--------------|-------------|
| Bundle size (client) | ~500KB | ~30KB | **-94%** |
| TypeScript support | Partial (@types/ethers) | Native | **Full** |
| React integration | Manual hooks | Built-in hooks | **DX boost** |
| Tree-shakeable | No | Yes | **Smaller bundles** |
| Type safety | Runtime checks | Compile-time | **Fewer bugs** |

## Backward Compatibility

The migration is **non-breaking** for the Express server:
- All existing API endpoints continue to work
- The `bovineService.ts` exports the same function signatures
- Only the internal implementation changes (ethers → viem)

For the frontend (when added), wagmi hooks provide a declarative alternative to manual ethers calls.

## Testing Strategy

### Unit Tests (Foundry — unchanged)
All smart contract tests remain in Solidity and are unaffected by the off-chain migration.

### Integration Tests (TypeScript)

```typescript
// test/bovineService.test.ts
import { describe, it, expect } from 'vitest';
import { 
  getBovine, 
  addVaccine, 
  getTotalBovines 
} from '../src/bovineService';

describe('BovineService', () => {
  it('should return total bovines count', async () => {
    const total = await getTotalBovines();
    expect(total).toBe(100); // After BulkMint.s.sol runs
  });

  it('should fetch a single bovine by ID', async () => {
    const bovine = await getBovine(BigInt(1));
    expect(bovine.name).toBeDefined();
    expect(bovine.breed).toBeDefined();
    expect(bovine.owner).toMatch(/^0x[0-9a-fA-F]{40}$/);
  });

  it('should add a vaccine to a bovine', async () => {
    const hash = await addVaccine(
      process.env.PRIVATE_KEY!,
      BigInt(1),
      'FMD Vaccine',
      BigInt(Math.floor(Date.now() / 1000))
    );
    
    expect(hash).toMatch(/^0x[0-9a-fA-F]{64}$/);
    
    // Verify vaccine was added
    const bovine = await getBovine(BigInt(1));
    expect(bovine.vaccines.length).toBeGreaterThan(0);
  });

  it('should fetch all bovines by breed', async () => {
    const holsteins = await getBovinesByBreed('Holstein');
    expect(holsteins.length).toBe(20); // 100 / 5 breeds
  });
});
```

## Conclusion

The viem + wagmi migration improves:
1. **Developer experience** with native TypeScript and React hooks
2. **Bundle size** for future frontend deployments
3. **Type safety** at compile time rather than runtime
4. **Future-proofing** as viem becomes the de facto standard

The Express server continues to work identically — only the internal implementation changes. The migration can be done incrementally without breaking existing functionality.

---

**Status:** Migration guide created  
**Priority:** P3 (Low / DX)  
**Effort:** M (1-5 days)  
**Dependencies:** None (can be done in parallel with other work)
