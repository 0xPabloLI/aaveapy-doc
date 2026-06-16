# Handoff: Brevis Forecast 合并到 forecast 子块

**日期**: 2026-06-14（后端）/ 2026-06-15（前端）
**类型**: Breaking API Change — `GET /api/meta/side-data`
**关联 Issues**: AAV-865（后端已实施）、AAV-872（前端 PRD）

## 变更摘要

`brevisForecast` 子块已移除，Brevis 数据合并到 `forecast.items[]` 中，与 Merkl forecast 共享同一个数组。

## 前端已完成的改动（AAV-872）

### 已移除

1. **`distributedSoFarUsd` 字段**：从 `BrevisCampaignBreakdown`、`BrevisIncentive`、`BrevisCampaignBreakdownSchema`、`BrevisIncentiveSchema`、`BrevisResolvedBreakdown`、`getBrevisDistributedSoFarUsd` helper 中移除
2. **`brevisForecast.ts` 模块**：`forecastBrevisAprPercent` 和 `forecastBrevisDetailed` 函数已删除
3. **`brevisForecast.test.ts`**：测试文件已删除

### 已新增

4. **Brevis breakdown `campaignType`**：`BrevisCampaignBreakdown` 和 `BrevisIncentive` 新增 `campaignType?: string` 字段
5. **Brevis breakdown `aprCap`**：`BrevisCampaignBreakdown` 和 `BrevisIncentive` 新增 `aprCap?: number | null` 字段
6. **`campaignId` 必选化**：`BrevisCampaignBreakdown.campaignId` 从 `string?` 改为 `string`

### APR 计算统一

7. **`sumForecastBrevisValues`**：新增 `forecastStates` 参数；当 Brevis breakdown 有 `campaignType` 和 `latestTvl` 时，通过 `mergeForecastState` + `forecastWithTVL` 计算 APR；否则 fallback 到 nominal APR + position cap dilution
8. **`buildBrevisCampaignDetails`**：新增 `forecastStates` 参数；同上策略
9. **Position cap dilution**：保留为 calculator 层附加步骤（`computePositionCapEligibility`），在 `forecastWithTVL` 结果之上叠加
10. **`aprCap` fallback**：Brevis 没设 `aprCap` 时，用 `campaignApr` 作为 fallback（`effectiveAprCap = resolved.aprCap ?? resolved.campaignApr`）

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
| positionCap (原 perUserRewardCapUsd) | ❌ | ✅ | Brevis 专属（position cap，同 Merit selfApr 级别） |

**Forecast** (`/api/meta/side-data`) — Merkl vs Brevis：

| 字段 | Merkl | Brevis | 说明 |
|------|-------|--------|------|
| campaignId | ✅ | ✅ | |
| requiredDaily | ✅ 可选 | ❌ | Merkl MAX 有，FIX/Brevis 无 |
| distributedSoFar | ✅ | ✅ | |
| endTimestamp | ✅ 必选 | ✅ 必选 | AAV-865 统一 |
