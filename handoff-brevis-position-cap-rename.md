# Handoff: Brevis `perUserRewardCapUsd` → `positionCap`

**日期**: 2026-06-16 · Updated: 2026-06-17
**类型**: Breaking API Change — `GET /api/markets`
**关联**: AAV-865

## 变更摘要

1. `perUserRewardCapUsd` → `positionCap`（已完成 ✅）
2. `mapActionType` 扩展，加入 5001/5002/5003/6001（已完成 ✅）
3. ~~新增 `positionCapScope`~~ → **不需要**，前端已按 campaignId 去重推导 shared cap（YAGNI）
4. ~~3001 combined bug 修复~~ → **前端已解决**，`computeBrevisSharedCampaignDeposits` 按 campaignId 跨 supplys/borrows 去重

## Position Cap 语义确认（铁证，勿反复讨论）

**5000 USDC 是 position cap（持仓上限），不是 reward cap（奖励上限）。**

对 `type=3001` (both) 的 campaign，5000 是 **supply + borrow 合计持仓**上限：
```
eligiblePosition = min(supplyPosition + borrowPosition, positionCap)
```

铁证来源：
1. **Brevis 官方博客** (2025-08-13)： "up to a **combined collateral and debt cap of 5,000 USDC**" — https://blog.brevis.network/2025/08/13/setting-a-new-standard-for-on-chain-incentives-with-metamask-linea-and-brevis/
2. **Linea 官方活动页**： "$5,000 **combined balance per user (supply + borrow)**" — https://linea.build/hub/events/boosted-yield-on-aave
3. **多家媒体报道**： "combined cap of 5,000 USDC in collateral and debt" — MEXC, BitcoinEthereumNews, CryptoDataSpace 等

详见 `docs/api/brevis-supplement.md` Section 2.5。

---

## 已完成的工作 ✅

### 后端

| 变更 | 文件 |
|---|---|
| `perUserRewardCapUsd` → `positionCap` | shared-contracts, brevis-api, incentive-prune, tests, OpenAPI |
| 拆出 `extractPositionCapFromDescription()` | brevis-api.ts |
| 去掉 `type === 3001` 过滤 | brevis-api.ts |
| 清理 `budgetNormalizedAmount` / `budgetTokenSymbol` | generate-openapi.ts, OpenAPI spec |
| `mapActionType` 扩展 5001/5002/5003/6001 | brevis-api.ts |
| 文档更新 | api-documentation.md, brevis-supplement.md |

### 前端

| 变更 | 状态 |
|---|---|
| `perUserRewardCapUsd` → `positionCap` 重命名 | ✅ 已完成，零残留 |
| 清理 `budgetNormalizedAmount` / `budgetTokenSymbol` | ✅ 已完成，零残留 |
| Shared cap 去重逻辑 | ✅ 已完成（`computeBrevisSharedCampaignDeposits` 按 campaignId 去重） |

---

## `positionCapScope` 为何不需要

前端 `rateSimulationCalculator.ts:465-524` 的 `computeBrevisSharedCampaignDeposits` 已实现：

| 条件 | positionCap 语义 |
|---|---|
| 同 `campaignId` 在 supplys + borrows 两边 + 元数据一致 | **合计**（`isSharedSupplyBorrow: true`） |
| 同 `campaignId` 两边但元数据不一致 | **独立**（跳过共享，warn） |
| `campaignId` 仅在单侧 | **独立** |
| 无 `campaignId` | **独立** |

`positionCapScope` 与 `actionType` 是 1:1 映射（`supply`↔`supply`，`borrow`↔`borrow`，`both`↔`combined`），信息冗余。前端已能从数据结构（同 campaignId 跨数组）推导 shared cap，不需要后端额外传 scope 字段。按 YAGNI 原则，不加。

---

## `mapActionType` 完整映射

| Code | 协议 | actionType | 证据来源 |
|---|---|---|---|
| 2001 | Euler borrow | `borrow` | 官方文档 Incentra docs: Euler campaigns |
| 2002 | Euler lend | `supply` | 官方文档 Incentra docs: Euler campaigns |
| 3001 | Aave both (gRPC 实测) | `both` | gRPC 运行时数据 + 项目代码映射 |
| 5001 | Aave lend | `supply` | 官方文档 Incentra docs: Aave campaigns |
| 5002 | Aave borrow | `borrow` | 官方文档 Incentra docs: Aave campaigns |
| 5003 | Aave lend_net | `supply` | 官方文档 Incentra docs: Aave campaigns |
| 6001 | Morpho lend | `supply` | 官方文档 Incentra docs: Morpho campaigns |

5001/5002/5003/6001 尚未在 gRPC 响应中观察到，但有官方文档依据，提前加入 `mapActionType`。

---

## 关联文档

- `aaveapy-doc/handoff-brevis-forecast-merge.md` — 上一次 Brevis handoff（AAV-865）
- `docs/api/api-documentation.md` — API 字段文档
- `docs/api/brevis-supplement.md` — Brevis 数据源补充说明（含 position cap 铁证 + action type 完整映射）
