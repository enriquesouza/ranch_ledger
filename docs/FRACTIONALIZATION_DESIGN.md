# NFT Fractionalization — Architecture & Design Document

**Status:** Implemented
**Priority:** P1 (High)
**Effort:** L (1-3 weeks)
**Dependencies:** BovineNFT (ERC-721), OpenZeppelin v5.1.0

## Overview
The FractionalizationManager enables bovine NFT owners to fractionalize their cattle NFT into tradable ERC-20 shares. Each share represents proportional ownership of the underlying cow. Investors can buy shares, and when the cow is sold or slaughtered, proceeds are distributed proportionally to shareholders.

**Key Innovation:** RWA (Real World Asset) tokenization of cattle — each cow becomes a tradable, divisible asset on-chain.

## Problem Statement
- Cattle are high-value, illiquid assets ($500-$2000 per head)
- Ranchers need upfront capital but selling entire animals is all-or-nothing
- Investors want exposure to cattle as an asset class but can't buy partial cows
- No existing EVM tool enables fractional ownership of individual cattle

**Solution:** NFT fractionalization — each cow NFT is deposited into a manager contract, which mints ERC-20 share tokens representing proportional ownership.

## Architecture

### Core Components
```
┌─────────────────────────────────────────────────────────────┐
│                FractionalizationManager                      │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              NFT Custody                                ││
│  │  • Holds fractionalized BovineNFTs                      ││
│  │  • Tracks ownership via Fractionalization struct        ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Share Token Factory                         ││
│  │  • Creates BovineShareToken per NFT                     ││
│  │  • Names: "Bovine Share #<tokenId>"                     ││
│  │  • Symbols: "BOVN-<tokenId>"                            ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Marketplace                                 ││
│  │  • buyShares() — buy with ETH                           ││
│  │  • redeemShares() — proportional payout after sale       ││
│  │  • markAsSold() — trigger redemption window              ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Data Flow
1. **Owner fractionalizes** → NFT transferred to manager, BovineShareToken created, all shares minted to owner
2. **Investors buy shares** → ETH sent to manager, shares transferred from owner to investor, ETH forwarded to original owner
3. **Cow is sold/slaughtered** → LIQUIDATOR_ROLE calls markAsSold(tokenId, salePrice)
4. **Shareholders redeem** → shares burned, proportional ETH payout received

## Smart Contracts

### FractionalizationManager.sol

```solidity
contract FractionalizationManager is AccessControl, ReentrancyGuardTransient {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    
    struct Fractionalization {
        address owner;
        uint256 totalShares;
        uint256 initialPrice;
        bool isFractionalized;
        uint256 salePrice;
        bool isSold;
    }
    
    mapping(uint256 => Fractionalization) private _fractionalizations;
    mapping(uint256 => address) public tokenToShareContract;
    mapping(address => uint256) public shareContractToTokenId;
}
```

**Key functions:**
- `fractionalize(address nftContract, uint256 tokenId, uint256 totalShares, uint256 initialPricePerShare)` — transfers NFT to manager, creates BovineShareToken, mints all shares to owner
- `buyShares(address nftContract, uint256 tokenId, uint256 sharesToBuy)` — payable, buys shares with ETH
- `redeemShares(uint256 tokenId)` — burns shares, sends proportional ETH payout
- `markAsSold(uint256 tokenId, uint256 salePrice)` — LIQUIDATOR_ROLE only, sets sale price and triggers redemption

**Errors:** NFTNotOwnedByManager, AlreadyFractionalized, NotFractionalized, InsufficientShares, InvalidSalePrice, SaleNotComplete

**Events:** Fractionalized, SharesPurchased, SharesRedeemed, SaleComplete

### BovineShareToken.sol

```solidity
contract BovineShareToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    address public immutable underlyingNft;
    uint256 public immutable tokenId;
    
    constructor(string memory name_, string memory symbol_, address _underlyingNft, uint256 _tokenId)
        ERC20(name_, symbol_)
}
```

- Per-cow ERC-20 with immutable references to underlying NFT
- MINTER_ROLE for minting (held by FractionalizationManager)
- burnFrom() for redemption flow (requires allowance)

## Use Cases

### 1. Rancher Capital Raising
A rancher with 50 cows worth $1000 each can fractionalize each cow into 100 shares at $10/share, raising capital while retaining partial ownership.

### 2. Investment Fund
An investor can buy shares across multiple cows, diversifying their cattle portfolio without buying entire animals.

### 3. Cooperative Model
A cooperative can fractionalize a herd and distribute shares to members proportional to their contribution.

### 4. Slaughter Proceeds Distribution
When a cow is slaughtered, the sale price is set via markAsSold(), and shareholders redeem their proportional proceeds.

## Security Considerations

- **NFT Custody:** Manager holds the NFT — simple custody model, no proxy pattern
- **ReentrancyGuard:** All state-changing functions use nonReentrant modifier
- **AccessControl:** ADMIN_ROLE for management, LIQUIDATOR_ROLE for marking sold
- **Share token creation:** Dynamic `new BovineShareToken(...)` per fractionalization
- **Proportional payout:** `proceedsPerShare = salePrice / totalShares` — integer division, small rounding loss possible

## Future Enhancements

- **Secondary market:** DEX integration for trading shares without going through buyShares()
- **Dividend distribution:** Ongoing payouts from milk/wool production (not just slaughter)
- **Health-score-adjusted pricing:** Share price adjusts based on BovineTracking health data
- **Integration with RanchLendingVault:** Use share tokens as collateral for loans
- **GovernorRanch integration:** Shareholders vote on cattle management decisions