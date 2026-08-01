# V3↔V4 抵押参数、Health Factor 与 Risk Premium

> **来源**：Aave V3.6 合约 `GenericLogic.sol` + Aave V4 合约 `Spoke.sol:706-813` + V4 `LiquidationLogic.sol`
> **用途**：前后端共享知识，为 AAV-1222（per-reserve ltv + liquidationThreshold）和 AAV-756（Portfolio LTV constraint + HF + Net Effective APY）提供协议级知识基础。
> **补充**：链上实测数据（targetHealthFactor、collateralRisk）+ 合约源码分析结论（V4 overview.md 未提及的发现）。

---

## 一、V3↔V4 术语对应表

V3 和 V4 在抵押/清算参数上存在**架构性差异**，不能简单按字段名映射。以下是概念级对应关系：

| 概念 | V3 合约字段 | V3 SDK 路径 | V4 合约字段 | V4 SDK 路径 | 关系 |
|------|------------|------------|------------|------------|------|
| **借款能力上限** | `baseLTVasCollateral` (uint16, BPS) | `supplyInfo.maxLTV.value` | `collateralFactor` (uint16, BPS, `DynamicReserveConfig`) | `settings.collateralFactor.value` | **语义等价**：决定最多能借多少 |
| **清算触发线** | `liquidationThreshold` (uint16, BPS) | `supplyInfo.liquidationThreshold.value` | `collateralFactor` (同上，**复用**) | 同上 | **V4 合并**：借款能力 = 清算线，无独立阈值 |
| **清算奖金** | `liquidationBonus` (uint16, BPS) | `supplyInfo.liquidationBonus.value` | `maxLiquidationBonus` (uint32, BPS, `DynamicReserveConfig`) | `settings.collateralFactor` 同层 | **语义等价**：清算人获得的额外抵押品 |
| **风险评分** | 不存在 | 不存在 | `collateralRisk` (uint24, BPS, `ReserveConfig`) | `settings.collateralRisk.value` | **V4 独有**：影响 Risk Premium → 等效借款利率 |
| **清算手续费** | 不存在 | 不存在 | `liquidationFee` (uint16, BPS, `DynamicReserveConfig`) | 同层 | **V4 独有**：从清算奖金中截留给协议 |
| **平均借款能力** | `avgLtv` | 合约内计算返回 | `avgCollateralFactor` | 合约内计算返回 | **语义等价**（但 V4 无 avg liquidationThreshold） |
| **平均清算阈值** | `avgLiquidationThreshold` | 合约内计算返回 | 不存在（= avgCollateralFactor） | — | **V4 不区分** |
| **Risk Premium** | 不存在 | 不存在 | `riskPremium` (uint24, BPS) | 合约内计算返回 | **V4 独有**：贪心分配算法 |

### 核心架构差异

| 维度 | V3 | V4 |
|------|-----|-----|
| **借款/清算参数** | 两个独立参数：`ltv`（较低）+ `liquidationThreshold`（较高） | 单一参数：`collateralFactor` 同时充当两者 |
| **安全缓冲带** | `liquidationThreshold - ltv > 0`（用户可借到 ltv 上限但不被清算） | 无缓冲（借到上限时 HF = 1.0，即清算线） |
| **Frozen 联动** | `ltv → 0`（阻止新借款），`liquidationThreshold` 不变 → HF 不受影响 | `collateralFactor` 独立管理（需治理单独操作） |
| **配置粒度** | per reserve（静态，单次配置） | per reserve per key（`DynamicReserveConfig` 版本化，新配置只对新仓位生效） |
| **Risk Premium** | 不存在 | 存在：基于 `collateralRisk` 贪心分配，影响等效借款利率 |

---

## 二、Health Factor 公式对比

### V3 Health Factor

**合约来源**：`GenericLogic.calculateUserAccountData()` ([L65-L182](https://github.com/aave-dao/aave-v3-origin/blob/96c2e96/src/contracts/protocol/libraries/logic/GenericLogic.sol#L65-L182))

\[
\text{HF}_{V3} = \frac{\sum_{i} (\text{collateralValue}_i \times \text{liquidationThreshold}_i)}{\text{totalDebt}}
\]

其中：
- `collateralValue_i` = 用户在 asset *i* 的抵押品价值（base currency）
- `liquidationThreshold_i` = asset *i* 的清算阈值（BPS，如 8000 = 80%）
- `totalDebt` = 用户总债务（base currency）

**清算条件**：`HF < 1.0`

### V3 最大可借量

\[
\text{maxBorrow}_{V3} = \sum_{i} (\text{collateralValue}_i \times \text{ltv}_i) - \text{totalDebt}
\]

其中 `ltv_i`（BPS，如 7500 = 75%）始终 ≤ `liquidationThreshold_i`。

### V4 Health Factor

**合约来源**：`Spoke._processUserAccountData()` ([L706-L813](https://github.com/aave/aave-v4/blob/ef3c7ad7/src/spoke/Spoke.sol#L706-L813))

\[
\text{HF}_{V4} = \frac{\sum_{i} (\text{collateralFactor}_i \times \text{collateralValue}_i)}{\text{totalDebt}}
\]

其中：
- `collateralFactor_i` = asset *i* 的抵押因子（BPS，来自 `DynamicReserveConfig`）
- `collateralValue_i` = 用户在 reserve *i* 的抵押品价值
- `totalDebt` = 用户总债务（RAY precision）

**清算条件**：`HF < 1.0`（`HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18`）

### V4 最大可借量

\[
\text{maxBorrow}_{V4} = \sum_{i} (\text{collateralFactor}_i \times \text{collateralValue}_i) - \text{totalDebt}
\]

**关键区别**：V4 的 maxBorrow 和 HF 使用**同一个参数** `collateralFactor`。借到上限时 `HF = 1.0`，无安全缓冲带。

### 公式结构对比

| 公式 | V3 使用的参数 | V4 使用的参数 |
|------|-------------|-------------|
| maxBorrow | `ltv` | `collateralFactor` |
| Health Factor | `liquidationThreshold` | `collateralFactor` |

V4 将 V3 的两个独立参数合并为一个。前端若统一公式，可：
- `maxBorrow = Σ(supplyUsd × ltv) - totalBorrow`
- `HF = Σ(supplyUsd × liquidationThreshold) / totalBorrow`

V3 时两值不同，V4 时两值相同（`ltv = liquidationThreshold = collateralFactor`），逻辑自然兼容。

---

## 三、avgCollateralFactor vs Risk Premium

`_processUserAccountData` 函数在一次遍历中**并行计算两个独立的聚合值**，它们使用不同的合约参数和不同的算法：

### avgCollateralFactor — 加权平均

**用途**：Health Factor 计算 + 最大可借量

**算法**：简单加权平均

\[
\text{avgCollateralFactor} = \frac{\sum_{i} (\text{collateralFactor}_i \times \text{collateralValue}_i)}{\text{totalCollateralValue}}
\]

**合约源码** (`Spoke.sol:748`)：
```solidity
accountData.avgCollateralFactor += collateralFactor * userCollateralValue;
// 循环后:
accountData.avgCollateralFactor = avgCollateralFactor.bpsToWad() / totalCollateralValue;
```

**HF 在除法之前计算**（L773），此时 `avgCollateralFactor` 仍是加权总和：
```solidity
accountData.healthFactor = Math.mulDiv(
    accountData.avgCollateralFactor.bpsToWad(),  // 仍是 Σ(cf × cv)，未除以 totalCollateral
    WadRayMath.RAY,
    accountData.totalDebtValueRay,
    Math.Rounding.Floor
);
```

### Risk Premium — 贪心分配

**用途**：等效借款利率调整

\[
R_{\text{eff}} \approx R_{\text{borrow}} \times \left(1 + \frac{\text{RP}}{10000}\right)
\]

**算法**：贪心分配（从最低风险抵押品开始"消耗"债务）

\[
\text{RP} = \frac{\sum_{j \in \text{sorted}} (\text{allocatedValue}_j \times \text{collateralRisk}_j)}{\text{coveredDebt}}
\]

**合约源码** (`Spoke.sol:788-810`)：
```solidity
// sort by collateral risk in ASC, collateral value in DESC
collateralInfo.sortByKey();

uint256 debtValueLeftToCover = totalDebtValue;
for (uint256 index = 0; index < collateralInfo.length(); ++index) {
    if (debtValueLeftToCover == 0) break;
    (uint256 collateralRisk, uint256 userCollateralValue) = collateralInfo.uncheckedAt(index);
    userCollateralValue = userCollateralValue.min(debtValueLeftToCover);
    accountData.riskPremium += userCollateralValue * collateralRisk;
    debtValueLeftToCover -= userCollateralValue;
}
accountData.riskPremium = riskPremium.divUp(totalDebtValue - debtValueLeftToCover);
```

**贪心排序规则** (`KeyValueList.sortByKey()`)：
- 主键：`collateralRisk` **升序**（最低风险 = 最优 = 排最前）
- 次键：`collateralValue` **降序**（同风险时大额抵押品优先）

### 两者关系

| 维度 | avgCollateralFactor | Risk Premium |
|------|---------------------|---------------|
| **合约参数** | `collateralFactor` (uint16, BPS, `DynamicReserveConfig`) | `collateralRisk` (uint24, BPS, `ReserveConfig`) |
| **参数层级** | per reserve per key（版本化动态配置） | per reserve（静态配置） |
| **算法** | 加权平均（所有抵押品按价值等比例参与） | 贪心分配（按风险升序逐个消耗债务） |
| **影响范围** | 借款能力 + 清算（HF） | 等效借款利率（利息溢价） |
| **V3 有无** | 有（分为 avgLtv + avgLiquidationThreshold） | 无 |
| **共同输入** | `collateralValue_i`（用户每个 reserve 的抵押品价值） | 同左 |
| **独立性** | 不依赖 RP | 不依赖 avgCF |

**核心结论**：两者是同一函数内的并行独立计算。`avgCollateralFactor` 决定"能借多少 + 何时被清算"，`riskPremium` 决定"借了之后利率加多少"。它们共享用户仓位输入，但使用不同的合约参数和不同的数学算法。

### 为什么 Risk Premium 用贪心而非加权平均？

V4 的设计意图：**利率溢价应反映实际覆盖债务的抵押品风险，而非全部抵押品的平均风险**。

示例：用户有 $100 债务，抵押品 A（risk=100, $80）和 B（risk=500, $200）。

- **加权平均**（如果用 avgCF 的方式）：`RP = (80×100 + 200×500) / 280 = 371 BPS`
- **贪心分配**：先消耗 A 的 $80（risk=100），再消耗 B 的 $20（risk=500）
  - `RP = (80×100 + 20×500) / 100 = 180 BPS`

贪心算法给出**更低的 RP**，因为最低风险的抵押品优先覆盖债务，只有溢出部分才按更高风险计算。这降低了借款人的等效利率，激励用户提供优质抵押品。

---

## 四、AAV-1222 API 映射策略

### 设计决策

后端 `GET /markets` API 需要在每个 reserve 中增加 `ltv` 和 `liquidationThreshold` 字段。V3 和 V4 的数据来源和映射策略：

| API 字段 | V3 来源 | V4 来源 | V4 映射 | 单位 |
|----------|---------|---------|---------|------|
| `ltv` | `supplyInfo.maxLTV.value` (decimal → ×100) | `settings.collateralFactor.value` (decimal → ×100) | `collateralFactor` → `ltv` | percent (80 = 80%) |
| `liquidationThreshold` | `supplyInfo.liquidationThreshold.value` (decimal → ×100) | 无独立字段 | `collateralFactor` → `liquidationThreshold`（同值） | percent (80 = 80%) |

### 精度约定

遵循 `units.ts` 的 `FIELD_UNITS` 注册表：
- `ltv` 和 `liquidationThreshold` 注册为 `'percent'`（in-memory 已是 percent number，serializer passthrough）
- V3 SDK 的 `.value` 是 decimal fraction（如 `0.8`），fetcher 用 `percentValueToPercent()` 转为 percent（`80`）
- V4 SDK 的 `.value` 同理

### V3 数据来源验证

V3 GraphQL SDK (`@aave/client` `markets()`) 的 `supplyReserves[]` 中，每个 reserve 有 `supplyInfo` 对象。`buildV3BaseDataset()` 已从 `supplyInfo` 读取 `apy` 和 `supplyCap`，`maxLTV` 和 `liquidationThreshold` 在同一对象中可用。

### V4 数据来源验证

V4 GraphQL SDK (`@aave/client-v4` `reserves()`) 的每个 reserve 有 `settings` 对象。`v4-fetcher.ts` 已从 `r.settings` 读取 `collateralRisk`、`supplyCap`、`borrowCap`。`collateralFactor` 在同一 `settings` 对象中可用（PercentNumber 类型）。

### 前端公式统一

AAV-756 实现 Portfolio Simulation 时，可使用统一公式：

\[
\text{maxBorrowUsd} = \sum_{i} (\text{supplyUsd}_i \times \text{ltv}_i / 100) - \text{totalBorrowUsd}
\]

\[
\text{HF} = \frac{\sum_{i} (\text{supplyUsd}_i \times \text{liquidationThreshold}_i / 100)}{\text{totalBorrowUsd}}
\]

- V3 reserve：`ltv` < `liquidationThreshold`（有安全缓冲）
- V4 reserve：`ltv` = `liquidationThreshold` = `collateralFactor`（无缓冲）
- 两个公式对 V3 和 V4 都成立，前端无需区分版本

### Net Effective APY（AAV-756 子目标）

有了 LTV 约束后，Net Effective APY 才有物理意义：
- 用户的实际借款能力受 `Σ(supplyUsd × ltv)` 约束
- V4 用户的等效借款利率受 `riskPremium` 调整（已有 `collateralRisk` 字段支撑）
- Net Effective APY = Supply APY - Borrow APY × (实际借款 / 实际抵押 × ltv)

---

## 五、V4 清算机制详解

### 三层 HF 概念

| 概念 | 值 | 粒度 | 谁设 | 合约位置 |
|------|-----|------|------|---------|
| `HEALTH_FACTOR_LIQUIDATION_THRESHOLD` | 硬编码 `1e18`（= 1.0） | 全局常量 | 不可改 | `LiquidationLogic.sol:182` |
| `targetHealthFactor` | 治理配置，必须 ≥ 1.0 | **per-Spoke** | 治理 `updateLiquidationConfig()` | `Spoke._liquidationConfig` |
| 用户实际 HF | 运行时计算 | **per-User** | 合约自动算 | `_processUserAccountData()` |

**关键澄清**：`targetHealthFactor` 不是用户级别的——同一 Spoke 上所有用户共享同一个 `targetHealthFactor`。但不同 Spoke 可以有不同的值。

### 借入约束 vs 清算目标（合约源码分析，V4 overview 未明确区分）

> **⚠️ 此节内容为合约源码分析结论，V4 `docs/overview.md` 未明确区分这两个约束。**

**借入约束**（`Spoke.sol:691-693`）：
```solidity
require(
    accountData.healthFactor >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
    HealthFactorBelowThreshold()
);
```
检查的是 `HF >= 1.0`（`HEALTH_FACTOR_LIQUIDATION_THRESHOLD`），**不是** `HF >= targetHealthFactor`。

**清算触发**（`LiquidationLogic.sol:544-546`）：
```solidity
require(
    params.healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
    ISpoke.HealthFactorNotBelowThreshold()
);
```
检查的也是 `HF < 1.0`。

**清算目标**（`LiquidationLogic.sol:795-813`）：
`targetHealthFactor` 只在 `_calculateDebtToTargetHealthFactor()` 中使用，计算"需要还多少债才能让用户 HF 恢复到 target"。

**结论**：用户**可以**借到 `collateralFactor` 上限（HF=1.0），即使 `targetHealthFactor=1.24`。`targetHealthFactor` 不是借入约束，只影响清算时的还款量计算。

### 链上实测：各 Spoke 的 targetHealthFactor

> 数据获取时间：2026-08-01，通过 `cast call` 查询各 Spoke 合约的 `getLiquidationConfig()`。

| Spoke 名称 | 链 | targetHealthFactor | healthFactorForMaxBonus | liquidationBonusFactor |
|------------|-----|-------------------|------------------------|----------------------|
| Main | Ethereum | 1.24 | 0.90 | 9000 (90%) |
| Bluechip | Ethereum | 1.174 | 0.90 | 9000 (90%) |
| Gold | Ethereum | 1.307 | 0.90 | 9000 (90%) |
| Lombard | Ethereum | 1.061 | 0.99 | 10000 (100%) |
| Forex | Ethereum | 1.044 | 0.99 | 10000 (100%) |
| Ethena Ecosystem | Ethereum | 1.033 | 0.99 | 10000 (100%) |
| USDG Pendle | Ethereum | 1.027 | 0.99 | 10000 (100%) |
| Ethena Correlated | Ethereum | 1.027 | 0.99 | 10000 (100%) |
| Kelp | Ethereum | 1.021 | 0.99 | 10000 (100%) |
| Etherfi | Ethereum | 1.019 | 0.99 | 10000 (100%) |
| Lido | Ethereum | 1.013 | 0.99 | 10000 (100%) |

**观察**：各 Spoke 差异显著（1.013 ~ 1.307）。高风险 Spoke（Gold、Main）的 targetHealthFactor 更高，给清算后更大的安全余量；低风险 LST Spoke（Lido、Etherfi、Kelp）接近 1.0。

两组配置模式：
- **高风险组**（Main、Bluechip、Gold）：`healthFactorForMaxBonus=0.90`，`liquidationBonusFactor=9000`（90%）
- **低风险组**（LST + Ethena + Forex）：`healthFactorForMaxBonus=0.99`，`liquidationBonusFactor=10000`（100%）

### 链上实测：Risk Premium 当前状态

> ⚠️ **V4 overview.md 描述了 Risk Premium 机制，但未提及链上当前是否已激活。**

查询 `data/debug/v4-raw-sdk-response.json` 中 78 个 V4 reserve 的 `collateralRisk` 值：

- `collateralRisk = 0`：78 个（全部）
- `collateralRisk > 0`：0 个

**结论**：Risk Premium 机制已在合约层部署，但治理**尚未激活**。所有资产当前都被视为"无风险"（ETH 级别），`RP = 0`，等效借款利率 = 基础 drawnRate，无额外溢价。

### Risk Premium 的激活机制

> ⚠️ **V4 overview.md 描述了 `collateralRisk` 和 `riskPremiumThreshold`，但未说明 RP 没有"全局开关"。**

Risk Premium **没有全局开关**，激活方式是**两层 per-reserve/per-spoke 配置**：

**第一层：`collateralRisk`（per-Reserve，在 Spoke 端配置）**
- 合约位置：`Reserve.collateralRisk` (uint24, BPS)，属于 `ReserveConfig`
- 设置方式：治理通过 `SpokeConfigurator.addReserve()` 或 `updateReserveConfig()` 逐个 reserve 设置
- 作用：作为 RP 贪心算法的输入——如果所有 reserve 的 `collateralRisk = 0`，贪心算法输出的 `RP = 0`，不产生任何 premium shares
- **这是"RP 未激活"的根本原因**：78 个 reserve 全部 `collateralRisk = 0`

**第二层：`riskPremiumThreshold`（per-Asset per-Spoke，在 Hub 端配置）**
- 合约位置：`SpokeData.riskPremiumThreshold` (uint24, BPS)，属于 Hub 层 `SpokeConfig`
- 设置方式：治理通过 `HubConfigurator.updateSpokeRiskPremiumThreshold(hub, assetId, spoke, threshold)` 逐个设置
- 作用：**上限约束**——限制该 Spoke 对该 asset 的 `premiumShares / drawnShares` 比率上限。如果 `= MAX_RISK_PREMIUM_THRESHOLD` 则无限制。
- 这不是开关，是 cap。即使设了阈值，如果 `collateralRisk = 0` → `RP = 0` → `premiumShares = 0` → 阈值不会触发。

**完整的 RP 激活条件**：
1. Reserve 设置 `collateralRisk > 0`（Spoke 端）
2. SpokeData 设置 `riskPremiumThreshold`（Hub 端，可选——默认 0 表示无限制或需要治理设值）
3. 用户在该 Spoke 有多资产抵押仓位（触发贪心算法计算）

当前链上状态：第 1 步未完成（全部 `collateralRisk = 0`），所以 RP = 0。

### V4 清算 vs V3 清算

| 维度 | V3 | V4 |
|------|-----|-----|
| 清算量 | 固定 close factor 50%（HF<0.95 时 100%） | 动态：计算使 HF 恢复到 `targetHealthFactor` 所需的债务量 |
| 清算奖金 | 固定值（如 5%） | Dutch auction 变量：HF 越低 → 奖金越大 → 清算人越积极 |
| Dust 处理 | 剩余 < 阈值时 revert | 动态调大 maxRepay 允许全部还清 |
| 清算后 HF | 不保证恢复到安全水平 | 恢复到 `targetHealthFactor`（如 1.24） |

V4 清算奖金公式（`LiquidationLogic.sol:312-333`）：
```
if (HF ≤ healthFactorForMaxBonus):
    bonus = maxLiquidationBonus          // 最低 HF → 最高奖金
else:
    bonus = minBonus + (maxBonus - minBonus) × (1 - HF) / (1 - healthFactorForMaxBonus)
    // 线性插值
``

---

## 六、Spoke 隔离 vs V3 Market/Pool 隔离

### Spoke = V3 Market

| 概念 | V3 | V4 |
|------|-----|-----|
| 用户交互入口 | Pool | Spoke |
| 项目术语 | Market | Market（`CONTEXT.md` 定义：V4 的 per-chain 部署单元，等价于 Market） |
| HF 计算范围 | per-Pool | per-Spoke |

V3 用户在不同 Pool（Market）也有不同的 HF——每个 Pool 的 `getUserAccountData(user)` 独立计算。V4 的 Spoke 隔离机制与 V3 的 Pool 隔离**架构等价**。

### 用户在不同 Spoke 之间独立的维度

> V4 `docs/overview.md` 描述了 Spoke 隔离，但未系统列举哪些用户数据是 per-Spoke 独立的。

以下用户数据**按 Spoke 完全隔离**（来自 `SpokeStorage.sol` storage 布局）：

| 独立维度 | 合约 storage | 说明 |
|---------|-------------|------|
| **Health Factor** | `_positionStatus[user]` + `_userPositions[user][reserveId]` | 每个用户在每个 Spoke 有独立的 HF |
| **Risk Premium** | `_positionStatus[user].riskPremium` (uint24) | 每个用户在每个 Spoke 有独立的 RP |
| **仓位数据** | `_userPositions[user][reserveId]` (UserPosition) | suppliedShares, drawnShares, premiumShares, premiumOffsetRay — 全部 per-Spoke |
| **Dynamic Config 快照** | `_userPositions[user][reserveId].dynamicConfigKey` | 每个用户在每个 Spoke 的每个 reserve 独立绑定 config 版本 |
| **Collateral/Borrow bitmap** | `_positionStatus[user].map` | 哪些 reserve 被设为抵押/借款 — per-Spoke |
| **Reserve 数量限制** | `MAX_USER_RESERVES_LIMIT` | per-Spoke 限制（不同 Spoke 可设不同上限） |
| **LiquidationConfig** | `_liquidationConfig` | targetHealthFactor 等 — per-Spoke，同 Spoke 所有用户共享 |

**跨 Spoke 不共享的**：HF、RP、仓位、dynamic config 快照、collateral bitmap。
**跨 Spoke 共享的**（Hub 层）：利率（drawnRate）、流动性、addCap/drawCap、deficit 聚合。

---

## 七、V4 为什么去掉 V3 的缓冲带（设计分析）

> **⚠️ 此节为讨论分析结论，V4 `docs/overview.md` 未直接论述"为什么不保留 ltv/lt 分离"。**

V3 的 ltv/lt 缓冲带解决两个问题，V4 分别用不同机制替代：

### 问题一：治理变更不伤害已有仓位

- **V3 方案**：治理降 ltv（如 80%→70%），已有仓位 maxBorrow 降低，但 liquidationThreshold 不变 → 不会被清算。代价：资本效率低（所有人只能借到 ltv，而非 lt）。
- **V4 方案**：Dynamic Risk Configuration——治理创建新 config 降低 collateralFactor，**只对新仓位生效**，老仓位保持旧 `dynamicConfigKey` 快照不变。好处：初始 collateralFactor 可设到 V3 的 liquidationThreshold 水平，用户能多借。

### 问题二：用户日常安全

- **V3 方案**：静态 5% 缓冲带。但闪崩时 5% 不够——价格跌 6% 用户照样被清算。缓冲带给人**虚假的安全感**。
- **V4 方案**：不假装提供缓冲。用更好的清算机制替代：
  - `targetHealthFactor`（如 1.24）：清算后恢复到安全线以上，不会被反复清算到归零
  - Dutch auction 变量奖金：HF 越低 → 奖金越大 → 清算人越积极 → 更早被清算 → 坏账更少
  - `DUST_LIQUIDATION_THRESHOLD`：防止清算后残留 dust 仓位

### 设计权衡

| 维度 | V3 缓冲带 | V4 无缓冲 |
|------|----------|----------|
| 资本效率 | 低（5% 被锁死借不出来） | 高（用户可借到 collateralFactor 上限） |
| 日常安全 | 假缓冲（闪崩穿透） | 用户自管理（无假象） |
| 治理保护 | ltv/lt 分离 | Dynamic Config 版本化 |
| 清算质量 | 固定 50% close factor | 精准恢复到 targetHealthFactor |
| 清算激励 | 固定奖金 | 变量奖金（Dutch auction） |

**核心设计哲学**：V4 认为"5% 静态缓冲带"既不够安全（闪崩照样穿透），又浪费资本效率。不如去掉缓冲，给用户更高借款能力，用 Dynamic Config + 精准清算来处理风险。