# Aave V3.x & V4 合约内 Supply Rate 与 Borrow Rate 换算公式

> **版本：Aave V3.6 + Aave V4（Hub-and-Spoke 架构）** | **来源：链上合约源码**

本文档整合 Aave V3.6 与 V4 链上合约中 Supply Rate（存款利率）与 Borrow Rate（借款利率）的换算逻辑，涵盖坏账（deficit）、风险溢价（premium）、费率扣减（$F_{acc}$ / reserveFactor）等机制。

---

## V3 vs V4 核心差异速查

| 概念 | Aave V3 | Aave V4 |
|------|---------|---------|
| 债务增长 | `borrowIndex` 全额增长 | `drawnIndex` 全额增长（唯一指数） |
| 供应增长 | `liquidityIndex` 隐式扣费后增长 | $exchangeRate = totalAddedAssets / addedShares$ |
| 协议扣费 | 隐式：`liquidityIndex` 增长率中内嵌 | 显式：$F_{acc}$ 从 `totalAddedAssets` 中扣除 |
| 费用变量 | ❌ 无 $F_{acc}$ | ✅ `realizedFees + unrealizedFees` |
| 风险溢价 | ❌ 无 | ✅ premium debt（虚拟债务，随 index 复利） |
| 借款人等效利率 | $R_{borrow}$ | $\approx R_{borrow} \times (1 + RP/10000)$ |
| Supply Rate 变量 | ✅ `currentLiquidityRate`（显式） | ❌ 不存在，兑换率变化率隐式表达 |
| Borrow Rate 变量 | ✅ `currentVariableBorrowRate` | ✅ `drawnRate` |
| 利用率分母 | $totalDebt + availableLiquidity$ | $L + D + S$（不含 $P$ 和 $Def$） |
| Deficit 影响 | 仅在 Supply Rate 分母中 | 减少分子（$D$ 变小）+ 膨胀分母 |

---

# Part 1：Aave V3.6

> **合约：DefaultReserveInterestRateStrategyV2.sol**

## 1. 核心换算公式

$$Supply\ Rate = Borrow\ Rate \times supplyUsageRatio \times (1 - reserveFactor)$$

展开为合约实际运算：

$$Supply\ Rate = BorrowRate \times \frac{totalDebt}{totalDebt + availableLiquidity + deficit} \times \left(1 - \frac{reserveFactor}{PERCENTAGE\_FACTOR}\right)$$

其中 $PERCENTAGE\_FACTOR = 10000$，$reserveFactor$ 以 bps 为单位（如 1000 = 10%）。

## 2. 参数说明

| 参数 | 合约中的名称 | 单位 | 说明 |
|------|-------------|------|------|
| **Supply Rate** | `currentLiquidityRate` | ray ($10^{27} = 100\%$) | 存款人收到的年化利率 |
| **Borrow Rate** | `currentVariableBorrowRate` | ray ($10^{27} = 100\%$) | 借款人支付的年化利率（可变），由利率曲线决定 |
| **totalDebt** | `totalVariableDebt` | underlying units | 当前总可变债务 |
| **availableLiquidity** | 实时计算 | underlying units | 可用流动性（= virtualUnderlyingBalance + liquidityAdded - liquidityTaken） |
| **deficit** | `reserve.deficit` / `unbacked` | underlying units | 坏账金额，清算时资不抵债产生的缺口 |
| **reserveFactor** | `reserveFactor` | bps ($10000 = 100\%$) | 协议准备金率，利息中归国库的比例 |
| **PERCENTAGE_FACTOR** | `PERCENTAGE_FACTOR` | 常量 10000 | bps 精度因子 |

## 3. Deficit 的作用机制（V3.6 合约特有逻辑）

Deficit 是**坏账金额**，它在 `supplyUsageRatio` 的**分母**中出现，从而**压低**存款利率。

### 3.1 合约内对比公式

**Borrow Rate 的利用率（不受 deficit 影响）：**

$$borrowUsageRatio = \frac{totalDebt}{totalDebt + availableLiquidity}$$

**Supply Rate 的利用率（受 deficit 影响）：**

$$supplyUsageRatio = \frac{totalDebt}{totalDebt + availableLiquidity + deficit}$$

### 3.2 影响效果

- **deficit = 0**：$supplyUsageRatio = borrowUsageRatio$，两者利用率相等
- **deficit > 0**：分母变大 → $supplyUsageRatio$ 变小 → Supply Rate 降低
- **关键**：deficit **只惩罚存款人**，borrow rate 完全不受影响（借款人该付多少还是付多少）

### 3.3 极端情况

当 deficit 极大时（坏账严重），$supplyUsageRatio \to 0$，存款利率趋近于零——即使借款人仍在支付高额利息，存款人也几乎拿不到收益。

## 4. 合约源码溯源

### 4.1 参数组装（ReserveLogic.sol）

[`src/contracts/protocol/libraries/logic/ReserveLogic.sol#L145-L154`](file:///Users/pabloli/Documents/code/aave-v3-origin/src/contracts/protocol/libraries/logic/ReserveLogic.sol#L145-L154)

```solidity
(uint256 nextLiquidityRate, uint256 nextVariableRate) = IReserveInterestRateStrategy(
    interestRateStrategyAddress
).calculateInterestRates(
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

### 4.2 利率计算（DefaultReserveInterestRateStrategyV2.sol）

[`src/contracts/misc/DefaultReserveInterestRateStrategyV2.sol#L130-L150`](file:///Users/pabloli/Documents/code/aave-v3-origin/src/contracts/misc/DefaultReserveInterestRateStrategyV2.sol#L130-L150)

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

### 4.3 数据结构（DataTypes.sol）

[`src/contracts/protocol/libraries/types/DataTypes.sol#L315-L325`](file:///Users/pabloli/Documents/code/aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol#L315-L325)

```solidity
struct CalculateInterestRatesParams {
    uint256 unbacked;           // ← deficit 映射到这里
    uint256 liquidityAdded;
    uint256 liquidityTaken;
    uint256 totalDebt;
    uint256 reserveFactor;
    address reserve;
    bool usingVirtualBalance;   // v3.4+ 始终为 true
    uint256 virtualUnderlyingBalance;
}
```

## 5. Deficit 的来源

Deficit 是清算过程中的坏账，在以下情况产生：

- 清算时，抵押品价值不足以偿还债务（价格剧烈波动、清算延迟等）
- 被清算用户的 debt token 被销毁，但 collateral token 不够覆盖 → 差额计入 deficit

## 6. Borrow Rate 的计算（V3.6 利率曲线）

Supply Rate 依赖于 Borrow Rate，而 Borrow Rate 由合约内的**分段线性曲线**决定：

```
                  borrowRate
                      ↑
  base + slope1 + slope2│          ╱
                        │        ╱
                        │      ╱
            base + slope1│    ╱
                        │  ╱
                        │╱
                  base  │
                        └────────────→ borrowUsageRatio
                             optimal
                   < slope1 > < slope2 >
```

### 合约内计算公式

**当 $borrowUsageRatio \leq optimalUsageRatio$ 时：**

$$variableBorrowRate = baseVariableBorrowRate + variableRateSlope1 \times \frac{borrowUsageRatio}{optimalUsageRatio}$$

**当 $borrowUsageRatio > optimalUsageRatio$ 时：**

$$excessRatio = \frac{borrowUsageRatio - optimalUsageRatio}{RAY - optimalUsageRatio}$$

$$variableBorrowRate = baseVariableBorrowRate + variableRateSlope1 + variableRateSlope2 \times excessRatio$$

### 策略参数

| 参数 | 合约字段 | 单位 | 含义 |
|------|---------|------|------|
| `baseVariableBorrowRate` | `baseVariableBorrowRate` | ray | 最低借款利率（利用率为 0 时） |
| `variableRateSlope1` | `variableRateSlope1` | ray | 低利用率段斜率 |
| `variableRateSlope2` | `variableRateSlope2` | ray | 高利用率段斜率 |
| `optimalUsageRatio` | `optimalUsageRatio` | ray | 最优利用率（拐点/kink） |

策略参数可通过 `DefaultReserveInterestRateStrategyV2.getInterestRateDataBps(reserve)` 查询。

### 利率参数全零与借款禁用的关系（V3 vs V4）

基于 2026-05-15 实测数据分析。

#### 强条件：baseBorrowRate = 0 AND slope1 = 0 AND slope2 = 0 → 一定被禁用

当利率曲线三个参数全为 0 时，borrowRate 在**任意利用率**下恒为 0，即真正意义上的零成本无限借款。治理不可能允许此情况存在。

**V3**：不存在三参数全零的 reserve（共 0 个）。V3 即使设 baseBorrowRate=0，至少有一个 slope > 0，利率曲线仍可工作。

**V4**：三参数全零的 reserve 共 19 个，全部被禁用：

| 禁用方式 | 案例 | 数量 |
|---------|------|------|
| `borrowDisabled=true`（即 `borrowable=false`） | AAVE, LINK, WBTC, WETH, wstETH, weETH, sUSDe, XAUt, PT-* 等 | 18 |
| `isFrozen=true` | rsETH (Kelp) | 1 |

> 三参数全零是 borrowDisabled/frozen 的**充分条件**（当前数据无反例）。

#### 弱条件：仅 baseBorrowRate = 0 → 不一定被禁用

**V4**：V4 中 baseBorrowRate=0 的可借资产仍有借款能力，因为 slope > 0，利用率上来后 rate 被 slope 推高。但 V4 中 baseBorrowRate=0 且 slope 也为 0 的资产全部被禁用（见上）。

**V3**：大量 `baseBorrowRate=0` 且可正常借款的资产（DAI, USDC, WETH, USDT, GHO 等），因为 slope1/slope2 > 0，利用率 > 0 时 `borrowRate = slope1 × (U/U_optimal) > 0`。

#### 设计解读

- `baseBorrowRate=0` 仅表示**利用率=0 时**借款成本为零，一旦有人借款利率曲线即推高 rate，不是"零成本借款"
- 三参数全零 = **利率曲线退化为常零函数**，borrowRate 在任意利用率下恒为 0，治理必须禁用
- V3 不存在三参数全零的 reserve，不是因为合约限制，而是治理选择：V3 单层架构下全零利率曲线是明显的零成本无限借款漏洞，治理不会这么配
- V4 存在全零利率曲线是因为 V4 的多 Hub 架构允许**同一资产在不同 Hub 上有不同利率配置**：

| 资产 | Hub | base | slope1 | slope2 | borrowable | 含义 |
|------|-----|------|--------|--------|------------|------|
| WETH | Core (Main) | 0 | 2.35 | 14 | true | 正常借贷 |
| WETH | Prime (Bluechip) | 0 | 0 | 0 | false | 该 Hub 不支持 WETH 借款 |

V4 的利率曲线粒度是 **per (hub, asset)**，不是 per reserve 也不是 per spoke。全零利率曲线 + borrowable=false 的实质是：**该资产在这个 Hub 上不提供借款功能**，是 Hub 级别的"不参与借贷"声明，配合 borrowable=false 双重保险。同一资产在另一个 Hub 可以有正常利率曲线和借款能力。

## 7. 合约公式换算示例

### 示例参数

| 参数 | 值 |
|------|-----|
| Borrow Rate | 5%（$0.05 \times 10^{27} = 5 \times 10^{25}$ ray） |
| totalDebt | 800 |
| availableLiquidity | 200 |
| reserveFactor | 10%（$1000$ bps） |

### 场景一：无坏账（deficit = 0）

$$Supply\ Rate = 5\% \times \frac{800}{800 + 200 + 0} \times 0.90 = 5\% \times 0.80 \times 0.90 = 3.60\%$$

### 场景二：有坏账（deficit = 100）

$$Supply\ Rate = 5\% \times \frac{800}{800 + 200 + 100} \times 0.90 = 5\% \times 0.727 \times 0.90 = 3.27\%$$

坏账 100 时，存款人收益从 3.60% 降到 3.27%，缩水约 **9.2%**。

### 场景三：严重坏账（deficit = 400）

$$Supply\ Rate = 5\% \times \frac{800}{800 + 200 + 400} \times 0.90 = 5\% \times 0.571 \times 0.90 = 2.57\%$$

坏账 400 时，存款人收益降到 2.57%，缩水约 **28.6%**。

## 8. 合约查询路径汇总

| 合约 | 函数 | 获取内容 |
|------|------|----------|
| `Pool` | `getReserveData(asset)` | `currentLiquidityRate`, `currentVariableBorrowRate`, `deficit` |
| `Pool` | `getConfiguration(asset)` | `reserveFactor`（需调用 `.getParams()` 解析） |
| `AaveProtocolDataProvider` | `getReserveData(asset)` | `liquidityRate`, `variableBorrowRate` |
| `UiPoolDataProviderV3` | `getReservesData(provider)` | 批量获取所有资产数据（含 `liquidityRate`, `deficit`） |
| `DefaultReserveInterestRateStrategyV2` | `getInterestRateDataBps(reserve)` | 利率曲线参数（`baseVariableBorrowRate` 等） |
| `Pool` | `RESERVE_INTEREST_RATE_STRATEGY()` | 获取当前池的利率策略合约地址 |

## 9. 术语速查与数据来源

> 本表为 V3 术语的统一命名与数据获取路径。

### 9.1 核心术语速查

| 术语 | 别名 | 说明 |
|------|------|------|
| **Utilization** | borrowUsageRatio, U | `U = totalDebt / (availableLiquidity + totalDebt)` |
| **Supply utilization** | supplyUsageRatio | `U_s = totalDebt / (availableLiquidity + totalDebt + deficit)`，仅用于 Supply Rate |
| **Supply APR (ray)** | liquidityRate, currentLiquidityRate | 年化供应利率，1e27 = 100% |
| **Borrow APR (ray)** | variableBorrowRate, currentVariableBorrowRate | 年化可变借款利率，1e27 = 100%，由利率曲线决定 |
| **Supply APY (前端展示)** | — | 合约使用**简单利率**，前端展示 ≈ APR（或标注「simple」） |
| **Borrow APY (前端展示)** | — | 可由 `variableBorrowRate` 复利推导：$(1 + rate/1e27)^{secondsPerYear} - 1$ |
| **Supply index** | liquidityIndex | 供应累计乘数，`balance = scaledBalance × liquidityIndex`，**线性增长** |
| **Borrow index** | variableBorrowIndex | 可变债务累计乘数，`debt = scaledDebt × variableBorrowIndex`，**复利增长** |
| **Scaled supply balance** | scaledATokenBalance | 存储的 aToken「份额」，`balance = scaled × liquidityIndex` |
| **Scaled variable debt** | scaledVariableDebt | 存储的 vToken「份额」，`debt = scaled × variableBorrowIndex` |
| **Virtual underlying balance** | virtualUnderlyingBalance | 利率计算的账面余额，supply/repay 时 +，withdraw/borrow/flash 时 − |
| **Actual underlying balance** | availableLiquidity | `IERC20(underlying).balanceOf(aTokenAddress)`，池内真实代币余额 |
| **Deficit** | unbacked (参数中) | 坏账（清算缺口），详见 §3 |
| **Market reference currency unit** | — | Oracle 计价单位，如 1e18 = 1 ETH，配合 `marketReferenceCurrencyPriceInUsd` 换算 USD |

### 9.2 Index 增长公式

**Supply（线性）：**
$$liquidityIndex_{new} = liquidityIndex_{old} \times (1 + liquidityRate \times \Delta t / SECONDS\_PER\_YEAR)$$

**Borrow（复利）：**
$$variableBorrowIndex_{new} = variableBorrowIndex_{old} \times (1 + x + x^2/2 + x^3/6)$$
其中 $x = variableBorrowRate \times \Delta t / SECONDS\_PER\_YEAR$（ray 精度）

### 9.3 UI 数据来源

| 来源 | 接口 | 获取内容 |
|------|------|----------|
| Pool + UiPoolDataProviderV3 | `getReservesData(provider)` | indexes, rates, scaled debt, strategy params, virtual/actual balance, deficit |
| UiIncentiveDataProvider | — | 奖励 APY |
| 前端服务层 | UiPoolService / UiIncentivesService | 调用上述 helper 合约，可选转换 rate → APY |

### 9.4 借款人复利与 Treasury 流转

- **借款人复利**：不单独存储余额，体现在 `variableBorrowIndex` 的增长中。指数随 `variableBorrowRate` 复利增长 → 用户 `debt = scaledDebt × variableBorrowIndex` 随时间增加 → 还款时流入池内 → 成为「利息收入」分配。
- **reserveFactor（如 10%）**：每次状态更新时，变额债务累计利息的一部分（按 underlying 计算）转换为 scaled aToken，加入 `reserve.accruedToTreasury`。调用 `Pool.mintToTreasury(assets)` 时，各 reserve 的累计额铸造为 aToken 打入 Collector（国库）合约。

---

## 10. 模拟计算：存入 X 后的 APR/APY

> **这是 §1-§8 的实践操作指南**：给定当前 reserve 状态和假设供应量 X，计算执行后的 Supply/Borrow APR/APY。

### 10.1 目标

- **输入**：reserve（市场 + 资产）、当前状态、**假设供应量 X**（underlying 单位）
- **输出**：供应后的 **Supply APR/APY** 和 **Borrow APR/APY**（即新的 `liquidityRate` 和 `variableBorrowRate`，ray → %）

### 10.2 所需数据（从 Subgraph 或链上获取）

| 字段 | 说明 | 用途 |
|------|------|------|
| `reserve` (资产地址) | reserve 的底层资产 | Params + strategy 查询 |
| `virtualUnderlyingBalance` | 协议账面流动性 (underlying units) | Params |
| `totalScaledVariableDebt` | 所有用户的 scaled 变额债务汇总 | 计算 totalDebt |
| `variableBorrowIndex` | 当前借款指数 (ray) | `totalDebt = scaled × index` |
| `deficit` | 坏账 (underlying units) | Params (作为 unbacked) |
| `reserveFactor` | 准备金率 (bps, 如 1000 = 10%) | Params |

**计算当前总债务：**

```ts
totalDebt = (totalScaledVariableDebt * variableBorrowIndex) / RAY
```

**利率策略参数**（从策略合约按 reserve 查询）：

- `baseVariableBorrowRate` (ray)
- `variableRateSlope1` (ray)
- `variableRateSlope2` (ray)
- `optimalUsageRatio` (ray)

策略地址：`Pool.RESERVE_INTEREST_RATE_STRATEGY()`（同 Pool 内所有 reserve 共用）

### 10.3 构建「存入 X 后」的参数

```ts
const params = {
  unbacked: reserve.deficit,
  liquidityAdded: supplyAmountX,   // 假设供应量 (underlying units)
  liquidityTaken: 0n,
  totalDebt: currentTotalVariableDebt,  // 供应不改变债务
  reserveFactor: reserve.reserveFactor,
  reserve: reserve.underlyingAsset,
  usingVirtualBalance: true,
  virtualUnderlyingBalance: reserve.virtualUnderlyingBalance,  // 供应前
};
```

### 10.4 调用策略合约 (view)

```ts
// 合约调用（view，零 gas）
const [liquidityRate, variableBorrowRate] =
  strategy.calculateInterestRates(params);
// 返回值均为 ray 精度
```

### 10.5 Ray → %

```ts
const RAY = 10n ** 27n;
const rayToPercent = (rateRay: bigint): number =>
  Number(rateRay) / Number(RAY) * 100;

// Supply APR/APY（供应后）= rayToPercent(liquidityRate)
// Borrow APR/APY（供应后）= rayToPercent(variableBorrowRate)
```

> 注：合约对 Supply 使用**简单利率**，所以前端展示 Supply APY ≈ APR（可标注「simple」）；Borrow 可以用 `(1 + rate/1e27)^(secondsPerYear) - 1` 推导复利 APY。

### 10.6 端到端步骤

1. **获取** reserve 数据：`virtualUnderlyingBalance`、`totalScaledVariableDebt`、`variableBorrowIndex`、`deficit`、`reserveFactor`、`underlyingAsset`。从 Pool 获取策略地址和参数。
2. **计算** `currentTotalVariableDebt = totalScaledVariableDebt × variableBorrowIndex / RAY`
3. **构建** `CalculateInterestRatesParams`：`liquidityAdded = X`、`liquidityTaken = 0`、`totalDebt = currentTotalVariableDebt`
4. **调用** `strategy.calculateInterestRates(params)` (view)
5. **转换** `(liquidityRate, variableBorrowRate)` → `rayToPercent()`
6. **展示**为「存入后的 Supply APY」和「存入后的 Borrow APY」

> 此模拟无需更新 index 或 timestamp——只需要**当前**状态 + 假设供应量 X。

---

# Part 2：Aave V4

> **架构：Hub-and-Spoke** | **核心：shares-based 兑换率模型**

## 1. 术语映射

| 符号 | 术语 | 合约字段 | 单位 | 说明 |
|------|------|----------|------|------|
| $R_{borrow}$ | Borrow APY | `Asset.drawnRate` | RAY ($10^{27}=100\%$) | 借款人支付的年化利率 |
| Supply APY | Supply APY | 兑换率年化变化率 | % | 无显式变量，由兑换率增长率隐式表达 |
| $L$ | liquidity | `Asset.liquidity` | underlying units | 可用流动性 |
| $S$ | swept | `Asset.swept` | underlying units | 被 reinvestment controller 抽走的流动性 |
| $D$ | drawn debt | $drawnShares \times drawnIndex$ | underlying units | 借款本金（实际提取的流动性） |
| $P$ | premium debt | $premiumShares \times drawnIndex - P_{offset}$ | underlying units | 风险溢价（虚拟债务，归供应端） |
| $P_{offset}$ | premium offset | `Asset.premiumOffsetRay` | RAY | premium 锚点值，使 $P$ 从 0 起算 |
| $Def$ | deficit | `Asset.deficitRay` | underlying units | 坏账（不产生利息） |
| $F_{acc}$ | 累计费用 | `realizedFees + unrealizedFees` | underlying units | 协议已抽走的费用 |
| $\ell$ | 协议费率 | `Asset.liquidityFee` | BPS ($10000=100\%$) | 利息中归协议的比例 |
| $RP$ | 风险溢价率 | 用户级别计算 | BPS ($10000=100\%$) | 用户抵押品风险加权平均值 |
| $drawnIndex$ | 债务指数 | `Asset.drawnIndex` | RAY | 唯一指数，按 $R_{borrow}$ 复利增长 |

> **新增符号 $P_{offset}$**：这是理解 premium 增长率的关键。它与 $P$ 共同构成 premium 的完整市值：
>
> $$P_{offset} + P = premiumShares \times drawnIndex$$

## 2. 兑换率模型（取代 V3 的 liquidityIndex）

### 核心公式

$$exchangeRate = \frac{totalAddedAssets}{addedShares}$$

`addedShares` 是供应者持有的总份额（不变），`totalAddedAssets` 随时间增长。

### totalAddedAssets 的组成

```solidity
// AssetLogic.sol:L80-L96
totalAddedAssets = L + S + (D + P + Def) - F_acc
```

其中 $(D + P + Def)$ 来自 `_calculateAggregatedOwedRay` ([AssetLogic.sol:L229-L242](file:///Users/pabloli/Documents/code/aave-v4/src/hub/libraries/AssetLogic.sol#L229-L242))：

```solidity
aggregatedOwedRay = (drawnShares × drawnIndex) + premiumRay + deficitRay
                  = D + P + Def
```

## 3. Borrow APY（drawnRate）的计算

### 利率策略

[AssetInterestRateStrategy.sol:L102-L137](file:///Users/pabloli/Documents/code/aave-v4/src/hub/AssetInterestRateStrategy.sol#L102-L137)

$$U = \frac{D}{L + D + S} \qquad \text{（不含 $P$ 和 $Def$，含 $S$）}$$

分段线性模型：

$$
R_{borrow} =
\begin{cases}
R_{base} + slope_1 \times \dfrac{U}{U_{opt}} & U \leq U_{opt} \\[12pt]
R_{base} + slope_1 + slope_2 \times \dfrac{U - U_{opt}}{1 - U_{opt}} & U > U_{opt}
\end{cases}
$$

**注意**：`deficit` 参数虽传入 `calculateInterestRate`，但实现中该参数被注释为 `/* deficit */`，不参与计算。`premium` 完全不传入。

### 策略参数（InterestRateData）

```solidity
// IAssetInterestRateStrategy.sol:L15-L20
struct InterestRateData {
    uint16 optimalUsageRatio;        // 最优利用率拐点 (BPS)
    uint32 baseDrawnRate;            // 基础利率 (BPS)
    uint32 rateGrowthBeforeOptimal;  // 最优利用率前斜率 (BPS)
    uint32 rateGrowthAfterOptimal;   // 最优利用率后斜率 (BPS)
}
```

## 4. Supply APY 的推导

### Step 1：年度价值增长

只有 $D$ 和 $P$ 随 `drawnIndex` 复利增长。但注意，$P$ 的增长速率取决于 premium 的**完整市值** $P + P_{offset}$，而非仅 $P$ 自身：

$$d(P)/dt = premiumShares \times d(drawnIndex)/dt = (P + P_{offset}) \times R_{borrow}$$

同理，费用 `unrealizedFees` 基于 `totalOwed` 的完整增量 $(drawnShares + premiumShares) \times \Delta drawnIndex$ 来计算：

$$d(F_{acc})/dt = (drawnShares + premiumShares) \times d(drawnIndex)/dt \times \ell = (D + P + P_{offset}) \times R_{borrow} \times \ell$$

因此：

$$
\begin{aligned}
\text{年度债务增长} &= (D + P + P_{offset}) \times R_{borrow} \\[4pt]
\text{年度协议费用} &= (D + P + P_{offset}) \times R_{borrow} \times \ell \\[4pt]
\text{年度供应净得} &= (D + P + P_{offset}) \times R_{borrow} \times (1 - \ell)
\end{aligned}
$$

> **旧版错误**：之前写为 $(D + P) \times R_{borrow}$，遗漏了 $P_{offset}$ 项。$P_{offset}$ 是 premium debt 中尚未「变现」的部分，但它同样是虚拟债务的组成部分，随时间一同复利增长。

### Step 2：两个版本的公式

**代码公式**（匹配 on-chain `totalAddedAssets`）：

$$
Supply\ APY = \frac{(D + P + P_{offset}) \times R_{borrow} \times (1 - \ell)}{L + S + D + P + Def - F_{acc}}
$$

定义 **代码有效利用率**：

$$
U_{eff} = \frac{D + P + P_{offset}}{L + S + D + P + Def - F_{acc}}
$$

等价于合约层面的表达（用 shares 和 index 直接计算）：

$$
Supply\ APY = \frac{(drawnShares + premiumShares) \times drawnIndex \times R_{borrow} \times (1 - \ell)}{RAY \times totalAddedAssets}
$$

→ **$Supply\ APY = R_{borrow} \times U_{eff} \times (1 - \ell)$**

**经济公式**（分母 = 供应者实际存入本金，排除 $P$ 和 $Def$）：

$$
Supply\ APY = \frac{(D + P + P_{offset}) \times R_{borrow} \times (1 - \ell)}{L + S + D - F_{acc}}
$$

定义 **经济有效利用率**：

$$
U_{eff}^{econ} = \frac{D + P + P_{offset}}{L + S + D - F_{acc}}
$$

**两种公式对比**：经济公式分母排除了虚拟债务 $P$ 和坏账 $Def$，所以分母更小 → Supply APY 更高。$P$ 起到了类似「杠杆」的效果：在更小的本金基座上产生额外收益。

## 5. Premium（风险溢价）完整解析

### 5.1 核心等式

$$P_{offset} + P = premiumShares \times drawnIndex$$

```
┌───────────────────────────┐   ┌──────────────────┐   ┌─────┐
│  虚拟债务的「当前市值」     │ = │  已 nullify / 抵消  │ + │ 真实 │
│  (随 drawnIndex 一直增长)  │   │  的虚拟债务价值     │   │premium│
└───────────────────────────┘   └──────────────────┘   └─────┘
```

**直觉**：想象一个不断涨水的水库，$P_{offset}$ 是钉在水库壁上的「水位线标记」，只算超过标记的水量（= $P$）。初始时水位刚好在标记上（$P=0$），随时间水面不断升高，超过标记的部分就是真实 premium debt。

### 5.2 静态环境下的完整推导

```
时刻 0（刚借出，RP=5%，借款 100 USDC，drawnIndex=1.00）：

  premiumShares = 5              ← 虚拟债务份额数
  premiumShares × drawnIndex = 5 ← 虚拟债务市值
  P_offset = 5                   ← 初始设为与市值相等
  P = 5 - 5 = 0                  ← 真实 premium 从 0 开始
  

时刻 1（一年后，drawnIndex=1.05）：

  premiumShares × drawnIndex = 5 × 1.05 = 5.25  ← 市值因利率涨了
  P_offset = 5                  ← 锚点不变！
  P = 5.25 - 5 = 0.25           ← 超出的部分就是真实 premium debt

  这个 0.25 是真钱，用户还款时真的要掏出来，流入 supply 池。
```

**$P_{offset}$ 的作用**：就是把虚拟债务在时间维度上「分期分批」变为真实债务。锚点以上是已变现的真实 premium，锚点以下是被冲销掉的虚拟部分。

### 5.3 Collateral Risk 与 Risk Premium 的计算

**Collateral Risk（CR）**：每个抵押品资产的风险参数（BPS），由 Governor 配置。ETH=0（最安全），高风险代币接近 1000_00。

**Risk Premium（RP）**：用户级别的风险加权平均值。

```
1. 将用户抵押品按 CR 从小到大排序
2. 按顺序用抵押品价值覆盖总债务
3. 计算覆盖债务所需的抵押品的 CR 加权平均：

   RP = Σ(CR_i × 抵押品价值_i) / Σ(抵押品价值_i)
```

**premiumShares 的计算**（[UserPositionUtils.sol:L68-L70](file:///Users/pabloli/Documents/code/aave-v4/src/spoke/libraries/UserPositionUtils.sol#L68-L70)）：

```solidity
newPremiumShares = (drawnShares - drawnSharesTaken).percentMulUp(riskPremium)
```

→ $premiumShares = (drawnShares - sharesTaken) \times RP$（BPS 乘）

**$P_{offset}$ 的计算**（[UserPositionUtils.sol:L71-L73](file:///Users/pabloli/Documents/code/aave-v4/src/spoke/libraries/UserPositionUtils.sol#L71-L73)）：

```solidity
newPremiumOffsetRay = (newPremiumShares × drawnIndex) - (premiumDebtRay - restoredPremiumRay)
```

→ $P_{offset} = premiumShares \times drawnIndex - (P_{old} - P_{restored})$（由等式倒挤出来）

### 5.4 Refresh 机制

**触发条件**：用户 Risk Premium 变化时（抵押品组合改变、借款/还款/提款）。

**不变量**（[Hub.sol:L954](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L954)）：

```solidity
require(premiumRayAfter + restoredPremiumRay == premiumRayBefore);
```

→ **刷新瞬间 $P$ 不变，只改变未来的增长速率。**

**Refresh 示例（RP 从 5% → 10%）**：

```
Refresh 前：
  premiumShares=50, P_offset=50e27, P=2.5e27

Refresh 后：
  premiumShares=100, P_offset=97.5e27, P=2.5e27 (不变!)

  但 d(P)/dt 从 2.5×R_borrow 变为 ~5.0×R_borrow (增速翻倍)
```

### 5.5 Premium 在 Supply APY 公式中的角色

$$
\begin{aligned}
\text{分子} &: P + P_{offset} = premiumShares \times drawnIndex \quad \text{（完整市值，随 index 复利，产生真实利息收入）} \\[4pt]
\text{分母（代码）} &: P \in totalAddedAssets \quad \text{（$L+S+D+P+Def-F_{acc}$）} \\[4pt]
\text{分母（经济）} &: P \notin actual\ deposits \quad \text{（$L+S+D-F_{acc}$）}
\end{aligned}
$$

**关键结论**：$P_{offset}$ 参与利息产出（分子），但不直接出现在分母中。它存在于 $premiumShares \times drawnIndex$ 的「隐藏」部分，用户看不到但利息在增长。

### 5.6 借款人的等效实际利率（双流模型）

**从借款人视角看**：虽然 utilization 公式本身不考虑 risk premium，但用户的**实际借款成本**是两条并行债务流共同作用的结果。

用户的总债务由两条流组成：

$$
D_{u,i}(t) = \underbrace{D_{u,i}^{\text{base}}(t)}_{\text{drawn debt}} + \underbrace{D_{u,i}^{\text{premium}}(t)}_{\text{premium debt}}
$$

两条流共享同一个 `drawnIndex`（按 $R_{borrow}$ 复利增长）：

$$
\begin{aligned}
D &= drawnShares_u \times drawnIndex \\[4pt]
P &= premiumShares_u \times drawnIndex - P_{offset,u}
\end{aligned}
$$

其中 $premiumShares_u = drawnShares_u \times \frac{RP_u}{10000}$。

**债务增长速率**：

$$
\frac{d}{dt}(D + P) = (drawnShares_u + premiumShares_u) \times \frac{d(drawnIndex)}{dt}
$$

代入 $\frac{d(drawnIndex)}{dt} = drawnIndex \times R_{borrow}$：

$$
\frac{d}{dt}(D + P) = drawnShares_u \times \left(1 + \frac{RP_u}{10000}\right) \times drawnIndex \times R_{borrow}
$$

因此借款人的**等效实际利率**为：

$$
\boxed{R_{u}^{\text{eff}} \approx R_{borrow} \times \left(1 + \frac{RP_u}{10000}\right)}
$$

> **解读**：$RP_u$ 越高（抵押品风险越大），借款人支付的实际利率就越高。RP=0（全 ETH 抵押）时，$R_u^{\text{eff}} = R_{borrow}$；RP=800（8% 风险溢价）时，$R_u^{\text{eff}} = 1.08 \times R_{borrow}$。

## 6. $F_{acc}$（realizedFees + unrealizedFees）完整推导

### 6.1 为什么 $F_{acc}$ 必须从「本金」中扣除

**直觉**：$D+P$ 是借款人欠的「总账单（含税）」，$F_{acc}$ 是协议已「扣留」的税款，`totalAddedAssets` 减去它才是供应者的「净收入」。

```
初始状态（刚借出）：
  L + S + D = 900，F_acc = 0
  totalAddedAssets = 900  ← 恰好等于供应者存入

一年后（5% 利息，10% 费率）：
  D_new = 800 × 1.05 = 840（全额，含协议那份）
  产生利息 40 → 协议拿走 40×10% = 4

  如果 totalAddedAssets = L + S + D_new = 940：
    → 供应者以为有 940 → 错了，里面有 4 是协议的！

  正确：totalAddedAssets = L + S + D_new - F_acc_new
    F_acc_new = 4
    totalAddedAssets = 936 = 900 + 40×(1-10%) ✓

F_acc 就是这笔「不属于供应者的累积差额」。
```

本质：**$D$ 和 $P$ 的增长是全额（含协议的份额），$F_{acc}$ 才是把「含税总额」折算成「供应者净值」的减项。**

### 6.2 为什么 V4 需要 $F_{acc}$，V3 不需要

```
V3（隐式扣费）：
  borrowIndex:     1.00 → 1.05    ← 借款人全额
  liquidityIndex:  1.00 → 1.045   ← 供应者扣费后（5%×(1-10%)=4.5% 增长）
  两条线天生有差值 = protocol fee，不需要单独变量追踪

V4（显式扣费）：
  drawnIndex:      1.00 → 1.05    ← 唯一指数，全额增长
  totalAddedAssets = L + S + D + P + Def - F_acc
  → 只有一条线，扣费必须通过显式变量 F_acc 完成
```

### 6.3 unrealizedFees 的精确公式

[AssetLogic.sol:L187-L226](file:///Users/pabloli/Documents/code/aave-v4/src/hub/libraries/AssetLogic.sol#L187-L226)

`totalOwed` 在两次指数之间的差值为：

$$\Delta totalOwed = (drawnShares + premiumShares) \times \Delta drawnIndex$$

其中 $P_{offset}$ 和 $Def$ 不变 → 完美抵消。

$$unrealizedFees = \Delta totalOwed \times \ell$$

利用 $\Delta drawnIndex / drawnIndex \approx R_{borrow} \times \Delta t$：

$$unrealizedFees \approx (D + P + P_{offset}) \times R_{borrow} \times \Delta t \times \ell$$

### 6.4 realizedFees

每次 `accrue()` 将 `unrealizedFees` 检入：

```solidity
// AssetLogic.sol:L141-L150
function accrue(IHub.Asset storage asset) internal {
    uint256 drawnIndex = asset.getDrawnIndex();
    asset.realizedFees += asset.getUnrealizedFees(drawnIndex).toUint120();
    asset.drawnIndex = drawnIndex.toUint120();
    asset.lastUpdateTimestamp = block.timestamp.toUint40();
}
```

$$realizedFees = \sum \text{(历次 accrue 触发的 unrealizedFees)} \approx \int_{0}^{t} (D + P + P_{offset}) \times R_{borrow} \times \ell \times dt$$

### 6.5 三者关系

| | 含义 | 范围 |
|---|---|------|
| unrealizedFees | 自上次 accrue 至今产生的费用 | 增量（未检入） |
| realizedFees | 所有 accrue 点已检入的费用 | 累积（已检入） |
| **$F_{acc}$** | **= realizedFees + unrealizedFees** | **总累计（完整快照）** |

### 6.6 完整导数推导（修正版）

$$
\begin{aligned}
\text{(1) drawnIndex 的增长速率：} \quad \frac{d(drawnIndex)}{dt} &= drawnIndex \times R_{borrow} \\[6pt]
\text{(2) $D$ 的增长速率：} \quad \frac{dD}{dt} &= drawnShares \times \frac{d(drawnIndex)}{dt} = D \times R_{borrow} \\[6pt]
\text{(3) $P$ 的增长速率：} \quad \frac{dP}{dt} &= premiumShares \times \frac{d(drawnIndex)}{dt} = (P + P_{offset}) \times R_{borrow} \\[6pt]
\text{(4) $F_{acc}$ 的增长速率：} \quad \frac{dF_{acc}}{dt} &= (drawnShares + premiumShares) \times \frac{d(drawnIndex)}{dt} \times \ell \\
&= (D + P + P_{offset}) \times R_{borrow} \times \ell \\[6pt]
\text{(5) $totalAddedAssets$ 的导数：} \quad \frac{d(totalAddedAssets)}{dt} &= \frac{dL}{dt} + \frac{dS}{dt} + \frac{dD}{dt} + \frac{dP}{dt} + \frac{d(Def)}{dt} - \frac{dF_{acc}}{dt} \\
&= 0 + 0 + D \times R + (P + P_{offset}) \times R + 0 - (D + P + P_{offset}) \times R \times \ell \\
&= (D + P + P_{offset}) \times R_{borrow} \times (1 - \ell)
\end{aligned}
$$

$$
\boxed{Supply\ APY = \frac{(D + P + P_{offset}) \times R_{borrow} \times (1 - \ell)}{L + S + D + P + Def - F_{acc}}}
$$

**关键发现**：$\frac{dF_{acc}}{dt}$ 在分子求导时包含 $P_{offset}$ 项，完美抵消协议份额。分母中的 $F_{acc}$ 只是快照值。

### 6.7 $F_{acc}$ 与 $\ell$ 的关系

$$
\ell = \text{费率（BPS）}，\quad F_{acc} = \text{历年累计费用金额（asset units）}
$$

$$
\frac{dF_{acc}}{dt} = (D + P + P_{offset}) \times R_{borrow} \times \ell
$$

$\ell$ 是「税率」，$F_{acc}$ 是「历年已缴税款累积总额」。

### 6.8 F_acc 的触发时机

`accrue()` 在所有 Hub 用户操作前被调用（**交互驱动**，非定时）：

| 操作 | Hub.sol 行号 |
|------|-------------|
| `add()`（供应） | [L204](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L204) |
| `remove()`（提取） | [L228](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L228) |
| `draw()`（借款） | [L253](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L253) |
| `restore()`（还款） | [L282](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L282) |
| `reportDeficit()` | [L312](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L312) |
| `eliminateDeficit()` | [L342](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L342) |
| `refreshPremium()` | [L366](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L366) |
| `payFeeShares()` | [L384](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L384) |
| `transferShares()` | [L397](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L397) |
| `sweep()` / `reclaim()` | [L410](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L410) |
| `updateAssetConfig()` | [L122](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L122) |
| `mintFeeShares()` | [L193](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L193) |

## 7. Deficit（坏账）对 Supply APY 的影响

### 7.1 双层追踪

| 层级 | 字段 | 语义 |
|------|------|------|
| Hub 聚合 | `Asset.deficitRay` | 该 asset 所有 spoke 的坏账总额 |
| Spoke 分量 | `SpokeData.deficitRay` | 该 spoke 对该 asset 的坏账 |

**不变量**：$Asset.deficitRay = \sum SpokeData.deficitRay$

### 7.2 产生与消除

- **产生**：清算后仍资不抵债 → `reportDeficit()` → `drawnShares` 减少，`deficitRay` 等量增加
- **消除**：Spoke 调用 `eliminateDeficit()` → `deficitRay` 减少，`addedShares` 销毁

### 7.3 对 Supply APY 的影响

清算产生 deficit 时，债务被核销（V3: `totalDebt` 减少；V4: `drawnShares` 减少），差额计入 deficit。

**对 supplyUsageRatio 的影响（V3 与 V4 数学等价）**：

| 版本 | 分子 | 分母 |
|------|------|------|
| V3 | `totalDebt`（清算后的剩余债务） | `totalDebt + availableLiquidity + deficit` |
| V4 | `drawnShares × drawnIndex`（清算后的剩余债务） | `drawnShares × drawnIndex + liquidity + deficitRay` |

**数学结果相同**：分子都是清算后的有效债务，分母都包含 deficit。

**V3 vs V4 的区别**仅在会计路径：
- V3：`totalDebt` 和 `deficit` 是两个独立变量，清算后 `totalDebt↓`，差额存入 `deficit`
- V4：`drawnShares↓` 和 `deficitRay↑` 在 shares 系统中等量转换，满足不变量

**经济学意义**：deficit 对应的债务无借款人支付利息，供应者通过降低的 supply APY 承担损失。

## 8. 正向与反向换算

### Borrow APY → Supply APY

**代码公式**（匹配 on-chain $totalAddedAssets$）：

$$
Supply\ APY = R_{borrow} \times \frac{(D + P + P_{offset}) \times (1 - \ell)}{L + S + D + P + Def - F_{acc}}
$$

**经济公式**（分母排除 $P$ 和 $Def$）：

$$
Supply\ APY = R_{borrow} \times \frac{(D + P + P_{offset}) \times (1 - \ell)}{L + S + D - F_{acc}}
$$

### Supply APY → Borrow APY

$$
R_{borrow} = \frac{Supply\ APY}{U_{eff} \times (1 - \ell)}
$$

其中 $U_{eff}$ 按上述公式计算。需注意分段线性模型的反推：给定 $R_{borrow}$，先反推 $U$，再判断当前处于利率曲线的哪个分段。

## 9. 数值示例

### 示例参数

| 参数 | 符号 | 值 |
|------|------|-----|
| liquidity | $L$ | 1000 |
| swept | $S$ | 200 |
| drawn | $D$ | 800 |
| premium | $P$ | 50 |
| **premium offset** | $P_{offset}$ | **200** |
| deficit | $Def$ | 0 / 100 / 850 |
| $F_{acc}$ | $F_{acc}$ | 10 |
| Borrow APY | $R_{borrow}$ | 5.00% |
| liquidityFee | $\ell$ | 10.00%（1000 BPS） |

### 修正前后对比（$Def = 0$）

| 公式版本 | 分子 | $U_{eff}$ | Supply APY | 差异 |
|---------|------|-----------|------------|------|
| ❌ **旧版** | $D + P = 850$ | $850/2040 = 0.4167$ | **1.875%** | — |
| ✅ **修正** | $D + P + P_{offset} = 1050$ | $1050/2040 = 0.5147$ | **2.316%** | **+23.5%** |

旧版把 $P_{offset} = 200$ 的利息产出忽略了。这 200 是 premium 完整市值的一部分，drawnIndex 的复利作用在整个市值上。

### 场景一：无坏账（$Def = 0$）

**代码公式（修正版）**：

$$
\begin{aligned}
U_{eff} &= \frac{800 + 50 + 200}{1000 + 200 + 800 + 50 + 0 - 10} = \frac{1050}{2040} = 0.5147 \\[6pt]
Supply\ APY &= 5\% \times 0.5147 \times 0.90 = \mathbf{2.316\%}
\end{aligned}
$$

**经济公式（修正版）**：

$$
\begin{aligned}
U_{eff}^{econ} &= \frac{1050}{1000 + 200 + 800 - 10} = \frac{1050}{1990} = 0.5276 \\[6pt]
Supply\ APY &= 5\% \times 0.5276 \times 0.90 = \mathbf{2.374\%}
\end{aligned}
$$

### 场景二：有坏账（$Def = 100$）

**代码公式（修正版）**：

$$
\begin{aligned}
U_{eff} &= \frac{1050}{1000 + 200 + 800 + 50 + 100 - 10} = \frac{1050}{2140} = 0.4907 \\[6pt]
Supply\ APY &= 5\% \times 0.4907 \times 0.90 = \mathbf{2.208\%} \quad \text{（降幅 } -4.7\%\text{）}
\end{aligned}
$$

**经济公式（修正版）**：不受 $Def$ 影响，仍为 $\mathbf{2.374\%}$。

### 场景三：严重坏账（$Def = 850$）

**代码公式（修正版）**：

$$
\begin{aligned}
U_{eff} &= \frac{1050}{2990} = 0.3512 \\[6pt]
Supply\ APY &= 5\% \times 0.3512 \times 0.90 = \mathbf{1.580\%} \quad \text{（降幅 } -32\%\text{）}
\end{aligned}
$$

### 借款人等效利率示例

假设借款用户 $RP_u = 800$（8% 风险溢价），市场份额利率 $R_{borrow} = 5\%$：

$$
R_u^{\text{eff}} \approx 5\% \times \left(1 + \frac{800}{10000}\right) = 5\% \times 1.08 = \mathbf{5.40\%}
$$

相比纯 ETH 抵押用户（$RP=0$）支付的 5.00%，该用户多付 0.40%。

## 10. 前端获取 Supply APY

由于 V4 **没有显式 `supplyRate` 变量**，前端获取 Supply APY 需要：

### 方法 A：两次兑换率做差（推荐）

```typescript
const rate1 = hub.previewRemoveByShares(assetId, 1e18)
// ... 等待一段时间 ...
const rate2 = hub.previewRemoveByShares(assetId, 1e18)
const timeDeltaDays = (t2 - t1) / 86400
const supplyAPY = (Number(rate2) / Number(rate1)) ** (365 / timeDeltaDays) - 1
```

### 方法 B：公式实时计算（修正版）

```typescript
const drawnRate = hub.getAssetDrawnRate(assetId)           // RAY 精度
const drawnIndex = hub.getAssetDrawnIndex(assetId)         // RAY 精度
const asset = hub.getAsset(assetId)

// 核心计算（修正版：分子 = 完整市值 = premiumShares × drawnIndex）
const D = (asset.drawnShares * drawnIndex) / 1e27
const premiumFull = (asset.premiumShares * drawnIndex) / 1e27  // = P + P_offset
const P = premiumFull - (asset.premiumOffsetRay / 1e27)        // 仅「已变现」部分

const totalAdded = (
    asset.liquidity +
    asset.swept +
    D +
    P +
    (asset.deficitRay / 1e27) -
    F_acc
)

const U_eff = premiumFull / totalAdded
const supplyAPY = (drawnRate / 1e27) * U_eff * (1 - asset.liquidityFee / 10000)
```

---

# 单位转换速查

| 精度 | 常量 | 值 | 用途 |
|------|------|-----|------|
| **ray** | `RAY` | $10^{27}$ | `liquidityRate`/`drawnRate`, `liquidityIndex`/`drawnIndex` |
| **wad** | `WAD` | $10^{18}$ | 以 ETH 为单位的金额 |
| **bps** | `PERCENTAGE_FACTOR` | $10000$ | `reserveFactor`/`liquidityFee`, 策略参数 |
| **ray 与 bps 互转** | — | $10^{23}$ | $bpsToRay(n) = n \times 10^{23}$ |

### 转换示例

```solidity
// 5% APR → ray
5% = 0.05 × 1e27 = 5e25

// 10% reserveFactor/liquidityFee (bps) → percentMul 输入
10% = 1000 bps
percentMul(value, 10000 - 1000) = value × (100% - 10%)

// V4 利率策略参数 (BPS → 实际值)
optimalUsageRatio = 8000 → 80% 利用率拐点
```

---

# 关键合约文件清单

## V3.6 合约

| 文件 | 作用 |
|------|------|
| `src/contracts/misc/DefaultReserveInterestRateStrategyV2.sol` | 利率策略核心实现；含 `calculateInterestRates()` |
| `src/contracts/protocol/libraries/logic/ReserveLogic.sol` | 准备金状态更新；调用利率策略 |
| `src/contracts/protocol/libraries/types/DataTypes.sol` | 数据结构 |
| `src/contracts/protocol/libraries/math/WadRayMath.sol` | ray/wad 数学运算 |
| `src/contracts/protocol/libraries/math/PercentageMath.sol` | bps 百分比运算 |
| `src/contracts/helpers/AaveProtocolDataProvider.sol` | 链上数据查询 helper |
| `src/contracts/helpers/UiPoolDataProviderV3.sol` | 前端批量数据查询 helper |

## V4 合约

| 文件 | 作用 |
|------|------|
| `src/hub/AssetInterestRateStrategy.sol` | 利率策略核心实现；`calculateInterestRate()` |
| `src/hub/libraries/AssetLogic.sol` | 资产逻辑；`totalAddedAssets`、`accrue`、`getUnrealizedFees` |
| `src/hub/libraries/Premium.sol` | Premium 计算 |
| `src/hub/Hub.sol` | Hub 主合约；所有用户操作 |
| `src/hub/interfaces/IHub.sol` | Asset 和 SpokeData 结构体定义 |
| `src/hub/interfaces/IAssetInterestRateStrategy.sol` | InterestRateData 结构体 |
| `src/spoke/libraries/UserPositionUtils.sol` | `calculatePremiumDelta`；$P_{offset}$ 计算 |
| `src/spoke/Spoke.sol` | `_notifyRiskPremiumUpdate`；refresh 触发 |
| `docs/overview.md` | 系统架构概览 |
| `docs/deficit-analysis.md` | deficit 双层追踪和影响分析 |
