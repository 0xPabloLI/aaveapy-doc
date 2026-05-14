# Aave Deficit 分析手册（V3 + V4）

---

# Part 1：Aave V3 Deficit 机制

## 1. Deficit 定义

Deficit（坏账）是清算过程中产生的资金缺口：当抵押品价值不足以偿还债务时，差额计入 deficit。

| 属性 | 说明 |
|------|------|
| 存储 | `reserve.deficit`（per reserve，单层存储，无 Hub/Spoke 双层） |
| 单位 | underlying token units |
| 数据获取 | `Pool.getReserveData(asset)` → `deficit` 字段；或 `UiPoolDataProviderV3.getReservesHumanized()` |
| fallback | RPC 失败时默认 `"0"` |

## 2. 产生机制

清算时，被清算用户的 debt token 被销毁，但 collateral token 不够覆盖债务：

```
用户抵押品价值 < 用户债务
→ 清算后差额 = 债务 - 实际收回抵押品价值
→ 差额计入 reserve.deficit
```

常见触发场景：
- 价格剧烈波动导致抵押品价值骤降
- 清算延迟导致抵押品进一步贬值
- 闪电崩盘中清算机器人无法及时执行

## 3. 对利率的影响

### 3.1 核心公式

Deficit **只出现在 `supplyUsageRatio` 的分母中**，压低存款利率：

**Borrow Rate 的利用率（不受 deficit 影响）：**

$$borrowUsageRatio = \frac{totalDebt}{totalDebt + availableLiquidity}$$

**Supply Rate 的利用率（受 deficit 影响）：**

$$supplyUsageRatio = \frac{totalDebt}{totalDebt + availableLiquidity + deficit}$$

**Supply Rate 换算公式：**

$$Supply\ Rate = BorrowRate \times supplyUsageRatio \times \left(1 - \frac{reserveFactor}{10000}\right)$$

### 3.2 影响效果

| 场景 | 效果 |
|------|------|
| deficit = 0 | `supplyUsageRatio = borrowUsageRatio`，两者相等 |
| deficit > 0 | 分母变大 → `supplyUsageRatio` 变小 → Supply Rate 降低 |
| deficit 极大 | `supplyUsageRatio → 0`，存款利率趋近于零 |

**关键**：deficit **只惩罚存款人**，borrow rate 完全不受影响（借款人该付多少还是付多少）。

### 3.3 合约源码溯源

参数组装（`ReserveLogic.sol`）：

```solidity
(uint256 nextLiquidityRate, uint256 nextVariableRate) =
    IReserveInterestRateStrategy(interestRateStrategyAddress)
    .calculateInterestRates(
        DataTypes.CalculateInterestRatesParams({
            unbacked: reserve.deficit,        // ← deficit 作为 unbacked 传入
            liquidityAdded: liquidityAdded,
            liquidityTaken: liquidityTaken,
            totalDebt: totalVariableDebt,
            reserveFactor: reserveCache.reserveFactor,
            reserve: reserveAddress,
            usingVirtualBalance: true,
            virtualUnderlyingBalance: reserve.virtualUnderlyingBalance
        })
    );
```

利率计算（`DefaultReserveInterestRateStrategyV2.sol`）：

```solidity
vars.availableLiquidity =
    params.virtualUnderlyingBalance +
    params.liquidityAdded -
    params.liquidityTaken;

vars.availableLiquidityPlusDebt = vars.availableLiquidity + params.totalDebt;

// Borrow rate 利用率（无 deficit）
vars.borrowUsageRatio = params.totalDebt.rayDiv(vars.availableLiquidityPlusDebt);

// Supply rate 利用率（含 deficit）
vars.supplyUsageRatio = params.totalDebt.rayDiv(
    vars.availableLiquidityPlusDebt + params.unbacked
);

// 换算公式
vars.currentLiquidityRate = vars
    .currentVariableBorrowRate
    .rayMul(vars.supplyUsageRatio)
    .percentMul(PercentageMath.PERCENTAGE_FACTOR - params.reserveFactor);
```

## 4. 数值示例

| 场景 | deficit | supplyUsageRatio | Supply Rate | 相对无坏账 |
|------|---------|-----------------|------------|-----------|
| 无坏账 | 0 | 800/1000 = 0.800 | 3.60% | 基准 |
| 有坏账 | 100 | 800/1100 = 0.727 | 3.27% | -9.2% |
| 严重坏账 | 400 | 800/1400 = 0.571 | 2.57% | -28.6% |

（假设 Borrow Rate = 5%，reserveFactor = 10%，totalDebt = 800，availableLiquidity = 200）

## 5. 合约查询路径

| 合约 | 函数 | 获取内容 |
|------|------|----------|
| `Pool` | `getReserveData(asset)` | `deficit`, `currentLiquidityRate`, `currentVariableBorrowRate` |
| `UiPoolDataProviderV3` | `getReservesData(provider)` | 批量获取所有资产数据（含 deficit） |
| `AaveProtocolDataProvider` | `getReserveData(asset)` | `liquidityRate`, `variableBorrowRate` |

## 6. V3 vs V4 Deficit 对比速查

| 概念 | Aave V3 | Aave V4 |
|------|---------|---------|
| 存储层级 | 单层：`reserve.deficit`（per reserve） | 双层：`Asset.deficitRay`（Hub 聚合）+ `SpokeData.deficitRay`（per spoke） |
| 不变量 | 无 | `Asset.deficitRay = Σ SpokeData.deficitRay` |
| 对 Supply APY 影响 | 仅膨胀分母（supplyUsageRatio） | 双重打击：分子减小（drawShares↓）+ 分母膨胀 |
| 对 Borrow APY 影响 | 不影响 | 不影响（策略参数虽传入但被 `/* deficit */` 注释忽略） |
| 产生 | 清算后资不抵债 → 计入 reserve.deficit | `reportDeficit()` → Hub 双层级同步递增 |
| 消除 | 无原生机制（需治理处理） | `eliminateDeficit()` → addedShares 销毁 + deficit 双层级递减 |
| 跨 spoke 消除 | 不适用 | 支持（caller spoke 和 covered spoke 可不同） |

---

# Part 2：Aave V4 Hub & Spoke 参数与查询手册

---

## 速查：API 字段 Hub/Spoke 归属分类

以下为前端/API 层常见字段列表，标注每个字段属于 **Hub 共享**（同一 Hub 同一 Asset 下所有 Spoke 共享）还是 **Spoke 独有**（每个 Spoke 各自独立），以及其在本文档中的对应参数。

| 字段 | 归属 | 对应文档参数 | 说明 |
|------|------|-------------|------|
| `reserveId` | Spoke 独有 | §2.1 `getReserve(reserveId)` | Spoke 内 Reserve 的唯一标识，每个 Spoke 各自编号 |
| `marketName` | 外部元数据 | — | 市场名称（CORE/PLUS/PRIME），由 Hub 决定，但通常作为前端标签 |
| `chainName` | 外部元数据 | — | 链名称，部署环境元数据 |
| `chainId` | 外部元数据 | — | 链 ID，部署环境元数据 |
| `tokenName` | 外部元数据 | — | Token 名称，链下元数据 |
| `tokenSymbol` | 外部元数据 | — | Token 符号，链下元数据 |
| `tokenAddress` | Hub 共享 | §1.1 `underlying` | 底层 token 地址，同一 Asset 所有 Spoke 共享 |
| `aTokenAddress` | V4 不存在（null） | §2.1 TokenizationSpoke | V3 独立 aToken 合约；V4 由 TokenizationSpoke（ERC-4626 vault）的 share token 等价替代，SDK 不暴露 |
| `vTokenAddress` | V4 不存在（null） | — | V3 独立 vToken 合约；V4 无独立债务 token，借款通过 Spoke 内部 drawnShares 记账 |
| `aaveProReserveId` | Spoke 独有 | — | Aave Pro Reserve ID，Spoke 级别标识 |
| `hubId` | Hub 共享 | §1.3 | Hub 标识，同一 Hub 下所有 Spoke 共享 |
| `hubName` | Hub 共享 | — | Hub 名称（CORE_HUB/PLUS_HUB/PRIME_HUB） |
| `hubAddress` | Hub 共享 | §4.1 | Hub 合约地址，同一 Hub 下所有 Spoke 共享 |
| `spokeId` | Spoke 独有 | §1.2 `spoke` | Spoke 标识，每个 Spoke 各自独立 |
| `spokeName` | Spoke 独有 | §4.2 | Spoke 名称（MAIN_SPOKE 等），每个 Spoke 各自独立 |
| `spokeAddress` | Spoke 独有 | §4.2 | Spoke 合约地址，每个 Spoke 各自独立 |
| `supplyApy` | Hub 共享 | §1.1 `drawnRate` + supply share price | 供应 APY 由 Hub 共享的利率和 share price 决定 |
| `borrowApy` | Hub 共享 | §1.1 `drawnRate` | 借款 APY 由 Hub 共享的 drawnRate 决定 |
| `tokenPrice` | Spoke 独有 | §2.3 `ORACLE()` | 价格由 Spoke 的 Oracle 提供，各 Spoke 可不同 |
| `reserveSizeUsd` | 双层存储 | §1.1 `liquidity` / §1.2 `addedShares` | 总量在 Hub，各 Spoke 份额在 SpokeData |
| `supplyCapUsd` | Spoke 独有 | §1.2 `addCap` | 供应上限，每个 Spoke 各自独立配置 |
| `borrowCapUsd` | Spoke 独有 | §1.2 `drawCap` | 借款上限，每个 Spoke 各自独立配置 |
| `utilizationPct` | Hub 共享 | §1.1 `liquidity`, `drawnShares`, `drawnIndex` | 利用率由 Hub 层聚合数据计算，所有 Spoke 共享 |
| `supplyDisabled` | Spoke 独有 | §1.2 `active` / §2.1 `paused`/`frozen` | 供应是否禁用，由 Spoke 的 active/halted/paused/frozen 决定 |
| `borrowDisabled` | Spoke 独有 | §1.2 `active` / §2.1 `borrowable`/`paused`/`frozen` | 借款是否禁用，由 Spoke 的 active/halted/borrowable/paused/frozen 决定 |
| `isFrozen` | Spoke 独有 | §2.1 `frozen` | 冻结状态，Spoke Reserve 级别配置 |
| `isPaused` | Spoke 独有 | §2.1 `paused` / §1.2 `halted` | 暂停状态，Spoke 级别配置 |
| `decimals` | Hub 共享 | §1.1 `decimals` | 精度，同一 Asset 所有 Spoke 共享 |
| `availableLiquidity` | Hub 共享 | §1.1 `liquidity` | 总可用流动性，Hub 层聚合值 |
| `totalVariableDebt` | Hub 共享 | §1.1 `drawnShares` × `drawnIndex` | 总可变债务，Hub 层聚合值 |
| `deficit` | 双层存储 | §1.1 `deficitRay` / §1.2 `deficitRay` | 总 deficit 在 Hub，各 Spoke 的 deficit 在 SpokeData |
| `reserveFactor` | Hub 共享 | §1.1 `liquidityFee` | 协议费率，Hub Asset 层配置，所有 Spoke 共享 |
| `variableRateSlope1` | Hub 共享 | §1.1 `irStrategy` | 利率曲线参数1，由 Hub 的 irStrategy 决定 |
| `variableRateSlope2` | Hub 共享 | §1.1 `irStrategy` | 利率曲线参数2，由 Hub 的 irStrategy 决定 |
| `optimalUsageRate` | Hub 共享 | §1.1 `irStrategy` | 最优利用率，由 Hub 的 irStrategy 决定 |
| `baseVariableBorrowRate` | Hub 共享 | §1.1 `irStrategy` | 基础借款利率，由 Hub 的 irStrategy 决定 |
| `supplyIncentives` | Spoke 独有 | — | 供应激励，每个 Spoke 各自配置 |
| `borrowIncentives` | Spoke 独有 | — | 借款激励，每个 Spoke 各自配置 |
| `meritSupplys` | Spoke 独有 | — | Merit 供应奖励，Spoke 级别 |
| `meritBorrows` | Spoke 独有 | — | Merit 借款奖励，Spoke 级别 |
| `merklSupplys` | Spoke 独有 | — | Merkl 供应奖励，Spoke 级别 |
| `merklBorrows` | Spoke 独有 | — | Merkl 借款奖励，Spoke 级别 |
| `merklHolds` | Spoke 独有 | — | Merkl 持有奖励，Spoke 级别 |
| `brevisSupplys` | Spoke 独有 | — | Brevis 供应奖励，Spoke 级别 |
| `brevisBorrows` | Spoke 独有 | — | Brevis 借款奖励，Spoke 级别 |

**归属统计**：
- **Hub 共享**：15 个 — `tokenAddress`, `hubId`, `hubName`, `hubAddress`, `supplyApy`, `borrowApy`, `utilizationPct`, `decimals`, `availableLiquidity`, `totalVariableDebt`, `reserveFactor`, `variableRateSlope1`, `variableRateSlope2`, `optimalUsageRate`, `baseVariableBorrowRate`
- **Spoke 独有**：21 个 — `reserveId`, `aaveProReserveId`, `spokeId`, `spokeName`, `spokeAddress`, `tokenPrice`, `supplyCapUsd`, `borrowCapUsd`, `supplyDisabled`, `borrowDisabled`, `isFrozen`, `isPaused`, `supplyIncentives`, `borrowIncentives`, `meritSupplys`, `meritBorrows`, `merklSupplys`, `merklBorrows`, `merklHolds`, `brevisSupplys`, `brevisBorrows`
- **V3 仅有 / V4 为 null**：2 个 — `aTokenAddress`（V4 由 TokenizationSpoke share token 等价替代）, `vTokenAddress`（V4 无独立债务 token）
- **双层存储**：2 个 — `reserveSizeUsd`, `deficit`
- **外部元数据**：5 个 — `marketName`, `chainName`, `chainId`, `tokenName`, `tokenSymbol`

---

## 速查：supplySize 与 borrowSize 对应参数

> **supplySize**（总供应量）和 **borrowSize**（总借款量）在 Aave V4 的 Hub/Spoke 双层架构中，分别对应以下合约参数：

### supplySize（总供应量）

| 层级 | 参数 | 类型 | 查询方法 | 说明 |
|------|------|------|----------|------|
| **Hub Asset 层** | `totalAddedAssets` | uint120 | `getAddedAssets(assetId)` | **所有 Spoke 的总供应资产量**（聚合值，Hub 共享） |
| Hub Asset 层 | `addedShares` | uint120 | `getAddedShares(assetId)` | 所有 Spoke 的总供应 shares（Hub 共享） |
| Hub Asset 层 | `liquidity` | uint120 | `getAssetLiquidity(assetId)` | 总可用流动性（Hub 共享） |
| **SpokeData 层** | 该 spoke 的供应资产量 | uint120 | `getSpokeAddedAssets(assetId, spoke)` | **单个 Spoke 的供应资产量**（Spoke 独有） |
| SpokeData 层 | `addedShares` | uint120 | `getSpokeAddedShares(assetId, spoke)` | 单个 Spoke 的供应 shares（Spoke 独有） |
| **Spoke Reserve 层** | 总供应资产量 | uint120 | `getReserveSuppliedAssets(reserveId)` | **Spoke 内 Reserve 的总供应资产量**（Spoke 独有） |
| Spoke Reserve 层 | 总供应 shares | uint120 | `getReserveSuppliedShares(reserveId)` | Spoke 内 Reserve 的总供应 shares（Spoke 独有） |

**计算关系**：
- Hub `totalAddedAssets` = Σ(各 Spoke `getSpokeAddedAssets`)
- Hub `addedShares` = Σ(各 SpokeData `addedShares`)
- `totalAddedAssets` = `liquidity + swept + aggregatedOwed - realizedFees - unrealizedFees`
- 单个 Spoke 供应资产量 = `addedShares × (totalAddedAssets / totalAddedShares)`

### borrowSize（总借款量）

| 层级 | 参数 | 类型 | 查询方法 | 说明 |
|------|------|------|----------|------|
| **Hub Asset 层** | `drawnOwed` | uint120 | `getAssetOwed(assetId)` → drawn | **所有 Spoke 的总 drawn 债务**（聚合值，Hub 共享） |
| Hub Asset 层 | `drawnShares` | uint120 | `getAssetDrawnShares(assetId)` | 所有 Spoke 的总借款 shares（Hub 共享） |
| Hub Asset 层 | `drawnIndex` | uint120 | `getAssetDrawnIndex(assetId)` | 债务指数（Hub 共享，所有 Spoke 共用） |
| **Hub Asset 层** | `aggregatedOwed` | uint120 | `getAssetTotalOwed(assetId)` | **总欠款 = drawn + premium + deficit**（Hub 共享） |
| **SpokeData 层** | 该 spoke 的 drawn 欠款 | uint120 | `getSpokeOwed(assetId, spoke)` → drawn | **单个 Spoke 的 drawn 债务**（Spoke 独有） |
| SpokeData 层 | `drawnShares` | uint120 | `getSpokeDrawnShares(assetId, spoke)` | 单个 Spoke 的借款 shares（Spoke 独有） |
| **SpokeData 层** | 该 spoke 的总欠款 | uint120 | `getSpokeTotalOwed(assetId, spoke)` | **单个 Spoke 的总欠款 = drawn + premium + deficit**（Spoke 独有） |
| **Spoke Reserve 层** | drawn/premium 债务 | — | `getReserveDebt(reserveId)` | **Spoke 内 Reserve 的债务**（Spoke 独有） |
| Spoke Reserve 层 | 总债务 | uint120 | `getReserveTotalDebt(reserveId)` | Spoke 内 Reserve 的总债务（Spoke 独有） |

**计算关系**：
- Hub `drawnOwed` = `drawnShares × drawnIndex / RAY`
- Hub `drawnShares` = Σ(各 SpokeData `drawnShares`)
- Hub `aggregatedOwed` = `drawnOwed + premiumOwed + deficitRay`
- 单个 Spoke drawn 债务 = `drawnShares × drawnIndex / RAY`（drawnIndex 是 Hub 共享的）

### supplySize vs borrowSize 归属对比

| | supplySize | borrowSize |
|---|-----------|-----------|
| **Hub 聚合值** | `getAddedAssets(assetId)` | `getAssetOwed(assetId)` → drawn |
| **Hub shares** | `getAddedShares(assetId)` | `getAssetDrawnShares(assetId)` |
| **Hub 指数/价格** | share price = `totalAddedAssets / addedShares` | `drawnIndex`（`getAssetDrawnIndex(assetId)`） |
| **Spoke 独有值** | `getSpokeAddedAssets(assetId, spoke)` | `getSpokeOwed(assetId, spoke)` → drawn |
| **Spoke shares** | `getSpokeAddedShares(assetId, spoke)` | `getSpokeDrawnShares(assetId, spoke)` |
| **Spoke Reserve 值** | `getReserveSuppliedAssets(reserveId)` | `getReserveDebt(reserveId)` |
| **计息模型** | Share-price model（隐式升值） | Index-based accrual（`drawnIndex` 单调递增） |
| **Hub = Σ Spoke** | `addedShares` 满足 | `drawnShares` 满足 |

---

## 一、Hub 合约参数

### 1.1 Asset 层参数（per Hub per Asset，所有 Spoke 共享）

| 参数 | 类型 | 说明 | 查询方法 | 输入参数 |
|------|------|------|----------|----------|
| `underlying` | address | 底层 token 地址 | `getAsset(assetId)` | `assetId` |
| `decimals` | uint8 | 精度 | `getAsset(assetId)` | `assetId` |
| `liquidity` | uint120 | 总可用流动性 | `getAssetLiquidity(assetId)` | `assetId` |
| `swept` | uint120 | 被再投资控制器抽走的流动性 | `getAssetSwept(assetId)` | `assetId` |
| `addedShares` | uint120 | 总供应 shares（所有 spoke 之和） | `getAddedShares(assetId)` | `assetId` |
| `drawnShares` | uint120 | 总借款 shares（所有 spoke 之和） | `getAssetDrawnShares(assetId)` | `assetId` |
| `premiumShares` | uint120 | 总溢价 shares | `getAssetPremiumData(assetId)` | `assetId` |
| `premiumOffsetRay` | int200 | 总溢价偏移 | `getAssetPremiumData(assetId)` | `assetId` |
| `drawnIndex` | uint120 | 债务指数（共享） | `getAssetDrawnIndex(assetId)` | `assetId` |
| `drawnRate` | uint96 | 利率（共享） | `getAssetDrawnRate(assetId)` | `assetId` |
| `lastUpdateTimestamp` | uint40 | 上次计息时间 | `getAsset(assetId)` | `assetId` |
| `realizedFees` | uint120 | 已实现费用 | `getAssetAccruedFees(assetId)` | `assetId` |
| `liquidityFee` | uint16 | 协议费率 (BPS) | `getAssetConfig(assetId)` | `assetId` |
| `irStrategy` | address | 利率策略合约（address-book 无独立地址，需通过此方法获取） | `getAssetConfig(assetId)` | `assetId` |
| `reinvestmentController` | address | 再投资控制器 | `getAssetConfig(assetId)` | `assetId` |
| `feeReceiver` | address | 费用接收 spoke | `getAssetConfig(assetId)` | `assetId` |
| `deficitRay` | uint200 | 总 deficit（所有 spoke 之和） | `getAssetDeficitRay(assetId)` | `assetId` |

**衍生共享值**（无独立 getter，从上述参数计算）：

| 衍生值 | 计算方式 | 可通过 getter 间接获取 |
|--------|----------|----------------------|
| `totalAddedAssets` | `liquidity + swept + aggregatedOwed - realizedFees - unrealizedFees` | `getAddedAssets(assetId)` |
| `aggregatedOwed` | `drawnShares × drawnIndex + premiumRay + deficitRay` | `getAssetTotalOwed(assetId)` |
| `drawnOwed, premiumOwed` | drawn 和 premium 各自的欠款 | `getAssetOwed(assetId)` → `(drawn, premium)` |
| `premiumRay` | 溢价欠款（RAY 精度） | `getAssetPremiumRay(assetId)` |

### 1.2 SpokeData 层参数（per Hub per Asset per Spoke）

#### 仓位数据（与 Asset 层保持 Σ 求和关系）

| 参数 | 类型 | 说明 | 查询方法 | 输入参数 |
|------|------|------|----------|----------|
| `addedShares` | uint120 | 该 spoke 的供应 shares | `getSpokeAddedShares(assetId, spoke)` | `assetId, spoke` |
| `drawnShares` | uint120 | 该 spoke 的借款 shares | `getSpokeDrawnShares(assetId, spoke)` | `assetId, spoke` |
| `premiumShares` | uint120 | 该 spoke 的溢价 shares | `getSpokePremiumData(assetId, spoke)` | `assetId, spoke` |
| `premiumOffsetRay` | int200 | 该 spoke 的溢价偏移 | `getSpokePremiumData(assetId, spoke)` | `assetId, spoke` |
| `deficitRay` | uint200 | 该 spoke 的 deficit | `getSpokeDeficitRay(assetId, spoke)` | `assetId, spoke` |

**衍生值**：

| 衍生值 | 查询方法 | 输入参数 |
|--------|----------|----------|
| 该 spoke 的供应资产量 | `getSpokeAddedAssets(assetId, spoke)` | `assetId, spoke` |
| 该 spoke 的 drawn/premium 欠款 | `getSpokeOwed(assetId, spoke)` | `assetId, spoke` |
| 该 spoke 的总欠款 | `getSpokeTotalOwed(assetId, spoke)` | `assetId, spoke` |
| 该 spoke 的溢价欠款（RAY） | `getSpokePremiumRay(assetId, spoke)` | `assetId, spoke` |

#### 配置数据（仅 SpokeData 层，无 Asset 层对应）

| 参数 | 类型 | 说明 | 查询方法 | 输入参数 |
|------|------|------|----------|----------|
| `addCap` | uint40 | 供应上限 | `getSpokeConfig(assetId, spoke)` | `assetId, spoke` |
| `drawCap` | uint40 | 借款上限 | `getSpokeConfig(assetId, spoke)` | `assetId, spoke` |
| `riskPremiumThreshold` | uint24 | 风险溢价阈值 (BPS) | `getSpokeConfig(assetId, spoke)` | `assetId, spoke` |
| `active` | bool | 是否激活 | `getSpokeConfig(assetId, spoke)` | `assetId, spoke` |
| `halted` | bool | 是否暂停 | `getSpokeConfig(assetId, spoke)` | `assetId, spoke` |

### 1.3 Hub 整体参数

| 参数 | 查询方法 | 输入参数 |
|------|----------|----------|
| asset 总数 | `getAssetCount()` | 无 |
| underlying → assetId 映射 | `getAssetId(underlying)` | `underlying` |
| underlying 是否已上架 | `isUnderlyingListed(underlying)` | `underlying` |
| spoke 总数（某 asset） | `getSpokeCount(assetId)` | `assetId` |
| spoke 是否已上架 | `isSpokeListed(assetId, spoke)` | `assetId, spoke` |
| spoke 地址（按索引） | `getSpokeAddress(assetId, index)` | `assetId, index` |

### 1.4 Hub 预览/换算方法

| 方法 | 输入参数 | 返回 | 说明 |
|------|----------|------|------|
| `previewAddByAssets(assetId, assets)` | `assetId, assets` | shares | 资产量 → 供应 shares |
| `previewAddByShares(assetId, shares)` | `assetId, shares` | assets | 供应 shares → 资产量 |
| `previewRemoveByAssets(assetId, assets)` | `assetId, assets` | shares | 资产量 → 取出 shares |
| `previewRemoveByShares(assetId, shares)` | `assetId, shares` | assets | 取出 shares → 资产量 |
| `previewDrawByAssets(assetId, assets)` | `assetId, assets` | shares | 资产量 → 借款 shares |
| `previewDrawByShares(assetId, shares)` | `assetId, shares` | assets | 借款 shares → 资产量 |
| `previewRestoreByAssets(assetId, assets)` | `assetId, assets` | shares | 资产量 → 还款 shares |
| `previewRestoreByShares(assetId, shares)` | `assetId, shares` | assets | 还款 shares → 资产量 |

---

## 二、Spoke 合约参数

### 2.1 Reserve 层参数（per Spoke per Reserve）

| 参数 | 类型 | 说明 | 查询方法 | 输入参数 |
|------|------|------|----------|----------|
| `underlying` | address | 底层 token 地址 | `getReserve(reserveId)` | `reserveId` |
| `hub` | IHubBase | 关联的 Hub 地址 | `getReserve(reserveId)` | `reserveId` |
| `assetId` | uint16 | Hub 中的 asset ID | `getReserve(reserveId)` | `reserveId` |
| `decimals` | uint8 | 精度 | `getReserve(reserveId)` | `reserveId` |
| `collateralRisk` | uint24 | 抵押风险 (BPS) | `getReserveConfig(reserveId)` | `reserveId` |
| `paused` | bool | 是否暂停 | `getReserveConfig(reserveId)` | `reserveId` |
| `frozen` | bool | 是否冻结 | `getReserveConfig(reserveId)` | `reserveId` |
| `borrowable` | bool | 是否可借 | `getReserveConfig(reserveId)` | `reserveId` |
| `receiveSharesEnabled` | bool | 清算是否可收 shares | `getReserveConfig(reserveId)` | `reserveId` |
| `dynamicConfigKey` | uint32 | 当前动态配置 key | `getReserve(reserveId)` | `reserveId` |

**动态配置**（per Reserve per dynamicConfigKey）：

| 参数 | 类型 | 说明 | 查询方法 | 输入参数 |
|------|------|------|----------|----------|
| `collateralFactor` | uint16 | 抵押因子 (BPS) | `getDynamicReserveConfig(reserveId, key)` | `reserveId, dynamicConfigKey` |
| `maxLiquidationBonus` | uint32 | 最大清算奖金 (BPS) | `getDynamicReserveConfig(reserveId, key)` | `reserveId, dynamicConfigKey` |
| `liquidationFee` | uint16 | 清算手续费 (BPS) | `getDynamicReserveConfig(reserveId, key)` | `reserveId, dynamicConfigKey` |

**Reserve 衍生值**：

| 衍生值 | 查询方法 | 输入参数 |
|--------|----------|----------|
| 总供应资产量 | `getReserveSuppliedAssets(reserveId)` | `reserveId` |
| 总供应 shares | `getReserveSuppliedShares(reserveId)` | `reserveId` |
| drawn/premium 债务 | `getReserveDebt(reserveId)` | `reserveId` |
| 总债务 | `getReserveTotalDebt(reserveId)` | `reserveId` |

### 2.2 UserPosition 层参数（per Spoke per Reserve per User）

| 参数 | 类型 | 说明 | 查询方法 | 输入参数 |
|------|------|------|----------|----------|
| `drawnShares` | uint120 | 借款 shares | `getUserPosition(reserveId, user)` | `reserveId, user` |
| `premiumShares` | uint120 | 溢价 shares | `getUserPosition(reserveId, user)` | `reserveId, user` |
| `premiumOffsetRay` | int200 | 溢价偏移 | `getUserPosition(reserveId, user)` | `reserveId, user` |
| `suppliedShares` | uint120 | 供应 shares | `getUserPosition(reserveId, user)` | `reserveId, user` |
| `dynamicConfigKey` | uint32 | 用户动态配置 key | `getUserPosition(reserveId, user)` | `reserveId, user` |

**UserPosition 衍生值**：

| 衍生值 | 查询方法 | 输入参数 |
|--------|----------|----------|
| 用户供应资产量 | `getUserSuppliedAssets(reserveId, user)` | `reserveId, user` |
| 用户供应 shares | `getUserSuppliedShares(reserveId, user)` | `reserveId, user` |
| 用户 drawn/premium 债务 | `getUserDebt(reserveId, user)` | `reserveId, user` |
| 用户总债务 | `getUserTotalDebt(reserveId, user)` | `reserveId, user` |
| 用户溢价债务（RAY） | `getUserPremiumDebtRay(reserveId, user)` | `reserveId, user` |
| 用户是否抵押/是否借款 | `getUserReserveStatus(reserveId, user)` | `reserveId, user` |

### 2.3 Spoke 整体参数

| 参数 | 查询方法 | 输入参数 |
|------|----------|----------|
| reserve 总数 | `getReserveCount()` | 无 |
| hub+assetId → reserveId | `getReserveId(hub, assetId)` | `hub, assetId` |
| 清算配置 | `getLiquidationConfig()` | 无 |
| 用户账户数据 | `getUserAccountData(user)` | `user` |
| 用户上次风险溢价 | `getUserLastRiskPremium(user)` | `user` |
| 清算奖金 | `getLiquidationBonus(reserveId, user, healthFactor)` | `reserveId, user, healthFactor` |
| position manager 是否激活 | `isPositionManagerActive(positionManager)` | `positionManager` |
| position manager 是否被用户授权 | `isPositionManager(user, positionManager)` | `user, positionManager` |
| Oracle 地址 | `ORACLE()` | 无 |
| 最大用户储备数 | `MAX_USER_RESERVES_LIMIT()` | 无 |

### 2.4 TokenizationSpoke（ERC-4626 Vault，非 SDK 暴露层）

TokenizationSpoke 与 Spoke 是**不同的合约**，地址无交集：

| 维度 | Spoke | TokenizationSpoke |
|------|-------|-------------------|
| 合约性质 | 市场入口，用户通过 Spoke 进行 supply/borrow/withdraw | ERC-4626 vault，tokenize 单个底层资产（`asset()` 返回唯一 `ASSET` immutable） |
| 部署粒度 | per-market（如 MAIN_SPOKE、BLUECHIP_SPOKE），一个 Spoke 管理多个 reserve | per-Hub per-Asset（如 `CORE_WETH_TOKENIZATION_SPOKE`），每个 reserve 一个实例 |
| address-book 来源 | `AaveV4Ethereum.SPOKES`（11 个） | `AaveV4Ethereum.TOKENIZATION_SPOKES`（31 个） |
| SDK 暴露 | GraphQL `Reserve.spoke` → `{id, name, address}` | **不暴露**，GraphQL schema 中无 `TokenizationSpoke` 实体 |
| 本项目使用 | `spokeAddress` → oracle 价格查询 | 仅 address-book 有地址，代码未直接使用 |

V3 vs V4 供应/债务凭证对比：

| 概念 | Aave V3 | Aave V4 |
|------|---------|---------|
| 供应凭证 token | aToken（独立 ERC20） | TokenizationSpoke 的 share token（ERC20Upgradeable，同时是 ERC-4626 vault share） |
| 借款凭证 token | vToken / variableDebtToken（独立 ERC20） | 无独立 token，Spoke 内部 `UserPosition.drawnShares` 记账 |
| 余额计算 | `aToken.balanceOf(user)` | `TokenizationSpoke.balanceOf(user)`（share tokens） |

---

## 三、参数共享关系总结

### 同一 Hub 同一 Asset，所有 Spoke 共享的值

- `drawnRate`、`drawnIndex`、`lastUpdateTimestamp` — 利率和计息
- `irStrategy`、`liquidityFee`、`feeReceiver`、`reinvestmentController` — 配置
- `liquidity`、`swept`、`realizedFees` — 流动性和费用
- `underlying`、`decimals` — 资产元数据
- supply share price（`totalAddedAssets / addedShares`）— 供应汇率

### 同一 Hub 同一 Asset，各 Spoke 独立的值

- `addCap`、`drawCap`、`riskPremiumThreshold` — 限额和风控
- `active`、`halted` — 运营状态

### 双层存储（Asset 层 = Σ SpokeData 层）

- `addedShares`、`drawnShares`、`premiumShares`、`premiumOffsetRay`、`deficitRay`

### 会计模型

- **债务侧**：Index-based accrual，`drawnIndex` 单调递增，债务 = `shares × drawnIndex / RAY`
- **供应侧**：Share-price model，无 `addedIndex`，share price 随 `totalAddedAssets` 增长而隐式上升

---

## 四、已部署合约地址（Ethereum Mainnet）

来源：[aave-address-book](https://github.com/aave-dao/aave-address-book) `src/AaveV4Ethereum.sol`（PR #1351，npm v4.49.0+）

### 4.1 Hub 合约（查询 deficit 等参数的目标合约）

| 名称 | 地址 | 用途 |
|------|------|------|
| CORE_HUB | `0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9` | 查询 CORE 市场所有 Asset/SpokeData 参数 |
| PLUS_HUB | `0x06002e9c4412CB7814a791eA3666D905871E536A` | 查询 PLUS 市场所有 Asset/SpokeData 参数 |
| PRIME_HUB | `0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931` | 查询 PRIME 市场所有 Asset/SpokeData 参数 |

### 4.2 Spoke 合约（查询 Reserve/UserPosition 参数的目标合约）

| 名称 | 地址 | 关联 Hub |
|------|------|----------|
| MAIN_SPOKE | `0x94e7A5dCbE816e498b89aB752661904E2F56c485` | CORE_HUB |
| BLUECHIP_SPOKE | `0x973a023A77420ba610f06b3858aD991Df6d85A08` | CORE_HUB |
| LIDO_E_SPOKE | `0xe1900480ac69f0B296841Cd01cC37546d92F35Cd` | CORE_HUB |
| ETHERFI_E_SPOKE | `0xbF10BDfE177dE0336aFD7fcCF80A904E15386219` | CORE_HUB |
| KELP_E_SPOKE | `0x3131FE68C4722e726fe6B2819ED68e514395B9a4` | CORE_HUB |
| ETHENA_CORRELATED_SPOKE | `0x58131E79531caB1d52301228d1f7b842F26B9649` | PLUS_HUB |
| ETHENA_ECOSYSTEM_SPOKE | `0xba1B3D55D249692b669A164024A838309B7508AF` | PLUS_HUB |
| FOREX_SPOKE | `0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1` | PLUS_HUB |
| GOLD_SPOKE | `0x65407b940966954b23dfA3caA5C0702bB42984DC` | PLUS_HUB |
| LOMBARD_BTC_SPOKE | `0x7EC68b5695e803e98a21a9A05d744F28b0a7753D` | PRIME_HUB |
| TREASURY_SPOKE | `0xB9B0b8616f6Bf6841972a52058132BE08d723155` | — |

### 4.3 其他核心合约

| 名称 | 地址 | 用途 |
|------|------|------|
| ACCESS_MANAGER | `0x08aE3BE30958cDd1847ec58fFfd4C451a87fDF01` | 权限管理 |
| HUB_CONFIGURATOR | `0x1F0753480bB03EaA00863224602267B7E0525C3d` | Hub 配置 |
| SPOKE_CONFIGURATOR | `0x9BFFf48BFb5A7AE70c348d4d4cb97E8DEFa5389a` | Spoke 配置 |
| CONFIG_ENGINE | `0xe8096f931734286a95b6A63eFFCEFD3C56F3f6a9` | 配置引擎 |
| LIQUIDATION_LOGIC | `0x88dF535473C5adf1f57789734A05E555F7Deb8DB` | 清算逻辑库 |

### 4.4 地址覆盖情况

文档中所有查询方法需要的合约地址**均已覆盖**：

| 需要的合约 | 是否有地址 | 来源 |
|-----------|-----------|------|
| Hub（查询 Asset/SpokeData 参数） | 有 | `AaveV4EthereumHubs` |
| Spoke（查询 Reserve/UserPosition 参数） | 有 | `AaveV4EthereumSpokes` |
| TokenizationSpoke | 有 | `AaveV4EthereumTokenizationSpokes`（ERC-4626 vault，per-Hub per-Asset 部署，share token 等价 V3 aToken；SDK 不暴露此层） |
| AaveOracle（Spoke 的 Oracle） | 有 | `AaveV4EthereumSpokes` 中的 `_SPOKE_ORACLE` |
| AccessManager | 有 | `AaveV4Ethereum` |
| HubConfigurator / SpokeConfigurator | 有 | `AaveV4Ethereum` |
| ConfigEngine | 有 | `AaveV4Ethereum` |
| PositionManagers | 有 | `AaveV4EthereumPositionManagers` |
| AssetInterestRateStrategy | **无独立地址** | 需通过 `Hub.getAssetConfig(assetId).irStrategy` 获取 |

**注意**：`AssetInterestRateStrategy` 的地址未在 address-book 中直接列出，但可通过 Hub 合约的 `getAssetConfig(assetId)` 查询 `irStrategy` 字段获得。

### 4.5 address-book 本地路径

```
/Users/pabloli/Documents/code/aave-address-book/
```

---

## 五、Shares-Based 供应模型与 Supply Rate

### 5.1 V4 没有 Supply Index

Aave V3 使用 `liquidityIndex` 追踪供应者余额增长，V4 完全移除了该机制，改用 **shares-based** 模型（类似 ERC-4626）：

| 概念 | Aave V3 | Aave V4 |
|------|---------|---------|
| 供应者余额增长 | `scaledBalance × liquidityIndex` | `suppliedShares × (totalAddedAssets / addedShares)` |
| 借款债务增长 | `scaledBalance × variableBorrowIndex` | `drawnShares × drawnIndex + premium` |
| 供应指数 | `liquidityIndex`（显式存储） | ❌ 不存在 |
| 借款指数 | `variableBorrowIndex` | `drawnIndex`（唯一指数） |

**核心区别**：供应者持有固定 shares，收益通过 shares 兑换率增长隐式体现，无需单独的 supply index。

### 5.2 用户供应余额计算

Spoke 层存储用户 `suppliedShares`，余额通过 Hub 的兑换率计算：

```solidity
// UserPosition 结构
struct UserPosition {
    uint120 suppliedShares;   // 用户的供应 shares（固定不变）
    uint120 drawnShares;      // 用户的借款 shares
    uint120 premiumShares;    // 用户的 premium shares
    int200 premiumOffsetRay;  // premium 偏移量
}

// 用户供应余额 = shares × 兑换率
userBalance = hub.previewRemoveByShares(assetId, userPosition.suppliedShares)
```

### 5.3 Supply Exchange Rate 公式

`previewRemoveByShares` 的完整计算链：

```
previewRemoveByShares(assetId, shares)
  → toAddedAssetsDown(shares)
  → shares × (totalAddedAssets + VIRTUAL_ASSETS) / (addedShares + VIRTUAL_SHARES)
```

其中 `totalAddedAssets` 包含 deficit：

```
totalAddedAssets = liquidity + swept + aggregatedOwed - realizedFees - unrealizedFees

aggregatedOwed = drawnShares × drawnIndex + premiumRay + deficitRay
```

**虚拟份额**（`VIRTUAL_ASSETS = 1e6`, `VIRTUAL_SHARES = 1e6`）用于防止 share manipulation 攻击。

### 5.4 Deficit 对 Supply Rate 的影响

Deficit 通过 `totalAddedAssets` 直接影响供应份额的兑换率：

| 场景 | totalAddedAssets | 兑换率影响 |
|------|-----------------|-----------|
| 无 deficit | `liquidity + swept + drawn + premium - fees` | 正常增长 |
| 产生 deficit | 同上，但 `aggregatedOwed` 中包含 `deficitRay` | deficit 作为"虚拟债务"维持账面平衡 |
| 消除 deficit | 销毁供应 shares，`addedShares` 减少 | 剩余 shares 兑换率回升 |

**关键**：deficit 被计入 `aggregatedOwed`，使得 `totalAddedAssets` 账面不变，但实际可提取资产减少。供应者通过兑换率下降承担损失。

### 5.5 为什么 V4 不暴露 Supply Rate 变量

| 原因 | 说明 |
|------|------|
| 架构简化 | 只维护 `drawnIndex` 一个指数，不需要 `liquidityIndex` |
| Shares 模型 | 收益通过 exchange rate 增长体现，无需显式 rate |
| Gas 优化 | 少维护一个状态变量 = 每次操作少一次 SSTORE |
| ERC-4626 兼容 | 与 vault 标准一致，`previewRedeem` 即可获取份额价值 |

如需获取 supply APY，需链下计算两个时间点的 exchange rate 增长率：

```solidity
uint256 currentRate = hub.previewRemoveByShares(assetId, 1e18);
// supplyAPY = (currentRate - previousRate) × 365 days / (timeDelta × previousRate)
```

---

## 六、Deficit 双层追踪机制

### 6.1 存储层级

Deficit 在 Hub 上**双层存储**，不存在于 Reserve 级别（Hub 不感知 Reserve）：

| 层级 | 字段 | 映射键 | 语义 | 查询方法 |
|------|------|--------|------|----------|
| Hub 聚合 | `Asset.deficitRay` | `assetId` | 该 asset 所有 spoke 的总 bad debt | `getAssetDeficitRay(assetId)` |
| Spoke 分量 | `SpokeData.deficitRay` | `assetId + spoke` | 该 spoke 对该 asset 的 bad debt | `getSpokeDeficitRay(assetId, spoke)` |

**不变量**：`Asset.deficitRay = Σ SpokeData.deficitRay`（所有 spoke 之和）

存储位置（`src/hub/HubStorage.sol:16-19`）：

```solidity
mapping(uint256 assetId => IHub.Asset) internal _assets;
mapping(uint256 assetId => mapping(address spoke => IHub.SpokeData)) internal _spokes;
```

结构定义（`src/hub/interfaces/IHub.sol`）：

```solidity
struct Asset {
    // ...
    uint200 deficitRay;  // line 55: 所有 spoke 的总 deficit
}

struct SpokeData {
    // ...
    uint200 deficitRay;  // line 90: 该 spoke 的 deficit
}
```

### 6.2 产生：reportDeficit（Spoke 清算后向 Hub 报告 bad debt）

触发链路：

1. Spoke 上清算后用户仍资不抵债（`isUserInDeficit`）→ `src/spoke/Spoke.sol:375-377`
2. 调用 `LiquidationLogic.notifyReportDeficit`，遍历用户所有借贷 reserve → `src/spoke/libraries/LiquidationLogic.sol:252-299`
3. 对每个 reserve 调用 `hub.reportDeficit(assetId, ...)` → Hub 侧 `src/hub/Hub.sol:320-323`

Hub 侧更新逻辑（**两个层级同步递增**）：

```solidity
uint256 deficitAmountRay = uint256(drawnShares) * asset.drawnIndex
    + premiumDelta.restoredPremiumRay;
asset.deficitRay += deficitAmountRay.toUint200();    // Hub 聚合 +1
spoke.deficitRay += deficitAmountRay.toUint200();    // Spoke 分量 +1
```

### 6.3 消除：eliminateDeficit（用 addedShares 覆盖 bad debt）

`src/hub/Hub.sol:338-358`：caller spoke 用其 `addedShares` 去消除 covered spoke 的 deficit。

```solidity
SpokeData storage coveredSpoke = _spokes[assetId][spoke];  // 被覆盖的 spoke
uint256 deficitRay = coveredSpoke.deficitRay;               // 取该 spoke 的 deficit 分量
uint256 deficitAmountRay = (amount < deficitRay.fromRayUp()) ? amount.toRay() : deficitRay;
// ...
asset.addedShares -= shares;
callerSpoke.addedShares -= shares;        // caller spoke 付出 shares
asset.deficitRay -= deficitAmountRay.toUint200();       // Hub 聚合 -1
coveredSpoke.deficitRay -= deficitAmountRay.toUint200(); // Spoke 分量 -1
```

关键：caller spoke 和 covered spoke 可以不同，允许跨 spoke 消除 deficit。

### 6.4 Deficit 对利率的影响

利率策略使用 **Hub 聚合 deficit**（`Asset.deficitRay`），而非单个 spoke 的 deficit：

```solidity
// src/hub/libraries/AssetLogic.sol:170-182
function getDrawnRate(IHub.Asset storage asset, uint256 assetId, uint256 drawnIndex) internal view returns (uint256) {
    return IBasicInterestRateStrategy(asset.irStrategy).calculateInterestRate({
        deficit: asset.deficitRay.fromRayUp(),  // Hub 聚合 deficit
        // ...
    });
}
```

### 6.5 数据流图

```
                    Hub
   ┌──────────────────────────────────────────┐
   │  _assets[assetId].deficitRay             │  ← 聚合 total deficit per asset
   │     = Σ _spokes[assetId][spoke].deficitRay │  ← 不变量
   │                                          │
   │  _spokes[assetId][spoke_A].deficitRay    │  ← spoke A 的 deficit（如 Ethereum Mainnet）
   │  _spokes[assetId][spoke_B].deficitRay    │  ← spoke B 的 deficit（如 L2）
   │  ...                                     │
   └──────────────────────────────────────────┘

   产生：Spoke 清算 → LiquidationLogic.notifyReportDeficit → Hub.reportDeficit（双层级 +1）
   消除：任意 Spoke → Hub.eliminateDeficit（caller spoke 付 addedShares，covered spoke deficit 双层级 -1）
   消费：利率策略 ← Asset.deficitRay（Hub 聚合值）
```

### 6.6 归属结论

| 问题 | 答案 |
|------|------|
| deficit 是 per spoke？ | 是，`SpokeData.deficitRay` 按 `(assetId, spoke)` 存储 |
| deficit 是 per reserve？ | 否，Hub 不感知 Reserve，deficit 不存在于 Reserve 级别 |
| deficit 是 per hub？ | 是，`Asset.deficitRay` 按 `assetId` 聚合，用于利率计算 |
| 两层关系？ | `Asset.deficitRay = Σ SpokeData.deficitRay`，同步增减 |

---

### 5.6 Supply Rate vs Utilization Rate

注意区分两个概念：

- **Utilization Rate** = `drawn / (drawn + liquidity)`，反映资金使用效率
- **Supply Rate (APY)** = exchange rate 的年化增长率，反映供应者实际收益

V3 中 `Supply Rate = Borrow Rate × Utilization × (1 - reserveFactor)`，V4 中无此显式公式，收益完全由 shares 兑换率变化体现。


