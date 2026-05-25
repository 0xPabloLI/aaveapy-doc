# Net Position Constraint — 前端对接指南

**文档版本**: 2026-05-25
**状态**: 后端已实现，前端需适配

---

## 1. 背景

Merkl 上部分 Aave incentive 是 **net position** 类型（`AAVE_NET_LENDING` / `AAVE_NET_BORROWING`），意思是 APR 仅针对 **净仓位**（supply - offset borrows）生效，而非全额 supply/borrow。

例如：Ink 链上 GHO 的 Merkl 机会描述为：

> "Earn rewards on your **net lending position** (GHO supply minus GHO, USDC, USDe, USDG, USD₮0 borrows) on Tydro on Ink"

前端在 Portfolio simulation 中计算实际收益时，**必须用净仓位而非全额仓位**来乘以 APR，否则会高估收益。

---

## 2. 数据位置

`netPositionConstraint` 是 **incentive opportunity 级别**的字段，挂在 `merklSupplys[]` / `merklBorrows[]` / `merklHolds[]` 的每个 opportunity 对象上，**不在 reserve 顶层**。

### 2.1 API 路径

```
GET /api/markets → { snapshot, reserves[] }
```

### 2.2 数据结构

```typescript
interface MerklOpportunity {
  link: string;
  name: string;
  message: string | null;           // 人类可读描述，含 "net lending/borrowing position" 提示
  opportunityType: string;          // "AAVE_NET_LENDING" | "AAVE_NET_BORROWING" | "LENDING" | "BORROWING" 等
  netPositionConstraint?: {         // ⚠️ 仅 net position 类型存在，普通 opportunity 无此字段
    sourceSide: "supply" | "borrow";
    offsetReserveIds: string[];     // 需要从 source 仓位中扣除的 reserve 的 ID 列表
  } | null;
  breakdowns: MerklBreakdown[];
}

interface Reserve {
  // ... 其他字段 ...
  merklSupplys: MerklOpportunity[];  // 每个 opportunity 可能含 netPositionConstraint
  merklBorrows: MerklOpportunity[];
  merklHolds: MerklOpportunity[];
}
```

### 2.3 实际示例（Ink 链 GHO）

```json
{
  "reserveId": "57073:0x2816cf...:0xfc421a...",
  "tokenAddress": "0xfc421aD3C883Bf9E7C4f42dE845C4e4405799e73",
  "merklSupplys": [{
    "name": "Lend GHO on Tydro",
    "opportunityType": "AAVE_NET_LENDING",
    "message": "Earn rewards on your net lending position (GHO supply minus GHO, USDC, USDe, USDG, USD₮0 borrows) on Tydro on Ink",
    "netPositionConstraint": {
      "sourceSide": "supply",
      "offsetReserveIds": [
        "57073:0x2816cf...:0xfc421a...",   // GHO 自身（self-offset：supply 的 GHO 不算 offset，但 GHO borrow 要扣）
        "57073:0x2816cf...:0x2d270e...",   // USDC borrow
        "57073:0x2816cf...:0x5d3a1f...",   // USDe borrow
        "57073:0x2816cf...:0xe34316...",   // USDG borrow
        "57073:0x2816cf...:0x0200c2..."    // USD₮0 borrow
      ]
    },
    "breakdowns": [...]
  }]
}
```

---

## 3. 前端计算逻辑

### 3.1 Portfolio Simulation 中的仓位计算

对每个 incentive opportunity：

1. **无 `netPositionConstraint`** → 用全额仓位（普通 lending/borrowing）
2. **有 `netPositionConstraint`** → 用 **净仓位**：

```typescript
function getEffectivePosition(
  opportunity: MerklOpportunity,
  userPositions: Map<string, { supply: number; borrow: number }>,  // reserveId → 仓位
): number {
  if (!opportunity.netPositionConstraint) {
    // 普通 opportunity：全额仓位
    // 由调用方根据 sourceSide 决定用 supply 还是 borrow
    return -1; // signal: use full position
  }

  const { sourceSide, offsetReserveIds } = opportunity.netPositionConstraint;

  // 先找到 source reserve 的仓位
  // sourceSide = "supply" → 用该 reserve 的 supply 仓位
  // sourceSide = "borrow" → 用该 reserve 的 borrow 仓位
  // （source reserve 就是 merklSupplys/merklBorrows 所属的那个 reserve）

  let netPosition = sourceSide === "supply"
    ? sourceReserveUserSupply   // 用户在该 reserve 的 supply 量
    : sourceReserveUserBorrow;  // 用户在该 reserve 的 borrow 量

  // 减去所有 offset reserve 的仓位
  for (const offsetReserveId of offsetReserveIds) {
    const offsetPos = userPositions.get(offsetReserveId);
    if (!offsetPos) continue;

    // offset 逻辑：
    // sourceSide = "supply" → 减去 offset reserve 的 borrow（净 lending = supply - Σ offset borrows）
    // sourceSide = "borrow" → 减去 offset reserve 的 supply（净 borrowing = borrow - Σ offset supplies）
    netPosition -= sourceSide === "supply"
      ? offsetPos.borrow
      : offsetPos.supply;
  }

  return Math.max(0, netPosition); // 净仓位不可能为负
}
```

### 3.2 APR 收益计算

```typescript
const effectivePosition = getEffectivePosition(opp, userPositions);
const incentiveReward = effectivePosition * (opp.apr / 100);
```

⚠️ **关键**：如果前端仍用全额仓位（忽略 `netPositionConstraint`），收益会被 **严重高估**。例如 GHO net lending 的 APR 只对 `supply - borrows` 生效，但前端若按全额 supply 算，收益会多算 2-5 倍。

---

## 4. 当前数据分布

截至 2026-05-25 Staging 部署（commit `82cebd5`），`netPositionConstraint` 分布：

| 链 | chainId | 有 NPC 的 opportunity 数 |
|----|---------|------------------------|
| Ink | 57073 | 6 |
| Sonic | 4326 | 1 |
| Ethereum | 1 | 1 |
| Gnosis | 100 | — |
| Bob | 9745 | 3 |
| Mantle | 5000 | 6 |

**总计 13 个 reserves、17 个 opportunities** 含 `netPositionConstraint`。

---

## 5. 后端 resolve 规律（供前端理解 offsetReserveIds 构造）

### 5.1 reserveId 格式与版本推断

| 版本 | reserveId 格式 | 段数 | 示例 |
|------|---------------|:----:|------|
| V3 | `{chainId}:{poolAddress}:{tokenAddress}` | 3 | `1:0x87870B...:0x6B1754...` |
| V4 | `{chainId}:{hubAddress}:{assetAddress}:{spokeAddress}` | 4+ | `57073:0x2816cf...:0xfc421a...:0x5a6e5e...` |

**关键区分**：V3 用 `poolAddress`，V4 用 `hubAddress` + 可变段数（spoke chain 地址）。

### 5.2 同 Pool/Spoke 约束

`resolveOffsetReserveIds` 的核心规则：**offset reserve 必须与 source reserve 在同一个 pool/spoke 下**。

1. 从 source reserveId 提取前缀 `chainId:poolAddress`（V3）或 `chainId:hubAddress`（V4）
2. 用该前缀 + offset token 地址拼出候选 reserveId
3. **V3**：唯一匹配 → `prefix:offsetTokenAddr`（三段式，直接查 reserveIdSet）
4. **V4**：可能有多个 spoke → `prefix:offsetTokenAddr:*`（前缀匹配，返回所有 spoke 下的 reserve）

这保证了 **offset 不会跨 pool/hub**，也解释了为什么 V4 的 `offsetReserveIds` 可能包含同一 asset 在多个 spoke 上的 reserve。

### 5.3 反查 Map 构建规律

`tokenAddrToReserveId` 为每个 reserve 注册 **4 种地址映射**：

| 映射 key | 来源字段 | 用途 |
|----------|---------|------|
| `chainId:tokenAddress` | underlying token | V3 主要匹配路径 |
| `chainId:aTokenAddress` | aToken | V3 Merkl opp explorerAddress 可能是 aToken |
| `chainId:vTokenAddress` | vToken/variableDebt token | V3 opp explorerAddress 可能是 vToken |
| `chainId:spokeAddress` | V4 spoke 合约地址 | V4 opp explorerAddress 可能是 spoke 地址 |

Merkl opportunity 的 `explorerAddress` 可能是以上任一地址。反查时用 `chainId:explorerAddress` 去 map 中找对应的 `reserveId`。

### 5.4 resolve 流程总览

```
Merkl opp.explorerAddress
  → tokenAddrToReserveId 查找 → oppReserveId
  → inferVersionFromReserveId(oppReserveId) → v3 | v4
  → extractPoolSpokePrefix(oppReserveId) → chainId:poolOrHub
  → 对每个 offset token address:
      V3: prefix:offsetAddr → 唯一 reserveId
      V4: prefix:offsetAddr:* → 可能多个 spoke 下的 reserveId
```

---

## 6. V4 链的特殊注意

### 6.1 symbol/name 可能缺失

V4 链（Ink chainId=57073 等）的 reserve 可能 **没有 `symbol`/`name`/`underlying` 字段**（API 按 undefined-omit 规则省略）。前端不能用 `symbol` 做 reserve 匹配，必须用 `reserveId` 或 `tokenAddress`。

### 6.2 reserveId 格式

V4 的 `reserveId` 格式为 `{chainId}:{hubAddress}:{assetAddress}`（三段式），V3 是 `{chainId}:{poolAddress}:{tokenAddress}`。前端如果硬编码两段式解析会出错。

---

## 7. opportunityType 值域

| opportunityType | 含义 | 预期有 netPositionConstraint |
|-----------------|------|:---:|
| `LENDING` | 普通 supply 激励 | ❌ |
| `BORROWING` | 普通 borrow 激励 | ❌ |
| `AAVE_NET_LENDING` | Aave 净 supply 仓位激励 | ✅ |
| `AAVE_NET_BORROWING` | Aave 净 borrow 仓位激励 | ✅ |

前端可用 `opportunityType.startsWith("AAVE_NET_")` 快速判断是否需要处理 net position，但**仍应检查 `netPositionConstraint` 字段是否存在**（防御性编程，未来可能有新的 net 类型）。

---

## 8. 前端 Checklist

- [ ] 从 `merklSupplys[i].netPositionConstraint` / `merklBorrows[i].netPositionConstraint` 读取约束（不是从 reserve 顶层）
- [ ] Simulation 中对 `AAVE_NET_LENDING` / `AAVE_NET_BORROWING` 用净仓位计算收益
- [ ] 净仓位 = source 仓位 - Σ(offset reserve 仓位)，clamp ≥ 0
- [ ] 用 `reserveId`（非 `symbol`）匹配 offset reserve
- [ ] V4 链 reserve 可能无 symbol，用 tokenAddress/reserveId 兜底
- [ ] 无 `netPositionConstraint` 的 opportunity 保持全额仓位逻辑不变
