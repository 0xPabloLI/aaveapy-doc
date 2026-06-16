# Merkl Distribution Types 完整分类

**文档版本**: 2026-06-16  
**状态**: 研究完成，TARGET_TOTAL_APR 类型已实现  
**数据来源**: [Merkl 官方文档](https://docs.merkl.xyz/merkl-mechanisms/distributions) + [Schema API](https://api.merkl.xyz/v4/schemas/distributionMethod) + 实际 API 数据验证

---

## 1. 四大 Distribution Type Family

Merkl 有 4 种分发模型 Family，对应 4 种经济行为：

| # | Family | distributionMethod | APR cap 字段 | 当前 APR 字段 | 与 TVL 的关系 |
|---|---|---|---|---|---|
| 1 | Variable Reward Rate | `DUTCH_AUCTION` | 无 cap | top-level `apr` | ❌ APR 被 TVL 被动稀释，budget_rate 固定 |
| 2 | Fixed Reward Rate | `FIX_APR` | `distributionSettings.apr` | top-level `apr` | ⚠️ APR 值不随 TVL 变化，但 cost ∝ TVL |
| 3 | Capped Reward Rate | `MAX_APR` | `distributionSettings.apr` | top-level `apr` | ✅ APR = min(cap, budget_rate / TVL) |
| 4 | Target Total APR | 7 种子类型（见下） | `distributionSettings.targetAPR` | top-level `apr` | ✅ daily cost = Merkl APR × TVL |

---

## 2. Target Total APR 的 7 种子类型

### 2.1 总览

| # | distributionMethod | 描述 | APR 公式 | 额外字段 | budget-bound mode |
|---|---|---|---|---|---|
| 1 | `AAVE_NET_APR` | 衡贴 Aave V3 native APR 到 target | `max(targetAPR - aaveNativeAPR, 0)` | `assetId` | `MAX_APR` |
| 2 | `AAVE_V4_NET_APR` | 衡贴 Aave V4 native APR 到 target | `max(targetAPR - aaveV4NativeAPR, 0)` | `assetId`, `hubAddress`, `side` | `MAX_APR` |
| 3 | `ERC4626_APR` | 衡贴 ERC4626 vault APR 到 target | `max(targetAPR - vaultAPR, 0)` | - | `MAX_APR` |
| 4 | `ERC4626_SPREAD_CAPPED` | 同上，但 Merkl 实付 APR 有 cap | `min(max(targetAPR - vaultAPR, 0), cap)` | `cap` | `FIX_APR` |
| 5 | `ERC4626_TARGET_APR_WITH_MERKL` | 还要扣除已有 Merkl opportunity APR | `max(targetAPR - vaultAPR - merklOppAPR, 0)` | - | 待验证 |
| 6 | `SOFR_SPREAD_RATCHET` | 动态 target（SOFR + TVL 分层 spread） | `max(SOFR + spread(maxTVL) - vaultAPR, 0)` | spread tier table | 待验证 |
| 7 | `DEEL_DISTRIBUTION` | 衡贴到 2.5% effective APR + SOFR treasury skim | `max(0.025 - vaultAPR - merklOppAPR, 0)` | treasury address | 待验证 |

### 2.2 详细说明

#### `AAVE_NET_APR`

- **用途**: 衡贴 Aave V3 用户的 native APR 到目标值
- **经济模型**: Merkl 只支付差额，native APR ≥ target 时不付费
- **实际验证**: campaign 13116567236794890552，targetAPR=0.047 (4.7%)，mode=MAX_APR
- **Aave 关联**: V3 market

#### `AAVE_V4_NET_APR`

- **用途**: 衡贴 Aave V4 用户的 native APR 到目标值
- **与 AAVE_NET_APR 的区别**: 针对V4 spoke/hub 架构，distributionSettings 额外有 `hubAddress` 和 `side` 字段
- **实际验证**: campaign 8647796357084493685，targetAPR=0.077 (7.7%)，mode=MAX_APR；campaign 12662496063613214537，targetAPR=0.0583 (5.83%)，mode=MAX_APR
- **Aave 关联**: V4 market

#### `ERC4626_APR`

- **用途**: 衡贴 ERC4626 vault 的 native APR 到目标值
- **与 AAVE_NET_APR 的区别**: vault 来源不同（通用 ERC4626 而非 Aave）
- **实际验证**: campaign 4553084979058180369，targetAPR 字段存在，mode=MAX_APR

#### `ERC4626_SPREAD_CAPPED`

- **用途**: 与 ERC4626_APR 相同，但 Merkl 实付 APR 有一个额外 cap 上限
- **双重 cap 机制**: 
  - `targetAPR` = 目标总 APR（用户看到的 total APR）
  - `cap` = Merkl 最多支付的 APR（防止 Merkl 支付过多）
  - 实际 Merkl APR = `min(max(targetAPR - vaultAPR, 0), cap)`
- **实际验证**: campaign 4472263355938713809 (Morpho)，targetAPR=0.035 (3.5%)，cap=0.0025 (0.25%)，mode=FIX_APR
- **⚠️ 这是唯一拥有双重 cap 的子类型**

#### `ERC4626_TARGET_APR_WITH_MERKL`

- **用途**: 衡贴时还要扣除已有 Merkl opportunity APR
- **与 ERC4626_APR 的区别**: `targetAPR - vaultAPR - merklOppAPR`，多减了一个 merklOppAPR
- **适用场景**: vault 上已有其他 Merkl campaign，此 campaign 要在此基础上继续衡贴
- **⚠️ 目前未在 Aave/Morpho 的实际数据中发现活跃 campaign，mode 待验证**

#### `SOFR_SPREAD_RATCHET`

- **用途**: 动态 target APR，基于 SOFR + TVL 分层 spread
- **双重 TVL 依赖**: 
  1. target 本身随 maxTVL 变化（ratchet: spread 只紧不松）
  2. daily cost = Merkl APR × TVL
- **SOFR**: NY Fed Secured Overnight Financing Rate（30 天平均），每次 engine run 刷新
- **Spread tier**: 随 TVL 增长而收紧（如 $1B 以下 336bps，$7B+ 仅 51bps）
- **One-way ratchet**: spread 只收紧不放松——即使 TVL 下降，target 也不会回升
- **⚠️ 目前未在实际数据中发现活跃 campaign，mode 待验证**

#### `DEEL_DISTRIBUTION`

- **用途**: 衡贴 vault holders 到 2.5% effective APR，同时将 SOFR 衍生的 treasury skim 发给指定地址
- **与 ERC4626_TARGET_APR_WITH_MERKL 的关系**: 
  - 本质是 ERC4626_TARGET_APR_WITH_MERKL 的特化版（targetAPR 固定 2.5%）
  - **额外行为**: treasury skim（基于 SOFR 利率计算一笔金额发给指定地址）
- **treasury skim 计算方式**: Merkl Schema API 和官方文档均未给出精确公式和比例。只说明是 "SOFR-derived"（基于 SOFR 利率动态调整），未暴露计算参数或系数。具体金额由 Merkl 引擎内部决定，API 不返回
- **treasury skim 是否会超过 targetAPR?**: 不会影响用户 APR——treasury skim 是从 campaign budget 中额外扣减的独立流。如果 budget 不足以同时支付用户衡贴 + treasury skim，则触发 budget-bound fallback
- **依赖**: 需要运行在 vault-tracking campaign (MORPHOVAULT, ERC20LOGPROCESSOR) 之上，使用其 TVL 数据
- **⚠️ 目前未在实际数据中发现活跃 campaign，mode 待验证**

---

## 2.3 distributionType → CampaignForecastType 映射表（Level 2）

代码中的 2 级分类逻辑：

1. **Level 2**: `distributionType` 精确匹配 → 返回 `CampaignForecastType`
2. **Level 3 fallback**: Level 2 未命中时，若 `distributionSettings.targetAPR` 存在且为正数 → 返回 `TARGET_TOTAL_APR`
3. 返回 `null` → campaign 被跳过（无 forecast 字段，但仍有 `campaignApr`）

| distributionType | → CampaignForecastType | Note |
|---|---|---|
| `MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE` | `MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE` | |
| `MAX_REWARD_VALUE_PER_LIQUIDITY_AMOUNT` | `MAX_REWARD_VALUE_PER_LIQUIDITY_AMOUNT` | |
| `FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE` | `FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE` | |
| `FIX_REWARD_AMOUNT_PER_LIQUIDITY_VALUE` | `FIX_REWARD_AMOUNT_PER_LIQUIDITY_VALUE` | |
| `FIX_REWARD_AMOUNT_PER_LIQUIDITY_AMOUNT` | `FIX_REWARD_AMOUNT_PER_LIQUIDITY_AMOUNT` | |
| `DUTCH_AUCTION` | `DUTCH_AUCTION` | |
| `AAVE_NET_APR` | `TARGET_TOTAL_APR` | |
| `AAVE_V4_NET_APR` | `TARGET_TOTAL_APR` | |
| `ERC4626_APR` | `TARGET_TOTAL_APR` | |
| `ERC4626_SPREAD_CAPPED` | `TARGET_TOTAL_APR` | |
| `ERC4626_TARGET_APR_WITH_MERKL` | `TARGET_TOTAL_APR` | |
| `SOFR_SPREAD_RATCHET` | `TARGET_TOTAL_APR` | |
| `DEEL_DISTRIBUTION` | `TARGET_TOTAL_APR` | |

**Level 3 fallback**: 如果一个 campaign 的 `distributionType` 不在上述列表中，但 `distributionSettings.targetAPR` 存在且为正数，则归为 `TARGET_TOTAL_APR`。这提供了前向兼容——Merkl 新增 `distributionType` 变体时不需要改代码。

**Level 1 (distributionMethod) 已移除**: 在 Aave 场景下 `distributionMethod` 始终为空字符串，Level 1 从未命中，已于 2026-06-16 移除。

---

## 2.4 TARGET_TOTAL_APR 对前端 APR 的影响

TARGET_TOTAL_APR 类型的 `campaignApr` 语义与其他类型不同：

### 其他类型的 `campaignApr`
- `MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE` / `FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE` / `DUTCH_AUCTION`: `campaignApr` = Merkl 实付 APR（可直接使用）

### TARGET_TOTAL_APR 的 `campaignApr`
- **`campaignApr` = Merkl 实付 APR**（后端已做 APR↔APY 转换后减去 nativeAPY，再转回 APR）
- **`aprCap` = targetAPR 原始值**（总 APR 目标，未做转换）

后端转换公式（月复利 n=12，与 Aave interface 和前端 `rateCalculations.ts` 一致）：

```
Supply 侧: incentiveAPY = convertAprToApy(targetAPR) - nativeAPY
           如果 incentiveAPY ≤ 0 → campaignApr = 0
           否则 campaignApr = convertApyToApr(incentiveAPY)

Borrow 侧: incentiveAPY = nativeAPY - convertAprToApy(targetAPR)
           如果 incentiveAPY ≤ 0 → campaignApr = 0
           否则 campaignApr = convertApyToApr(incentiveAPY)
```

**前端处理**：`campaignApr` 可以和其他类型一样直接使用，无需额外转换。前端最终展示时再 APR→APY 统一转换即可。

## 3. Budget-bound Behavior (`mode` 字段)

### 3.1 只有 Target Total APR 才有 mode 字段

| distributionMethod | mode 字段存在 | 说明 |
|---|---|---|
| `DUTCH_AUCTION` | ❌ 无 | budget 固定分发，不存在不够用的问题 |
| `FIX_APR` | ❌ 无 | budget 用尽 → campaign 提前结束（这是其固有行为，无需声明） |
| `MAX_APR` | ❌ 无 | APR 自然被 TVL 稀释（这是其固有行为，无需声明） |
| `AAVE_NET_APR` | ✅ `MAX_APR` 或 `FIX_APR` | 需要选择 budget 用尽后的策略 |
| `AAVE_V4_NET_APR` | ✅ 同上 | 同上 |
| `ERC4626_APR` | ✅ 同上 | 同上 |
| `ERC4626_SPREAD_CAPPED` | ✅ 同上 | 同上 |
| 其他 Target Total APR 子类型 | ✅ 待验证 | 同上 |

### 3.2 mode 的两种值及语义

| mode 值 | budget 用尽后行为 | 类比 | 对用户的影响 |
|---|---|---|---|
| `MAX_APR` | dilutive — APR 降至 target 以下 | 像 Capped Reward Rate | 用户 APR 低于 target，但 campaign 持续到结束 |
| `FIX_APR` | early-end — campaign 提前结束 | 像 Fixed Reward Rate | 用户 APR 维持 target 直到 campaign 突然结束 |

**注意**: mode 值 `MAX_APR` / `FIX_APR` 与 distributionMethod 的 `MAX_APR` / `FIX_APR` **同名但语义不同**。mode 是 "budget 用尽后的 fallback 策略"，不是 "分发类型"。

### 3.3 mode 的 API 路径

```
campaign.params.distributionMethodParameters.distributionSettings.mode
```

代码中已有读取：`merklForecastService.ts:537`

---

## 4. Capped Reward Rate (MAX_APR) 的 Dilutive 行为

### 4.1 APR 计算公式

```
APR = min(cap, budget_rate / TVL)
```

其中 `budget_rate` = 每秒分发量（= totalBudget / durationSeconds），`cap` = `distributionSettings.apr`

### 4.2 Dilutive 不是"最后一天"才发生

- 当 TVL 较低时：`budget_rate / TVL > cap` → APR = cap，部分 budget 花不出去
- 当 TVL 超过 `budget_rate / cap` 时：APR 开始低于 cap → **dilutive 开始**
- 此后 TVL 越高，APR 越低，贯穿整个 campaign 剩余期

### 4.3 展开示例：Capped Reward Rate (MAX_APR) 的 Dilutive 过程

**场景**：Campaign budget = 10,000 tokens，30 天，cap = 15%

**budget_rate 计算**：
```
budget_rate = totalBudget / durationSeconds = 10,000 / (30 × 86400) = 0.003858 tokens/秒
daily_budget_rate = 10,000 / 30 = 333.33 tokens/天
```

**APR 公式**：`APR = min(cap, daily_budget_rate_in_usd / TVL)`

为简化，假设 1 token = $1：

| 天数 | TVL | daily_budget_rate/TVL | 实际 APR | 日消耗 | 累计消耗 | 说明 |
|---|---|---|---|---|---|---|
| 1 | $100K | 121.7% | 15% (cap) | $41.10 | $41.10 | 大部分预算未花费 |
| 10 | $100K | 121.7% | 15% | $41.10 | $411 | 预算远未用尽 |
| 11 | $500K | 24.3% | 15% (cap) | $205.48 | $616 | TVL 增加，预算利用率提高 |
| 15 | $800K | 15.2% | 15% (cap) | $328.77 | $1,929 | 刚好在 cap 边界 |
| 16 | $1M | 12.2% | **12.2%** | $333.33 | $2,262 | ⚠️ **开始 dilutive** |
| 20 | $1.5M | 8.1% | **8.1%** | $333.33 | $3,595 | 持续 dilutive |
| 25 | $2M | 6.1% | **6.1%** | $333.33 | $5,262 | 严重 dilutive |
| 30 | $2M | 6.1% | **6.1%** | $333.33 | $6,929 | **未用尽 budget** (剩余 $3,071 退给 creator) |

**关键观察**：
1. **Dilutive 从第 16 天开始**，不是最后一天
2. **TVL 超过阈值 `$333.33 / 15% = $2,222` 时 APR 就低于 cap**（按日算的简化阈值）
3. **低 TVL 时预算花不完**，最终剩余 budget 退还给 creator
4. **budget_rate 是按整个 campaign 天数均分的**（`totalBudget / totalDays`），不是按剩余天数调整

### 4.4 Target Total APR 的 Dilutive（mode=MAX_APR 时）

Target Total APR 的 dilutive 与 Capped Reward Rate 不同：

- **Capped Reward Rate**: dilutive 发生在 TVL 高时（budget 不够按 cap 支付所有人）
- **Target Total APR (mode=MAX_APR)**: dilutive 发生在 budget 不够维持 target APR 时
  - 原因：TVL × (targetAPR - nativeAPR) 的日消耗超过 budget 剩余 / 剩余天数
  - 结果：实际 APR 降到 target 以下，但 campaign 继续到结束

**Target Total APR (mode=FIX_APR)**: 不 dilutive——只要 budget 够就维持 target，budget 用完 campaign 立即结束

---

## 5. Forecast Simulation 需要的额外字段

### 5.1 各 distributionMethod 需要的字段清单

| distributionMethod | APR cap 来源 | 额外字段 | 字段路径 |
|---|---|---|---|
| `MAX_APR` | `distributionSettings.apr` | 无 | - |
| `FIX_APR` | `distributionSettings.apr` | 无 | - |
| `DUTCH_AUCTION` | 无 | 无 | - |
| `AAVE_NET_APR` | `distributionSettings.targetAPR` | 无 | - |
| `AAVE_V4_NET_APR` | `distributionSettings.targetAPR` | 无 | - |
| `ERC4626_APR` | `distributionSettings.targetAPR` | 无 | - |
| `ERC4626_SPREAD_CAPPED` | `distributionSettings.targetAPR` | `cap` | `distributionSettings.cap` |
| `ERC4626_TARGET_APR_WITH_MERKL` | `distributionSettings.targetAPR` | 无（merklOppAPR 来自运行时） | - |
| `SOFR_SPREAD_RATCHET` | `distributionSettings.targetAPR` | spread tier table | 待确认路径 |
| `DEEL_DISTRIBUTION` | `distributionSettings.targetAPR` | 无（treasury skim 不影响用户 APR） | - |

### 5.2 字段路径统一

所有 Target Total APR 子类型的 APR cap 统一在：
```
campaign.params.distributionMethodParameters.distributionSettings.targetAPR
```

当前 APR（top-level，percentage 格式）在：
```
campaign.apr
```

注意单位差异：
- `targetAPR` = decimal 格式（如 0.047 = 4.7%）
- `apr` (top-level) = percentage 格式（如 4.7 = 4.7%）
- `distributionSettings.apr` (MAX_APR/FIX_APR) = decimal 格式（如 0.034 = 3.4%）

---

## 6. Fixed Reward Rate 与 Capped Reward Rate 的 distributionType 变体

### 6.1 命名规律

`distributionType` 命名格式：`{MAX/FIX}_REWARD_{VALUE/AMOUNT}_PER_LIQUIDITY_{VALUE/AMOUNT}`

- `VALUE` = dollar 计价
- `AMOUNT` = token 数量计价

**组合出 6 种 distributionType**（FIX 3 种 + MAX 3 种）：

| distributionType | 含义 | rewardTokenPricing | targetTokenPricing | 实际数据存在 |
|---|---|---|---|---|
| `FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE` | 每 $1 流动性固定 $1 奖励 → **Fixed dollar per dollar** | `true` | `true` | ✅ 大量 (Arbitrum, Base 等) |
| `FIX_REWARD_AMOUNT_PER_LIQUIDITY_VALUE` | 每 $1 流动性固定 N 个 token → **Fixed token per dollar** | `false` | `true` | ✅ Base (IPOR), BSC |
| `FIX_REWARD_AMOUNT_PER_LIQUIDITY_AMOUNT` | 每 N 个 target token 固定 N 个 reward token → **Fixed token per token** | `false` | `false` | ✅ Angle (chain 146) |
| `MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE` | Capped: 每 $1 流动性最多 $1 奖励 → **Capped dollar per dollar** | `true` | `true` | ✅ 大量 |
| `MAX_REWARD_VALUE_PER_LIQUIDITY_AMOUNT` | Capped: 每 N 个 target token 最多 $1 奖励 → **Capped dollar per token** | `true` | `false` | ❌ 未找到实际数据 |
| `MAX_REWARD_AMOUNT_PER_LIQUIDITY_VALUE` | Capped: 每 $1 流动性最多 N 个 token → **Capped token per dollar** | `false` | `true` | ❌ 未找到实际数据 |

### 6.2 rewardTokenPricing 与 targetTokenPricing 的含义推断

| 字段 | `true` | `false` |
|---|---|---|
| `rewardTokenPricing` | reward token 有 USD 价格，APR 以 dollar 计 | reward token 无价格（points token），APR 以 token 数量计 |
| `targetTokenPricing` | target token（被激励的资产）有 USD 价格 | target token 无价格 |

**⚠️ 此推断基于实际数据观察，Merkl 官方文档未明确说明这两个字段的语义。**

### 6.3 实际 API 验证数据

| 属性 | Fixed dollar per dollar | Fixed token per dollar | Fixed token per token |
|---|---|---|---|
| Campaign ID | 14885251677142679755 | 6132312600992582704 | (chain 146, AnglesPoint-S2) |
| distributionType | `FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE` | `FIX_REWARD_AMOUNT_PER_LIQUIDITY_VALUE` | `FIX_REWARD_AMOUNT_PER_LIQUIDITY_AMOUNT` |
| rewardTokenPricing | `true` | `false` | `false` |
| targetTokenPricing | `true` | `true` | `false` |
| rewardToken.price | 有值 (0.09) | `null` | `null` |
| distributionSettings.apr | 0.06 (decimal, dollar APR) | 18.25 (decimal, token APR) | (token APR) |
| top-level apr | 6 (percentage) | 0 (无法换算 USD APR) | 0 |

### 6.4 对用户 APR 的影响

| 类型 | USD APR | Token 数量 | 适用场景 |
|---|---|---|---|
| Fixed dollar per dollar | ✅ 固定 | 随 token 价格变化 | 正常有价格的 token 激励 |
| Fixed token per dollar | 随 token 价格变化 | ✅ 固定 | Points token / 无价格 token 激励 |
| Fixed token per token | 随双方 token 价格变化 | ✅ 固定 | 无价格的 token 激励无价格的资产 |

### 6.5 Aave 数据现状

**Aave 目前只有 `FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE`（Fixed dollar per dollar）**，从未出现过 `AMOUNT` 变体。

Aave breakdown 中所有 distributionType：`MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE`、`AAVE_NET_APR`、`AAVE_V4_NET_APR`、`DUTCH_AUCTION`。

### 6.6 当前代码的映射问题

当前 `DISTRIBUTION_TYPE_PATTERNS` 将三种 FIX 变体**全部映射到 `FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE`**：

```typescript
{ pattern: 'FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE', result: 'FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE' },
{ pattern: 'FIX_REWARD_AMOUNT_PER_LIQUIDITY_VALUE', result: 'FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE' },  // 语义不准确
{ pattern: 'FIX_REWARD_AMOUNT_PER_LIQUIDITY_AMOUNT', result: 'FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE' },  // 语义不准确
```

同理 MAX 的两种（`MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE` 和 `MAX_REWARD_VALUE_PER_LIQUIDITY_AMOUNT`）也被合并了。

**这应该作为后续优化处理**——新增 `ForecastCampaignTypeLite` 枚举值来精确区分 `VALUE` vs `AMOUNT` 变体。当前不阻塞 TARGET_TOTAL_APR 的 P0 修复，因为：
1. FIX 的三种变体当前**都能正常工作**（不报错），只是语义标签不精确
2. TARGET_TOTAL_APR 是 P0 bug（3 个 campaign 持续报错），应优先修复
3. 变体区分需要前端配合改动，影响面更大

---

## 7. Aave Campaign 实际数据验证

### 7.1 3 个 Failing Campaign（2026-06-01 起持续报错）

| Campaign ID | distributionMethod | distributionType | targetAPR | mode | top-level apr |
|---|---|---|---|---|---|
| 13116567236794890552 | `AAVE_NET_APR` | `AAVE_NET_APR` | 0.047 | `MAX_APR` | 4.7 |
| 12662496063613214537 | `AAVE_V4_NET_APR` | `AAVE_V4_NET_APR` | 0.0583 | `MAX_APR` | 5.83 |
| 8647796357084493685 | `AAVE_V4_NET_APR` | `AAVE_V4_NET_APR` | 0.077 | `MAX_APR` | 7.7 |

### 7.2 所有 Aave Campaign 的 distributionMethod 分布

| distributionMethod | 数量 | has apr | has targetAPR | has cap |
|---|---|---|---|---|
| `MAX_APR` | ~166 | ✅ | ❌ | ❌ |
| `AAVE_NET_APR` | 1 | ❌ | ✅ | ❌ |
| `AAVE_V4_NET_APR` | 2 | ❌ | ✅ | ❌ |
| `DUTCH_AUCTION` | ~1 | ❌ | ❌ | ❌ |

### 7.3 Morpho Campaign 分布（用于 ERC4626 验证）

| distributionMethod | 数量 | has apr | has targetAPR | has cap | mode |
|---|---|---|---|---|---|
| `MAX_APR` | ~264 | ✅ | ❌ | ❌ | NONE |
| `ERC4626_APR` | 少量 | ❌ | ✅ | ❌ | MAX_APR |
| `ERC4626_SPREAD_CAPPED` | 少量 | ❌ | ✅ | ✅ | FIX_APR |
| `DUTCH_AUCTION` | 少量 | ❌ | ❌ | ❌ | NONE |

---

## 8. 当前代码问题总结

1. **`extractMaxApr` 只读 `distributionSettings.apr`，不读 `distributionSettings.targetAPR`** → Target Total APR 类型全部报 "Missing APR cap"
2. **Lite file builder (`buildCampaignSnapshotLiteForForecastFile`) 只序列化 `apr`，不序列化 `targetAPR`** → 后端从 lite file 无法获取 targetAPR
3. **`buildForecastFieldsLite` 只对 MAX/FIX 类型提取 aprCap**，且只读 `apr` 字段 → Target Total APR 的 aprCap 未被提取
4. **`normalizeCampaignType` 将 `AAVE_NET_APR`/`AAVE_V4_NET_APR`/`ERC4626_APR` 映射到 `MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE`** → 语义错误，应映射到新的 `TARGET_TOTAL_APR` 类型
5. **`ERC4626_SPREAD_CAPPED` 的 `cap` 字段完全未被读取或存储**
