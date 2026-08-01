# Aave V4 Architecture Deep Dive: Hub-Spoke Model

> **Type**: Protocol knowledge (video script / educational)
> **Sources**: V4 contract source code (`aave-v4/`) + V4 `docs/overview.md` + on-chain queries
> **Companion doc**: `v3-v4-collateral-and-health-factor.md` (for collateral/HF/RP details)

---

## 1. V4 Architecture: Hub-Spoke Model

In Aave V3 and earlier, liquidity was isolated across different Markets. For example, Ethereum had Core and Prime markets, each with independent liquidity pools. This design isolated risk but also fragmented liquidity and required bootstrapping from scratch whenever a new market was launched [1].

Aave V4 introduces the Hub-Spoke model. The core philosophy: **unified liquidity, isolated risk** [1].

### Hub (Liquidity Hub)

Hub is the immutable center of Aave V4 architecture. Each blockchain network (e.g., Ethereum mainnet) can have one or more Hubs [1].

- **Immutability**: Hub's core smart contracts are immutable, designed to be as simple as possible to ensure protocol-level fund safety [1].
- **Unified Liquidity Pool**: All underlying assets (ERC-20 tokens) are stored in the Hub. Regardless of which Spoke a user supplies through, funds ultimately converge into the Hub's unified pool [1].
- **Accounting Invariants**: Hub maintains global accounting invariants:
  1. Total borrowed shares == sum of Spoke debt shares
  2. Hub added assets amount >= sum of Spoke added assets amount
  3. Hub added shares == sum of Spoke added shares
  4. Supply share price and drawn index cannot decrease [1]
- **Cap Management**: Hub sets Add caps and Draw caps per asset per Spoke, controlling each Spoke's access to global liquidity [1].
- **Interest Rate & Fee**: Hub manages the interest rate strategy per asset and the liquidity fee (protocol's share of interest revenue) [1].

### Spoke (Market Module)

Spoke is the upgradeable user-facing component that connects to one or more Hubs. Users interact exclusively through Spokes — all `supply`, `withdraw`, `borrow`, and `repay` operations are routed through a specific Spoke [1].

- **Upgradeable**: Unlike Hub's immutability, Spoke contracts are upgradeable [1].
- **Independent Risk Parameters**: Each Spoke has its own:
  - `LiquidationConfig` (targetHealthFactor, healthFactorForMaxBonus, liquidationBonusFactor) — per-Spoke [2]
  - Oracle (`ORACLE` immutable, set at construction) — per-Spoke [2]
  - `MAX_USER_RESERVES_LIMIT` — per-Spoke [2]
  - Reserve-level configs: `collateralRisk`, `frozen`, `paused`, `borrowable` [2]
  - Dynamic configs: `collateralFactor`, `maxLiquidationBonus`, `liquidationFee` — per-Reserve per-key versioning [2]

### Reserve (Per-Spoke Per-Token)

Reserve is the lending state unit for a single underlying token within a Spoke. Each Reserve is linked to exactly one Hub and one assetId [2].

- **Reserve-level**: `collateralRisk`, `flags` (paused/frozen/borrowable/receiveSharesEnabled), `dynamicConfigKey`
- **Hub-level** (shared across Spokes connected to same Hub): interest rate (`drawnRate`), liquidity, `addCap`/`drawCap`, `deficitRay`

> **Key distinction**: Reserve ID is Spoke-local (uint256 auto-increment). The same underlying token in different Hubs → different reserves within the same Spoke. See `id-namespace-taxonomy.md` for hierarchy diagrams.

---

## 2. Spoke Isolation: What's Independent Per-Spoke

> ⚠️ **V4 `docs/overview.md` describes Spoke isolation but does not systematically list which user data is per-Spoke independent.** The following is from `SpokeStorage.sol` storage layout analysis.

A user with positions in multiple Spokes has **completely independent** data in each:

| Independent Dimension | Contract Storage | Description |
|-----------------------|-------------------|-------------|
| Health Factor | `_positionStatus[user]` + `_userPositions[user][reserveId]` | User has independent HF per Spoke |
| Risk Premium | `_positionStatus[user].riskPremium` (uint24) | User has independent RP per Spoke |
| Position Data | `_userPositions[user][reserveId]` | suppliedShares, drawnShares, premiumShares, premiumOffsetRay — all per-Spoke |
| Dynamic Config Snapshot | `_userPositions[user][reserveId].dynamicConfigKey` | Per-Reserve config version binding |
| Collateral/Borrow Bitmap | `_positionStatus[user].map` | Which reserves are collateral/borrowing |
| Reserve Count Limit | `MAX_USER_RESERVES_LIMIT` | Per-Spoke limit |
| LiquidationConfig | `_liquidationConfig` | Per-Spoke, shared by all users on same Spoke |

**Shared across Spokes** (Hub layer): interest rate (`drawnRate`), liquidity, `addCap`/`drawCap`, deficit aggregation.

> **V3 equivalent**: V3 users in different Pools (Markets) also had independent HFs. V4's Spoke isolation is architecturally equivalent to V3's Pool isolation.

---

## 3. Spoke Application Scenarios: Actual Deployments vs Speculative

> ⚠️ **The original version of this document contained speculative scenarios (E-Mode Spoke, Isolation Spoke) that incorrectly attributed V3 concepts to V4. V4 has no E-Mode or Isolation Mode.**

> **Spoke list is dynamic**: Governance can add, modify, or retire Spokes at any time. The table below reflects on-chain data as of 2026-08-01. It will change.

### Hubs

V4 uses multiple Hubs per chain. As of 2026-08-01, 4 Hubs are deployed:

| Hub | Chain | Description |
|-----|-------|-------------|
| Core Hub | Ethereum, Avalanche | Primary hub, most Spokes connect here |
| Plus Hub | Ethereum | Ethena-focused |
| Prime Hub | Ethereum | Bluechip (higher risk profile) |
| Global Dollar Hub | Ethereum | USDG-specific |

> Official V4 docs (`aave-v4/liquidity/hubs`) name three: Core, Plus, Prime. The Global Dollar Hub and cross-Hub Spokes are visible in SDK data but not yet in official docs.

### Actual deployed Spokes (on-chain SDK data, as of 2026-08-01)

| Chain | Hub | Spoke | Reserves | targetHealthFactor |
|-------|-----|-------|----------|-------------------|
| Ethereum | Core | Main | 14 | 1.24 |
| Ethereum | Core | Bluechip | 4 | 1.174 |
| Ethereum | Core | Gold | 8 | 1.307 |
| Ethereum | Core | Lombard | 3 | 1.061 |
| Ethereum | Core | Forex | 7 | 1.044 |
| Ethereum | Core | Ethena Ecosystem | 3 | 1.033 |
| Ethereum | Core | USDG Pendle | 1 | 1.027 |
| Ethereum | Core | Lido | 2 | 1.013 |
| Ethereum | Core | Etherfi | 2 | 1.019 |
| Ethereum | Core | Kelp | 2 | 1.021 |
| Ethereum | Plus | Ethena Ecosystem | 7 | 1.033 |
| Ethereum | Plus | Ethena Correlated | 4 | 1.027 |
| Ethereum | Prime | Bluechip | 7 | 1.174 |
| Ethereum | Global Dollar | USDG Pendle | 3 | 1.027 |
| Avalanche | Core | Main | 6 | 1.24 |
| Avalanche | Core | Forex | 3 | 1.044 |
| Avalanche | Core | AVAX Correlated | 2 | — |

> Official V4 docs list a **Treasury Spoke** (`0xB9B0b861...`) on Ethereum which does not appear in SDK reserve data — likely has 0 reserves or is a different Spoke variant.

**Key observation**: The same Spoke name (e.g., Bluechip, Ethena Ecosystem, USDG Pendle) can connect to different Hubs with different Reserves. This is by design — a Spoke connects to one or more Hubs.

Observed configuration patterns (on-chain data, not design intent):
- Main, Bluechip, Gold: `healthFactorForMaxBonus=0.90`, `liquidationBonusFactor=9000` (90%)
- LST + Ethena + Forex Spokes: `healthFactorForMaxBonus=0.99`, `liquidationBonusFactor=10000` (100%)

### Why "E-Mode Spoke" and "Isolation Spoke" are incorrect

**E-Mode** (Efficiency Mode) is a **V3-only** concept:
- V3: A global configuration on the Pool that allows higher LTV for price-correlated asset pairs (e.g., USDC/USDT, wstETH/ETH)
- V3 contract: `EModeConfiguration.sol`, `eModeCategories`, `userEModeCategory`
- **V4 has no E-Mode**: grep of V4 contract source code (`aave-v4/src/`) and `docs/overview.md` returns zero matches for "eMode", "e-mode", "isolation", or "siloed"

**Isolation Mode** is a **V3-only** concept:
- V3: Assets can be marked as `isolated`, limiting them to be used as collateral only for borrowing specific stablecoins (the `borrowableInIsolation` flag)
- V3 contract: `BORROWABLE_IN_ISOLATION_MASK`, `DEBT_CEILING`
- **V4's alternative**: Spoke-level isolation + Hub-level `drawCap` achieves the same risk isolation without a separate "Isolation Mode" flag. Each Spoke inherently isolates its positions.

### What V4 actually has instead

| V3 concept | V3 mechanism | V4 status |
|------------|-------------|-----------|
| E-Mode | **User-selectable mode** within a Pool: user enters a category → that category overrides LTV and LT for assets in the category bitmap | **Removed entirely**. V4 has no user-selectable mode, no category concept, no bitmap override. Per-Reserve `collateralFactor` is always-on and protocol-set, not conditional on user mode. |
| Isolation Mode | `isolated` flag on asset, `debtCeiling`, `borrowableInIsolation` | **Removed**. Spoke isolation + Hub `drawCap` — each Spoke is inherently isolated, `drawCap` limits exposure. |
| Siloed Borrowing | `SILOED_BORROWING` flag — prevents borrowing a siloed asset alongside others | **Removed**. Spoke-level `borrowable` flag + `frozen`/`paused` replaces this. |
| Stable Rate Borrowing | `stableDebtToken`, `stableBorrowRate` — **deprecated in V3.2.0** (enum value renamed to `__DEPRECATED`, `stableDebtTokenAddress` deprecated) | **Not present**. V3.2.0 already deprecated stable rate; V4 continues without it. V4 has only one borrow mode (variable, via `drawnShares` + `drawnIndex`). |
| FlashLoan | V3: `flashLoan()`, `flashLoanSimple()`, `setFlashLoanEnabled()` | **Present in V4** — V4 docs mention a 0.05% flash loan fee for position swaps (`aave.com/docs/aave-v4/tools/swaps`). Not in V4 `Spoke.sol` source; likely implemented as a separate module. |
| aToken / variableDebtToken | ERC20 tokens representing supply/borrow positions | **Removed**. Positions tracked internally in `UserPosition` (non-transferable). |

> **Key distinction on E-Mode**: V3 E-Mode was not simply "higher LTV for certain assets" — V3 could already set per-Reserve LTV. E-Mode was a **user-selectable override**: the same Reserve had different LTV/LT depending on whether the user was in E-Mode or not. V4 has no such mechanism — each Reserve has one `collateralFactor` (at a given config version), regardless of what else the user does. You cannot "enter a mode" to get better terms in V4.

### TokenizationSpoke

V4 has a **TokenizationSpoke** variant — an ERC4626 vault that coexists with regular Spokes. TokenizationSpoke supports only `add` and `remove` (no `draw`/`borrow`), `drawCap=0`. See `frozen-paused-semantics.md` for details [2].

---

## 4. V3 ↔ V4 Concept Mapping

| V3 Concept | V3 Contract | V4 Concept | V4 Contract | Relationship |
|------------|-------------|------------|--------------|--------------|
| Pool | `Pool.sol` | Spoke | `Spoke.sol` | **Equivalent**: user entry point, position isolation boundary |
| Market (logical) | (abstract) | Market (logical) | (abstract) | **Same concept**: V3 = Pool, V4 = Spoke |
| Reserve | per-Pool per-token | Reserve | per-Spoke per-token per-Hub | **Equivalent, V4 adds Hub dimension** |
| — | — | Hub | `Hub.sol` | **V4 new**: cross-chain liquidity aggregation |
| — | — | Asset | per-Hub per-token | **V4 new**: Hub-level asset concept |
| `baseLTVasCollateral` | `ReserveConfigurationMap` | `collateralFactor` | `DynamicReserveConfig` | **Semantic equivalent**: max borrow ratio |
| `liquidationThreshold` | `ReserveConfigurationMap` | `collateralFactor` (same) | `DynamicReserveConfig` | **V4 merged**: borrow limit = liquidation threshold |
| `liquidationBonus` | `ReserveConfigurationMap` | `maxLiquidationBonus` | `DynamicReserveConfig` | **Semantic equivalent**: liquidator bonus |
| `reserveFactor` | `ReserveConfigurationMap` | `liquidityFee` | `Asset.liquidityFee` | **Semantic equivalent**: protocol fee on interest |
| E-Mode | `EModeConfiguration` | (none) | — | **V4 removed**: no user-selectable mode, no category override. Per-Reserve `collateralFactor` is always-on. |
| Isolation Mode | `BORROWABLE_IN_ISOLATION` | (none) | — | **V4 removed**: replaced by Spoke isolation + `drawCap` |
| Close Factor | 50% (100% if HF<0.95) | `targetHealthFactor` | `LiquidationConfig` | **V4 redesign**: dynamic, restore HF to target |
| `liquidationProtocolFee` | `ReserveConfigurationMap` | `liquidationFee` | `DynamicReserveConfig` | **Semantic equivalent**: protocol cut from bonus |
| — | — | `collateralRisk` | `ReserveConfig` | **V4 new**: drives Risk Premium |
| — | — | `riskPremium` | `PositionStatus` | **V4 new**: per-user greedy allocation, affects effective borrow rate |
| `aToken` | ERC20 | (none) | — | **V4 removed**: positions tracked internally in `UserPosition` |
| `variableDebtToken` | ERC20 | (none) | — | **V4 removed**: debt tracked internally via `drawnShares` + `drawnIndex` |
| `stableDebtToken` | ERC20 | (none) | — | **V4 removed**: stable rate borrowing eliminated, only variable mode |
| FlashLoan | `FlashLoanLogic`, `_flashLoanPremium` | FlashLoan fee | V4 Tools (position swaps) | **V4 has it**: 0.05% fee per V4 docs (`aave-v4/tools/swaps`), not in Spoke.sol source |
| `liquidityIndex` | implicit fee deduction | `exchangeRate` | `addedShares / totalAddedAssets` | **V4 redesign**: explicit shares-based accounting |
| `borrowIndex` | full debt growth | `drawnIndex` | `Asset.drawnIndex` | **Semantic equivalent**: single debt index |
| `deficit` | `reserve.deficit` | `deficitRay` | `Asset.deficitRay` + `SpokeData.deficitRay` | **V4 enhanced**: dual-layer tracking |

> For collateral/HF/RP formulas and on-chain values, see `v3-v4-collateral-and-health-factor.md`.

---

## 5. Position Swaps & FlashLoan

### V4 Position Swap mechanism

V4 natively integrates position swap functionality that V3 required external adapters (`ParaSwapLiquiditySwapAdapter`, `ParaSwapDebtSwapAdapterV3`) to achieve. Three swap types:

| Swap type | V4 activity type | What it does |
|-----------|-----------------|--------------|
| **SupplySwap** | `SupplySwapActivity` | Supply asset A → auto-swap to asset B → supply B |
| **BorrowSwap** | `BorrowSwapActivity` | Borrow asset A → auto-swap to asset B → receive B |
| **WithdrawSwap** | `WithdrawSwapActivity` | Withdraw asset A → auto-swap to asset B → receive B |

These swaps use an external DEX aggregator (ParaSwap or similar) and are atomic — the swap and the supply/borrow/withdraw happen in a single transaction.

### FlashLoan in V4

When a position swap requires temporarily borrowing assets (e.g., to swap collateral from ETH to WBTC, you need to borrow WBTC, swap ETH→WBTC, repay), V4 uses an internal flash loan mechanism:

- **Fee**: 0.05% of the borrowed amount, collected by the protocol treasury [3]
- **Scope**: Only for position swaps, not a standalone `flashLoan()` function like V3

This differs from V3:
- V3: `flashLoan()` and `flashLoanSimple()` were standalone functions anyone could call for any purpose
- V4: Flash loan is internal to the swap tool — users don't call it directly; it's used when the swap engine needs temporary liquidity

> Source: V4 official docs (`aave-v4/tools/swaps`) [3]

---

## 6. Shares-Based Accounting Model

> "Shares-based" is not an official V4 term — it is our descriptive label for V4's internal accounting redesign. V4 `docs/overview.md` describes the mechanism but does not give it a single name.

V3 uses ERC20 tokens (`aToken` for supply, `variableDebtToken` for borrow) with implicit index growth (`liquidityIndex` for supply, `borrowIndex` for debt). Users receive token receipts and the index auto-compounds.

V4 **removes `aToken` and `variableDebtToken` entirely**. Instead, positions are tracked internally in `UserPosition` structs using explicit share accounting:

| Concept | V3 | V4 |
|---------|-----|-----|
| Supply tracking | `aToken` (ERC20, transferable) | `UserPosition.suppliedShares` (internal, non-transferable) |
| Borrow tracking | `variableDebtToken` (ERC20, transferable) | `UserPosition.drawnShares` (internal, non-transferable) |
| Supply index | `liquidityIndex` (implicit fee deduction) | `exchangeRate = totalAddedAssets / addedShares` (explicit) |
| Borrow index | `borrowIndex` (full debt growth) | `drawnIndex` (single debt index, Hub-level) |
| Premium debt | (none) | `premiumShares` + `premiumOffsetRay` (Risk Premium mechanism) |

**What this means for users:**
- **No transferable position tokens**: You can't transfer your supply/borrow positions to another wallet by sending tokens. Positions are bound to your address within a Spoke.
- **Hub-level debt index**: `drawnIndex` is shared across all Spokes connected to the same Hub — all borrowers of the same asset pay the same rate, regardless of which Spoke they borrowed through.
- **Explicit shares, not implicit index**: Supply value = `suppliedShares × exchangeRate`. Debt value = `drawnShares × drawnIndex + premiumDebtRay`.

> For supply/borrow rate formulas, see `aave-supply-borrow-rate-formula.md`.

---

## 7. Dynamic Risk Configuration

V3 has a single, global risk configuration per asset. Any parameter change immediately affects every open position, creating governance overhead and potential harm through unexpected liquidations [1].

V4 introduces **versioned Dynamic Risk Configuration** [1]:
- Each Reserve holds a `dynamicConfigKey` pointing to the current active config
- Each UserPosition snapshots the `dynamicConfigKey` at the time of its last risk-increasing action
- When governance adjusts parameters, a **new config key** is created — old positions keep their snapshot, new positions bind to the latest

**What this means for users (plain English):**

Imagine you supply ETH as collateral and borrow USDC. The protocol sets your ETH's collateral factor at 80% — meaning you can borrow up to 80% of your ETH's value.

Now governance decides ETH is riskier and lowers the collateral factor to 70%. In V3, this change hits **immediately** — your borrowing power drops instantly, and if you were near the limit, you could be liquidated through no fault of your own.

In V4, governance creates a **new config version** (key #2) with 70% CF. Your existing position keeps using the **old version** (key #1, 80% CF). Your old deposits are protected — you still have 80% borrowing power.

But this protection is **not permanent**. When you do something that increases your risk, your position "refreshes" to the latest config:

| Action | Refreshes config? | Scope | Why? |
|--------|:-----------------:|-------|------|
| Supply more (to same reserve) | No | — | Supplying increases collateral → reduces risk |
| Repay debt | No | — | Repaying reduces debt → reduces risk |
| Enable as collateral | Yes | That reserve only | New collateral commitment → bind to current config |
| Borrow | Yes | **All** collateral reserves | Adding debt increases overall position risk → re-evaluate everything |
| Withdraw | Yes | **All** collateral reserves | Removing collateral increases overall position risk → re-evaluate everything |
| Disable as collateral | Yes | **All** collateral reserves | Removing collateral backing → re-evaluate everything + HF check |
| Liquidation | No | — | Liquidation improves position |

**Important clarification on supply:** Supplying more tokens to a reserve you already have collateral in does **NOT** refresh your configKey. Your `suppliedShares` simply accumulates — whether you deposit 1 ETH or 10 ETH across 10 separate transactions, you still have one `UserPosition` with one `dynamicConfigKey`. The new deposits don't trigger a snapshot refresh.

This means: if governance lowers your CF after your first deposit, your subsequent deposits also stay on the old config — until you do a risk-increasing action (borrow, withdraw, enable collateral).

**The trade-off**: V4 gives users a grace period when governance tightens risk parameters, but it doesn't freeze them forever. Once you interact with the protocol in a way that increases risk, you're brought up to the current risk parameters. This replaces V3's approach of separating `ltv` (borrow limit, lower) from `liquidationThreshold` (liquidation line, higher) as a static 5% buffer.

> For detailed analysis of why V4 removed the ltv/lt buffer, see `v3-v4-collateral-and-health-factor.md` §七.

**Design philosophy: why does supply not refresh, but withdraw does?**

Supply and withdraw operate on the same asset, but they have opposite risk effects:

- **Supply = adding collateral** → your position becomes *safer* (more backing for your debt). The protocol has no reason to re-evaluate your risk parameters — you just improved your position. So `supply()` simply adds `suppliedShares` and exits. No config refresh, no HF check.

- **Withdraw = removing collateral** → your position becomes *riskier* (less backing for your debt). The protocol *must* re-evaluate: are you still safe under the *current* risk parameters? So `withdraw()` calls `_refreshAndValidateUserAccountData()`, which refreshes ALL collateral reserves to their latest configKeys AND checks `HF >= 1.0`.

The key insight: **config refresh is tied to risk direction, not asset identity**. Supplying ETH and withdrawing ETH touch the same reserve, but supply reduces risk (no refresh needed) while withdraw increases risk (refresh required). This is why `borrow` also refreshes all configs (adding debt = risk increase) while `repay` does not (reducing debt = risk decrease).

---

## 8. Liquidation Engine

### Key differences from V3

| Dimension | V3 | V4 |
|-----------|-----|-----|
| Liquidation amount | Fixed close factor 50% (100% if HF<0.95) | Dynamic: calculate debt needed to restore HF to `targetHealthFactor` |
| Liquidation bonus | Fixed value (e.g., 5%) | Dutch auction: bonus increases linearly as HF decreases |
| Dust handling | Reverts if remaining < threshold | Dynamically increases maxRepay to allow full repayment |
| Post-liquidation HF | Not guaranteed | Restored to `targetHealthFactor` (e.g., 1.24 for Main Spoke) |

### Dutch auction liquidation bonus

```
if (HF ≤ healthFactorForMaxBonus):
    bonus = maxLiquidationBonus
else:
    bonus = minBonus + (maxBonus - minBonus) × (HF_THRESHOLD - HF) / (HF_THRESHOLD - HF_maxBonus)
```

where `minBonus = (maxLiquidationBonus - 100%) × liquidationBonusFactor + 100%`

> See `v3-v4-collateral-and-health-factor.md` §五 for on-chain `targetHealthFactor` values per Spoke and full liquidation formula.

---

## References

[1] Aave V4 Overview Document. GitHub. https://github.com/aave/aave-v4/blob/main/docs/overview.md
[2] Aave V4 Contract Source Code. GitHub. https://github.com/aave/aave-v4/tree/main/src
[3] Aave V4 Official Documentation. https://aave.com/docs/aave-v4

## Companion Documents

| Document | Scope |
|----------|-------|
| `v3-v4-collateral-and-health-factor.md` | Collateral parameters, HF formulas, Risk Premium algorithm, on-chain values |
| `v3-v4-sdk-field-mapping.md` | SDK field-level mapping (API → SDK → processing) |
| `hub-spoke-position-isolation.md` | Spoke isolation, cross-Hub collateral, borrowable constraint chain |
| `frozen-paused-semantics.md` | V3/V4 frozen/paused/active/halted semantics |
| `id-namespace-taxonomy.md` | ID hierarchy (Hub → Asset → Spoke → Reserve) with mermaid diagrams |
| `aave-supply-borrow-rate-formula.md` | Supply/Borrow rate formulas (V3 + V4) |
| `deficit-analysis.md` | Deficit mechanism (V3 + V4) |
| `field-glossary.md` | API field → frontend display concept reference |
