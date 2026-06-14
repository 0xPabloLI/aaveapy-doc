# Handoff: Brevis Forecast 合并到 forecast 子块

**日期**: 2026-06-14
**类型**: Breaking API Change — `GET /api/meta/side-data`

## 变更摘要

`brevisForecast` 子块已移除，Brevis 数据合并到 `forecast.items[]` 中，与 Merkl forecast 共享同一个数组。

## 前端需要的改动

### 1. 移除 `brevisForecast` 子块消费

**Before**:
```typescript
// side-data response 中有独立的 brevisForecast 子块
const brevisItems = sideData.brevisForecast?.items ?? [];
```

**After**:
```typescript
// Brevis 条目已在 forecast.items[] 中，无需单独读取
// 区分 Merkl 和 Brevis 条目：Brevis 条目无 requiredDaily，endTimestamp 可选
const allForecastItems = sideData.forecast?.items ?? [];
```

### 2. 字段名变更

| 旧字段 | 新字段 | 说明 |
|--------|--------|------|
| `brevisForecast.items[].distributedSoFarUsd` | `forecast.items[].distributedSoFar` | 字段名与 Merkl 统一 |

### 3. 新增字段

| 字段 | 说明 |
|------|------|
| `forecast.items[].endTimestamp` (Brevis 条目) | 可选，campaign 结束时间（Unix seconds） |

### 4. `partial` 计数变更

- 旧：5 个子块（categories, fdv, forecast, brevisForecast, campaignAccess）
- 新：4 个子块（categories, fdv, forecast, campaignAccess）
- `partial` 判断阈值从 `< 5` 改为 `< 4`

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
| `endTimestamp` | 必有（Unix seconds） | 可选（Unix seconds） |

前端可用 `requiredDaily in item` 或 `endTimestamp` 是否存在来区分，但更可靠的方式是匹配 campaignId 与 `/api/markets` breakdown 中的 Merkl/Brevis campaignId。

## 链上缓存 TTL 变更（对前端透明）

`fetchBrevisDistributedSoFar` 新增 1h 链上缓存 TTL。`tokenCumulativeRewards` 约 4 小时变一次，1h TTL 意味着最多延迟 1 小时更新。前端无需感知此变更，`staleTimeMs` 仍由 forecast 子块的 10m cron 控制。

## 完整的 forecast.items[] 条目结构

```typescript
interface ForecastItem {
  campaignId: string;
  requiredDaily?: number;      // Merkl MAX 有，Merkl FIX/Brevis 无
  distributedSoFar: number;    // USD，两种来源都有
  endTimestamp?: number;       // Unix seconds，Merkl 必有，Brevis 可选
}
```
