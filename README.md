# Arcadia Protocol

> **Where Digital Capital Builds the Real World**

[![Demo Video](https://img.shields.io/badge/Demo-Watch%20Video-red?style=for-the-badge&logo=youtube)](https://youtu.be/6SjM-wrfU0E)

A decentralized financial engine built on Stacks that transforms dormant Bitcoin holdings into productive capital for acquiring real-world assets through self-liquidating loans.

## Overview

The Arcadia Protocol is a decentralized prime brokerage layer for the tokenized world. It enables holders of digital assets (starting with Bitcoin via sBTC) to finance high-value, real-world assets without selling their holdings. The protocol's revolutionary **Yield Accelerator Engine** uses collateral yield to automatically pay down loan principal, creating the first truly self-liquidating financing protocol.

## Core Innovation: The Three Pillars

### 1. Universal Collateral Vault
- Lock sBTC as collateral in secure smart contract vaults
- Mint stablecoin loans against collateral
- Acquire real-world assets with the liquidity
- Asset ownership is tokenized as NFTs held in protocol escrow
- NFT transfers to borrower upon loan completion

### 2. Yield Accelerator Engine
The protocol's killer feature that transforms passive collateral into active loan repayment:
- Locked sBTC is deployed into vetted yield strategies (Stacks staking, DeFi protocols)
- Generated yield automatically pays down loan principal
- Transforms 30-year loans into potentially 5-10 year payoffs
- Multiple strategy options with varying risk/reward profiles

### 3. Stability & Insurance Pool
A guardian system that replaces harsh liquidations:
- Protocol revenue feeds a stablecoin Stability Pool
- Automatic intervention during market volatility
- Makes loan payments on behalf of users when needed
- Protects users from cascading liquidations

## Smart Contracts

The protocol consists of five core contracts deployed on Stacks testnet:

### Core Contracts
- **arcadia-core** (`ST336VQZA4VAGC9RQVX5F95FCCSVBV99Z3JA1MJJ9.arcadia-core`)
  - Main protocol logic for loan creation and management
  - Collateral vault system
  - Stability pool operations

- **yield-strategy** (`ST336VQZA4VAGC9RQVX5F95FCCSVBV99Z3JA1MJJ9.yield-strategy`)
  - Manages yield generation from locked collateral
  - Multiple strategy implementations (conservative to aggressive)
  - Automated yield compounding and distribution

- **asset-nft** (`ST336VQZA4VAGC9RQVX5F95FCCSVBV99Z3JA1MJJ9.asset-nft`)
  - SIP-009 compliant NFT for tokenized asset ownership
  - Asset verification and appraisal tracking
  - Legal description and document management

### Token Contracts
- **ant-token** - Arcadia Note Token (SIP-010)
  - Yield-bearing tokens representing loan cash flows
  - Enables secondary market trading of loan positions
  - Automated yield distribution to token holders

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   User Interface                    │
└─────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────┐
│                  Arcadia Core                       │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │ Loan Manager │  │ Collateral   │  │ Stability │ │
│  │              │  │ Vaults       │  │ Pool      │ │
│  └──────────────┘  └──────────────┘  └───────────┘ │
└─────────────────────────────────────────────────────┘
         │                    │                  │
    ┌────────┐         ┌──────────┐      ┌──────────┐
    │ Asset  │         │  Yield   │      │   ANT    │
    │  NFT   │         │ Strategy │      │  Token   │
    └────────┘         └──────────┘      └──────────┘
```

## Features

### For Borrowers
- **Capital Efficient**: Maintain Bitcoin exposure while accessing liquidity
- **Self-Liquidating Loans**: Collateral yield automatically pays down principal
- **Protection from Liquidation**: Stability pool provides buffer during market volatility
- **Real Asset Ownership**: Clear, tokenized proof of ownership via NFTs

### For Investors (ANT Token Holders)
- **Yield-Bearing Assets**: Earn from loan cash flows
- **Secondary Market**: Trade loan positions via ANT tokens
- **Diversification**: Access to real-world asset-backed yield
- **Transparent Returns**: On-chain tracking of all yield distributions

## Technology Stack

- **Blockchain**: Stacks (Bitcoin Layer 2)
- **Smart Contracts**: Clarity
- **Token Standards**: SIP-009 (NFT), SIP-010 (Fungible Token)
- **Development**: Clarinet SDK, Vitest
- **Collateral**: sBTC (Secured Bitcoin)

## Getting Started

### Prerequisites
```bash
# Install Clarinet
curl -L https://install.clarinet.io | sh

# Install dependencies
npm install
```

### Development

```bash
# Run tests
npm test

# Run with coverage
npm run test:report

# Watch mode
npm run test:watch

# Start local devnet
clarinet integrate
```

### Deploy to Testnet

```bash
# Generate deployment plan
clarinet deployment generate --testnet

# Deploy contracts
clarinet deployment apply -p deployments/default.testnet-plan.yaml
```

## Project Structure

```
├── contracts/
│   ├── arcadia-core.clar       # Main protocol logic
│   ├── yield-strategy.clar     # Yield generation strategies
│   ├── asset-nft.clar          # Asset ownership NFTs
│   ├── ant-token.clar          # Arcadia Note Tokens
│   ├── sip-009-nft-trait.clar  # NFT standard
│   └── sip-010-ft-trait.clar   # Fungible token standard
├── tests/                      # Vitest test suites
├── deployments/               # Deployment configurations
└── settings/                  # Network settings
```

## Roadmap

### Phase 1: Launch (Current)
- ✅ Core smart contracts
- ✅ Testnet deployment
- 🔄 Initial yield strategies
- 🔄 Basic frontend interface

### Phase 2: Expansion
- [ ] Mainnet launch with Arcadia Homes vertical
- [ ] Secondary market for ANT tokens
- [ ] Advanced yield strategies
- [ ] Oracle integration for asset pricing

### Phase 3: Platform
- [ ] Arcadia Auto (vehicle financing)
- [ ] Arcadia Founders (startup financing)
- [ ] Arcadia Gallery (art & collectibles)
- [ ] Multi-asset support beyond sBTC

## Why Stacks?

1. **Generational Security**: Real-world assets require multi-decade contracts. Only Stacks inherits Bitcoin's generational security and social consensus.

2. **Native Bitcoin Programmability**: sBTC enables Bitcoin to be used productively in DeFi for the first time, powering our Yield Accelerator Engine.

3. **Clarity's Predictability**: Long-term financial agreements demand transparent, predictable smart contract execution.


## Security

This is experimental software under active development. Contracts have not been formally audited. Use at your own risk on testnet only.

## License

MIT License - see [LICENSE](LICENSE) for details.


---

**Built in Goa, India** 🌴 - Where ancient fishing businesses meet cutting-edge crypto startups, proving the universal need for capital bridges.
