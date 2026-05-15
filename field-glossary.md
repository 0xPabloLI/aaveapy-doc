# API 字段含义对照表（Frontend Glossary）

本文档将 `GET /api/markets` 响应中的 `reserves[]` 字段映射到前端展示概念，方便前后端对齐。

---

## 一、核心数值字段

| API 字段 | 前端展示名称 | 展示区域 | 计算/类型 | 说明 |
|----------|------------|---------|-----------|------|
| `reserveSizeUsd` | **Total supplied** / **Supply Size** | Size 列（Supply 行）、CapProgressRing、SupplyCapSheet、DeficitLiquidityRing | `number` USD | 市场总供应量（TVL），美元计价。对应 aave.com 的 "Total supplied" |
| `totalVariableDebt` | **Total borrowed** / **Borrow Size** | Size 列（Borrow 行）、BorrowCapProgressRing、BorrowCapSheet | `string` raw token → 前端转为 USD | 前端通过 `totalVariableDebt / 10^decimals * tokenPrice` 换算为 USD 展示 |
| `availableLiquidity` | **Pool liquidity** / **Liquidity** | BorrowCapSheet、Utilization 列（Liquidity 排序） | `string` raw token → 前端转为 USD | 池中可用流动性。前端通过 `availableLiquidity / 10^decimals * tokenPrice` 换算 |
| `utilizationPct` | **Utilization** | Utilization 列（百分比 + 指示条） | `number` 百分比 0-100 | 资金利用率。前端还展示 `optimalUsageRate` 对应的 "Optimal" 标记 |
| `tokenPrice` | **Price** | Price 列 | `number` USD | 每个 token 的美元价格 |
| `supplyApy` | **Supply** (Native) | Supply 列主数值、SimulationSubRow | `number` 百分比 | 基础 Supply APY（不含激励）。前端合计：`supplyApy + sum(supplyIncentives等)` |
| `borrowApy` | **Borrow** (Native) | Borrow 列主数值、SimulationSubRow | `number` 百分比 | 基础 Borrow APY（不含激励）。前端合计：`borrowApy - sum(borrowIncentives等)` |
| `supplyCapUsd` | **Supply cap** / **Available to supply** / **% of cap** | CapProgressRing、SupplyCapSheet | `number` USD | 供应上限及相关派生值 |
| `borrowCapUsd` | **Borrow cap** / **Available to borrow** / **% of cap** | BorrowCapProgressRing、BorrowCapSheet | `number` USD | 借贷上限及相关派生值 |
| `deficit` | **Deficit** / **Deficit (%)** | Size 列（Deficit 行）、DeficitLiquidityRing | `string` raw token → 前端转为 USD + 计算占比 | 坏账。**双层存储：Hub 聚合 `Asset.deficitRay`（per asset）+ SpokeData 分量 `SpokeData.deficitRay`（per asset per spoke），无 Reserve 级别**。前端计算 `deficit / 10^decimals * tokenPrice` 得 USD 值，再算 `deficitUsd / (deficitUsd + totalSuppliedUsd)` 得占比 |

---

## 1.5 变量 Reserve 级别归属速查

| 分类 | 变量 | 粒度 | 说明 |
|------|------|------|------|
| **有 Reserve 级别** | `underlying`, `hub`, `assetId`, `decimals` | per Reserve | Reserve 结构体 |
| **有 Reserve 级别** | `collateralRisk`, `paused`, `frozen`, `borrowable`, `receiveSharesEnabled`, `dynamicConfigKey` | per Reserve | Reserve 配置 |
| **有 Reserve 级别** | `collateralFactor`, `maxLiquidationBonus`, `liquidationFee` | per Reserve per key | 动态配置 |
| **有 Reserve 级别** | `drawnShares`, `premiumShares`, `premiumOffsetRay`, `suppliedShares`（UserPosition） | per Reserve per User | 用户仓位 |
| **无 Reserve 级别** | `liquidity`, `realizedFees`, `swept`, `drawnIndex`, `drawnRate`, `lastUpdateTimestamp`, `liquidityFee`, `irStrategy`, `reinvestmentController`, `feeReceiver`, `deficitRay`（Asset） | per Asset (Hub) | Hub Asset 独占 |
| **无 Reserve 级别** | `addCap`, `drawCap`, `riskPremiumThreshold`, `active`, `halted`, `deficitRay`（SpokeData） | per Asset per Spoke | Hub SpokeData 独占 |
| **无 Reserve 级别（双层）** | `addedShares`, `drawnShares`, `premiumShares`, `premiumOffsetRay`, `deficitRay` | Asset 聚合 + SpokeData 分量 | Asset = Σ SpokeData |

**核心规律**：Spoke 端按 `reserveId` 索引的变量有 Reserve 级别；Hub 端只认识 `(assetId, spoke)`，不认识 `reserveId`，因此 Hub 侧变量均无 Reserve 级别。

---

## 二、利率计算字段（一般不直接展示）

| API 字段 | 前端使用方式 | 说明 |
|----------|------------|------|
| `decimals` | `availableLiquidity` / `totalVariableDebt` / `deficit` 的 USD 换算除数 | 代币精度 |
| `reserveFactor` | 传入 `useRateSimulation` 参与利率模拟 | 储备因子（percent） |
| `variableRateSlope1` | 传入 `useRateSimulation` 参与利率模拟 | 利率曲线斜率 1（percent） |
| `variableRateSlope2` | 传入 `useRateSimulation` 参与利率模拟 | 利率曲线斜率 2（percent） |
| `optimalUsageRate` | Utilization 列 "Optimal" 标记、UtilizationSheet | 最优利用率（percent），前端展示百分比 |
| `baseVariableBorrowRate` | 传入 `useRateSimulation` 参与利率模拟 | 基础可变借款利率（percent） |

---

## 三、激励字段

| API 字段 | 前端展示名称 | 说明 |
|----------|------------|------|
| `supplyIncentives` | **Protocol Incentive** | Aave 协议供应激励，累加后合入总 Supply APY |
| `borrowIncentives` | **Protocol Incentive** | Aave 协议借贷激励，累加后从总 Borrow APY 扣除 |
| `meritSupplys` / `meritBorrows` | **ACI Incentive** | Merit 激励，同协议激励处理 |
| `merklSupplys` / `merklBorrows` / `merklHolds` | **Merkl Incentive** | Merkl 激励，同协议激励处理；有白名单切换开关 |
| `brevisSupplys` / `brevisBorrows` | **Brevis Incentive** | Brevis 激励，同协议激励处理 |

激励整合（前端 `formatters.ts`）—— API 返回数组字段，前端求和后参与计算：
- **Total Supply APY** = `supplyApy + sum(supplyIncentives) + sum(meritSupplys) + sum(merklSupplys) + sum(brevisSupplys)`（均经 APR→APY 转换）
- **Total Borrow APY** = `borrowApy - sum(borrowIncentives) - sum(meritBorrows) - sum(merklBorrows) - sum(brevisBorrows)`
- **Spread** = `totalSupplyApy - totalBorrowApy`

### Spread 完整展开

$$Spread = totalSupplyApy - totalBorrowApy$$

展开为各组成元素：

| 侧 | 元素 | 来源 | 对 Spread 的贡献方向 | 说明 |
|----|------|------|---------------------|------|
| **Supply** | `supplyApy` | 链上合约/SDK | **正向** (+) | 基础供应 APY，V3 由 `SupplyRate = BorrowRate × supplyUsageRatio × (1-reserveFactor)` 算出；V4 由 exchange rate 年化增长率隐式表达 |
| | `sum(supplyIncentives)` | Aave 协议奖励 | **正向** (+) | Aave 协议供应激励 APR→APY |
| | `sum(meritSupplys)` | Merit (ACI) API | **正向** (+) | ACI 供应激励 |
| | `sum(merklSupplys)` | Merkl API | **正向** (+) | Merkl 供应激励 |
| | `sum(brevisSupplys)` | Brevis API | **正向** (+) | Brevis 供应激励 |
| **Borrow** | `borrowApy` | 链上合约/SDK | **负向** (-) | 基础借款 APY，由利率曲线分段函数算出 |
| | `sum(borrowIncentives)` | Aave 协议奖励 | **正向** (+) | Aave 协议借款激励（从 borrow APY 扣减→Spread 增大） |
| | `sum(meritBorrows)` | Merit (ACI) API | **正向** (+) | ACI 借款激励（同上） |
| | `sum(merklBorrows)` | Merkl API | **正向** (+) | Merkl 借款激励（同上） |
| | `sum(brevisBorrows)` | Brevis API | **正向** (+) | Brevis 借款激励（同上） |

**影响 `supplyApy` / `borrowApy` 链上层公式的因素**（间接影响 Spread）：

| 因素 | 版本 | 对 supplyApy 的影响 | 对 borrowApy 的影响 |
|------|------|-------------------|-------------------|
| **deficit** (坏账) | V3 | 清算后 totalDebt 减少，差额存入 deficit → 分母膨胀 | 不影响 |
| **deficit** (坏账) | V4 | 清算后 drawnShares 减少，差额计入 deficitRay → 数学等价 V3 | 不影响（策略参数虽传入但被忽略） |
| **reserveFactor** / **liquidityFee** | V3/V4 | 乘 `(1-factor)` 扣减→降低 | 不影响 |
| **premium** (风险溢价) | V4 only | `P+P_offset` 增大分子→提升 | 不直接影响（但提高借款人等效利率） |
| **F_acc** (累计协议费用) | V4 only | 从 totalAddedAssets 扣减→分母减小→提升 | 不影响 |
| **swept** (再投资抽走流动性) | V4 only | 出现在利用率分母→影响 borrowRate→间接影响 | 增大分母→降低 |
| **利率曲线参数** (slope1/slope2/optimal/base) | V3/V4 | 决定 borrowRate→间接决定 supplyRate | 直接决定 |

> 详细公式见 [aave-supply-borrow-rate-formula.md](aave-supply-borrow-rate-formula.md)，deficit 分析见 [deficit-analysis.md](deficit-analysis.md)。

---

## 四、状态/标识字段

| API 字段 | 前端展示名称 | 说明 |
|----------|------------|------|
| `supplyDisabled` | **Supply unavailable**（tooltip） | 供应是否被禁用 |
| `borrowDisabled` | **Borrow disabled**（tooltip） | 借贷是否被禁用 |
| `isFrozen` | **Frozen** / **Paused**（badge + ❄ icon） | 市场冻结/暂停状态 |
| `isPaused` | 同 `isFrozen` 处理 | 同上 |

---

## 五、基础标识字段

| API 字段 | 前端展示名称 |
|----------|------------|
| `tokenName` | Token 名称（如 "Aave Token"） |
| `tokenSymbol` | Token 符号（如 "AAVE"） |
| `tokenAddress` | 合约地址 |
| `marketName` | Market 列（如 "AaveV3Ethereum"） |
| `chainName` | 链名称（如 "Ethereum"） |
| `chainId` | 链 ID（如 `1`） |
| `reserveId` | 后端唯一标识键，前端无需展示 |
| `aaveProReserveId` | pro.aave.com 深链拼接用（仅 V4） |

---

## 六、V4 Hub & Spoke 字段

| API 字段 | 前端使用方式 |
|----------|------------|
| `hubId` | 拼接待用（`https://pro.aave.com/explore/hub/${hubId}`） |
| `hubName` | 显示 Hub 名称（如 "Core"） |
| `hubAddress` | 合约交互用 |
| `spokeId` | 拼接待用 |
| `spokeName` | 显示 Spoke 名称（如 "Main"） |
| `spokeAddress` | 合约交互用（市场入口） |

---
## 七、V4 SDK `borrowable` vs `canBorrow` 三层语义

在 V4 SDK 原始响应（`/api/markets` 的数据源）中，每个 reserve 存在三个与「借款」相关的字段，
分属不同层级，含义各不相同：

### 1. `summary.borrowable` — 可用借款数量（Erc20Amount 对象）

位于 `reserve.summary` 下，是 `__typename: "Erc20Amount"` 复杂对象，表示 **协议池子还剩多少可被借出**：

```json
"summary": {
  "supplied":   { ... },   // 总存款
  "borrowed":   { ... },   // 总借款
  "borrowable": {           // 剩余流动性 = 存款 - 借款
    "amount": { "onChainValue": "184229214", "value": "1.84229214" },
    "exchange": { "value": "149934.6142", "name": "USD" }
  }
}
```

### 2. `settings.borrowable` — 协议风险配置开关（boolean）

位于 `reserve.settings`（`ReserveSettings`），是管理员/治理配置的 **策略开关**——是否允许该资产被借出：

```json
"settings": {
  "borrowable": false,   // false = 协议不允许借款
  "collateral": true,
  "suppliable": true
}
```

> 对应合约层 Spoke `ReserveFlagsMap.borrowable`（位掩码 `0x04`），详见
> [frozen-paused-semantics.md](frozen-paused-semantics.md#borrowable借款开关)。

### 3. `canBorrow` — 运行时综合判断（boolean）

位于 reserve 顶层，面向用户的 **最终综合判断**，合并了所有状态条件：

```json
"canBorrow": false,        // 综合结果：能借吗？
"canSupply": true,
"canUseAsCollateral": true
```

### 判断逻辑链

```
settings.borrowable = true
  AND status.frozen = false
  AND status.paused = false
  AND status.active = true
→ canBorrow = true
```

| 字段 | 位置 | 类型 | 含义 |
|------|------|------|------|
| `summary.borrowable` | 数据层 | `Erc20Amount` 对象 | 还剩多少可借（流动性数量） |
| `settings.borrowable` | 配置层 | `boolean` | 协议是否允许借款（管理员开关） |
| `canBorrow` | 运行时层 | `boolean` | 用户现在能不能借（综合判断） |

> 可能 `settings.borrowable=true` 但 `canBorrow=false`（如资产被暂停），反之不可能。
>
> API 对外暴露 `borrowDisabled`（=`!canBorrow`的运行时值），不直接暴露 SDK 原始三层字段。

---
## 八、表头列与排序选项对照

```
┌─────────┬──────────┬────────┬──────────┬──────────┬──────────┐
│  Token  │  Market  │  Price │   Size   │   Util   │  Supply  │
│         │          │        │ ┌──────┐ │ ┌──────┐ │ ┌──────┐ │
│         │          │        │ │Supply│ │ │Util% │ │ │Total │ │
│         │          │        │ │Borrow│ │ │Liq.  │ │ │Native│ │
│         │          │        │ │Avail │ │ └──────┘ │ │Incent│ │
│         │          │        │ │Defic │ │          │ └──────┘ │
│         │          │        │ │Def%  │ │          │          │
│         │          │        │ └──────┘ │          │          │
├─────────┼──────────┼────────┼──────────┼──────────┼──────────┤
│         │          │        │  Spread  │   Borrow │          │
│         │          │        │ ──────── │ ┌──────┐ │          │
│         │          │        │          │ │Total │ │          │
│         │          │        │          │ │Native│ │          │
│         │          │        │          │ │Incent│ │          │
│         │          │        │          │ └──────┘ │          │
│         │          │        │          │          │          │
└─────────┴──────────┴────────┴──────────┴──────────┴──────────┘
```

### 排序选项与对应字段

| 列 | 排序选项 | 前端 key | 数据源字段 |
|----|---------|---------|-----------|
| **Size** | Supply | `supply` | `reserveSizeUsd` |
| | Borrow Size | `borrow` | `totalVariableDebt` → USD |
| | Borrow Avail | `borrowAvailability` | `min(borrowCapUsd - borrowedUsd, poolLiquidityUsd)`（派生） |
| | Deficit | `deficitAmount` | `deficit` → USD |
| | Deficit (%) | `deficitRatio` | `deficitUsd / (deficitUsd + totalSuppliedUsd)`（派生） |
| **Util** | Utilization | `utilization` | `utilizationPct` |
| | Liquidity | `liquidity` | `availableLiquidity` → USD |
| **Supply** | Total | `supplyTotal` | `supplyApy + sum(supplyIncentives等)`（派生） |
| | Native | `supplyNative` | `supplyApy` |
| | Incentive | `supplyIncentive` | `sum(supplyIncentives)`（派生） |
| **Borrow** | Total | `borrowTotal` | `borrowApy - sum(borrowIncentives等)`（派生） |
| | Native | `borrowNative` | `borrowApy` |
| | Incentive | `borrowIncentive` | `sum(borrowIncentives)`（派生） |
| **Spread** | — | — | `totalSupplyApy - totalBorrowApy`（派生） |

---

## 九、前端派生值计算公式

| 派生值 | 公式 | 代码位置 |
|--------|------|---------|
| Total Supply APY | `supplyApy + sum(incentiveApy)` | `formatters.ts:371-374` |
| Total Borrow APY | `borrowApy - sum(incentiveApy)` | `formatters.ts:384-388` |
| Spread | `totalSupplyApy - totalBorrowApy` | `formatters.ts:392-395` |
| Total Borrowed (USD) | `totalVariableDebt / 10^decimals * tokenPrice` | `scenarioSize.ts:106-119` |
| Pool Liquidity (USD) | `availableLiquidity / 10^decimals * tokenPrice` | `scenarioSize.ts:139-152` |
| Deficit (USD) | `deficit / 10^decimals * tokenPrice` | `deficit.ts:91-98` |
| Deficit Share Ratio | `deficitUsd / (deficitUsd + totalSuppliedUsd)` | `deficit.ts:100-111` |
| Available to Borrow | `min(borrowCapUsd - borrowedUsd, poolLiquidityUsd)` | `scenarioSize.ts:173-193` |

---

## 十、响应示例（字段 → 前端映射标注）

```json
{
  "reserveId": "1:0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2:0xbe9895146f7af43049ca1c1ae358b0541ea49704",
  "marketName": "AaveV3Ethereum",        // Market 列
  "chainName": "Ethereum",                // Market 列
  "chainId": 1,
  "tokenName": "Coinbase Wrapped Staked ETH",
  "tokenSymbol": "cbETH",                 // Token 列
  "tokenAddress": "0xBe9895146f7AF43049ca1c1AE358B0541Ea49704",
  "supplyApy": 0.18,                      // Supply > Native
  "borrowApy": 3.97,                      // Borrow > Native
  "tokenPrice": 3942.52,                  // Price 列
  "reserveSizeUsd": 1083255123.44,        // Size > Supply
  "supplyCapUsd": 2000000000,             // Supply cap ring
  "borrowCapUsd": 1000000000,             // Borrow cap ring
  "utilizationPct": 61.08,                // Utilization 列
  "availableLiquidity": "4512942554869044630386380",  // → Pool liquidity
  "totalVariableDebt": "1023456789012345678901234",   // → Total borrowed
  "deficit": "0",                         // → Deficit
  "supplyIncentives": [0.5],              // Supply > Incentive
  "borrowIncentives": [0.3],              // Borrow > Incentive
  "supplyDisabled": false,
  "borrowDisabled": false
}
```

---

## 十、常见前端用语 ↔ API 字段速查

| 前端说 | 找 API 字段 |
|--------|-----------|
| "Total supplied" / "总供应量" | `reserveSizeUsd` |
| "Total borrowed" / "总借款" | `totalVariableDebt`（需 USD 换算） |
| "Pool liquidity" / "池流动性" | `availableLiquidity`（需 USD 换算） |
| "Supply cap" / "供应上限" | `supplyCapUsd` |
| "Borrow cap" / "借贷上限" | `borrowCapUsd` |
| "Available to supply" | `supplyCapUsd - reserveSizeUsd`（派生） |
| "Available to borrow" | `min(borrowCapUsd - borrowed, poolLiquidity)`（派生） |
| "Utilization" / "利用率" | `utilizationPct` |
| "Deficit" / "坏账" | `deficit`（需 USD 换算 + 占比计算） |
| "Supply APY" | `supplyApy`（Native）+ 各激励（合计） |
| "Borrow APY" | `borrowApy`（Native）- 各激励（合计） |
| "Spread" | `totalSupplyApy - totalBorrowApy`（派生） |
| "Protocol Incentive" | `supplyIncentives` / `borrowIncentives` |
| "ACI Incentive" | `meritSupplys` / `meritBorrows` |
| "Merkl Incentive" | `merklSupplys` / `merklBorrows` / `merklHolds` |
| "Brevis Incentive" | `brevisSupplys` / `brevisBorrows` |
