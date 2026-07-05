# Polygon Amoy Testnet Deployment Runbook

## Overview

This document describes how to deploy ranch_ledger contracts to Polygon Amoy testnet for external testing and integration validation.

**Network Details:**
- **Name:** Polygon Amoy Testnet
- **Chain ID:** 80002
- **RPC URL:** `https://rpc-amoy.polygon.technology`
- **Block Explorer:** https://amoy.polygonscan.com
- **Gas Token:** MATIC (testnet)

**Why Amoy?**
- Polygon's testnet for development and testing
- Free testnet MATIC from faucet
- Fast block times (~2s)
- Compatible with mainnet deployment patterns

## Prerequisites

1. **Foundry installed** (`forge --version` should return ≥ 0.2.0)
2. **Polygon wallet** with testnet MATIC
3. **Environment variables configured:**
   ```bash
   export AMOY_RPC_URL=https://rpc-amoy.polygon.technology
   export PRIVATE_KEY_AMOY=0x_your_private_key_here
   ```

## Getting Testnet MATIC

1. Visit the [Polygon Faucet](https://faucet.polygon.technology/)
2. Select "Amoy Testnet"
3. Enter your wallet address
4. Request 0.5 MATIC (sufficient for multiple deployments)

Alternative: Use [Chainlink Faucet](https://faucets.chain.link/polygon/amoy)

## Deployment Steps

### Step 1: Verify Environment

```bash
# Check Foundry version
forge --version

# Test RPC connectivity
cast block-number --rpc-url $AMOY_RPC_URL

# Verify wallet balance (should be > 0 MATIC)
cast balance $(cast wallet address --private-key $PRIVATE_KEY_AMOY) --rpc-url $AMOY_RPC_URL
```

### Step 2: Build Contracts

```bash
forge build
```

Expected output:
```
Compiler run successful!
[⠊] Compiling...
[⠒] Compiling 3 files with Solc 0.8.28
[⠢] Solc 0.8.28 finished in 1.2s
```

### Step 3: Deploy to Amoy

```bash
forge script script/DeployAmoy.s.sol --broadcast -vvvv \
  --rpc-url $AMOY_RPC_URL \
  --private-key $PRIVATE_KEY_AMOY
```

Expected output:
```
Deploying from: 0xYourAddress...
RPC URL: https://rpc-amoy.polygon.technology
BovineTracking deployed to: 0xContract1...
BovineNFT deployed to: 0xContract2...
RanchToken deployed to: 0xContract3...

=== Deployment Summary ===
BovineTracking: 0xContract1...
BovineNFT:      0xContract2...
RanchToken:     0xContract3...
Network:        Polygon Amoy Testnet

Deployment info written to deployments/amoy.json
```

### Step 4: Verify Deployment

Check the deployment file:
```bash
cat deployments/amoy.json
```

Expected format:
```json
{
  "BovineTracking": "0x...",
  "BovineNFT": "0x...",
  "RanchToken": "0x..."
}
```

### Step 5: Verify Contracts on Polygonscan

1. Visit https://amoy.polygonscan.com/verifyContract
2. Select each contract address
3. Upload the corresponding source file from `out/` directory:
   - `BovineTracking.sol/BovineTracking.json` → BovineTracking.sol
   - `BovineNFT.sol/BovineNFT.json` → BovineNFT.sol
   - `RanchToken.sol/RanchToken.json` → RanchToken.sol
4. Fill in constructor arguments (admin address)
5. Click "Verify and Publish"

## Post-Deployment Testing

### Test Contract Interaction

```bash
# Check contract balance
cast balance 0xContractAddress --rpc-url $AMOY_RPC_URL

# Call a view function
cast call 0xContractAddress "totalBovines()" --rpc-url $AMOY_RPC_URL

# Send a test transaction (requires funded account)
cast send 0xContractAddress "addBovine(string,uint256,string,string,address)" \
  "TestCattle" 5 "Holstein" "Farm A" 0xYourAddress \
  --rpc-url $AMOY_RPC_URL \
  --private-key $PRIVATE_KEY_AMOY \
  --gas-price 30000000000  # 30 gwei
```

### Monitor Transactions

1. Visit https://amoy.polygonscan.com/txs
2. Look for recent transactions from your deployer address
3. Verify contract interactions are successful

## Cost Estimation

**Deployment Costs (Amoy):**
- BovineTracking: ~50,000 gas × 30 gwei = 0.0015 MATIC
- BovineNFT: ~120,000 gas × 30 gwei = 0.0036 MATIC  
- RanchToken: ~80,000 gas × 30 gwei = 0.0024 MATIC
- **Total deployment:** ~0.0075 MATIC (~$0.003 USD)

**Transaction Costs (Amoy):**
- addBovine: ~150,000 gas × 30 gwei = 0.0045 MATIC
- addVaccine: ~80,000 gas × 30 gwei = 0.0024 MATIC
- **Typical transaction:** ~$0.001-0.005 USD

## Troubleshooting

### "Insufficient funds" error

**Cause:** Wallet doesn't have enough testnet MATIC

**Solution:**
```bash
# Check balance
cast balance $(cast wallet address --private-key $PRIVATE_KEY_AMOY) --rpc-url $AMOY_RPC_URL

# Get more from faucet
# Visit https://faucet.polygon.technology/ and request Amoy MATIC
```

### "Nonce too low" error

**Cause:** Transaction ordering issue (rare on testnets)

**Solution:** Wait a few seconds and retry, or use `--nonce N` to specify exact nonce

### "Contract deployment failed" error

**Cause:** Constructor arguments mismatch or out of gas

**Solution:**
1. Verify constructor parameters match the contract signature
2. Increase gas limit with `--gas-limit 5000000`
3. Check compiler version matches (should be 0.8.28)

### "RPC connection failed" error

**Cause:** Network connectivity issue or RPC rate limiting

**Solution:**
```bash
# Test basic connectivity
curl -X POST https://rpc-amoy.polygon.technology \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Try alternative RPC endpoints
export AMOY_RPC_URL=https://polygon-amoy-rpc.publicnode.com
```

## Security Considerations

⚠️ **IMPORTANT:** This is a TESTNET deployment only.

- Never use mainnet private keys for testnet deployments
- Testnet contracts have no real value but demonstrate functionality
- For production, deploy to Polygon PoS mainnet with proper security audits
- Consider using hardware wallets (Ledger/Trezor) for mainnet deployments

## Next Steps

1. **Integration Testing:** Use the deployed contracts in your application
2. **Performance Testing:** Measure gas costs and transaction times on real network
3. **Mainnet Preparation:** Review deployment for production readiness
4. **Documentation Update:** Add contract addresses to README.md after successful deployment

## Cleanup

After testing, you can optionally:
- Delete `deployments/amoy.json` if not needed
- Revoke any testnet permissions granted during testing
- Document lessons learned for mainnet deployment planning

---

**Last Updated:** 2026-07-05  
**Maintainer:** ranch_ledger team
