# Handoff: Brevis `perUserRewardCapUsd` → `positionCap`

**日期**: 2026-06-16
**类型**: Breaking API Change — `GET /api/markets`
**关联**: AAV-865

## 变更摘要

1. `perUserRewardCapUsd` → `positionCap`（已完成 ✅）
2. `mapActionType` 扩展，加入 5001/5002/5003/6001（已完成 ✅）
3. 去掉 `type === 3001` 过滤（已完成 ✅）

### 决策：不加 positionCapScope

在 grill 过程中确认：前端已按 `campaignId` 去重推导 shared cap（`computeBrevisSharedCampaignDeposits`），后端不需要额外加 `positionCapScope` 字段。YAGNI。

### 决策：不需要修复 3001 combined bug

前端 `computeBrevisSharedCampaignDeposits` 已解决同一 campaignId 在 supply 和 borrow 中共享 cap 的问题。后端保持现状即可。

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

## 已完成的后端工作 ✅

| 变更 | 文件 |
|---|---|
| `perUserRewardCapUsd` → `positionCap` | shared-contracts, brevis-api, incentive-prune, tests, OpenAPI |
| 拆出 `extractPositionCapFromDescription()` | brevis-api.ts |
| 去掉 `type === 3001` 过滤 | brevis-api.ts |
| `mapActionType` 扩展 5001/5002/5003/6001 | brevis-api.ts |
| 清理 `budgetNormalizedAmount` / `budgetTokenSymbol` | generate-openapi.ts, OpenAPI spec |
| 文档更新（铁证 + action type 映射） | api-documentation.md, brevis-supplement.md |

---

## 前端工作 🔲

### 1. 重命名字段

```
perUserRewardCapUsd → positionCap
```

### 2. Position cap 语义

5000 USDC 是 **supply + borrow 合计持仓**上限，不是各自独立。前端 `computeBrevisSharedCampaignDeposits` 已按 campaignId 去重处理。

### 3. 清理 `budgetNormalizedAmount` / `budgetTokenSymbol`

这两个字段已从 API 移除，前端 Zod schema 中如有可删。

---

## API 输出示例

```json
{
  "brevisSupplys": [{
    "link": "https://incentra.brevis.network/campaign/",
    "name": "MetaMask Card",
    "message": "Eligible MetaMask Card users...",
    "breakdowns": [{
      "campaignApr": 2.4,
      "campaignStartedAt": "2025-08-13T13:00:00.000Z",
      "campaignEndedAt": "2026-08-08T00:00:00.000Z",
      "campaignId": "1754995104",
      "campaignType": "FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE",
      "aprCap": 2.4,
      "latestTvl": 4151203.07,
      "totalBudget": 9998600,
      "positionCap": 5000
    }]
  }]
}
```

## 字段映射表

| 旧字段名 | 新字段名 | 类型 | 说明 |
|---|---|---|---|
| `perUserRewardCapUsd` | `positionCap` | `number?` | 持仓上限 USD |
| `budgetNormalizedAmount` | _(已移除)_ | — | 内部字段，不对外 |
| `budgetTokenSymbol` | _(已移除)_ | — | 内部字段，不对外 |

## 更新后的 Brevis Breakdown 完整字段表

| 字段 | 类型 | 说明 |
|---|---|---|
| campaignApr | number | 百分数（后端已 ×100） |
| campaignStartedAt | string | ISO 8601 |
| campaignEndedAt | string | ISO 8601 |
| campaignId | string | 必选 |
| campaignType | string? | 当前固定 `FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE` |
| aprCap | number? | = campaignApr |
| totalBudget | number? | USD |
| latestTvl | number? | USD |
| **positionCap** | **number?** | **持仓上限 USD（combined: supply + borrow 合计）** |

## 关联文档

- `aaveapy-doc/handoff-brevis-forecast-merge.md` — 上一次 Brevis handoff（AAV-865）
- `docs/api/api-documentation.md` — API 字段文档
- `docs/api/brevis-supplement.md` — Brevis 数据源补充说明（含 position cap 铁证 + action type 完整映射）
