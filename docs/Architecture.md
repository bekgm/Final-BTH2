# Prediction Market Protocol - Architecture Document

## Table of Contents
1. [Executive Summary](#1-executive-summary)
2. [System Context (C4 Level 1)](#2-system-context-c4-level-1)
3. [Container & Component Diagram](#3-container--component-diagram)
4. [Contract Architecture](#4-contract-architecture)
5. [Sequence Diagrams](#5-sequence-diagrams)
6. [Data Model & Storage Layouts](#6-data-model--storage-layouts)
7. [Trust Assumptions](#7-trust-assumptions)
8. [Design Decision Records (ADRs)](#8-design-decision-records-adrs)

---

## 1. Executive Summary

The Prediction Market Protocol is a decentralized prediction market platform built on Ethereum L2 networks (Base, Arbitrum). It enables users to:
- Create prediction markets on any verifiable event
- Trade outcome tokens (YES/NO) representing positions
- Provide liquidity to earn fees
- Participate in protocol governance through PGOV tokens

**Key Technical Characteristics:**
- **UUPS Proxy Pattern**: Upgradeable contracts with timelock-governed upgrades
- **Automated Market Maker (AMM)**: Constant product formula for price discovery
- **Chainlink Integration**: Oracle price feeds for market resolution
- **The Graph Subgraph**: Off-chain data indexing for frontend queries
- **Governance**: OpenZeppelin Governor with timelock-controlled execution

---

## 2. System Context (C4 Level 1)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           External Systems                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │   Chainlink  │  │   The Graph  │  │    USDC      │  │   L2 Nodes   │ │
│  │    Oracles   │  │   Subgraph   │  │   Token      │  │  (Base/Arb)  │ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘ │
└─────────┼─────────────────┼─────────────────┼─────────────────┼─────────┘
          │                 │                 │                 │
          │ Price Feeds     │ Event Indexing  │ Collateral      │ Execution
          │                 │                 │                 │
┌─────────┼─────────────────┼─────────────────┼─────────────────┼─────────┐
│         │                 │                 │                 │         │
│   ┌─────▼─────────────────▼─────────────────▼─────────────────▼─────┐ │
│   │                                                                  │ │
│   │              Prediction Market Protocol                           │ │
│   │         (Smart Contracts + Subgraph + Frontend)                   │ │
│   │                                                                  │ │
│   └──────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│   ┌──────────────────────────────────────────────────────────────────┐ │
│   │                         Actors                                    │ │
│   │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │ │
│   │  │  Trader  │ │ Liquidity│ │  Market  │ │Governance│            │ │
│   │  │          │ │ Provider │ │ Creator  │ │  Voter   │            │ │
│   │  └──────────┘ └──────────┘ └──────────┘ └──────────┘            │ │
│   └──────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

**Actors:**
- **Trader**: Buys/sells outcome tokens, redeems winnings
- **Liquidity Provider**: Adds/removes liquidity, earns trading fees
- **Market Creator**: Creates new prediction markets (governance-controlled)
- **Governance Voter**: Stakes PGOV, creates/votes on proposals

---

## 3. Container & Component Diagram

### 3.1 Contract Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Protocol Contracts                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    GOVERNANCE LAYER                                   │   │
│  │  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────┐  │   │
│  │  │ PredictionGovernor│◄───│ GovernorTimelock │    │GovernanceToken│  │   │
│  │  │                  │    │   (2-day delay)  │    │  (PGOV/vePGOV)│  │   │
│  │  │  - Voting: 1 day │    │                  │    │              │  │   │
│  │  │  - Period: 1 week│    │  - Execution     │    │  - ERC20Votes│  │   │
│  │  │  - Quorum: 4%    │    │  - Delayed ops   │    │  - Permit    │  │   │
│  │  │  - Threshold: 1% │    │                  │    │  - Mintable  │  │   │
│  │  └──────────────────┘    └─────────┬────────┘    └──────────────┘  │   │
│  │                                    │                                 │   │
│  │                                    │ Controls                        │   │
│  │                                    ▼                                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    MARKET LAYER (Upgradeable)                         │   │
│  │                                                                      │   │
│  │   ┌─────────────────────────────────────────────────────────────┐   │   │
│  │   │              PredictionMarket (UUPS Proxy)                   │   │   │
│  │   │  ┌─────────────────────────────────────────────────────────┐  │   │   │
│  │   │  │             PredictionMarket (Implementation)            │  │   │   │
│  │   │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │  │   │   │
│  │   │  │  │   Market     │  │     AMM      │  │   Oracle     │  │  │   │   │
│  │   │  │  │   Storage    │  │  (Constant   │  │  Integration │  │  │   │   │
│  │   │  │  │              │  │   Product)   │  │              │  │  │   │   │
│  │   │  │  │  - question  │  │              │  │  - Price     │  │  │   │   │
│  │   │  │  │  - reserves  │  │  - getAmount │  │    validation│  │  │   │   │
│  │   │  │  │  - outcome   │  │  - swap      │  │  - Resolution│  │  │   │   │
│  │   │  │  │  - fees      │  │  - liquidity │  │              │  │  │   │   │
│  │   │  │  └──────────────┘  └──────────────┘  └──────────────┘  │  │   │   │
│  │   │  └─────────────────────────────────────────────────────────┘  │   │   │
│  │   └─────────────────────────────────────────────────────────────────┘   │   │
│  │                                    │                                     │   │
│  │                                    │ Uses                                  │   │
│  │                                    ▼                                     │   │
│  │   ┌──────────────────┐     ┌──────────────────┐     ┌──────────────┐   │   │
│  │   │   OutcomeToken   │     │    FeeVault      │     │OracleAdapter │   │   │
│  │   │   (ERC-1155)     │     │   (ERC-4626)     │     │              │   │   │
│  │   │                  │     │                  │     │              │   │   │
│  │   │ - YES/NO tokens  │     │ - Yield bearing  │     │ - Chainlink  │   │   │
│  │   │ - Mint/burn      │     │ - Fee collection │     │   interface  │   │   │
│  │   │ - Batch transfer │     │ - Claim rewards  │     │ - Price feeds│   │   │
│  │   └──────────────────┘     └──────────────────┘     └──────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    ACCESS CONTROL ROLES                             │   │
│  │                                                                      │   │
│  │  DEFAULT_ADMIN_ROLE  ──► Timelock (governance-controlled)         │   │
│  │  MARKET_CREATOR_ROLE ──► Timelock (create new markets)              │   │
│  │  UPGRADER_ROLE       ──► Timelock (upgrade proxy implementation)     │   │
│  │  PAUSER_ROLE         ──► Timelock (emergency pause)                  │   │
│  │  MINTER_ROLE         ──► Timelock (mint governance tokens)          │   │
│  │  DEPOSITOR_ROLE      ──► PredictionMarket (deposit fees)            │   │
│  │  MARKET_ROLE         ──► PredictionMarket (mint/burn outcomes)       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 External Dependencies

| Component | External System | Purpose | Risk Level |
|-----------|----------------|---------|------------|
| Oracle | Chainlink Price Feeds | Market resolution price validation | Medium |
| Collateral | USDC (Circle) | Trading collateral | Low |
| Indexing | The Graph | Event indexing, queries | Low |
| Execution | Base/Arbitrum L2 | Transaction execution | Low |

---

## 4. Contract Architecture

### 4.1 Proxy Pattern

The `PredictionMarket` uses the **UUPS (Universal Upgradeable Proxy Standard)** pattern:

```
User ──► ERC1967Proxy ──► PredictionMarket (Implementation)
              │                  ▲
              │                  │ delegatecall
              │            ┌─────┴──────┐
              │            │   Storage  │
              │            │  ┌────────┐ │
              │            │  │markets │ │
              │            │  │reserves│ │
              │            │  │fees    │ │
              │            │  └────────┘ │
              │            └─────────────┘
              │
              │ Upgrade authorization:
              │ UPGRADER_ROLE only (Timelock)
```

**Why UUPS over Transparent Proxy?**
- Smaller proxy bytecode (minimal overhead)
- Cheaper deployment cost
- Upgrade authorization lives in implementation (more flexible)
- Single contract for all markets (vs factory pattern)

### 4.2 Inheritance Hierarchy

```
PredictionMarket
├── UUPSUpgradeable (OpenZeppelin)
├── AccessControl (OpenZeppelin)
├── ReentrancyGuard (OpenZeppelin)
├── Pausable (OpenZeppelin)
└── AMM (internal library)
    └── Inline Yul optimizations for gas

OutcomeToken
├── ERC1155 (OpenZeppelin)
├── AccessControl (OpenZeppelin)
└── SupplyTracking (custom)

GovernanceToken
├── ERC20Votes (OpenZeppelin - ERC20Permit + voting checkpoint)
├── AccessControl (OpenZeppelin)
└── ERC20Permit (OpenZeppelin - gasless approvals)

FeeVault
├── ERC4626 (OpenZeppelin - tokenized vault)
└── AccessControl (OpenZeppelin)

PredictionGovernor
├── Governor (OpenZeppelin)
├── GovernorSettings (voting params)
├── GovernorVotes (token integration)
├── GovernorVotesQuorumFraction (4% quorum)
└── GovernorTimelockControl (execution delay)

GovernorTimelock
└── TimelockController (OpenZeppelin)
```

---

## 5. Sequence Diagrams

### 5.1 Create Market & Trade Flow

```
┌─────────┐     ┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│  User   │     │ PredictionMarket│     │ OutcomeToken │     │   FeeVault  │
└────┬────┘     └───────┬─────────┘     └──────┬───────┘     └──────┬──────┘
     │                  │                       │                    │
     │ 1. createMarket()│                       │                    │
     │ ─────────────────>│                       │                    │
     │                  │ 2. Create market      │                    │
     │                  │    struct             │                    │
     │                  │                       │                    │
     │ 3. buyTokens()   │                       │                    │
     │ ─────────────────>│                       │                    │
     │                  │ 4. Calculate output   │                    │
     │                  │    (AMM.getAmountOut) │                    │
     │                  │                       │                    │
     │                  │ 5. Transfer USDC      │                    │
     │                  │    from user          │                    │
     │                  │                       │                    │
     │                  │ 6. mint()             │                    │
     │                  │ ─────────────────────>│                    │
     │                  │                       │ 7. Mint YES/NO     │
     │                  │                       │    tokens to user  │
     │                  │                       │                    │
     │                  │ 8. depositFees()      │                    │
     │                  │ ──────────────────────────────────────────>│
     │                  │                       │                    │ 9. Store fees
     │                  │                       │                    │
     │ 10. Tokens received│                     │                    │
     │ <─────────────────│                       │                    │
```

### 5.2 Governance Proposal Flow

```
┌──────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌───────────┐
│ Proposer │   │GovernanceToken│   │PredictionGov │   │GovernorTimelock│   │TargetContract│
└────┬─────┘   └───────┬──────┘   └───────┬──────┘   └───────┬──────┘   └─────┬─────┘
     │                 │                  │                  │                │
     │ 1. Delegate votes │                │                  │                │
     │ ────────────────>│                │                  │                │
     │                 │                │                  │                │
     │ 2. Self-delegate │                │                  │                │
     │ ────────────────>│                │                  │                │
     │                 │                │                  │                │
     │ 3. propose()     │                │                  │                │
     │ ────────────────────────────────>│                  │                │
     │                 │ 4. Check voting  │                  │                │
     │                 │    power (1M)    │                  │                │
     │                 │ <───────────────│                  │                │
     │                 │                │ 5. Create proposal │                │
     │                 │                │                  │                │
     │ 6. Wait 1 day    │                │                  │                │
     │ (voting delay)   │                │                  │                │
     │                 │                │                  │                │
     │ 7. Users cast votes               │                  │                │
     │ ────────────────────────────────>│                  │                │
     │                 │                │                  │                │
     │ 8. Wait 1 week   │                │                  │                │
     │ (voting period)  │                │                  │                │
     │                 │                │                  │                │
     │ 9. execute()     │                │                  │                │
     │ ────────────────────────────────>│                  │                │
     │                 │                │ 10. Queue to timelock            │
     │                 │                │ ────────────────────────────────>│
     │                 │                │                  │ 11. Wait 2 days│
     │                 │                │                  │                │
     │                 │                │                  │ 12. execute()│
     │                 │                │                  │ ──────────────>│
     │                 │                │                  │ 13. Operation  │
     │                 │                │                  │    executed    │
     │                 │                │                  │ <──────────────│
```

### 5.3 Market Resolution & Redemption Flow

```
┌─────────┐   ┌─────────────────┐   ┌─────────────┐   ┌──────────────┐   ┌──────────┐
│ Resolver│   │ PredictionMarket│   │OracleAdapter│   │   USDC Token  │   │  Trader  │
└────┬────┘   └───────┬─────────┘   └──────┬──────┘   └──────┬───────┘   └────┬─────┘
     │                │                    │                 │                │
     │ 1. resolveMarket()│                  │                 │                │
     │ ────────────────>│                  │                 │                │
     │                │ 2. Check resolution │                 │                │
     │                │    time reached     │                 │                │
     │                │                    │                 │                │
     │                │ 3. validatePrice() │                 │                │
     │                │ ──────────────────>│                 │                │
     │                │                    │ 4. Check Chainlink
     │                │                    │    price feed   │                │
     │                │                    │ <─────────────│                │
     │                │ 5. Price data      │                 │                │
     │                │ <──────────────────│                 │                │
     │                │                    │                 │                │
     │                │ 6. Set winning     │                 │                │
     │                │    outcome         │                 │                │
     │                │                    │                 │                │
     │ 7. Resolved    │                    │                 │                │
     │ <──────────────│                    │                 │                │
     │                │                    │                 │                │
     │                │         8. redeemWinnings()          │                │
     │                │ <─────────────────────────────────────────────────────│
     │                │                    │                 │                │
     │                │ 9. Verify winning    │                 │                │
     │                │    tokens held       │                 │                │
     │                │                    │                 │                │
     │                │ 10. Burn winning tokens               │                │
     │                │ ─────────────────────────────────────────────────────>│
     │                │                    │                 │                │
     │                │ 11. Transfer USDC    │                 │                │
     │                │ ────────────────────────────────────>│               │
     │                │                    │                 │ 12. USDC to  │
     │                │                    │                 │     user     │
     │                │                    │                 │ ────────────>│
```

---

## 6. Data Model & Storage Layouts

### 6.1 PredictionMarket Storage Layout (UUPS Upgradeable)

**CRITICAL: Storage slots must never change order in upgrades**

```solidity
// Slot 0: UUPSUpgradeable gap
uint256[50] private __gap_UUPS;

// Slot 1-50: AccessControl gap
uint256[50] private __gap_AccessControl;

// Slot 51: Pausable
bool private _paused;                    // 1 byte
// Padding: 31 bytes

// Slot 52: ReentrancyGuard
uint256 private _status;                 // 1 = not entered, 2 = entered

// Slot 53-55: Address mappings
address public usdc;                     // 20 bytes
address public outcomeToken;             // 20 bytes
address public feeVault;                 // 20 bytes
address public oracleAdapter;            // 20 bytes

// Slot 56: Market counter
uint256 public marketCount;

// Slot 57+: Markets mapping (keccak256)
mapping(uint256 => Market) public markets;

struct Market {
    string question;                     // Slot: dynamic (offset)
    address creator;                     // 20 bytes
    address oracleFeed;                  // 20 bytes
    uint256 resolutionTime;              // 32 bytes
    uint256 createdAt;                   // 32 bytes
    uint256 totalCollateral;             // 32 bytes
    uint256 yesReserve;                  // 32 bytes
    uint256 noReserve;                   // 32 bytes
    uint256 feesAccrued;                 // 32 bytes
    bool resolved;                       // 1 byte
    uint8 winningOutcome;                // 1 byte
    // 30 bytes padding
}
```

**Storage Collision Prevention:**
- All inherited OZ contracts use `__gap` arrays
- Custom storage uses sequential slots after gaps
- Mapping data is at `keccak256(slot + key)`

### 6.2 GovernanceToken Storage (ERC20Votes)

```solidity
// ERC20 (inherited)
mapping(address => uint256) _balances;           // keccak256(0)
mapping(address => mapping(address => uint256)) _allowances; // keccak256(1)
uint256 _totalSupply;                            // Slot 2
string _name;                                    // Slot 3 (dynamic)
string _symbol;                                  // Slot 4 (dynamic)

// ERC20Permit
domainSeparator;                                 // Slot 5
mapping(address => Counters.Counter) _nonces;    // keccak256(6)

// ERC20Votes
checkpoints;                                     // keccak256(7)
delegatees;                                      // keccak256(8)

// AccessControl
roles;                                           // keccak256(9)

// Custom
bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18;
```

### 6.3 FeeVault Storage (ERC4626)

```solidity
// ERC20 (shares)
mapping(address => uint256) _balances;           // keccak256(0)
mapping(address => mapping(address => uint256)) _allowances;
uint256 _totalSupply;
string _name = "FeeVault Share";
string _symbol = "fvUSDC";

// ERC4626
address public asset;                            // USDC
uint256 public totalAssetsCache;
mapping(address => uint256) maxDepositCache;

// AccessControl
roles mapping;

// Fee tracking
uint256 public totalFeesCollected;
mapping(address => uint256) userDeposits;
```

### 6.4 Timelock Storage

```solidity
// TimelockController
mapping(bytes32 => bool) private _timestamps;  // keccak256(0)
uint256 private _minDelay;                       // Slot 1

// Role management (AccessControl)
mapping(bytes32 => RoleData) private _roles;     // keccak256(2)
mapping(bytes32 => EnumerableSet.AddressSet) _roleMembers;

// Role constants (not storage)
bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
```

### 6.5 Upgrade Safety Checklist

When upgrading `PredictionMarket`, verify:
1. New variables are appended at the end
2. No existing variable types are changed
3. No variables are deleted
4. `__gap` arrays remain in all inherited contracts
5. Storage layout report matches pre-upgrade

---

## 7. Trust Assumptions

### 7.1 Role Capabilities Matrix

| Role | Holder | Powers | Mitigation |
|------|--------|--------|------------|
| `DEFAULT_ADMIN_ROLE` | Timelock | Grant/revoke all roles | 2-day timelock delay |
| `MARKET_CREATOR_ROLE` | Timelock | Create new markets | Governance vote required |
| `UPGRADER_ROLE` | Timelock | Upgrade proxy implementation | 2-day timelock + governance |
| `PAUSER_ROLE` | Timelock | Emergency pause/unpause | Time-limited, revocable |
| `MINTER_ROLE` | Timelock | Mint PGOV tokens | Governance-controlled supply |
| `DEPOSITOR_ROLE` | Market only | Deposit to FeeVault | Automated, no human control |
| `MARKET_ROLE` | Market only | Mint/burn outcomes | Automated via AMM |

### 7.2 Centralization Risks

**High Risk: None** (all critical roles assigned to timelock)

**Medium Risk:**
- **Initial Deployment**: Deployer has admin rights until ownership transfer
- **Oracle Dependency**: Chainlink feeds could fail or be manipulated
- **USDC Dependency**: Circle can freeze/blacklist addresses

**Low Risk:**
- **L2 Sequencer**: Base/Arbitrum sequencer could censor transactions
- **The Graph**: Subgraph downtime affects frontend, not contracts

### 7.3 Compromise Scenarios

**If Multisig/Timelock Compromised:**
- Attacker can upgrade contracts (after 2-day delay)
- Attacker can mint unlimited PGOV (but has timelock delay)
- Attacker can drain FeeVault (if upgrade injects malicious code)

**Defense:**
- 2-day timelock allows monitoring and emergency response
- Governance can revoke compromised proposers
- Users can withdraw funds during timelock delay

**If Oracle Compromised:**
- Attacker can manipulate market resolutions
- Defense: Multi-feed validation, time delays, manual override (governance)

---

## 8. Design Decision Records (ADRs)

### ADR-001: UUPS Proxy vs Transparent Proxy

**Context:** Need upgradeable contracts for bug fixes and feature additions

**Options:**
1. Transparent Proxy - Separate admin contract, larger bytecode
2. UUPS Proxy - Smaller proxy, upgrade logic in implementation
3. Beacon Proxy - Single upgrade point for all instances

**Decision:** UUPS Proxy

**Rationale:**
- Smaller proxy deployment cost (important for L2 gas optimization)
- Simpler architecture (no separate proxy admin)
- Upgrade authorization in implementation (more transparent)

**Consequences:**
- Implementation must handle upgrade authorization
- Risk: Implementation could brick itself (mitigated by timelock)

---

### ADR-002: ERC-1155 vs ERC-20 for Outcome Tokens

**Context:** Need to represent multiple market outcomes efficiently

**Options:**
1. ERC-20 per market - Deploy new token for each market
2. ERC-1155 - Single contract, multiple token IDs
3. ERC-721 - Non-fungible (unsuitable for trading)

**Decision:** ERC-1155

**Rationale:**
- Single deployment for all markets
- Gas-efficient batch transfers
- Native support for semi-fungible tokens
- OpenSea/Rarible compatible for secondary markets

**Consequences:**
- More complex approval logic
- Frontends must handle token IDs
- Benefits outweigh complexity

---

### ADR-003: OpenZeppelin Governor vs Custom Governance

**Context:** Need robust, audited governance system

**Options:**
1. Custom governance - Full control, higher audit cost
2. Compound Governor - Battle-tested, widely used
3. OpenZeppelin Governor - Modular, well-documented

**Decision:** OpenZeppelin Governor

**Rationale:**
- Most modular and customizable
- Best documentation and community support
- Easy to extend with new modules
- Integrated with OZ Defender

**Consequences:**
- Tightly coupled to OZ library updates
- Governor must be deployed with timelock
- Well-understood attack surface

---

### ADR-004: Constant Product AMM vs Order Book

**Context:** Need mechanism for price discovery and trading

**Options:**
1. Centralized order book - Off-chain matching, gas-efficient
2. On-chain order book - Full decentralization, expensive
3. Constant product AMM (x*y=k) - Always liquid, simple

**Decision:** Constant Product AMM

**Rationale:**
- Always provides liquidity (no matching required)
- Simple to implement and verify
- Proven model (Uniswap, Balancer)
- Fits binary outcome markets well

**Consequences:**
- Slippage for large trades
- Impermanent loss for LPs
- Requires initial liquidity

---

### ADR-005: Chainlink vs Tellor vs API3

**Context:** Need reliable oracle for market resolution

**Options:**
1. Chainlink - Largest ecosystem, most feeds
2. Tellor - Permissionless, stake-based
3. API3 - First-party oracles

**Decision:** Chainlink with OracleAdapter abstraction

**Rationale:**
- Chainlink has most reliable price feeds
- OracleAdapter allows future oracle swaps
- Multi-feed validation possible

**Consequences:**
- Dependency on Chainlink node operators
- Feed could be deprecated
- Adapter adds gas overhead

---

### ADR-006: ERC-4626 FeeVault vs Direct Distribution

**Context:** Need to collect and distribute trading fees

**Options:**
1. Direct distribution - Immediate, complex accounting
2. ERC-4626 vault - Yield-bearing shares, auto-compounding
3. Merkle distributor - Periodic, gas-efficient claims

**Decision:** ERC-4626 FeeVault

**Rationale:**
- Tokenized fee shares (tradeable/transferable)
- Auto-compounding yield on USDC
- Standard interface (integrations)
- Natural for liquidity providers

**Consequences:**
- LPs must understand vault shares
- Share price increases over time
- Withdrawal could be delayed (not implemented)

---

## Appendix: Contract Addresses (Post-Deployment)

| Contract | Address | Network |
|----------|---------|---------|
| PredictionMarket (Proxy) | TBD | Base Sepolia |
| PredictionMarket (Impl) | TBD | Base Sepolia |
| OutcomeToken | TBD | Base Sepolia |
| FeeVault | TBD | Base Sepolia |
| OracleAdapter | TBD | Base Sepolia |
| GovernanceToken | TBD | Base Sepolia |
| GovernorTimelock | TBD | Base Sepolia |
| PredictionGovernor | TBD | Base Sepolia |

---

*Document Version: 1.0*  
*Last Updated: May 2026*  
*Protocol Version: v1.0.0*
