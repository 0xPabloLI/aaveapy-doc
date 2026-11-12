# V3 vs V4 SDK Field Mapping

> **Term layers**: Protocol concept (e.g., Market, Reserve) | Contract field (e.g., `baseLTVasCollateral`, `collateralFactor`) | SDK path (e.g., `r.settings.collateralFactor.value`) | API field (e.g., `ltv`) | Frontend concept (e.g., `maxBorrowUsd`)
>
> **精度统一（已完成）**：所有百分比字段已统一为 `number`、单位 %（例如 `9` = 9%）。

## Overview

| 维度 | V3 | V4 |
|------|-----|-----|
| **SDK 方法** | `markets()` → `market.supplyReserves[]` | 独立 GraphQL 查询：`chains()` + `hubs()` + `reserves()` |
| **处理文件** | `src/index.ts` (`buildV3BaseDataset()`) | `src/v4-fetcher.ts` (`fetchV4MarketsDataInner()`) |
| **Reserve ID** | `${chainId}:${poolAddress}:${token}` | `${chainId}:${spokeAddress}:${token}:${hubName}` |
| **数据级别** | 全部 Reserve 级别 | 部分 Hub 级别（来自 `r.asset`，同 hub 共享），部分 Reserve 级别 |

**V4 Hub 级字段来自 `r.asset.summary` / `r.asset.settings`**（HubAsset 绑定到 reserve 所属 hub），不需要 `hubAssets()` 预取。

---

## Core Field Mapping Tables

### Basic Info

| API field | Type | Frontend | V4 level | V4 SDK path | V3 SDK path |
|-----------|------|----------|-----------|-------------|-------------|
| `reserveId` | `string` | - | Reserve | 构造: `${chainId}:${spokeAddress}:${token}:${hubName}` | 构造: `${chainId}:${poolAddress}:${token}` |
| `marketName` | `string` | Market 列 | Reserve | 构造: `AaveV4${spokeName}` | `market.name` |
| `chainName` | `string` | Market 列 | Reserve | `r.chain?.name` | `market.chain?.name` |
| `chainId` | `number` | - | Reserve | `Number(r.chain?.chainId)` | `market.chain?.chainId` |
| `tokenName` | `string` | Token 名称 | Reserve | `r.asset?.underlying?.info?.name` | `reserve.underlyingToken?.name` |
| `tokenSymbol` | `string` | Token 列 | Reserve | `r.asset?.underlying?.info?.symbol` | `reserve.underlyingToken?.symbol` |
| `tokenAddress` | `string` | 合约地址 | Reserve | `r.asset?.underlying?.address` | `reserve.underlyingToken?.address` |
| `decimals` | `number` | 精度换算 | Reserve | `r.asset?.underlying?.info?.decimals` | `reserve.underlyingToken?.decimals` |

### Price & Size

| API field | Type | Frontend | V4 level | V4 SDK path | V3 SDK path |
|-----------|------|----------|-----------|-------------|-------------|
| `tokenPrice` | `number`, USD | Price 列 | Reserve | `r.summary?.supplied?.exchangeRate` | `reserve.size?.usdPerToken` ?? `reserve.usdExchangeRate` |
| `reserveSizeUsd` | `number`, USD | Size 列 | Reserve | `r.summary?.supplied?.exchange` | `reserve.size?.usd` |
| `supplyCapUsd` | `number`, USD | Supply cap | **Reserve** | `r.settings?.supplyCap?.exchange` | `reserve.supplyInfo?.supplyCap?.usd` |
| `borrowCapUsd` | `number`, USD | Borrow cap | **Reserve** | `r.settings?.borrowCap?.exchange` | `reserve.borrowInfo?.borrowCap?.usd` |
| `reserveSize` | `string`, raw | 后端派生 | Reserve | `r.summary?.supplied?.amount?.onChainValue` | `reserve.size?.amount?.raw` |
| `supplyCap` | `string`, raw | 后端派生 | Reserve | `r.settings?.supplyCap?.amount?.onChainValue` | `reserve.supplyInfo?.supplyCap?.amount?.raw` |
| `borrowCap` | `string`, raw | 后端派生 | Reserve | `r.settings?.borrowCap?.amount?.onChainValue` | `reserve.borrowInfo?.borrowCap?.amount?.raw` |
| `availableLiquidityUsd` | `number`, USD | 后端 | **Hub** | `r.asset.summary.availableLiquidity.exchange.value` | `reserve.borrowInfo?.availableLiquidity?.usd` |
| `totalVariableDebtUsd` | `number`, USD | 后端 | Reserve | `r.summary?.borrowed?.exchange` | `reserve.borrowInfo?.total?.usd` |

### APY & Rate

| API field | Type | Frontend | V4 level | V4 SDK path | V3 SDK path |
|-----------|------|----------|-----------|-------------|-------------|
| `supplyApy` | `number`, % | Supply > Native | **Hub** | `r.summary?.supplyApy?.value` | `reserve.supplyInfo?.apy?.value` |
| `borrowApy` | `number`, % | Borrow > Native | **Hub** | `r.summary?.borrowApy?.value` | `reserve.borrowInfo?.apy?.value` |
| `utilizationPct` | `number`, % | Util 列 | **Hub** | `r.asset.summary.utilizationRate.value × 100` | `reserve.borrowInfo?.utilizationRate?.value × 100` |
| `availableLiquidity` | `string`, raw | 后端子段 | **Hub** | `r.asset.summary.availableLiquidity.amount.onChainValue` | `reserve.borrowInfo?.availableLiquidity?.amount?.raw` |
| `totalVariableDebt` | `string`, raw | Borrowed | Reserve | `r.summary?.borrowed?.amount?.onChainValue` | `reserve.borrowInfo?.total?.amount?.raw` |

### Rate Model Parameters (all percent number)

| API field | Type | Frontend | V4 level | V4 SDK path | V3 SDK path |
|-----------|------|----------|-----------|-------------|-------------|
| `protocolFee` | `number`, % **optional** | rate calc | **Hub** | `r.asset.settings.liquidityFee.value × 100` | `reserve.borrowInfo?.reserveFactor.value × 100` |
| `variableRateSlope1` | `number`, % | rate calc | **Hub** | `r.asset.settings.slopeBelowOptimal.value × 100` | `reserve.borrowInfo?.variableRateSlope1.value × 100` |
| `variableRateSlope2` | `number`, % | rate calc | **Hub** | `r.asset.settings.slopeAboveOptimal.value × 100` | `reserve.borrowInfo?.variableRateSlope2.value × 100` |
| `optimalUsageRate` | `number`, % | Util sheet | **Hub** | `r.asset.settings.optimalUtilizationRate.value × 100` | `reserve.borrowInfo?.optimalUsageRate.value × 100` |
| `baseVariableBorrowRate` | `number`, % | rate calc | **Hub** | `r.asset.settings.baseBorrowRate.value × 100` | 链上 RPC (`UiPoolDataProvider`) 或 APY→APR 反推 |

### Contract Addresses

| API field | Frontend | V4 level | V4 SDK path | V3 SDK path |
|-----------|----------|-----------|-------------|-------------|
| `aTokenAddress` | - | N/A | `null` (V4 无 aToken) | `reserve.aToken?.address` |
| `vTokenAddress` | - | N/A | `null` (V4 无 vToken) | `reserve.vToken?.address` |
| `hubId` | pro.aave.com | **Hub** | `hub?.id` | N/A |
| `hubName` | Hub 名称 | **Hub** | `hub?.name` | N/A |
| `hubAddress` | 合约交互 | **Hub** | `hub?.address` | N/A |
| `spokeId` | 拼接 | Reserve | `spoke?.id` | N/A |
| `spokeName` | Spoke 名称 | Reserve | `spoke?.name` | N/A |
| `spokeAddress` | 合约交互 | Reserve | `spoke?.address` | N/A |

### Status & Switches

| API field | Frontend | V4 level | V4 SDK path | V3 source |
|-----------|----------|-----------|-------------|-----------|
| `supplyDisabled` | tooltip | Reserve | `!r.canSupply` | 派生: `isFrozen \|\| isPaused \|\| supplyCap === 1` |
| `borrowDisabled` | tooltip | Reserve | `!r.canBorrow` | 派生: `borrowingState === "DISABLED" \|\| borrowCap === 1` |
| `isFrozen` | badge | Reserve | `r.status?.frozen` | `reserve.isFrozen` |
| `isPaused` | badge | Reserve | `r.status?.paused` | `reserve.isPaused` |

> **Verified (2026-05-04)**: V4 `isFrozen`/`isPaused` = true 时 `canSupply`/`canBorrow` 始终 false → `supplyDisabled`/`borrowDisabled` 始终 true。反向不成立。

### Incentives (external, all percent number)

| API field | Type | Frontend | V4 source | V3 source |
|-----------|------|----------|-----------|-----------|
| `supplyIncentives` | `number[]`, % | Protocol | SDK: `r.summary?.rewards` (通常跳过) | SDK: `reserve.incentives` |
| `borrowIncentives` | `number[]`, % | Protocol | SDK: `r.summary?.rewards` (通常跳过) | SDK: `reserve.incentives` |
| `meritSupplys`/`meritBorrows` | `MeritIncentive[]` | ACI | Merit API → `enrichDatasetWithIncentiveData()` | 同 |
| `merklSupplys`/`merklBorrows`/`merklHolds` | `MerklOpportunityGroup[]` | Merkl | Merkl API → `enrichDatasetWithIncentiveData()` | 同 |
| `brevisSupplys`/`brevisBorrows` | `BrevisIncentive[]` | Brevis | Brevis API → `enrichDatasetWithIncentiveData()` | 同 |

### Special

| API field | Type | Frontend | V4 | V3 source |
|-----------|------|----------|-----|-----------|
| `deficit` | `string`, raw | Deficit | N/A (SDK 不提供), 默认 `'0'` | 链上 RPC (`UiPoolDataProvider`) |
| `borrowingState` | `string` (V3 only) | borrow disabled | 通过 `canBorrow` 间接判断 | `reserve.borrowInfo?.borrowingState` |
| `ltv` | `number`, percent | Portfolio LTV constraint (AAV-756) | `settings.collateralFactor.value` → `percentValueToPercent()` | `supplyInfo.maxLTV.value` → `percentValueToPercent()` |
| `liquidationThreshold` | `number`, percent | Health Factor (AAV-756) | = `ltv` (V4 collateralFactor 合并) | `supplyInfo.liquidationThreshold.value` → `percentValueToPercent()` |

---

## V4 Hub-Level Fields

以下字段绑定到 `r.asset`（HubAsset），同一 Hub 内多个 Reserve 拿到的值相同：

`utilizationPct`, `availableLiquidity`, `availableLiquidityUsd`, `reserveFactor`, `variableRateSlope1`, `variableRateSlope2`, `optimalUsageRate`, `baseVariableBorrowRate`, `hubId`, `hubName`, `hubAddress`

**注意**：`supplyCapUsd`/`borrowCapUsd` 是 Reserve 级别（来自 `r.settings`），不是 Hub 级别。

**为什么 `supplyApy`/`borrowApy` 是 Hub 级别**：APY = f(utilizationPct, 利率模型参数)，两者都是 Hub 级别的。同一 Hub 内所有 Spoke 的 APY 必然相同。V3 中每个 reserve 有独立利率参数，APY 可以不同。

---

## Key Path Differences

```typescript
// reserveSizeUsd
// V3: reserve.size?.usd
// V4: r.summary?.supplied?.exchange

// supplyCapUsd / borrowCapUsd
// V3: reserve.supplyInfo?.supplyCap?.usd / reserve.borrowInfo?.borrowCap?.usd
// V4: r.settings?.supplyCap?.exchange / r.settings?.borrowCap?.exchange

// Hub-level fields (V4 only)
const a = r.asset; // HubAsset
const utilizationPct = percentNumberToPercent(a?.summary?.utilizationRate); // value × 100
const variableRateSlope1 = percentNumberToPercent(a?.settings?.slopeBelowOptimal);
```

**SDK response structure** (V4):
```typescript
// Erc20Amount: { amount: { onChainValue: string } } — used for borrowed, availableLiquidity
// ExchangeAmount: { value: string } — used for supplyCap, borrowCap
// PercentNumber: { value: string } — used for utilizationRate, liquidityFee, slopes, etc.
```

**Conversion functions** (all in `src/`):
- `toFiniteNumber(value)` → `number | null` — safe numeric conversion
- `percentNumberToPercent(pn)` → V4: `pn.value × 100` (decimal fraction → percent)
- `percentFromV3(pv)` → V3: `pv.value × 100` (same logic, different SDK type name)

**`protocolFee` 的缺失语义**：字段在 `RuntimeReserveData` 里是可选的，**缺失 = 0%**。后端序列化器（`backend/src/services/marketsApiSerialize.ts`）用真值判断决定是否写出该字段，因此 fee 为 0 的 reserve 在 `/markets` 里看不到 `protocolFee`。消费方必须把"没有这个字段"读成 0，不能读成"没有费率模型"——`AaveV4EthenaEcosystem` 的 USDe 就是这种形态。前端 `hasRateCalcFields` 只检查原生利率曲线需要的 7 个参数，`protocolFee` 不在门槛内（AAV-1350）。

---

## Data Source Priority

1. **SDK** (每分钟刷新，最优先)
2. **On-chain RPC** (仅 V3 覆盖，`deficit` 和 `baseVariableBorrowRate` 兜底)
3. **Fallback 计算/默认值**

V4 特有字段完全依赖 SDK，无 RPC 覆盖。

## Verification Scripts

- V3/V4 reserve 数量对比：`node scripts/validate-sdk-reserve-fields.mjs`
- SDK vs On-chain 匹配：`backend/scripts/validate-sdk-onchain-reserve-match.mjs`
- 基础利率 fallback：`backend/scripts/validate-base-rate-fallback.mjs`

## GraphQL Client

V3 和 V4 SDK 底层都使用 urql（非 Apollo Client），默认 `batch: true`。同一 tick 内多个 query 自动合并为单个 HTTP POST，无需额外配置。

```typescript
// V4: chains() + hubs() + reserves() 并行发起，urql 自动合并
const results = await Promise.all([
  chains(client, { query: { filter: 'ALL' } }),
  hubs(client, { /* ... */ }),
  reserves(client, { /* ... */ }),
]);
```

V3 的 `markets()` 支持批量 chainIds。当前实现逐个 chainId 调用（错误隔离优先于请求合并）。

---

**相关文档**: `field-glossary.md` (前端派生值公式), `v3-v4-precision-unification-plan.md` (精度统一), `v4-architecture-analysis.md` (V4 架构), `v3-v4-collateral-and-health-factor.md` (抵押/HF/RP)
