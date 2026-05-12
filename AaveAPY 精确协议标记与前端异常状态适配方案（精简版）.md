# AaveAPY 精确协议标记与前端异常状态适配方案（精简版）

## 权限矩阵

`protocolFlags.reserve` + `supplyDisabled` / `borrowDisabled` 共同构成后端输出的状态数据。前端按 V3/V4 权限矩阵派生用户可见状态和 action gating。

Y = 该状态本身不阻止操作；N = 该状态会阻止操作；Y* = 允许但仍可能受余额、健康因子、cap、用户仓位、isolation/eMode 等非状态条件限制。

### V3 权限矩阵

| 状态组合 | Supply | Borrow | Withdraw | Repay | Liquidate | Enable collateral | Disable collateral | UI 状态 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| paused=true | N | N | N | N | N | N | N | paused |
| frozen=true (paused=false) | N | N | Y* | Y* | Y* | Y* | Y* | frozen |
| paused=false, frozen=false | Y* | Y* | Y* | Y* | Y* | Y* | Y* | normal |
| supplyDisabled=true only | N | Y* | Y* | Y* | Y* | Y* | Y* | supply-disabled |
| borrowDisabled=true only | Y* | N | Y* | Y* | Y* | Y* | Y* | borrow-disabled |

V3 关键：V3 raw response 无 `active` 字段，`protocolFlags.reserve.active` 始终 `undefined`，前端不显示 inactive 状态。frozen 只阻止新 supply / borrow，不阻止 enable collateral。

### V4 权限矩阵

| 状态组合 | Supply | Borrow | Withdraw | Repay | Liquidate | Enable collateral | Disable collateral | UI 状态 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| paused=true | N | N | N | N | N | N | N | paused |
| active=false | N | N | N | N | N | N | N | inactive |
| frozen=true (active=true/unknown, paused=false) | N | N | Y* | Y* | Y* | N | Y* | frozen |
| active=true/unknown, paused=false, frozen=false | Y* | Y* | Y* | Y* | Y* | Y* | Y* | normal |
| supplyDisabled=true only | N | Y* | Y* | Y* | Y* | Y* | Y* | supply-disabled |
| borrowDisabled=true only | Y* | N | Y* | Y* | Y* | Y* | Y* | borrow-disabled |

V4 关键：V4 frozen 会阻止 enable collateral（与 V3 不同）。`status.active/frozen/paused` 来自 raw response 同级 status 对象。

## Raw Response 字段映射

以下基于 `aave-protocol-analysis/data/debug/` 下的实际数据验证。

### V3 raw response — `v3-raw-sdk-response.json`

结构：`markets[].supplyReserves[]` / `markets[].borrowReserves[]`

reserve 顶层状态字段：
- `isFrozen: boolean` — 54/291 为 true
- `isPaused: boolean` — 18/291 为 true
- **没有** `isActive`、`active`、`status` 对象
- `borrowInfo.borrowingState: "ENABLED" | "DISABLED"` — 部分 reserve `borrowInfo` 为 null

V3 映射规则：
- `protocolFlags.reserve.frozen = reserve.isFrozen === true`
- `protocolFlags.reserve.paused = reserve.isPaused === true`
- `protocolFlags.reserve.active` → **不填充**（raw response 无此字段）
- `supplyDisabled` — 维持现有逻辑（综合 frozen / paused / cap）
- `borrowDisabled` — 维持现有逻辑（综合 frozen / paused / borrowingState / cap）

### V4 raw response — `v4-raw-sdk-response.json`

结构：`reserves[]`，每个 reserve 顶层包含：

```text
status: { active: boolean, frozen: boolean, paused: boolean }  ← 三个 flag 同级
canSupply: boolean
canBorrow: boolean
canUseAsCollateral: boolean
canSwapFrom: boolean
```

实际分布（63 reserves）：
- `status.active`: 全部 true
- `status.frozen`: 61 false, 2 true
- `status.paused`: 全部 false
- Frozen 样本：`status={active:true, frozen:true, paused:false}`, `canSupply=false, canBorrow=false, canUseAsCollateral=false`

V4 映射规则：
- `protocolFlags.reserve.active = r.status.active`
- `protocolFlags.reserve.frozen = r.status.frozen`
- `protocolFlags.reserve.paused = r.status.paused`
- `supplyDisabled = !r.canSupply`
- `borrowDisabled = !r.canBorrow`

## API Contract

不新增 `protocolVersion` 字段，前端继续用 `src/lib/protocolVersion.ts` 的 `getProtocolVersion(marketName)` 区分 V3/V4。

### 待新增：`protocolFlags`

```ts
protocolFlags: {
  reserve: {
    active?: boolean;   // V4 从 r.status.active 映射；V3 不输出
    frozen: boolean;    // V3: isFrozen, V4: status.frozen
    paused: boolean;    // V3: isPaused, V4: status.paused
  };
};
```

`protocolFlags` 只承载**协议层事实 tag**（active/frozen/paused），不承载产品的 action gating（supplyDisabled/borrowDisabled 继续独立存在）。

字段语义：
- `reserve.active` — 仅在数据源明确为 `false` 时前端才显示 inactive。V3 不输出，前端视为 unknown。
- `reserve.frozen` / `reserve.paused` — 统一承载 V3 `isFrozen/isPaused` 与 V4 `status.frozen/status.paused`，让 badge、filter、copy 不再依赖不同协议版本的分散字段。

### 维持不变：`supplyDisabled` / `borrowDisabled`

这两个字段保持现有语义不变，始终表示当前产品场景下「新 supply / 新 borrow 不可用」。V3 后端自行计算，V4 从 `!r.canSupply` / `!r.canBorrow` 映射。

### 移除：`isFrozen` / `isPaused`

被 `protocolFlags.reserve.frozen/paused` 替代。前端所有读取 `isFrozen` / `isPaused` 的地方改读 `protocolFlags`。

### 明确不加入首期

`protocolVersion`、`borrowingEnabled`、`borrowable`、`receiveSharesEnabled`、`hub.halted`。前端已有 `getProtocolVersion()` 区分版本，其余字段当前 UI 不消费或 raw response 不提供。

## 后端改动

### `src/index.ts` — V3 构建

`buildV3BaseDataset()` 中新增：
- `protocolFlags.reserve.frozen = reserve.isFrozen === true`
- `protocolFlags.reserve.paused = reserve.isPaused === true`
- `protocolFlags.reserve.active` → **不填**（保持 undefined）

**同时移除**原有的 `isFrozen`、`isPaused` 输出字段。`supplyDisabled`、`borrowDisabled` 维持不变。

### `src/v4-fetcher.ts` — V4 映射

新增：
- `protocolFlags.reserve.active = r.status?.active`
- `protocolFlags.reserve.frozen = r.status?.frozen`
- `protocolFlags.reserve.paused = r.status?.paused`

`supplyDisabled = !r.canSupply`、`borrowDisabled = !r.canBorrow` 维持现有逻辑不变。

**同时移除** `isFrozen`、`isPaused` 输出字段。

### `backend/src/services/marketsApiSerialize.ts`

`serializeReserveForApi()`：透传 `protocolFlags`，移除 `isFrozen`、`isPaused`。`supplyDisabled`、`borrowDisabled` 继续透传。

### `backend/src/types/index.ts`

`MarketWithSpread`：移除 `isFrozen` / `isPaused`，增加 `protocolFlags`。保留 `supplyDisabled` / `borrowDisabled`。

### `src/types/runtime-validation.ts`

`EXPECTED_RUNTIME_FIELDS`：移除 `isFrozen` / `isPaused`，增加 `protocolFlags`。

## 前端适配

### 类型与 Schema

`aaveapy/src/types/aave.ts` — `ReserveWithSpread`：
- 移除 `isFrozen?: boolean`、`isPaused?: boolean`
- 增加 `protocolFlags: ProtocolFlags`
- `supplyDisabled`、`borrowDisabled` 不动

`aaveapy/src/lib/apiSchemas.ts` — zod schema：
- 移除 `isFrozen`、`isPaused`
- 增加 `protocolFlags` schema（`reserve.active/frozen/paused` 均为 optional boolean）

### 新增 `src/lib/reserveStatus.ts` — 唯一的状态派生入口

```ts
export type ReserveRestrictionReason =
  | 'paused'
  | 'frozen'
  | 'inactive'
  | 'supply-disabled'
  | 'borrow-disabled';

export type ReserveAction =
  | 'supply' | 'borrow' | 'withdraw' | 'repay'
  | 'liquidate' | 'enable-collateral' | 'disable-collateral';

export function getReserveFlags(reserve: ReserveWithSpread): {
  frozen: boolean;
  paused: boolean;
  active: boolean | undefined;
}
```

读取规则（直接从 `protocolFlags` 取值）：
- `frozen = reserve.protocolFlags.reserve.frozen`
- `paused = reserve.protocolFlags.reserve.paused`
- `active = reserve.protocolFlags.reserve.active` — 仅在明确 `false` 时产生 inactive reason

`supplyDisabled` / `borrowDisabled` 继续通过 `reserve.supplyDisabled` / `reserve.borrowDisabled` 直接读取，不通过 `getReserveFlags()`。

### Action 派生规则

`getReserveActionState()` 按上方 V3/V4 权限矩阵实现，用 `getProtocolVersion(marketName)` 区分协议版本。

核心规则：
- `paused` 和 `active === false` 是最高优先级，阻止所有 actions
- `supplyDisabled` = 阻止 supply
- `borrowDisabled` = 阻止 borrow
- V3 frozen 阻止 supply / borrow
- V4 frozen 阻止 supply / borrow / enable-collateral
- `active === undefined` 不显示 inactive，exit actions 文案不做无条件承诺

### Primary Status 派生

`getPrimaryReserveStatus()` 返回优先级最高的 restriction reason：

1. `paused` — 最高优先级
2. `inactive` — active 明确为 false 时
3. `frozen`
4. `supply-disabled` — 仅 supplyDisabled=true 且非 paused/frozen/inactive
5. `borrow-disabled` — 仅 borrowDisabled=true 且非以上

### Restricted Reserve 判定

`isRestrictedReserve()`：
- true if paused
- true if frozen
- true if active === false
- 可选：true if supplyDisabled && borrowDisabled

## 异常状态视觉优先级

| 优先级 | 状态 | 样式 |
|---|---|---|
| 1 | paused | 现有 amber 样式 |
| 2 | inactive | 复用 paused 高严重度背景，文案区分 |
| 3 | frozen | 现有 sky 样式 |
| 4 | supply-disabled / borrow-disabled | 不改变整行背景，在 tooltip/simulation banner 中解释 |

多状态时行背景取最高优先级，tooltip 列出全部 reason。

## Show Restricted Assets

- UI 文案改为 "Show restricted assets"
- `isRestrictedReserve()` 按上节定义
- 默认隐藏 restricted assets，开启后显示并通过 status badge 标记原因
- Top Opportunities **不受** toggle 影响，始终按 action-state 过滤

## 组件适配

`src/components/dashboard/FrozenStatusBadge.tsx` → 改名为 `ReserveStatusBadge`：
- Props：`{ reserve }`，内部调用 `getReserveRestrictionReasons()` 和 `getPrimaryReserveStatus()`
- Frozen 文案不再无条件承诺 "can still be repaid, withdrawn"

`src/components/dashboard/DesktopReserveRow.tsx`：
- 行背景：`getPrimaryReserveStatus(reserve)` 决定
- supply gating：直接读 `reserve.supplyDisabled`（不变）
- borrow gating：直接读 `reserve.borrowDisabled`（不变）

`src/components/dashboard/MobileReserveCard.tsx`：
- `isReserveLocked` / `supplyLocked` / `borrowLocked`：supplyDisabled/borrowDisabled 读法不变，locked 判定加 `getReserveFlags()`
- Bottom sheet 使用 `getReserveRestrictionReasons()`

`src/components/dashboard/SimulationSubRow.tsx`：
- `supplySideBlocked` / `borrowSideBlocked`：读法不变
- Disabled banner 文案根据 primary reason 输出

`src/pages/Index.tsx`：
- State 变量名先保留（减少 diff），UI label 改 "Show restricted assets"
- Filter：`!showRestricted && isRestrictedReserve(reserve)` → skip

`src/components/dashboard/TopOpportunities.tsx`：
- Supply 榜：`!reserve.supplyDisabled`（不变）
- Looping 榜：`!reserve.supplyDisabled && !reserve.borrowDisabled`（不变）

## Tooltip 文案

- **Paused**："Paused: reserve actions are halted. Deposits, borrows, repays, withdrawals, collateral changes, and liquidations are blocked."
- **Inactive**："Inactive: the reserve is not active. Most protocol actions are unavailable."
- **Frozen**："Frozen: new deposits and borrows are disabled. Exit actions may remain available when the reserve is active and not paused."
- **Supply disabled**："Supply disabled: new deposits are unavailable for this reserve."
- **Borrow disabled**："Borrow disabled: new borrows are unavailable for this reserve."

多状态按优先级逐段展示。

## 测试策略

**后端**：
- V3 fixture：验证 `isFrozen/isPaused` → `protocolFlags.reserve.frozen/paused`；`active` 不存在；`isFrozen/isPaused` 不再出现在输出
- V4 fixture：验证 `status.active/frozen/paused` 直通 `protocolFlags.reserve.*`
- `marketsApiSerialize.test.ts`：验证 `isFrozen/isPaused` 不再输出，`protocolFlags` 正确透传，`supplyDisabled/borrowDisabled` 继续输出

**前端**：
- `apiSchemas.test.ts`：验证 `protocolFlags` schema 接受，`isFrozen/isPaused` 不在 schema
- `reserveStatus.test.ts`：覆盖 paused、frozen、inactive、supply-disabled、borrow-disabled、多状态、V3/V4 collateral 差异
- `TopOpportunities.test.tsx`：保持现有 supply/looping 过滤逻辑
- `DesktopReserveRow.test.tsx` / `MobileReserveCard.test.tsx`：覆盖 inactive primary status 和多状态 badge

## 分阶段落地

**第一阶段：后端**
- 新增 `protocolFlags.reserve.*`（仅 raw response 已存在的字段）
- 移除 `isFrozen`、`isPaused`
- `supplyDisabled`、`borrowDisabled` 保持不变
- 不输出 protocolVersion、borrowable、receiveSharesEnabled、hub.halted

**第二阶段：前端类型和 Schema**
- 加 `ProtocolFlags` 类型和 zod schema
- 移除 `isFrozen`、`isPaused` 类型和 schema
- 新增 `reserveStatus.ts` helper + 单元测试
- 批量替换 `reserve.isFrozen` → `reserve.protocolFlags.reserve.frozen`、`reserve.isPaused` → `reserve.protocolFlags.reserve.paused`

**第三阶段：UI 消费 helper**
- Badge / row background / mobile sheet / simulation gating / table filter 逐步切到 helper
- `supplyDisabled`/`borrowDisabled` 完全不动

**第四阶段（可选）：Hub halted**
- 如需展示 Hub halted，后端新增链上读取 `IHub.getSpokeConfig(assetId, spoke)` 或等 SDK 暴露
- 一旦有数据，前端只在 `reserveStatus.ts` 增加 reason，不改各组件
