# Handoff: TARGET_TOTAL_APR 前端适配

**日期**: 2026-06-16
**来源**: 后端 TARGET_TOTAL_APR 全链路已实现 + Level 1 移除 + Level 3 fallback 已实现
**对接人**: 前端 session
**父 Issue**: AAV-833

---

## 1. 后端已完成的部分

### 1.1 API 输出当前状态

TARGET_TOTAL_APR campaign 的 breakdown 已出现在 `/api/markets` 响应中：

```json
{
  "campaignApr": 4.7,
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

### 1.2 已完成的映射

**2026-06-16 更新**：Level 1 (`distributionMethod`) 映射已移除（Aave 场景下始终为空字符串，从未命中）。当前使用 2 级映射：

1. **Level 2**: `distributionType` 精确匹配
2. **Level 3 fallback**: `distributionSettings.targetAPR` 存在且为正数 → `TARGET_TOTAL_APR`

7 种 `distributionType` 映射到 `TARGET_TOTAL_APR`：

| distributionType | → campaignType | Aave lending 相关 |
|---|---|---|
| `AAVE_NET_APR` | TARGET_TOTAL_APR | ✅ V3 |
| `AAVE_V4_NET_APR` | TARGET_TOTAL_APR | ✅ V4 |
| `ERC4626_APR` | TARGET_TOTAL_APR | ❌ vault-based |
| `ERC4626_SPREAD_CAPPED` | TARGET_TOTAL_APR | ❌ vault-based |
| `ERC4626_TARGET_APR_WITH_MERKL` | TARGET_TOTAL_APR | ❌ vault-based |
| `SOFR_SPREAD_RATCHET` | TARGET_TOTAL_APR | ❌ vault-based |
| `DEEL_DISTRIBUTION` | TARGET_TOTAL_APR | ❌ vault-based |

**Aave lending 场景只有前两种**。后 5 种经 Merkl 官方 Schema API 确认全部是 ERC4626 vault-based。

Level 3 fallback 确保未来 Merkl 新增 `distributionType` 变体时，只要有 `targetAPR` 字段就能正确分类，不需要改代码。

### 1.3 aprCap 语义

| campaignType | aprCap 含义 | 来源字段 |
|---|---|---|
| MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE | Merkl 实付 APR 上限 | `distributionSettings.apr` |
| FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE | Merkl 实付 APR 上限 | `distributionSettings.apr` |
| **TARGET_TOTAL_APR** | **总 APR 目标 (targetAPR)** | `distributionSettings.targetAPR` |
| DUTCH_AUCTION | 无 APR cap | N/A |

**关键区别**：TARGET_TOTAL_APR 的 `aprCap` 是"用户应得的总 APR"，不是"Merkl 支付的部分"。但后端已自动将 `campaignApr` 转换为 Merkl 实付 APR，前端无需手动计算。

### 1.3.1 campaignApr 语义（2026-06-15 更新）

| campaignType | campaignApr 含义 | 前端使用方式 |
|---|---|---|
| MAX / FIX / DUTCH | Merkl 实付 APR | 直接使用 |
| **TARGET_TOTAL_APR** | **Merkl 实付 APR**（后端已计算） | **直接使用，无需手动减 nativeAPY** |

后端在序列化时已将 TARGET_TOTAL_APR 的 `campaignApr` 从 `targetAPR` 转换为实付 APR：

```
targetAPY = convertAprToApy(targetAPR)     // APR→APY (月复利 n=12)
incentiveAPY = targetAPY - nativeAPY       // supply; borrow 侧 = nativeAPY - targetAPY
campaignApr = apyToApr(max(incentiveAPY, 0)) // APY→APR，输出与 MAX/FIX 统一格式
```

转换公式与前端 `rateCalculations.ts` 完全一致（月复利 n=12）。`aprCap` 字段仍保留原始 `targetAPR`，供前端展示"目标 APR"。

### 1.4 budgetBoundMode 链路状态（已接通）

`budgetBoundMode` 是 TARGET_TOTAL_APR 的正交维度，决定 budget 用尽后的行为。链路已完全接通（2026-06-15 修复）：

| 环节 | 状态 | 代码位置 |
|---|---|---|
| Merkl API 返回 `distributionSettings.mode` | ✅ 有数据 | campaign params |
| Fetcher 提取为 `rawMode` 写入 lite 文件 | ✅ 已提取 | `merkl-api.ts:663-665`, `:687`, `:700` |
| Fetcher breakdown 构建时赋值 budgetBoundMode | ✅ 已赋值 | `merkl-api.ts:1278`（从 rawMode 读取，仅 TARGET_TOTAL_APR） |
| Backend 读取 lite 文件 | ✅ 提取 rawMode | `merklForecastService.ts` |
| `CampaignOpportunityMeta` 接口 | ✅ 含 rawMode | `merklForecastService.ts` |
| Forecast 计算 | ✅ 区分 MAX_APR / FIX_APR mode | `merklApiContract.ts`（field rules 动态化） |
| `MerklCampaignBreakdown.budgetBoundMode` | ✅ 运行时赋值 | fetcher `merkl-api.ts` |
| `ApiMerklBreakdown` | ✅ 等于 `MerklCampaignBreakdown`（Pick 列表已移除） | `shared-contracts/src/index.ts` |
| API 序列化输出 | ✅ 输出 budgetBoundMode | TARGET_TOTAL_APR 时包含，FIX_APR 时省略 plannedDaily |

**Forecast metrics 与 mode 的关系（已修复 2026-06-15）**：

`plannedDaily` = `totalBudget / totalDays` 是"预算均匀日耗"假设。对 MAX 模式有意义（budget 可能花不完，plannedDaily 是消耗上限参考）。对 FIX 模式**无意义**——FIX 的 cost ∝ TVL，实际消耗可能远超 plannedDaily，budget 提前用完 campaign 就结束。

代码已根据 `budgetBoundMode` 动态选择 field rules：
- `BREAKDOWN_FIELD_RULES`: FIX → `omit: ['plannedDaily']`；MAX → 输出 plannedDaily
- `FORECAST_FIELD_RULES`: FIX → `mode: 'fix'`, `includeRequiredDaily: false`；MAX → `mode: 'max'`, `includeRequiredDaily: true`
- TARGET_TOTAL_APR 根据 breakdown 上的 `budgetBoundMode` 自动选择 FIX/MAX 规则（不再硬编码 `mode: 'max'`）

### 1.5 各 distributionMethod 的官方定义与特定参数

来源：Merkl Schema API (`/v4/schemas/distributionMethod`)，2026-06-14 查询。

| distributionMethod | 官方描述 | Aave lending | 特定参数 |
|---|---|---|---|
| `AAVE_NET_APR` | Automatically tops up Aave native APR to reach a target APR | ✅ | `targetAPR`, `assetId` |
| `AAVE_V4_NET_APR` | Tops up Aave V4 native APR to reach a target total APR | ✅ | `targetAPR`, `assetId`, `hubAddress`, `side` |
| `ERC4626_APR` | Tops up ERC4626 vault APR to reach a target total APR | ❌ vault | `targetAPR` |
| `ERC4626_SPREAD_CAPPED` | Pays the spread between a target APR and the ERC4626 vault native APR, capped at a maximum Merkl-paid APR. Merkl APR = min(max(targetAPR - vaultAPR, 0), cap) | ❌ vault | `targetAPR`, `cap` |
| `ERC4626_TARGET_APR_WITH_MERKL` | Tops up an ERC4626 vault's native APR and the existing Merkl opportunity APR to reach a target total APR. Merkl APR = max(targetAPR - vaultAPR - merklOpportunityAPR, 0). Designed to run on top of a vault-tracking campaign (e.g. MORPHOVAULT, ERC20LOGPROCESSOR). | ❌ vault | `targetAPR`（merklOppAPR 来自运行时） |
| `SOFR_SPREAD_RATCHET` | Tops up an ERC4626 vault's native APR to a TVL-tiered target (live SOFR + a spread that tightens as campaign-tracked TVL grows, held by a one-way ratchet). Merkl APR = max(SOFR + spread(maxTVL) - vaultAPR, 0). Designed to run on top of a vault-tracking campaign (e.g. MORPHOVAULT, ERC20LOGPROCESSOR). | ❌ vault | spread tier table（动态 target） |
| `DEEL_DISTRIBUTION` | DEEL split distribution: tops up vault holders to 2.5% effective APR (net of Merkl opportunity APR and the vault native APR) and routes a SOFR-derived treasury skim to a target address. Designed to run on top of a vault-tracking campaign (e.g. MORPHOVAULT, ERC20LOGPROCESSOR) — uses the time-weighted TVL implicit in the per-user scores. | ❌ vault | 固定 target 2.5%（treasury skim 不影响用户 APR） |

**所有 7 种的 budgetBoundMode**：`MAX_APR` 或 `FIX_APR`（从 `distributionSettings.mode` 读取）。ERC4626_SPREAD_CAPPED 已验证为 `FIX_APR`，AAVE_NET_APR/AAVE_V4_NET_APR 已验证为 `MAX_APR`，其余待验证。

**vault-based 判定依据**：后 5 种的官方描述中包含 "ERC4626 vault"、"vault holders"、"vault-tracking campaign (e.g. MORPHOVAULT, ERC20LOGPROCESSOR)"，公式中减的是 `vaultAPR` 而非 `nativeAPR`。

**spreadCap 参数**：仅 `ERC4626_SPREAD_CAPPED` 拥有。已从代码中移除（YAGNI — 后端无法获取 vaultAPR，无消费者）。**Vault 模式预留**：未来支持 ERC4626 vault 时需重新引入 `spreadCap`（来源 `distributionSettings.cap`）以及 `vaultAPR` 数据源。

---

## 2. 前端当前代码状态（2026-06-16 审查）

### 2.0.1 `TARGET_TOTAL_APR` 当前在前端的行为

**问题：`TARGET_TOTAL_APR` 走错了 forecast 路径。**

前端 `merklForecast.ts` 的分支逻辑：

```typescript
const isMaxAprCampaign =
  forecastState.campaignType === 'MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE' ||
  forecastState.campaignType === 'MAX_REWARD_VALUE_PER_LIQUIDITY_AMOUNT';
const isFixAprCampaign =
  forecastState.campaignType === 'FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE' ||
  forecastState.campaignType === 'FIX_REWARD_AMOUNT_PER_LIQUIDITY_VALUE' ||
  forecastState.campaignType === 'FIX_REWARD_AMOUNT_PER_LIQUIDITY_AMOUNT';
const isRateLimitedCampaign = isMaxAprCampaign || isFixAprCampaign;
```

`TARGET_TOTAL_APR` 不匹配任何已知类型 → `isMaxAprCampaign=false`, `isFixAprCampaign=false` → **走 DUTCH_AUCTION 通用路径（无 APR cap、无 rate limiting）**。

但 TARGET_TOTAL_APR 应该根据 `budgetBoundMode` 走 MAX 或 FIX 路径，不是 Dutch-auction。

### 2.0.2 前端缺失的字段

| 字段 | 前端类型 | Zod schema | 说明 |
|---|---|---|---|
| `budgetBoundMode` | ❌ 缺失 | ❌ 缺失 | 后端已输出，前端未消费 |
| `distributionMethod` / `rawDistributionMethod` | N/A | N/A | 前端从未读取，后端已移除，零影响 |

### 2.0.3 `campaignApr` 已由后端转换

后端已将 TARGET_TOTAL_APR 的 `campaignApr` 从 `targetAPR` 转换为 Merkl 实付 APR（见 Section 1.3.1）。前端对 `campaignApr` 的使用方式与 MAX/FIX/DUTCH **完全一致**，无需特殊处理。

### 2.0.4 Zod schema 兼容性

`campaignType: z.string().optional()` — 不拒绝新值 `TARGET_TOTAL_APR`，但也不做特殊处理。Zod 使用 `.passthrough()`，未知字段（如 `budgetBoundMode`）会被透传不会报错，但 TypeScript 类型定义需要更新才能在代码中访问。

---

## 3. 前端需要做的改动

### 3.1 类型 + Schema：添加 `budgetBoundMode`

**文件**: `src/types/aave.ts`

```typescript
export interface MerklCampaignBreakdown extends BaseCampaignBreakdown {
  campaignId: string;
  whitelistOnly?: boolean;
  pointsPerThousandUsd?: number;
  campaignType?: string;
  totalBudget?: number;
  aprCap?: number | null;
  latestTvl?: number;
  plannedDaily?: number;
  budgetBoundMode?: string;  // ← 新增：'MAX_APR' | 'FIX_APR'
  rewardTokenSymbol?: string;
  rewardTokenIconUrl?: string;
}
```

**文件**: `src/lib/apiSchemas.ts` — 对应 Zod schema 添加 `budgetBoundMode: z.string().optional()`

### 3.2 `merklForecast.ts`：TARGET_TOTAL_APR 按 budgetBoundMode 归入正确路径

**文件**: `src/lib/merklForecast.ts` (行 51-57)

当前逻辑只识别 5 种 campaignType。需要让 `TARGET_TOTAL_APR` 根据 `budgetBoundMode` 归入 MAX 或 FIX：

```typescript
// 改动示意（具体实现可调整）
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

**`forecastState` 类型也需要添加 `budgetBoundMode`** — 来自 `mergeForecastState` 返回值。

### 3.3 `useRateSimulation.ts`：cap note 覆盖 TARGET_TOTAL_APR

**文件**: `src/hooks/useRateSimulation.ts` (行 774-787)

当前 cap note 逻辑只对 `FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE` 和 `MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE` 生成。TARGET_TOTAL_APR 的 cap 语义不同（是"总 APR 目标"而非"Merkl 实付上限"），但 `campaignApr` 已由后端转为实付 APR，所以：

- `budgetBoundMode=MAX_APR` → 走 MAX 路径的 cap note（APR_CAPPED regime）
- `budgetBoundMode=FIX_APR` → 走 FIX 路径的 cap note（fixRewardableDays）

### 3.4 `FORECAST_REQUIRING_CAMPAIGN_TYPES`：添加 TARGET_TOTAL_APR

**文件**: `src/lib/rateSimulationCalculator.ts` (行 114-117)

```typescript
const FORECAST_REQUIRING_CAMPAIGN_TYPES = new Set([
  'MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE',
  'MAX_REWARD_VALUE_PER_LIQUIDITY_AMOUNT',
  'FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE',
  'FIX_REWARD_AMOUNT_PER_LIQUIDITY_VALUE',
  'FIX_REWARD_AMOUNT_PER_LIQUIDITY_AMOUNT',
  'TARGET_TOTAL_APR',  // ← 新增
]);
```

### 3.5 campaignApr 使用方式

**无需改动。** 后端已将 TARGET_TOTAL_APR 的 `campaignApr` 转换为 Merkl 实付 APR，前端可直接与其他类型一样使用。

### 3.6 不需要改的

| 项目 | 原因 |
|---|---|
| `campaignApr` 计算 | 后端已完成 APR↔APY 转换 + nativeAPY 减法，前端直接用 |
| `distributionMethod` / `rawDistributionMethod` | 前端从未读取，零影响 |
| Zod 解析 | `z.string().optional()` 不拒绝新值，`.passthrough()` 不拒绝新字段 |
| `mergeForecastState` 的 `!campaignType` guard | 后端已确保 TARGET_TOTAL_APR 有 `campaignType`，不会返回 null |

---

## 4. 后端已完成的工作

### P1: 透传 budgetBoundMode — ✅ 已完成 (2026-06-15)

所有断路点已修复，field rules 已动态化。详见 Section 1.4。

### 暂不处理

| 字段 | 原因 |
|---|---|
| `spreadCap` | 已移除（YAGNI）。Vault 模式预留：未来 ERC4626 支持时需重新引入 `spreadCap`（来源 `distributionSettings.cap`）+ `vaultAPR` 数据源 |
| `rawDistributionMethod` | 已移除（2026-06-16）。Level 1 mapping 从未命中，`distributionType` Level 2 + `targetAPR` Level 3 fallback 已完全覆盖 |
| `vaultAPR` | Merkl API 不提供，无法透传 |
| `merklOppAPR` | 需聚合同 reserve 上其他 opportunity，当前未实现 |

---

## 5. 当前 Aave 活跃的 TARGET_TOTAL_APR Campaign

| campaignId | distributionMethod | reserve | side | targetAPR (aprCap) | budgetBoundMode |
|---|---|---|---|---|---|
| 13116567236794890552 | AAVE_NET_APR | 4326:0x7e32...c28 | supply | 4.7% | MAX_APR |
| 12662496063613214537 | AAVE_V4_NET_APR | 1:0x973a...e29:0xcca8...6c9 | supply | 5.83% | MAX_APR |
| 8647796357084493685 | AAVE_V4_NET_APR | 1:0x6540...1dc:0xcca8...6c9 | supply | 7.7% | MAX_APR |

全部是 `AAVE_NET_APR` / `AAVE_V4_NET_APR`，budgetBoundMode 全部为 `MAX_APR`。

---

## 6. 建议的前端实施顺序

1. **P0**: 类型 + Schema 添加 `budgetBoundMode`；`merklForecast.ts` 让 TARGET_TOTAL_APR 按 budgetBoundMode 归入 MAX/FIX 路径；`FORECAST_REQUIRING_CAMPAIGN_TYPES` 添加 TARGET_TOTAL_APR
2. **P1**: `useRateSimulation.ts` cap note 覆盖 TARGET_TOTAL_APR
3. **P2（defer）**: ERC4626 子类型支持（需要 vaultAPR 数据源，当前不可用）

---

## 7. 术语澄清

### campaignType vs distributionMethod vs budgetBoundMode — 三个正交维度

| 维度 | 字段 | 语义 | 前端用途 |
|---|---|---|---|
| 一级分类 | `campaignType` | APR cap 语义 + 计算逻辑族 | 选择 APR 计算方式 |
| 二级分类 | `distributionMethod` | 具体公式（被减数来源） | Aave lending 不需要区分 |
| budget 行为 | `budgetBoundMode` | budget 用尽后的 fallback 策略 | simulation 模式选择 |

Aave lending 场景下：`campaignType = TARGET_TOTAL_APR` 已足够区分计算逻辑，不需要透传 `distributionMethod`（Level 1 mapping 已移除，Level 3 targetAPR fallback 提供前向兼容）。`budgetBoundMode` 是正交维度，影响 simulation。

### aprCap 语义差异（重申）

| campaignType | aprCap 含义 | 前端计算 merklActualAPR |
|---|---|---|
| MAX | Merkl 实付上限 | `min(aprCap, budget_rate / TVL × 365)` |
| FIX | Merkl 实付固定值 | `aprCap`（固定） |
| **TARGET_TOTAL_APR** | **总 APR 目标** | **`max(aprCap - nativeAPR, 0)`** |
| DUTCH_AUCTION | 无 cap | `budget_rate / TVL × 365` |

---

## 8. 共享文档

- **`aaveapy-doc/merkl-distribution-types.md`** — 4 大 Family + 7 种子类型 + budget-bound mode + APR 公式 + dilutive 示例
- **`docs/adr/0024-merkl-campaign-type-multi-level-mapping.md`** — 映射表 + APR cap 语义差异
- **Merkl 官方文档** — https://docs.merkl.xyz/merkl-mechanisms/distributions
- **Merkl Schema API** — https://api.merkl.xyz/v4/schemas/distributionMethod
