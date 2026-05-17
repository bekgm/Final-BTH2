# Prediction Market Protocol

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FF6B6B.svg)](https://book.getfoundry.sh/)

A decentralized prediction market protocol with AMM-based pricing, DAO governance, and L2 deployment. Built with Foundry, OpenZeppelin, The Graph, and React.

## Overview

This protocol enables users to create and trade on binary outcome markets (YES/NO). Features include:
- **AMM Pricing**: Constant Product Market Maker (CPMM) with 0.3% fees
- **ERC-1155 Outcome Tokens**: Semi-fungible shares for each market outcome
- **DAO Governance**: OpenZeppelin Governor with 4% quorum, 1-day voting delay, 1-week voting period
- **Timelock Security**: 2-day execution delay for all governance actions
- **Chainlink Oracle**: Price feed integration with staleness checks
- **Fee Vault**: ERC-4626 vault for LP yield
- **L2 Deployment**: Deployed and verified on Base Sepolia

## Live Deployment (Base Sepolia)

| Contract | Address | Explorer |
|----------|---------|----------|
| **PredictionMarket (Proxy)** | `0x8A3711811c65E275343edbfBd6bF3350be1A79EC` | [View](https://sepolia.basescan.org/address/0x8A3711811c65E275343edbfBd6bF3350be1A79EC) |
| **PredictionMarket (Impl)** | `0x5EdF3a469317102BA4a2acC27575C1bcfbb9EcE5` | [View](https://sepolia.basescan.org/address/0x5EdF3a469317102BA4a2acC27575C1bcfbb9EcE5) |
| **GovernanceToken (PGOV)** | `0x2Ecb7aE92E533d3B304819be05a4BF86A01E3818` | [View](https://sepolia.basescan.org/address/0x2Ecb7aE92E533d3B304819be05a4BF86A01E3818) |
| **PredictionGovernor** | `0x661301A0628c8179109E13ae9AAa415e454Ff433` | [View](https://sepolia.basescan.org/address/0x661301A0628c8179109E13ae9AAa415e454Ff433) |
| **GovernorTimelock** | `0x53EbE1e93C26e29D65b23F4545bB44f4ad9ec8C1` | [View](https://sepolia.basescan.org/address/0x53EbE1e93C26e29D65b23F4545bB44f4ad9ec8C1) |
| **OutcomeToken** | `0x7809294178Da7e0a196b75F655F4Bc2532f79D6F` | [View](https://sepolia.basescan.org/address/0x7809294178Da7e0a196b75F655F4Bc2532f79D6F) |
| **FeeVault** | `0x23eDdf60043b45776bf9591658e4DDfeb8c77850` | [View](https://sepolia.basescan.org/address/0x23eDdf60043b45776bf9591658e4DDfeb8c77850) |
| **OracleAdapter** | `0x85fA9B9103AAc1F9Ae2b28aCD83687685643054c` | [View](https://sepolia.basescan.org/address/0x85fA9B9103AAc1F9Ae2b28aCD83687685643054c) |
| **MockAggregator** | `0xA6d9791a04Bbd5AD316a67b430d9A30c3BeB407a` | [View](https://sepolia.basescan.org/address/0xA6d9791a04Bbd5AD316a67b430d9A30c3BeB407a) |

**Network**: Base Sepolia (Chain ID: 84532)  
**USDC**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`  
**Block Explorer**: https://sepolia.basescan.org

## Architecture

### System Diagram (C4 Level 1)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           External Systems                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │   Chainlink  │  │   The Graph  │  │    USDC      │  │ Base Sepolia │ │
│  │    Oracles   │  │   Subgraph   │  │   Token      │  │   L2 Chain   │ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘ │
└─────────┼─────────────────┼─────────────────┼─────────────────┼─────────┘
          │                 │                 │                 │
┌─────────┼─────────────────┼─────────────────┼─────────────────┼─────────┐
│         │                 │                 │                 │         │
│   ┌─────▼─────────────────▼─────────────────▼─────────────────▼─────┐   │
│   │              Prediction Market Protocol                         │   │
│   │   ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐  │   │
│   │   │  Prediction │ │  ERC-1155   │ │   ERC-4626 FeeVault    │  │   │
│   │   │   Market    │ │   Tokens    │ │  ┌───────────────────┐  │  │   │
│   │   │  (UUPS)     │ │             │ │  │ Governance Token │  │  │   │
│   │   │  ┌────────┐ │ │ ┌─────────┐ │ │  │  (ERC20Votes)   │  │  │   │
│   │   │  │  AMM   │ │ │ │  YES/   │ │ │  │                 │  │  │   │
│   │   │  │ (Yul)  │ │ │ │   NO    │ │ │  │  ┌───────────┐  │  │  │   │
│   │   │  │x·y=k  │ │ │ │         │ │ │  │  │ Governor  │  │  │  │   │
│   │   │  └────────┘ │ │ └─────────┘ │ │  │  │ + Timelock│  │  │  │   │
│   │   └─────────────┘ └─────────────┘ │  │  └───────────┘  │  │  │   │
│   │                                   │  └───────────────────┘  │   │
│   └───────────────────────────────────┴───────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### Contract Relationships

```
┌─────────────────────────────────────────────────────────────────────┐
│                          GOVERNANCE LAYER                              │
│  PredictionGovernor ──► GovernorTimelock ──► Controls all contracts  │
│  (1 day delay)         (2 day delay)                                  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ owns (all admin roles)
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          MARKET LAYER                                │
│  PredictionMarket (Proxy) ◄─── PredictionMarket (Implementation)    │
│       │                                                     │       │
│       ├─► OutcomeToken (ERC-1155)                          │       │
│       ├─► FeeVault (ERC-4626)                              │       │
│       └─► OracleAdapter ──► Chainlink                     │       │
└─────────────────────────────────────────────────────────────────────┘
```

## Features Implemented

### Smart Contracts

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| **UUPS Proxy** | `PredictionMarket` with ERC1967 proxy | ✅ |
| **Inline Yul** | `AMM.getAmountOutAssembly()` vs `getAmountOut()` benchmark | ✅ |
| **ERC-20 Votes** | `GovernanceToken` (ERC20Votes + ERC20Permit) | ✅ |
| **ERC-1155** | `OutcomeToken` for YES/NO outcomes | ✅ |
| **ERC-4626** | `FeeVault` with full rounding invariants | ✅ |
| **CPMM AMM** | Constant product `x·y=k` with 0.3% fee | ✅ |
| **Chainlink Oracle** | `OracleAdapter` with staleness check | ✅ |
| **OpenZeppelin Governor** | Full stack: Governor + Timelock + Token | ✅ |
| **Access Control** | Role-based permissions throughout | ✅ |
| **Reentrancy Guard** | All external calls protected | ✅ |

### Governance Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Voting Delay | 1 day (86400 seconds) | Time before voting starts |
| Voting Period | 1 week (604800 seconds) | Duration of voting |
| Quorum | 4% | Minimum participation for valid vote |
| Proposal Threshold | 1M PGOV (1% of max) | Minimum to create proposal |
| Timelock Delay | 2 days (172800 seconds) | Execution delay after passing |
| Max PGOV Supply | 100,000,000 | Hard cap on governance tokens |

### Subgraph (The Graph)

| Entity | Purpose |
|--------|---------|
| `Market` | Market metadata, reserves, resolution state |
| `Trade` | Buy/sell transactions with price data |
| `LiquidityEvent` | Add/remove liquidity operations |
| `User` | Trading stats, volume, positions |
| `DailyVolume` | Time-series volume aggregation |

**8 GraphQL Queries**: See `subgraph/queries.graphql`
- GetActiveMarkets
- GetMarketWithTrades
- GetUserProfile
- GetUserTrades
- GetMarketDailyVolume
- GetTopTraders
- GetProviderLiquidityEvents
- GetMarketsByVolume

## Project Structure

```
.
├── src/
│   ├── core/
│   │   ├── PredictionMarket.sol    # Main market contract (UUPS)
│   │   ├── AMM.sol                  # Constant product AMM with Yul
│   │   └── PredictionMarketV2.sol   # V2 upgrade (placeholder)
│   ├── governance/
│   │   ├── PredictionGovernor.sol   # OZ Governor implementation
│   │   └── GovernorTimelock.sol     # 2-day timelock
│   ├── tokens/
│   │   ├── GovernanceToken.sol      # ERC20Votes + ERC20Permit
│   │   └── OutcomeToken.sol         # ERC-1155 outcome shares
│   ├── vault/
│   │   └── FeeVault.sol             # ERC-4626 fee vault
│   ├── oracle/
│   │   ├── OracleAdapter.sol        # Chainlink integration
│   │   └── MockAggregator.sol         # Test mock
│   └── interfaces/                   # All interface definitions
├── script/
│   ├── Deploy.s.sol                 # Main deployment (L2)
│   ├── VerifyDeployment.s.sol       # Post-deployment checks
│   └── LocalDeploy.s.sol            # Local Anvil deployment
├── test/
│   ├── AMM.t.sol                    # AMM unit & fuzz tests
│   ├── PredictionMarket.t.sol      # Market lifecycle tests
│   ├── Governance.t.sol             # Governor lifecycle tests
│   └── FeeVault.t.sol               # ERC-4626 invariant tests
├── subgraph/
│   ├── schema.graphql               # 5 entity definitions
│   ├── mappings.ts                  # Event handlers
│   └── queries.graphql              # 8 documented queries
├── frontend/                         # React + Wagmi dashboard
├── docs/
│   ├── Architecture.md              # 6+ page architecture doc
│   ├── SecurityAudit.md             # 8+ page audit report
│   └── CoverageReport.md            # Forge coverage results
└── .github/workflows/
    └── ci.yml                        # CI with tests, coverage, Slither
```

## Prerequisites

- **Foundry** (`forge`, `cast`, `anvil`) — [Installation](https://book.getfoundry.sh/)
- **Node.js** 18+ and `npm`
- **Docker** (for local Graph Node)
- **@graphprotocol/graph-cli** — `npm install -g @graphprotocol/graph-cli`

## Quick Start

### 1. Local Development

```bash
# Start local chain
anvil

# Deploy contracts locally
forge script script/LocalDeploy.s.sol:LocalDeployScript \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

### 2. Deploy to Base Sepolia

```bash
# Create .env file
export PRIVATE_KEY=0x...
export RPC_URL=https://sepolia.base.org
export ETHERSCAN_API_KEY=your_basescan_api_key
export USDC=0x036CbD53842c5426634e7929541eC2318f3dCF7e

# Deploy and verify
source .env && forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### 3. Run Verification Script

```bash
# Check all governance parameters and ownership
source .env && forge script script/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url $RPC_URL
```

### 4. Start Subgraph Locally

```bash
cd subgraph
docker compose up -d
npm ci
npm run codegen
npm run build
graph create --node http://localhost:8020/ prediction-protocol
graph deploy --node http://localhost:8020/ --ipfs http://localhost:5001/ prediction-protocol
```

### 5. Run Frontend

```bash
cd frontend
npm ci
npm run dev
```

## Testing

### Run All Tests

```bash
# Unit tests
forge test

# Coverage report
forge coverage --report summary

# Fuzz tests (included in test suite)
forge test --match-test "Fuzz"

# Invariant tests
forge test --match-test "Invariant"
```

### Test Coverage

| Component | Line Coverage | Status |
|-----------|---------------|--------|
| AMM | 95.23% | ✅ |
| PredictionMarket | 89.34% | ✅ |
| OutcomeToken | 92.59% | ✅ |
| GovernanceToken | 88.24% | ✅ |
| FeeVault | 87.50% | ✅ |
| OracleAdapter | 91.30% | ✅ |
| **Total** | **~90%** | ✅ |

### Security Tools

```bash
# Run Slither static analysis
slither src/ --config-file slither.config.json

# Format code
forge fmt

# Gas snapshot
forge snapshot
```

## CI/CD

GitHub Actions workflow (`.github/workflows/ci.yml`) runs on every push/PR:
- ✅ `forge build` — compilation
- ✅ `forge test` — full test suite
- ✅ `forge coverage` — coverage report
- ✅ Slither analysis — static security checks
- ✅ Frontend build & typecheck
- ✅ Subgraph codegen & build

## Documentation

| Document | Purpose | Location |
|----------|---------|----------|
| **Architecture** | C4 diagrams, storage layouts, ADRs | [`docs/Architecture.md`](docs/Architecture.md) |
| **Security Audit** | Findings, risk analysis, attack scenarios | [`docs/SecurityAudit.md`](docs/SecurityAudit.md) |
| **Coverage Report** | Test coverage details | [`docs/CoverageReport.md`](docs/CoverageReport.md) |

## Design Patterns Used

1. **UUPS Proxy** — Upgradeable contracts with admin-controlled upgrades
2. **Factory Pattern** — Contract deployment via Foundry scripts
3. **Checks-Effects-Interactions** — All external calls follow CEI pattern
4. **Access Control** — Role-based permissions (OpenZeppelin)
5. **Timelock** — 2-day delay on all governance actions
6. **Oracle Adapter** — Abstracted oracle interface for flexibility
7. **State Machine** — Market lifecycle (Active → Resolved → Redeemable)
8. **Pausable** — Emergency pause capability
9. **Reentrancy Guard** — Protection against reentrancy attacks

## Gas Comparison: L1 vs L2 (Base)

### Methodology

Measured using `forge test --gas-report` on identical contract bytecode. L1 costs use 20 gwei base fee, L2 costs use 0.001 gwei base fee plus L1 data availability costs.

### Deployment Costs

| Contract | L1 Gas | L2 Execution Gas | L1 Data Cost | Total L2 Cost | Savings |
|----------|--------|------------------|--------------|---------------|---------|
| **MockAggregator** | ~347k | ~347k | ~140k | ~487k | ~98% |
| **OracleAdapter** | ~527k | ~527k | ~210k | ~737k | ~98% |
| **OutcomeToken** (ERC-1155) | ~1.97M | ~1.97M | ~790k | ~2.76M | ~98% |
| **FeeVault** (ERC-4626) | ~1.71M | ~1.71M | ~684k | ~2.39M | ~98% |
| **PredictionMarket** (Impl) | ~4.16M | ~4.16M | ~1.66M | ~5.82M | ~98% |
| **GovernanceToken** (ERC20Votes) | ~2.34M | ~2.34M | ~936k | ~3.28M | ~98% |
| **GovernorTimelock** | ~1.18M | ~1.18M | ~472k | ~1.65M | ~98% |
| **PredictionGovernor** | ~2.05M | ~2.05M | ~820k | ~2.87M | ~98% |

### Transaction Costs (User Operations)

| Operation | L1 Gas | L2 Execution | L1 Data | L2 Total | L1 Cost* | L2 Cost* | Savings |
|-----------|--------|--------------|---------|----------|----------|----------|---------|
| **Create Market** | 185,420 | 185,420 | 74,168 | 259,588 | $11.12 | $0.006 | 99.9% |
| **Buy Tokens (AMM)** | 142,380 | 142,380 | 56,952 | 199,332 | $8.54 | $0.005 | 99.9% |
| **Sell Tokens (AMM)** | 128,640 | 128,640 | 51,456 | 180,096 | $7.72 | $0.004 | 99.9% |
| **Add Liquidity** | 167,520 | 167,520 | 67,008 | 234,528 | $10.05 | $0.005 | 99.9% |
| **Remove Liquidity** | 154,280 | 154,280 | 61,712 | 215,992 | $9.26 | $0.005 | 99.9% |
| **Redeem Winnings** | 98,740 | 98,740 | 39,496 | 138,236 | $5.92 | $0.003 | 99.9% |
| **Governance Proposal** | 234,680 | 234,680 | 93,872 | 328,552 | $14.08 | $0.008 | 99.9% |
| **Vote** | 87,420 | 87,420 | 34,968 | 122,388 | $5.25 | $0.003 | 99.9% |
| **Execute Proposal** | 178,920 | 178,920 | 71,568 | 250,488 | $10.74 | $0.006 | 99.9% |

\* L1: 20 gwei base fee × 1.5 priority fee, ETH=$2000  
\* L2: 0.001 gwei execution + L1 data calldata at 16 gas/byte

### Gas Optimization: Solidity vs Yul Assembly

The `AMM.getAmountOut()` function has two implementations:

| Implementation | Avg Gas | Savings |
|----------------|---------|---------|
| **Solidity** (baseline) | 2,847 | — |
| **Yul Assembly** | 2,521 | **11.4%** |

Benchmarked with `forge test --match-test testGasComparison --gas-report`

```bash
# Run gas benchmark
forge test --match-test "GasComparison" --gas-report -vv
```

### Key Findings

1. **L2 execution gas equals L1 gas** — Same EVM bytecode runs identically
2. **Savings come from L2 fee market** — Base L2 charges ~0.001 gwei vs L1's 10-50 gwei
3. **Data availability costs** — L2s post compressed data to L1 (~40% of L1 cost)
4. **Total user savings** — ~99% cheaper for all operations
5. **Yul optimization** — 11% gas savings on hot path (AMM pricing)

## Security

### Audits

- **Internal Audit**: [`docs/SecurityAudit.md`](docs/SecurityAudit.md)
  - 1 High, 2 Medium, 4 Low, 3 Informational findings
  - All High/Medium fixed, Low/Info acknowledged with justification
  - Slither: Zero High/Medium findings

### Access Control

All privileged functions use OpenZeppelin AccessControl:
- `DEFAULT_ADMIN_ROLE` → Timelock only
- `MARKET_CREATOR_ROLE` → Timelock only
- `UPGRADER_ROLE` → Timelock only
- `MINTER_ROLE` → Timelock only
- `PAUSER_ROLE` → Timelock only

### Emergency Procedures

- **Pause**: Governance can pause protocol via `PAUSER_ROLE`
- **Upgrade**: Timelock-controlled 2-day delay for all upgrades
- **Oracle Failure**: Governance can update oracle address

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'feat: add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

Use Conventional Commits:
- `feat:` — New feature
- `fix:` — Bug fix
- `test:` — Test changes
- `docs:` — Documentation
- `refactor:` — Code refactoring
- `ci:` — CI/CD changes

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- OpenZeppelin Contracts
- Foundry Toolkit
- The Graph Protocol
- Base L2 Network
- Chainlink Oracles

---

**Deployed by**: Development Team  
**Deployment Date**: May 2026  
**Network**: Base Sepolia (84532)  
**Protocol Version**: v1.0.0
