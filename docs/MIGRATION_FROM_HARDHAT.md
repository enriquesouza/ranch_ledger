# Migration from Hardhat to Foundry

**Status:** Reference Documentation  
**Priority:** P3 (Low / DX)  
**Effort:** S (< 1 day)

---

## Overview

This project was originally built with **Hardhat** and has been fully migrated to **Foundry**. This document serves as a quick reference for developers familiar with Hardhat commands, showing the Foundry equivalent.

## Command Mapping

### Compilation

| Hardhat | Foundry | Notes |
|---------|---------|-------|
| `npx hardhat compile` | `forge build` | Both compile all contracts in `src/` |
| `npx hardhat clean` | `forge clean` | Removes `artifacts/`, `cache/` → `out/`, `cache/` |

### Testing

| Hardhat | Foundry | Notes |
|---------|---------|-------|
| `npx hardhat test` | `forge test` | Runs all `.t.sol` files in `test/` |
| `npx hardhat test --grep "testMint"` | `forge test -m "testMint"` | Filter by function name |
| `npx hardhat test --grep "BovineTracking"` | `forge test -c BovineTrackingTest` | Filter by contract name |
| `npx hardhat test --gas-report` | `forge test --gas-report` | Gas usage per test |
| `npx hardhat test --verbose` | `forge test -vvv` | Verbosity levels: `-v`, `-vv`, `-vvv` |

### Deployment & Scripts

| Hardhat | Foundry | Notes |
|---------|---------|-------|
| `npx hardhat run scripts/deploy.js` | `forge script script/Deploy.s.sol --broadcast` | Script-based deployment |
| `npx hardhat node` | `anvil` | Local Ethereum node |
| `npx hardhat node --port 8545` | `anvil --port 8545` | Specify port |
| `npx hardhat run scripts/deploy.js --network localhost` | `forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast` | Deploy to local node |

### Contract Interaction

| Hardhat | Foundry | Notes |
|---------|---------|-------|
| `npx hardhat console` | `cast rpc eth_blockNumber` (or use `anvil` REPL) | Interactive console |
| `ethers.getContractAt("BovineTracking", address)` | Direct cast calls to contract address | No need for ABI files |

### Configuration

| Hardhat File | Foundry Equivalent | Notes |
|-------------|-------------------|-------|
| `hardhat.config.js` | `foundry.toml` | Main configuration file |
| `.env` (Hardhat network config) | Environment variables + `--rpc-url` flag | No config file needed for RPC URLs |

## Configuration Comparison

### Hardhat Config (`hardhat.config.js`)

```javascript
module.exports = {
  solidity: "0.8.24",
  networks: {
    hardhat: { chainId: 31337 },
    localhost: { url: "http://127.0.0.1:8545" }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  }
};
```

### Foundry Config (`foundry.toml`)

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.28"
optimizer = true
optimizer_runs = 200

[fuzz]
runs = 256
max_test_rejects = 65536
```

**Key differences:**
- Foundry uses TOML instead of JavaScript
- No network configuration needed (passed via CLI flags)
- Solidity version specified in `foundry.toml` or pragma in contracts
- Library paths use git submodules (`lib/`) instead of npm packages

## Project Structure Comparison

### Hardhat Structure

```
ranch_ledger/
├── contracts/          # Smart contracts (.sol files)
│   ├── BovineTracking.sol
│   └── BovineNFT.sol
├── test/               # Test files (.js or .ts)
│   └── bovine_tracking.js
├── scripts/            # Deployment scripts (.js)
│   └── deploy.js
├── artifacts/          # Compiled contracts (generated)
├── cache/              # Compilation cache (generated)
├── hardhat.config.js   # Configuration
├── package.json        # Dependencies + scripts
└── .env                # Environment variables
```

### Foundry Structure

```
ranch_ledger/
├── src/                # Smart contracts (.sol files)
│   ├── BovineTracking.sol
│   └── BovineNFT.sol
├── test/               # Test files (.t.sol)
│   ├── BovineTracking.t.sol
│   └── Tokens.t.sol
├── script/             # Deployment scripts (.s.sol)
│   ├── Deploy.s.sol
│   └── BulkMint.s.sol
├── lib/                # Git submodules (forge-std, OZ)
│   ├── forge-std/
│   └── openzeppelin-contracts/
├── out/                # Compiled contracts (generated)
│   └── BovineTracking.sol/
│       └── BovineTracking.json
├── cache/              # Compilation cache (generated)
├── foundry.toml        # Configuration
├── package.json        # Node scripts for convenience
└── .env                # Environment variables
```

**Key differences:**
- `contracts/` → `src/` (Foundry convention)
- `.js/.ts` tests → `.t.sol` Solidity tests
- `.js` scripts → `.s.sol` Foundry scripts
- `artifacts/` → `out/` (richer output format)
- npm packages → git submodules in `lib/`

## Migration Checklist

If you're migrating a Hardhat project to Foundry, follow these steps:

1. **Install Foundry**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Create `foundry.toml`** with your Solidity version and paths

3. **Move contracts** from `contracts/` to `src/`

4. **Rewrite tests** from `.js/.ts` to `.t.sol` using Foundry's testing library:
   ```solidity
   import "forge-std/Test.sol";
   
   contract MyTest is Test {
       function testSomething() public {
           // assertions
           assertEq(a, b);
           assertTrue(condition);
           vm.expectRevert();
       }
   }
   ```

5. **Rewrite deployment scripts** from `.js` to `.s.sol`:
   ```solidity
   import "forge-std/Script.sol";
   
   contract Deploy is Script {
       function run() external {
           vm.startBroadcast();
           new MyContract();
           vm.stopBroadcast();
       }
   }
   ```

6. **Install dependencies** as git submodules:
   ```bash
   forge install foundry-rs/forge-std
   forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
   ```

7. **Update `package.json` scripts** to use Foundry commands (optional, for convenience)

8. **Test everything** with `forge test -vvv`

## Common Pitfalls

### 1. Test File Naming

Hardhat: Any `.js` or `.ts` file in `test/`  
Foundry: Must end in `.t.sol` and contain a contract extending `Test`

```solidity
// ✅ Correct
contract BovineTrackingTest is Test { ... }

// ❌ Wrong - not a .sol file, doesn't extend Test
contract bovine_tracking_test { ... }
```

### 2. Import Paths

Hardhat: `require("@openzeppelin/contracts/token/ERC721/ERC721.sol");`  
Foundry: `import "@openzeppelin/contracts/token/ERC721/ERC721.sol";` (same syntax, different resolution)

### 3. Gas Reporting

Hardhat: Built into test runner with `gasReporter` plugin  
Foundry: `forge test --gas-report` (built-in, no plugin needed)

### 4. Fuzz Testing

Hardhat: Requires `@nomicfoundation/hardhat-toolbox` or manual setup  
Foundry: Built-in with `[fuzz]` section in `foundry.toml`:
```toml
[fuzz]
runs = 256
max_test_rejects = 65536
```

### 5. Environment Variables

Hardhat: `process.env.PRIVATE_KEY`  
Foundry: `vm.envUint("PRIVATE_KEY")` or `vm.envOr("PRIVATE_KEY", defaultValue)`

## Quick Reference Card

```bash
# Compile
forge build

# Test
forge test                    # All tests
forge test -vvv              # Verbose output
forge test --gas-report      # Gas usage
forge test -m "testMint"     # Filter by name
forge test -c "BovineTest"   # Filter by contract

# Deploy
anvil                        # Start local node
forge script script/Deploy.s.sol --broadcast  # Deploy

# Interact
cast call <address> "balanceOf(address)" <addr>    # Read
cast send <address> "transfer(address,uint256)" <to> <amount>  # Write

# Utilities
forge fmt                  # Format code
forge inspect <contract> abi   # View ABI
forge inspect <contract> storage # View storage layout
```

## Benefits of Foundry Over Hardhat

1. **Faster compilation:** Rust-based compiler vs JavaScript
2. **Better testing:** Native Solidity tests with fuzzing, invariant testing
3. **Simpler deployment:** Script-based with broadcast, no separate deploy step
4. **Richer tooling:** `cast` for RPC calls, `anvil` for local chain, `forge` for build/test/deploy
5. **No npm dependencies:** Git submodules instead of node_modules
6. **Better error messages:** Compiler errors point to exact lines with suggestions

## Conclusion

The migration from Hardhat to Foundry is straightforward for most projects. The main changes are:
- Test files become Solidity contracts extending `Test`
- Deployment scripts become Solidity contracts extending `Script`
- Configuration moves from JavaScript to TOML
- Dependencies move from npm to git submodules

All existing functionality is preserved, and you gain access to Foundry's superior testing and deployment tooling.

---

**Last Updated:** 2026-07-05  
**Maintainer:** ranch_ledger team
