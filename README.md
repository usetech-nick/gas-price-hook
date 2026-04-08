# 🎓 Gas Price Fees Hook

> **A learning project to understand Uniswap v4 Hooks**

This project implements a dynamic fee hook that adjusts swap fees based on network gas prices. Built as an educational resource to understand how Uniswap v4 hooks work.

⚠️ **NOT FOR PRODUCTION USE** - This is a learning exercise!

---

## 📚 What You'll Learn

- How Uniswap v4 hooks intercept pool operations
- Dynamic fee calculation based on external factors
- Moving average calculations in Solidity
- Testing hooks with Foundry

---

## 🧠 The Concept

**Problem:** Fixed swap fees don't adapt to network conditions.

**Solution:** Charge higher fees during network congestion (high gas prices) and lower fees when the network is quiet.

```
High Gas Price  →  Higher Fees  →  Discourages spam/MEV during congestion
Low Gas Price   →  Lower Fees   →  Attracts volume when network is cheap
```

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         UNISWAP V4 POOL                                 │
│                                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│  │ Initialize  │    │    Swap     │    │  Liquidity  │                 │
│  │    Pool     │    │             │    │  Operations │                 │
│  └──────┬──────┘    └──────┬──────┘    └─────────────┘                 │
│         │                  │                                            │
│         ▼                  ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    GasPriceFeesHook                              │  │
│  │                                                                  │  │
│  │   beforeInitialize()  │  beforeSwap()  │  afterSwap()           │  │
│  │          │            │       │        │      │                  │  │
│  │          ▼            │       ▼        │      ▼                  │  │
│  │   Check dynamic       │  Calculate     │  Update moving         │  │
│  │   fee is enabled      │  dynamic fee   │  average gas price     │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Hook Lifecycle

### Phase 1: Pool Creation

```
┌─────────────────────────────────────────────────────────────┐
│  Someone creates a pool with this hook attached             │
│                           │                                 │
│                           ▼                                 │
│              ┌────────────────────────┐                     │
│              │   beforeInitialize()   │                     │
│              └────────────────────────┘                     │
│                           │                                 │
│                           ▼                                 │
│              ┌────────────────────────┐                     │
│              │  Is dynamic fee flag   │                     │
│              │       enabled?         │                     │
│              └────────────────────────┘                     │
│                    │           │                            │
│                   YES          NO                           │
│                    │           │                            │
│                    ▼           ▼                            │
│               ✅ Allow    ❌ Revert                         │
│               pool        MustBeDynamicFees()               │
│               creation                                      │
└─────────────────────────────────────────────────────────────┘
```

### Phase 2: Every Swap

```
┌─────────────────────────────────────────────────────────────┐
│                     USER INITIATES SWAP                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 1: beforeSwap()                                       │
│  ────────────────────                                       │
│                                                             │
│  ┌─────────────────┐      ┌─────────────────┐              │
│  │  tx.gasprice    │      │  movingAverage  │              │
│  │  (current gas)  │      │  (historical)   │              │
│  └────────┬────────┘      └────────┬────────┘              │
│           │                        │                        │
│           └───────────┬────────────┘                        │
│                       ▼                                     │
│           ┌───────────────────────┐                         │
│           │      getFee()         │                         │
│           │                       │                         │
│           │  fee = BASE_FEE ×     │                         │
│           │  (current / average)  │                         │
│           └───────────┬───────────┘                         │
│                       │                                     │
│                       ▼                                     │
│           Return fee to PoolManager                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 2: Swap Executes                                      │
│  ─────────────────────                                      │
│                                                             │
│  PoolManager uses our returned fee to calculate             │
│  how much the swapper pays to liquidity providers           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 3: afterSwap()                                        │
│  ───────────────────                                        │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              updateMovingAverage()                   │   │
│  │                                                      │   │
│  │  newAvg = (oldAvg × count + currentGas) / (count+1) │   │
│  │  count++                                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  This updates our baseline for the NEXT swap                │
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 Fee Calculation Examples

Base fee is `0.5%` (5000 in pips where 1_000_000 = 100%)

| Scenario         | Current Gas | Average Gas | Ratio | Fee Charged    |
| ---------------- | ----------- | ----------- | ----- | -------------- |
| 🔥 Network busy  | 100 gwei    | 50 gwei     | 2.0x  | **1.0%**       |
| 😐 Normal        | 50 gwei     | 50 gwei     | 1.0x  | **0.5%**       |
| 😴 Network quiet | 25 gwei     | 50 gwei     | 0.5x  | **0.25%**      |
| 🚀 Extreme spike | 500 gwei    | 50 gwei     | 10x   | **5.0%**       |
| 💥 Capped        | 10000 gwei  | 50 gwei     | 200x  | **100%** (max) |

---

## 📁 Project Structure

```
gas-price-hook/
├── src/
│   └── GasPriceFeesHook.sol    # The hook implementation
├── test/
│   └── GasPriceFeesHook.t.sol  # Foundry tests
├── lib/                         # Dependencies (git submodules)
│   ├── forge-std/
│   ├── v4-core/
│   ├── v4-periphery/
│   └── uniswap-hooks/
├── foundry.toml                 # Foundry configuration
└── README.md
```

---

## 🔑 Key Concepts Explained

### 1. Hook Permissions

```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeInitialize: true,   // ✅ We validate dynamic fees
        afterInitialize: false,
        beforeAddLiquidity: false,
        beforeRemoveLiquidity: false,
        afterAddLiquidity: false,
        afterRemoveLiquidity: false,
        beforeSwap: true,         // ✅ We calculate the fee here
        afterSwap: true,          // ✅ We update the average here
        beforeDonate: false,
        afterDonate: false,
        beforeSwapReturnDelta: false,
        afterSwapReturnDelta: false,
        afterAddLiquidityReturnDelta: false,
        afterRemoveLiquidityReturnDelta: false
    });
}
```

### 2. Dynamic Fees

Pools must be created with `LPFeeLibrary.DYNAMIC_FEE_FLAG` to allow hooks to override fees per-swap.

```solidity
// In beforeSwap, we return the fee with OVERRIDE_FEE_FLAG
return (selector, ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
```

### 3. Moving Average (Gas Efficient)

Instead of storing all historical gas prices (expensive!), we use a cumulative moving average:

```solidity
// This formula maintains the average using only 2 storage slots
newAverage = (oldAverage × count + newValue) / (count + 1)
```

---

## 🧪 Running Tests

```bash
# Run all tests
forge test

# Run with verbosity (see traces)
forge test -vvv

# Run specific test
forge test --match-test test_getFee_highGas

# Run with gas report
forge test --gas-report
```

---

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Setup

```bash
# Clone the repo
git clone <your-repo-url>
cd gas-price-hook

# Install dependencies
forge install

# Build
forge build

# Test
forge test
```

---

## 🎯 Learning Exercises

Try these modifications to deepen your understanding:

1. **Add fee bounds**: Implement `MIN_FEE` and `MAX_FEE` constraints
2. **Decay factor**: Make older gas prices contribute less to the average
3. **Per-pool tracking**: Track gas averages per pool instead of globally
4. **Owner controls**: Add functions to update `BASE_FEE`
5. **Events**: Emit events when fees are calculated for off-chain tracking

---

## 📖 Resources

- [Uniswap v4 Documentation](https://docs.uniswap.org/)
- [Uniswap v4 Core](https://github.com/Uniswap/v4-core)
- [OpenZeppelin Uniswap Hooks](https://github.com/OpenZeppelin/uniswap-hooks)
- [Foundry Book](https://book.getfoundry.sh/)

---

## ⚠️ Disclaimer

This is an **educational project** meant for learning Uniswap v4 hooks. It has NOT been:

- Audited
- Tested for edge cases
- Optimized for gas
- Reviewed for security vulnerabilities

**DO NOT deploy this to mainnet with real funds!**

---

## 📝 License

MIT

---

_Built while learning Uniswap v4 hooks_ 🦄
