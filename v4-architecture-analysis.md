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

> **Spoke list is dynamic**: Governance can add, modify, or retire Spokes at any time. The tables below reflect `/api/markets` data as of 2026-11-12 (124 V4 reserves across 29 `(chain, hub, spoke)` pairs). They will change.

### Hubs

V4 uses multiple Hubs per chain. As of 2026-11-12, 6 Hubs are deployed:

| Hub | Chains | Description |
|-----|--------|-------------|
| Core Hub | Ethereum, Arc, Avalanche | Primary hub, most Spokes connect here |
| Plus Hub | Ethereum | Ethena-focused |
| Prime Hub | Ethereum | Bluechip (higher risk profile) |
| Global Dollar Hub | Ethereum | USDG-specific |
| Sentora Hub | Ethereum | Curated spokes (RLUSD Yield, OUSD Yield, Bluechip) |
| Coinbase Stocks Hub | Base | Single spoke, tokenized-equity collateral |

> Official V4 docs (`aave-v4/liquidity/hubs`) name three: Core, Plus, Prime. Global Dollar, Sentora and Coinbase Stocks are visible in the markets payload but not yet in official docs.
>
> ⚠️ **A Spoke name is not unique across Hubs.** `Bluechip` exists under Core, Prime *and* Sentora; `USDG Pendle` under Core *and* Global Dollar; `Ethena Ecosystem` under Core *and* Plus. The Hub is part of the Spoke's identity, so anything that keys or matches Spokes by name alone will collide — see `hub-spoke-position-isolation.md` and AAV-1356.

### Actual deployed Spokes (`/api/markets`, as of 2026-11-12)

| Chain | Hub | Spoke | Reserves |
|-------|-----|-------|----------|
| Ethereum | Core | Main | 15 |
| Ethereum | Core | Bluechip | 5 |
| Ethereum | Core | Gold | 8 |
| Ethereum | Core | Lombard | 3 |
| Ethereum | Core | Forex | 7 |
| Ethereum | Core | Ethena Ecosystem | 3 |
| Ethereum | Core | USDG Pendle | 1 |
| Ethereum | Core | Maple SyrupUSDG | 1 |
| Ethereum | Core | Lido | 2 |
| Ethereum | Core | Etherfi | 2 |
| Ethereum | Core | Kelp | 2 |
| Ethereum | Plus | Ethena Ecosystem | 7 |
| Ethereum | Plus | Ethena Correlated | 4 |
| Ethereum | Prime | Bluechip | 7 |
| Ethereum | Global Dollar | USDG Pendle | 4 |
| Ethereum | Global Dollar | Maple SyrupUSDG | 3 |
| Ethereum | Global Dollar | PAXG Gold | 3 |
| Ethereum | Global Dollar | Gold Correlated | 2 |
| Ethereum | Sentora | RLUSD Yield | 5 |
| Ethereum | Sentora | OUSD Yield | 5 |
| Ethereum | Sentora | Bluechip | 4 |
| Arc | Core | Main | 4 |
| Arc | Core | Forex | 2 |
| Arc | Core | Maple SyrupUSDC | 2 |
| Base | Coinbase Stocks | Coinbase Stocks | 9 |
| Avalanche | Core | Main | 6 |
| Avalanche | Core | Ethena Ecosystem | 3 |
| Avalanche | Core | Forex | 3 |
| Avalanche | Core | AVAX Correlated | 2 |

> The `targetHealthFactor` column this table used to carry is not in the `/api/markets` payload, so it is omitted rather than carried forward unverified. The 2026-08-01 snapshot that had it is in this file's git history.


### Treasury Spoke（V4 协议费用收取器）

V4 官方 Address Book（`aave.com/docs/resources/addresses`）在 SPOKES 分类下列出了 **Treasury Spoke**（`0xB9B0b8616f6Bf6841972a52058132BE08d723155`）。

**治理论坛确认的用途**（`governance.aave.com/t/aave-v4-testnet-and-codebase-are-live/23435`，2025-11）：

> "The Treasury Spoke: acts as the **Liquidity Fee collector**, routing protocol fees to the designated treasury destination."

> ⚠️ 注意：这是 testnet 阶段的描述。主网部署后功能可能已扩展或调整，以 ABI 分析为补充。

**Etherscan 合约分析**（与治理论坛描述一致）：
- ABI 有 `supply`/`supplySkimmed`/`withdraw`/`transfer`，无 `borrow`/`repay`/`liquidationCall`
- `supply`/`supplySkimmed` = 将收取的费用存入 Hub / 收取已累积的费用
- `withdraw` = 从 Hub 提取费用
- `transfer` = 将费用转移到指定的金库目标地址
- 不在 pro.aave.com 界面显示——是费用基础设施，不是用户市场

**为什么 Treasury Spoke 余额为 0？**

从 V4 SDK 数据（`data/debug/v4-raw-sdk-response.json`，2026-09-17，92 个以太坊 V4 Reserve）确认：两个字段在 `asset.settings` 下（`feeReceiver`、`liquidityFee`）。`liquidityFee` 是 `PercentNumber`：`value: "0.10"` 与 `normalized: "10.00"` 表达同一个 **10%**，`onChainValue: "1000"` 是 bps。把它读成 0.10% 会让费率小 100 倍。

| feeReceiver | Reserve 数 | liquidityFee 分布 |
|-------------|-----------|-------------------|
| Treasury Spoke `0xB9B0…3155` | 53 | 0% ×22、10% ×24、20% ×21、15% ×6、25% ×2 |
| `0x2C4A…13a6` | 11 | 0% ×1、10% ×6、20% ×2、15% ×1、25% ×1 |
| `0xcbd466…` | 6 | 10% ×4、15% ×1、20% ×1 |

合计 69/92 非 0，区间 10%–25%。所以"大多数以太坊 V4 Reserve 的 `liquidityFee` 为 0"不成立：费率早已配置，0 是占比四分之一的那部分。

余额为 0 的原因：
1. 费用先在 Hub 侧累积（`$F_{acc}$` 的 unrealized 部分），要经过 `supplySkimmed()` / `withdraw()` 才落到 Treasury Spoke；下方链上状态（0 ETH、1 笔 Transfer Ownership）说明这条提取路径还没跑过
2. V4 的 TVL 远小于 V3，即使 10% 费率，累积金额也有限
3. 以太坊上仍有 23/92 个 Reserve 的 `liquidityFee` 为 0

**与 DAO Collector 的关系**：

通过 aave-address-book（`github.com/aave-dao/aave-address-book` 的 `safe.csv`）确认：

| 实体 | 别名 | 地址 | Etherscan 标签 | 余额 | 活跃度 |
|------|------|------|----------------|------|--------|
| DAO Collector (V3 Ethereum) | Aave DAO Treasury / Treasury Collector | `0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c` | Aave: Treasury Collector V2 | 445 ETH + >$22M tokens (295 种) | 315 笔交易，5 天前最后活动 |
| Treasury Spoke (V4 Ethereum) | V4 Liquidity Fee Collector | `0xB9B0b8616f6Bf6841972a52058132BE08d723155` | Aave: Treasury Spoke | 0 ETH | 1 笔交易（Transfer Ownership，131 天前） |

**每条链有独立的 Collector**（V3 各链 Collector 地址，来自 aave-address-book `safe.csv`）：

| 链 | chainId | Collector 地址 |
|----|---------|----------------|
| Ethereum | 1 | `0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c` |
| Optimism | 10 | `0xB2289E329D2F85F1eD31Adbb30eA345278F21bcf` |
| BNB Chain | 56 | `0x25Ec457d1778b0E5316e7f38f3c22baF413F1A8C` |
| Gnosis | 100 | `0x3e652E97ff339B73421f824F5b03d75b62F1Fb51` |
| Polygon | 137 | `0xe8599F3cc5D38a9aD6F3684cd5CEa72f10Dbc383` |
| Monad | 143 | `0x22A14267f9F8bA21D11898F0772e652B09e6A8A1` |
| Sonic | 146 | `0x1aB55bBdD5DF0782BBCf73553Af93BC6B29A286B` |
| XLayer | 196 | `0x3E9CfB4FDe8180C48b823C12DD2c4B841843f92E` |
| ZkSync | 324 | `0xd69Cbda644c6be817AaFb5Fd9174f50C33803B6b` |
| Metis | 1088 | `0xB5b64c7E00374e766272f8B442Cd261412D4b118` |
| Base | 8453 | `0xBA9424d650A4F5c80a0dA641254d1AcCE2A37057` |
| Soneium | 1868 | `0xc7B3cc5F5988613b0D620623C514EDFB32539720` |
| MegaEth | 4326 | `0x7E195b3fc91fDd51A9CD5070cC044602212Ac983` |
| Mantle | 5000 | `0x0cd2670339Cd520BF9428Ad881bE60A698aB9B32` |
| Arbitrum | 42161 | `0x053D55f9B5AF8694c503EB288a1B7E552f590710` |
| Celo | 42220 | `0xC959439207dA5341B74aDcdAC59016aa9Be7E9E7` |
| Avalanche | 43114 | `0x5ba7fd868c40c16f7aDfAe6CF87121E13FC2F7a0` |
| Ink (Whitelabel) | 57073 | `0x9138E2cAdFEB23AFFdc0419F2912CaB8F135dba9` |
| Linea | 59144 | `0x86E2938daE289763D4e09a7e42c5cCcA62Cf9809` |
| Plasma | 9745 | `0x5E2d083417D12d4B0824E14Ecd48D26831F4Da7D` |
| Scroll | 534352 | `0x90eB541e1a431D8a30ED85A77675D1F001128cb5` |

> Ethereum 上 V3 的所有子实例（V2、V2 AMM、V2 Arc、V3、V3 EtherFi、V3 Horizon、V3 Lido）共享同一个 Collector 地址。
> V4 的 Treasury Spoke 目前只在 Ethereum 上部署（V4 还没有扩展到其他链）。

**结论**：
- DAO Collector 和 Treasury Spoke 是**不同地址、不同合约、不同协议版本的费率收取器**
- V3 费用 → 各链的 DAO Collector，以太坊主网（`0x464C...18c`）已运行 5 年+，持有 $23M+ 资产
- V4 费用 → Treasury Spoke（`0xB9B0...3155`），大部分 Reserve 费率为 0%，尚未产生收入
- 治理论坛提到的 "budget / asset-holding SAFEs"（金库 SAFE 多签钱包）地址**未在 aave-address-book 中公开**

**与 Stable Vaults FAQ 中 "the treasury" 的关系**：

Stable Vaults FAQ 原文提到 *"sweep the surplus to the treasury"*，"the treasury" 最可能指 DAO Collector（`0x464C...18c`）或由它资助的 budget SAFE。但 Stable Vaults 是独立产品层，"the treasury" 也可能指其自己的金库机制。**无法从现有文档 100% 确认**。

> 另一个治理话题（`governance.aave.com/t/arfc-aave-will-win-framework/24352`）提到 CoW Swap UI 费用路由"operates through a different mechanism than V4 Treasury Spoke fee collection"，确认 Treasury Spoke 专责 V4 协议费用收取。

**V3 vs V4 对比**：

| 维度 | V3 | V4 |
|------|-----|-----|
| 协议费用收取 | Collector 合约（`collectProtocolFee`，V3 Pool 合约内置） | **Treasury Spoke**（独立 Spoke 合约，收取 Hub 的 `liquidityFee` 并路由到金库） |
| 协议原生固定利率 | Stable Rate Borrowing（V3.2.0 已废弃，借款端固定利率） | **无**。V4 只有 utilization curve 变动利率 |
| 固定利率产品 | 无 | 无。Stable Vaults 是独立产品层，同时使用 V3、V4、sGHO、Veda 作为底层收益策略（见下方证据） |

> **"cover what it owes" 原文出处**（`aave.com/stable-vaults` FAQ）：
>
> Q: What happens if the yield earned differs from the yield paid to depositors?
>
> A: The vault continuously tracks its assets against its obligations to depositors. If earned yield falls short, principal is always guaranteed and an authorized party can top up the system to keep every user's earned interest fully withdrawable; if assets exceed obligations, an authorized caller may sweep the surplus to the treasury—though never in a way that would leave the vault unable to cover what it owes.
>
> 这里的 "the vault" = Stable Vaults，"what it owes" = Stable Vaults 对用户的固定利率负债。

**Key observation**: The same Spoke name (e.g., Bluechip, Ethena Ecosystem, USDG Pendle) can connect to different Hubs with different Reserves. This is by design — a Spoke connects to one or more Hubs.

Observed configuration patterns (on-chain data, not design intent):
- Main, Bluechip, Gold: `healthFactorForMaxBonus=0.90`, `liquidationBonusFactor=9000` (90%)
- LST + Ethena + Forex Spokes: `healthFactorForMaxBonus=0.99`, `liquidationBonusFactor=10000` (100%)

### V4 user interface

V4 is accessible at **pro.aave.com** (not app.aave.com which is V3-only). The navigation explicitly labels: "Aave Pro = V4, The full power of DeFi" vs "Aave = V3, The original DeFi protocol".

pro.aave.com features:
- Multi-chain, multi-Hub, multi-Market asset browser (All Chains / All Hubs / All Markets filters)
- Deposit and Borrow views
- Activity tracking (LiquidatedActivity, UsingAsCollateralActivity, UpdatedDynamicConfigActivity, UpdatedRiskPremiumActivity, TokenSwapActivity)
- Position swap support (SupplySwap, BorrowSwap, WithdrawSwap)

### Stable Vaults (not a V4 Spoke)

Stable Vaults is a **separate Aave product** that embeds fixed-rate stablecoin yield into financial products. It is **not** a V4 Spoke — it does not appear in the Hub-Spoke model. Do not confuse it with V3's deprecated Stable Rate Borrowing.

**How it achieves fixed-rate yield:**

```
User deposits stablecoin → Stable Vault (Accounting Chain, e.g. Arbitrum)
                              ↓
                        SubVault (fixed per-second rate)
                              ↓
                        Allocator (deploys to yield strategies)
                              ↓
                        ERC-4626 adapters (Aave V3, V4, sGHO, Veda, etc.)
```

- **SubVault**: Each deposit accrues at a fixed per-second rate. Returns stay predictable regardless of underlying market rate movements.
- **Off-chain rebalancer**: Continuously optimizes allocations across approved ERC-4626 yield adapters to sustain committed rates.
- **Surplus/deficit absorption (3-layer defense)**:
  1. **Off-chain rebalancer** (Manager role): First line — continuously moves allocations to higher-yielding approved strategies when one strategy's yield drops.
  2. **Surplus buffer**: When market yield > stable rate, surplus accumulates. This buffer is consumed first when market yield < stable rate. An authorized caller may sweep surplus to "the treasury", but "never in a way that would leave the vault unable to cover what it owes" (see Treasury Spoke section above for full quote and context).
  3. **"The treasury" top-up**: If surplus is exhausted, "the treasury" (指代不明，见上方 Treasury Spoke 章节的分析) injects capital to keep all earned interest fully withdrawable. This is a governance decision, not contract-enforced. **Principal is always guaranteed** — even if all yield strategies fail to earn anything, depositors get their principal back.
- **Multi-asset**: Deposit USDC, withdraw USDT (1:1 exchange enforced at contract level; slippage covered by external Slippage Coverage Vault, not user deposits).
- **Multi-chain**: Accounting Chain (Arbitrum) + Earning Chains (Ethereum), connected via CCIP/LayerZero/Hyperlane/Across. Chainlink oracle publishes balance snapshots.
- **Powering Aave App**: Stable Vaults powers the Aave App (iOS) earn experience.
- **Multi-protocol evidence**: Stable Vaults 同时使用 V3 和 V4 作为收益策略。
  - 产品页 (`aave.com/stable-vaults`): "Multi protocol: Aave v3, Aave v4, sGHO, Veda, and more."
  - 开发文档 (`aave.com/docs/vaults/stable-vaults/yield-strategies`): 列出 4 种策略类型 — "Aave V4 Markets"（ERC-4626 adapter wrapping V4 pool positions）、"Aave V3 Markets"（extended AToken vault adapter）、"Savings GHO Vault"、"Generic ERC-4626 Vault"

> Source: `aave.com/stable-vaults`, `aave.com/docs/vaults/stable-vaults/architecture`, `aave.com/docs/vaults/stable-vaults/yield-strategies`

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
