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

## 抓取链路（2026-11-12 更新，AAV-1365）

`positionCapUsd` 不是 Brevis API 字段：`extractPositionCapFromDescription()` 从 Brevis 前端 `_app` chunk 的 campaign 文案里刮数字，所以**文案就是契约**。原实现把文案当常量（单条正则 + 两个字面量锚点），改词即静默返回 `null`，前端随即按名义 APR 显示。现已加固（`packages/aave-fetcher/src/brevis-api.ts`）：

- 句式候选表 `POSITION_CAP_PATTERNS`（p1–p5）+ 择优 `isBetterCandidate`（句式具体程度 → 持仓上下文 → 出现位置），并加 `<=0 || >1e9` 量级闸门。
- 锚点候选表 `COPY_START_MARKERS` / `COPY_END_MARKERS`，全缺才放弃。
- `isMetaMaskCampaignFamily()` 归属门：抓来的 cap 只给名字含 MetaMask 的 campaign，避免第二族 campaign 继承别人的上限。
- 失败上报：`brevis_position_cap_extraction_failed`（带 campaignId / chainId / 命中句式 / 锚点对 / 文案片段）、`brevis_campaign_family_without_copy`。

实测文案（2026-11-12）：*"This promotional rate applies to a combined total of up to 5000 USDC in collateral and/or debt per user."* —— 与下面 §2.5 的铁证一致。**待补**：定时 live CI 检查（抓真页面断言锚点与 cap），见 AAV-1365 的「后续」。

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
