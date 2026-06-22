# Handoff: TARGET_TOTAL_APR 前端适配

**日期**: 2026-06-16
**对接人**: 前端 session
**父 Issue**: AAV-833

---

## 1. 背景

Merkl 有一种"Target Total APR"分发模式：Merkl 只支付 `targetAPR - nativeAPR` 的差额，不是全额。后端已完成全部适配，API 已输出 `campaignType: "TARGET_TOTAL_APR"` + `budgetBoundMode` + 转换后的 `campaignApr`。

**前端当前问题**：`TARGET_TOTAL_APR` 不在 `merklForecast.ts` 的已知类型列表中，走的是 Dutch-auction 通用路径（无 APR cap、无 rate limiting），**forecast 模拟结果不准确**。

---

## 2. API 输出示例

```json
{
  "campaignApr": 2.1,
  "campaignStartedAt": "2026-06-08T12:00:00.000Z",
  "campaignEndedAt": "2026-06-15T12:00:00.000Z",
  "campaignId": "13116567236794890552",
  "whitelistOnly": false,
  "campaignType": "TARGET_TOTAL_APR",
  "totalBudget": 448506.567296102,
  "aprCap": 4.7,
  "latestTvl": 568482827.0171667,
  "plannedDaily": 64072.366756586,
  "budgetBoundMode": "MAX_APR"
}
```

| 字段 | 说明 |
|---|---|
| `campaignApr` | **Merkl 实付 APR**（后端已做 APR↔APY 转换 + 减 nativeAPY），前端直接用，和其他类型一样 |
| `aprCap` | **总 APR 目标**（原始 targetAPR，未转换），不是"Merkl 实付上限" |
| `campaignType` | `"TARGET_TOTAL_APR"` |
| `budgetBoundMode` | `"MAX_APR"` 或 `"FIX_APR"`，决定 budget 用尽后的行为 |

---

## 3. campaignApr 语义（所有类型统一）

| campaignType | campaignApr 含义 | 前端使用方式 |
|---|---|---|
| MAX / FIX / DUTCH | Merkl 实付 APR | 直接使用 |
| **TARGET_TOTAL_APR** | **Merkl 实付 APR**（后端已转换） | **直接使用，无需手动减 nativeAPY** |

后端转换公式（月复利 n=12，与前端 `rateCalculations.ts` 一致）：

```
Supply: incentiveAPY = convertAprToApy(targetAPR) - nativeAPY
        如果 ≤ 0 → campaignApr = 0，否则 campaignApr = convertApyToApr(incentiveAPY)
Borrow: incentiveAPY = nativeAPY - convertAprToApy(targetAPR)
        如果 ≤ 0 → campaignApr = 0，否则 campaignApr = convertApyToApr(incentiveAPY)
```

---

## 4. aprCap 语义差异（需注意）

| campaignType | aprCap 含义 |
|---|---|
| MAX | Merkl 实付 APR 上限 |
| FIX | Merkl 实付 APR 固定值 |
| **TARGET_TOTAL_APR** | **总 APR 目标**（用户看到的 total APR，包含 native 部分） |
| DUTCH_AUCTION | 无 cap |

TARGET_TOTAL_APR 的 `aprCap` 不等于 Merkl 实付部分。但 `campaignApr` 已经是实付值了，前端展示 headline APR 时用 `campaignApr` 即可。`aprCap` 可用于展示"目标 APR = X%"。

---

## 5. budgetBoundMode

TARGET_TOTAL_APR 独有的正交维度，决定 budget 用尽后的行为：

| budgetBoundMode | budget 充足时 | budget 不足时 | 对应 forecast 路径 |
|---|---|---|---|
| `MAX_APR` | APR = target（实付） | APR 被 TVL 稀释降到 target 以下 | **走 MAX 路径**（dilutive, `requiredDaily`） |
| `FIX_APR` | APR = target（实付） | campaign 提前结束 | **走 FIX 路径**（early-end, `fixRewardableDays`） |

当前 3 个活跃 campaign 全部是 `MAX_APR`。

后端已根据 `budgetBoundMode` 动态选择 field rules：
- `MAX_APR` → 输出 `plannedDaily` + `requiredDaily`
- `FIX_APR` → 省略 `plannedDaily`，不输出 `requiredDaily`

---

## 6. 前端需要的改动

### 6.1 类型 + Schema：添加 `budgetBoundMode`

**文件**: `src/types/aave.ts` — `MerklCampaignBreakdown` 接口

```typescript
budgetBoundMode?: string;  // 新增：'MAX_APR' | 'FIX_APR'
```

**文件**: `src/lib/apiSchemas.ts` — 对应 Zod schema

```typescript
budgetBoundMode: z.string().optional(),
```

### 6.2 `merklForecast.ts`：TARGET_TOTAL_APR 按 budgetBoundMode 归入正确路径

**文件**: `src/lib/merklForecast.ts` (行 51-57)

当前 `TARGET_TOTAL_APR` 不匹配任何已知类型 → 走 Dutch-auction 路径（错误）。改为根据 `budgetBoundMode` 归入 MAX 或 FIX：

```typescript
const isMaxAprCampaign =
  forecastState.campaignType === 'MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE' ||
  forecastState.campaignType === 'MAX_REWARD_VALUE_PER_LIQUIDITY_AMOUNT' ||
  (forecastState.campaignType === 'TARGET_TOTAL_APR' && forecastState.budgetBoundMode === 'MAX_APR');
const isFixAprCampaign =
  forecastState.campaignType === 'FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE' ||
  forecastState.campaignType === 'FIX_REWARD_AMOUNT_PER_LIQUIDITY_VALUE' ||
  forecastState.campaignType === 'FIX_REWARD_AMOUNT_PER_LIQUIDITY_AMOUNT' ||
  (forecastState.campaignType === 'TARGET_TOTAL_APR' && forecastState.budgetBoundMode === 'FIX_APR');
```

`forecastState` 返回类型也需要加 `budgetBoundMode`（来自 `mergeForecastState`）。

### 6.3 `rateSimulationCalculator.ts`：FORECAST_REQUIRING_CAMPAIGN_TYPES 添加 TARGET_TOTAL_APR

**文件**: `src/lib/rateSimulationCalculator.ts` (行 114-117)

```typescript
const FORECAST_REQUIRING_CAMPAIGN_TYPES = new Set([
  'MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE',
  'MAX_REWARD_VALUE_PER_LIQUIDITY_AMOUNT',
  'FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE',
  'FIX_REWARD_AMOUNT_PER_LIQUIDITY_VALUE',
  'FIX_REWARD_AMOUNT_PER_LIQUIDITY_AMOUNT',
  'TARGET_TOTAL_APR',  // 新增
]);
```

### 6.4 `useRateSimulation.ts`：cap note 覆盖 TARGET_TOTAL_APR

**文件**: `src/hooks/useRateSimulation.ts` (行 774-787)

当前 cap note 只对 `FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE` 和 `MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE` 生成。TARGET_TOTAL_APR 需要覆盖：

- `budgetBoundMode=MAX_APR` → 走 MAX 路径的 cap note（`APR_CAPPED` regime）
- `budgetBoundMode=FIX_APR` → 走 FIX 路径的 cap note（`fixRewardableDays`）

### 6.5 不需要改的

| 项目 | 原因 |
|---|---|
| `campaignApr` 计算 | 后端已做 APR↔APY 转换 + nativeAPY 减法，前端直接用 |
| `distributionMethod` / `rawDistributionMethod` | 前端从未读取，零影响 |
| Zod 解析 | `z.string().optional()` 不拒绝新值，`.passthrough()` 不拒绝新字段 |
| `mergeForecastState` 的 `!campaignType` guard | 后端已确保 TARGET_TOTAL_APR 有 `campaignType`，不会返回 null |

---

## 7. 建议实施顺序

1. **P0**: 6.1 类型 + Schema；6.2 merklForecast.ts 路径修正；6.3 FORECAST_REQUIRING_CAMPAIGN_TYPES
2. **P1**: 6.4 useRateSimulation.ts cap note
3. **P2（defer）**: ERC4626 子类型支持（需要 vaultAPR 数据源，当前不可用）

---

## 8. 当前 Aave 活跃的 TARGET_TOTAL_APR Campaign

| campaignId | reserve | side | targetAPR (aprCap) | budgetBoundMode |
|---|---|---|---|---|
| 13116567236794890552 | 4326:0x7e32...c28 | supply | 4.7% | MAX_APR |
| 12662496063613214537 | 1:0x973a...e29:0xcca8...6c9 | supply | 5.83% | MAX_APR |
| 8647796357084493685 | 1:0x6540...1dc:0xcca8...6c9 | supply | 7.7% | MAX_APR |

---

## 9. 共享文档

- **`aaveapy-doc/merkl-distribution-types.md`** — 4 大 Family + 7 种子类型 + mapping table + TTA APR 影响 + budget-bound mode + dilutive 示例
- **`docs/adr/0024-merkl-campaign-type-multi-level-mapping.md`** — Level 1 移除 + Level 3 fallback + APR cap 语义差异
- **Merkl 官方文档** — https://docs.merkl.xyz/merkl-mechanisms/distributions
