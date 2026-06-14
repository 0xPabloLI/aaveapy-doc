# Handoff: Brevis Forecast 合并到 forecast 子块

**日期**: 2026-06-14
**类型**: Breaking API Change — `GET /api/meta/side-data`
**关联 Issues**: AAV-865（已实施）

## 变更摘要

`brevisForecast` 子块已移除，Brevis 数据合并到 `forecast.items[]` 中，与 Merkl forecast 共享同一个数组。

## 前端需要的改动

### 1. 移除 `brevisForecast` 子块消费

**Before**:
```typescript
const brevisItems = sideData.brevisForecast?.items ?? [];
```

**After**:
```typescript
const allForecastItems = sideData.forecast?.items ?? [];
```

### 2. 字段名变更

| 旧字段 | 新字段 | 说明 |
|--------|--------|------|
| `brevisForecast.items[].distributedSoFarUsd` | `forecast.items[].distributedSoFar` | 字段名与 Merkl 统一 |

### 3. 新增字段

| 字段 | 说明 |
|------|------|
| `forecast.items[].endTimestamp` (Brevis 条目) | 必选，campaign 结束时间（Unix seconds） |

### 4. `partial` 计数变更

- 旧：5 个子块（categories, fdv, forecast, brevisForecast, campaignAccess）
- 新：4 个子块（categories, fdv, forecast, campaignAccess）

### 5. `errors` key 变更

- 旧：errors 可能含 `brevisForecast` key
- 新：无 `brevisForecast` key；Brevis 错误包含在 `forecast.errors[]` 中（per-campaign 级）

## 如何区分 Merkl 和 Brevis 条目

合并后的 `forecast.items[]` 中两种条目的差异：

| 字段 | Merkl | Brevis |
|------|-------|--------|
| `campaignId` | Merkl campaign ID | Brevis campaign ID |
| `requiredDaily` | 可选（MAX 有，FIX 无） | 不存在 |
| `distributedSoFar` | 必有 | 必有 |
| `endTimestamp` | 必有（Unix seconds） | 必有（Unix seconds） |

最可靠的区分方式：匹配 campaignId 与 `/api/markets` breakdown 中的 Merkl/Brevis campaignId。

## 链上缓存 TTL 变更（对前端透明）

`fetchBrevisDistributedSoFar` 新增 1h 链上缓存 TTL。前端无需感知，`staleTimeMs` 仍由 forecast 子块的 10m cron 控制。

## 完整的 forecast.items[] 条目结构

```typescript
interface ForecastItem {
  campaignId: string;
  requiredDaily?: number;      // Merkl MAX 有，Merkl FIX/Brevis 无
  distributedSoFar: number;    // USD，两种来源都有
  endTimestamp: number;        // Unix seconds，Merkl 和 Brevis 均必选（AAV-865 统一）
}
```

---

## AAV-865 已完成的变更

以下变更已在 AAV-865 中实施：

### 6. Brevis breakdown 新增 `campaignType`

Brevis 所有 campaign 默认 `campaignType = 'FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE'`。与 Merkl FIX 一致，前端可统一处理。

### 7. Brevis breakdown 新增 `aprCap`

FIX 类型的 `aprCap = campaignApr`。Brevis 的 incentive APR 就是 APR cap（FIX 特性：APR 固定不变）。

### 8. Brevis forecast `endTimestamp` 改为必选

Brevis gRPC 的 `config.end` 必有值，`endTimestamp` 从可选改为必选。没有 `endTimestamp` 的条目不会出现在 `forecast.items[]` 中。

### 9. Brevis breakdown `campaignId` 改为必选

`campaignId` 从可选改为必选，与 Merkl 一致。

### 10. 移除 `budgetNormalizedAmount` / `budgetTokenSymbol`

从 `BrevisCampaignBreakdown` / `ApiBrevisBreakdown` 类型中移除。这两个字段是 `totalBudget` 计算的中间产物，enrich 后被 prune 剥离，不出现在 API 响应中。

### AAV-865 完成后的统一字段表

**Breakdown** (`/api/markets`) — Merkl vs Brevis：

| 字段 | Merkl | Brevis | 说明 |
|------|-------|--------|------|
| campaignApr | ✅ | ✅ | |
| campaignStartedAt | ✅ | ✅ | |
| campaignEndedAt | ✅ | ✅ | |
| campaignId | ✅ 必选 | ✅ 必选 | AAV-865 统一 |
| campaignType | ✅ | ✅ FIX | AAV-865 新增 Brevis |
| totalBudget | ✅ | ✅ | |
| aprCap | ✅ | ✅ (=campaignApr) | AAV-865 新增 Brevis |
| latestTvl | ✅ | ✅ | |
| whitelistOnly | ✅ | ❌ | Merkl 专属 |
| pointsPerThousandUsd | ✅ | ❌ | Merkl 专属 |
| plannedDaily | ✅ | ❌ | Merkl 专属 |
| perUserRewardCapUsd | ❌ | ✅ | Brevis 专属（position cap，同 Merit selfApr 级别） |

**Forecast** (`/api/meta/side-data`) — Merkl vs Brevis：

| 字段 | Merkl | Brevis | 说明 |
|------|-------|--------|------|
| campaignId | ✅ | ✅ | |
| requiredDaily | ✅ 可选 | ❌ | Merkl MAX 有，FIX/Brevis 无 |
| distributedSoFar | ✅ | ✅ | |
| endTimestamp | ✅ 必选 | ✅ 必选 | AAV-865 统一 |

---

## Spin-off Issues 状态

### AAV-866: forecast endTimestamp 是否与 breakdown campaignEndedAt 冗余 — Done

**结论：不冗余，保留。**

- Merkl: breakdown `campaignEndedAt`（ISO）来自 opportunities API，forecast `endTimestamp`（Unix）来自 campaign details API。同一字段但不同 endpoint，理论上可能有缓存不一致。
- Brevis: 两者同源（gRPC `config.end`），值完全一致，但格式不同（ISO vs Unix）。
- 前端消费模式不同：forecast `endTimestamp` 用于预算消耗天数计算，breakdown `campaignEndedAt` 用于展示。两者独立消费。

### AAV-867: Brevis 其他 distribution type（非 FIX）— Done

**结论：Brevis 只有 FIX。**

- gRPC `campaign.type` 是 action type（2001=borrow, 2002=supply, 3001=both），不是 distribution type。
- Brevis 没有 Dutch auction 或 MAX reward 机制。代码中已加注释说明默认值原因和未来更新条件。

### AAV-864: 单 cron + 缓存 TTL 重构 — Todo（需前端确认）

**后端侧评估完成，需前端确认消费场景后才能推进。**

- 核心决策点：`plannedDaily`/`totalBudget`/`aprCap` 前端是否只在 forecast 上下文消费
- 如果只在 forecast 上下文用 → 迁移到 forecast 合理
- 如果需要和 markets snapshot 同层消费 → 迁移增加 join 复杂度，不适合
- 后端已完成技术前提：Brevis 链上缓存（1h TTL）、Merkl metrics 动态 TTL（10m~6h）
