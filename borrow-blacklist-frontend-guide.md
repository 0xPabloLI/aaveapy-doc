# borrowBlacklist + borrowHookProtocols — 前端对接指南

**文档版本**: 2026-06-25
**状态**: 后端已实现（AAV-958 / AAV-1010 / AAV-1011），前端需适配
**架构决策**: [ADR-0033: 跨协议 BORROW_BL offset 与 blacklist 自动识别](../docs/adr/0033-cross-protocol-borrow-bl-blacklist-autodetect.md)

---

## 1. 背景

Merkl 上部分 Aave supply incentive 有**跨协议 borrow 排除**规则：用户在**任何协议**借了同一资产 → 该 supply incentive 归零。

与 `netPositionConstraint`（按比例抵消）语义不同：`borrowBlacklist` 是**二元排除**（有 borrow → 直接归零，不按量抵消）。

### 示例

USDtb on Aave (Ethereum) 的 Merkl 描述：

> "Earn rewards by lending USDtb to Aave on Ethereum. Borrowers of USDtb on **any** Ethereum-based market or protocol are not eligible for rewards"

即使用户是在 Spark/Morpho 等非 Aave 协议借了 USDtb，Aave 的 supply incentive 也归零。

---

## 2. 数据位置

### 2.1 `borrowBlacklist` — opportunity 级

`borrowBlacklist` 挂在 `merklSupplys[]` 的每个 opportunity 对象上，与 `netPositionConstraint` 同级。

```typescript
interface MerklOpportunity {
  link: string;
  name: string;
  message: string | null;
  opportunityType: string;
  netPositionConstraint?: { sourceSide: "supply" | "borrow"; offsetReserveIds: string[] } | null;
  borrowBlacklist?: true;                    // ⚠️ 仅存在且为 true 时有意义，不存在 = false
  breakdowns: MerklBreakdown[];
}
```

### 2.2 `borrowHookProtocols` — campaign 级

跨协议 borrow 排除的详细信息，通过 `/api/meta` 的 `campaignAccess` 返回。

```
GET /api/meta → { campaignAccess: { campaigns: Record<string, CampaignAccessEntry>, updatedAt: string } }
```

```typescript
interface CampaignAccessEntry {
  chainId: number;
  whitelist: string[];
  blacklist: string[];
  borrowHookProtocols?: {           // ⚠️ 可选，仅 hookType=14 的 campaign 存在
    protocol: number;                // Merkl 协议编号
    borrowBytesLike: string[];       // 该协议中被排除的 borrow 市场合约地址
  }[];
}
```

### 2.3 实际示例

`GET /api/markets` 返回的 USDtb reserve：

```json
{
  "reserveId": "1:0x87870B...:0xC13919...",
  "tokenSymbol": "USDtb",
  "merklSupplys": [{
    "name": "Lend USDtb on Aave",
    "opportunityType": "AAVE_SUPPLY",
    "message": "Earn rewards by lending USDtb to Aave on Ethereum. Borrowers of USDtb on any Ethereum-based market or protocol are not eligible for rewards",
    "borrowBlacklist": true,
    "netPositionConstraint": null,
    "breakdowns": [...]
  }]
}
```

`GET /api/meta` 返回的 campaignAccess：

```json
{
  "campaignAccess": {
    "campaigns": {
      "1575990960628026476": {
        "chainId": 1,
        "whitelist": [],
        "blacklist": ["0x2d4d2A...", "0xB8734a...", "0xDD1309...", "0x2Bf5d9...", "0x6Cd57B..."],
        "borrowHookProtocols": [
          { "protocol": 2, "borrowBytesLike": ["0xeA85a0..."] },
          { "protocol": 1, "borrowBytesLike": ["0x328646...", "0x8d1A62..."] },
          { "protocol": 0, "borrowBytesLike": ["0x88a18b...", "0xba5bb3...", "0xdf6d7f..."] },
          { "protocol": 3, "borrowBytesLike": ["0xA27201...", "0x621552...", "0xc6Eaa3...", "0xB59e39...", "0x8F4920..."] }
        ]
      }
    },
    "updatedAt": "2026-06-25T12:00:00.000Z"
  }
}
```

---

## 3. 前端计算逻辑

### 3.1 borrowBlacklist 判定（必须实现）

对每个 supply incentive opportunity：

```typescript
function isIncentiveZeroed(
  opportunity: MerklOpportunity,
  userBorrowAmount: number,   // 用户在该 token（或 offset token）上的 borrow 量
): boolean {
  if (!opportunity.borrowBlacklist) return false;
  return userBorrowAmount > 0;
}
```

**短路优先**：borrowBlacklist 检查在 netPositionConstraint 之前：

```typescript
function getEffectiveApr(
  opportunity: MerklOpportunity,
  userPositions: Map<string, { supply: number; borrow: number }>,
  sourceReserveId: string,
): number {
  const sourcePos = userPositions.get(sourceReserveId);
  if (!sourcePos) return opportunity.apr;

  // 1. borrowBlacklist 短路：有 borrow → 归零
  if (opportunity.borrowBlacklist && sourcePos.borrow > 0) {
    return 0;
  }

  // 2. netPositionConstraint 按比例抵消
  if (opportunity.netPositionConstraint) {
    const { sourceSide, offsetReserveIds } = opportunity.netPositionConstraint;
    let netPosition = sourceSide === "supply" ? sourcePos.supply : sourcePos.borrow;
    for (const offsetId of offsetReserveIds) {
      const offsetPos = userPositions.get(offsetId);
      if (!offsetPos) continue;
      netPosition -= sourceSide === "supply" ? offsetPos.borrow : offsetPos.supply;
    }
    return Math.max(0, netPosition) * (opportunity.apr / 100) / sourcePos.supply * 100;
  }

  // 3. 普通 opportunity：全额
  return opportunity.apr;
}
```

### 3.2 borrowHookProtocols 展示（可选增强）

`borrowHookProtocols` 提供"哪些协议的 borrow 导致 incentive 归零"的详细信息。前端可在 tooltip 或 detail panel 中展示。

protocol 编号含义（逆向推断，非官方文档）：

| protocol | 推断协议 | borrowBytesLike 内容 |
|---|---|---|
| 0 | Aave 自身 | 64 字节 hash（position identifier） |
| 1 | 未知协议（非 Aave） | vToken/debtToken 地址 |
| 2 | 未知协议（非 Aave） | vToken/debtToken 地址 |
| 3 | 未知协议（非 Aave） | 多个 vToken/debtToken 地址 |

⚠️ protocol 编号的具体含义**没有官方文档**，可能随 Merkl 升级变化。前端展示时应以 `message` 字段的文本为准，`borrowHookProtocols` 仅作为补充信息。

建议展示方式：

```
⚠️ Borrowers of USDtb on any Ethereum-based protocol are not eligible
   Affected protocols: 4 markets across multiple protocols
```

---

## 4. borrowBlacklist 检测机制（后端，供前端理解）

`borrowBlacklist: true` 由两条检测路径触发（OR 关系）：

| 路径 | 条件 | 覆盖场景 |
|---|---|---|
| 路径 1 | `identifier` 含 `BORROW_BL` | Merkl 显式标记的 opportunity |
| 路径 2 | `params.blacklist` 非空 + `params.hooks` 含 `hookType=14` | identifier 未标但实际有跨协议 borrow 排除 |

前端无需关心是哪条路径触发的，只需检查 `borrowBlacklist === true`。

---

## 5. 与 netPositionConstraint 的关系

| | borrowBlacklist | netPositionConstraint |
|---|---|---|
| 语义 | 二元排除（有 borrow → 归零） | 按比例抵消（supply - Σ offset borrows） |
| 检查优先级 | **先检查**（短路归零） | 后检查 |
| 有 borrow 时效果 | incentive = 0 | incentive = netPosition × APR |
| offset 范围 | 任何协议（跨协议） | 同 pool/hub/spoke（Aave 内部） |
| 数据位置 | `opportunity.borrowBlacklist` | `opportunity.netPositionConstraint` |
| 并存情况 | 理论上可能 | borrowBlacklist 短路，NPC 不生效 |

**关键**：同一个 opportunity **不会同时是** borrowBlacklist 和 netPositionConstraint（数据中无此情况）。如果未来出现并存，borrowBlacklist 优先短路归零。

---

## 6. 当前数据分布

5 个 LIVE opportunity 含 `borrowBlacklist: true`：

| Chain | Token | opportunityType | hookType=14 | identifier 含 BORROW_BL |
|---|---|---|---|---|
| Ethereum | USDtb | AAVE_SUPPLY | ✅ (protocol 0,1,2,3) | ✅ |
| Ethereum | USDe | MULTILOG_DUTCH | ✅ (protocol 2) | ✅ |
| Plasma | USDe | MULTILOG_DUTCH | ✅ (protocol 2) | ✅ |
| Mantle | USDe | MULTILOG_DUTCH | ✅ (protocol 2) | ✅ |
| MegaETH | USDe | AAVE_SUPPLY | ✅ (protocol 2) | ✅ |

- 全部是 **supply 侧** incentive
- 全部 **没有 offset tokens**
- 不存在 SUPPLY_BL（0 个 borrow opp 带 `_BL` 后缀）

---

## 7. 前端 Checklist

- [ ] 从 `merklSupplys[i].borrowBlacklist` 读取标记（不是 reserve 顶层）
- [ ] Simulation 中对 `borrowBlacklist: true` 的 opp，检查用户 borrow > 0 → incentive 归零
- [ ] borrowBlacklist 检查在 netPositionConstraint **之前**（短路优先）
- [ ] （可选）从 `/api/meta` → `campaignAccess.campaigns[id].borrowHookProtocols` 获取跨协议详情用于展示
- [ ] 无 `borrowBlacklist` 的 opportunity 保持现有逻辑不变
- [ ] 不需要解析 hookType=14 的具体内容（protocol, borrowBytesLike）来做计算

---

## 8. API 变更摘要

| API | 变更 | 向后兼容 |
|---|---|---|
| `GET /api/markets` | 无新字段（`borrowBlacklist` 已在 AAV-924 添加） | ✅ |
| `GET /api/meta` → `campaignAccess.campaigns[id]` | 新增 `borrowHookProtocols?: { protocol, borrowBytesLike }[]` | ✅ 可选字段 |

---

## 关联文档

- [ADR-0032: borrowBlacklist at CampaignGroup level](../docs/adr/0032-borrow-blacklist-campaigngroup-and-spoke-offset-default.md)
- [ADR-0033: 跨协议 BORROW_BL offset 与 blacklist 自动识别](../docs/adr/0033-cross-protocol-borrow-bl-blacklist-autodetect.md)
- [Net Position Constraint 前端对接指南](./net-position-constraint-frontend-guide.md)
- [BORROW_BL Simulation Handoff](../docs/plans/handoff-borrow-bl-simulation.md)
