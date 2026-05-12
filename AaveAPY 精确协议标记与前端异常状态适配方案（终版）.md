# AaveAPY 协议状态传递规则与实现方案（终版）

## 一、核心规则：互斥优先级传递

### 1.1 基本原则

`reserveStatus`（协议层原因）和 `supplyDisabled/borrowDisabled`（产品层结果）是**互斥传递**的两个字段组：

> **有协议层原因 → 只传 `reserveStatus`，省略 `supplyDisabled`/`borrowDisabled`**
> **无协议层原因 → 不传 `reserveStatus`，只传 `supplyDisabled`/`borrowDisabled`**

因为 frozen/paused/inactive 必然导致 supply 和 borrow 被禁用，传 `supplyDisabled=true` 是纯冗余。反之，如果只有 cap/borrowingState 导致的禁用，没有 `reserveStatus` 可传。

### 1.2 `reserveStatus` 枚举

```ts
type ReserveStatus = 'paused' | 'paused+frozen' | 'inactive' | 'frozen';
```

优先级顺序（决定行背景色、主 badge）：
1. `paused` — 最高（所有 actions 被暂停）
2. `paused+frozen` — 前端以 paused 视觉呈现
3. `inactive` — 仅 V4，reserve 不活跃
4. `frozen` — 仅 supply/borrow 被阻止，其余 action 视版本而定

---

## 二、所有状态组合枚举

### 2.1 V3 协议

V3 raw response 有 `isFrozen`、`isPaused`，没有 `active`。

| # | isFrozen | isPaused | 后端输出 | 说明 |
|---|---|---|---|---|
| 1 | true | false | `reserveStatus: "frozen"` | 不传 `supplyDisabled`/`borrowDisabled` |
| 2 | false | true | `reserveStatus: "paused"` | 不传 `supplyDisabled`/`borrowDisabled` |
| 3 | true | true | `reserveStatus: "paused+frozen"` | 不传 `supplyDisabled`/`borrowDisabled` |
| 4 | false | false | 不传 `reserveStatus` | 传 `supplyDisabled`/`borrowDisabled`（cap/borrowingState 决定） |

**组合 #4（无协议状态）下的子情况：**

| supplyCap | borrowingState / borrowCap | 输出 |
|---|---|---|
| =1 | normal | `"supplyDisabled": true` |
| ≠1 | DISABLED 或 borrowCap=1 | `"borrowDisabled": true` |
| =1 | DISABLED | `"supplyDisabled": true, "borrowDisabled": true` |
| ≠1 | normal | 都不输出（正常资产） |

### 2.2 V4 协议

V4 raw response 有 `status.active`、`status.frozen`、`status.paused`。

| # | active | frozen | paused | 后端输出 | 说明 |
|---|---|---|---|---|---|
| 1 | * | false | true | `reserveStatus: "paused"` | 不传 `supplyDisabled`/`borrowDisabled` |
| 2 | * | true | true | `reserveStatus: "paused+frozen"` | 不传 `supplyDisabled`/`borrowDisabled` |
| 3 | false | * | false | `reserveStatus: "inactive"` | 不传 `supplyDisabled`/`borrowDisabled`；paused 优先于 inactive |
| 4 | true | true | false | `reserveStatus: "frozen"` | 不传 `supplyDisabled`/`borrowDisabled` |
| 5 | true | false | false | 不传 `reserveStatus` | 传 `supplyDisabled`/`borrowDisabled`（`!canSupply`/`!canBorrow`） |

**组合 #5（无协议状态）下的子情况：**

| canSupply | canBorrow | 输出 |
|---|---|---|
| false | true | `"supplyDisabled": true` |
| true | false | `"borrowDisabled": true` |
| false | false | `"supplyDisabled": true, "borrowDisabled": true` |
| true | true | 都不输出（正常资产） |

### 2.3 为什么 V3 没有 `"inactive"`

V3 raw response 没有 `active` 字段，无法判断 reserve 是否 inactive。只有 V4 数据源提供了 `r.status.active` 才能输出 `"inactive"`。

### 2.4 为什么 `active=true` 不传 `"active"`

`active=true` 是正常态，没有任何前端消费价值。只在 `active=false` 时才输出 `"inactive"`。

---

## 三、权限矩阵

### 3.1 V3

| reserveStatus | Supply | Borrow | Withdraw | Repay | Liquidate | Enable collateral | Disable collateral |
|---|---|---|---|---|---|---|---|
| `"paused"` | N | N | N | N | N | N | N |
| `"paused+frozen"` | N | N | N | N | N | N | N |
| `"frozen"` | N | N | Y* | Y* | Y* | Y* | Y* |
| _(无)_ supplyDisabled=true | N | Y* | Y* | Y* | Y* | Y* | Y* |
| _(无)_ borrowDisabled=true | Y* | N | Y* | Y* | Y* | Y* | Y* |
| _(无)_ 均 false | Y* | Y* | Y* | Y* | Y* | Y* | Y* |

### 3.2 V4

| reserveStatus | Supply | Borrow | Withdraw | Repay | Liquidate | Enable collateral | Disable collateral |
|---|---|---|---|---|---|---|---|
| `"paused"` | N | N | N | N | N | N | N |
| `"paused+frozen"` | N | N | N | N | N | N | N |
| `"inactive"` | N | N | N | N | N | N | N |
| `"frozen"` | N | N | Y* | Y* | Y* | **N** | Y* |
| _(无)_ supplyDisabled=true | N | Y* | Y* | Y* | Y* | Y* | Y* |
| _(无)_ borrowDisabled=true | Y* | N | Y* | Y* | Y* | Y* | Y* |
| _(无)_ 均 false | Y* | Y* | Y* | Y* | Y* | Y* | Y* |

V3 vs V4 关键差异：**V4 frozen 阻止 enable collateral，V3 不阻止**。

---

## 四、API Contract

### 4.1 新增字段：`reserveStatus`

```ts
reserveStatus?: 'paused' | 'paused+frozen' | 'inactive' | 'frozen';
```

| 值 | 出现条件 | 出现协议 |
|---|---|---|
| `"paused"` | paused=true，frozen=false | V3/V4 |
| `"paused+frozen"` | paused=true，frozen=true | V3/V4 |
| `"inactive"` | active=false，paused=false | **仅 V4** |
| `"frozen"` | frozen=true，paused=false，active≠false | V3/V4 |
| _(无)_ | paused=false，frozen=false，active≠false | V3/V4 |

### 4.2 维持不变：`supplyDisabled` / `borrowDisabled`

仅在 `reserveStatus` 不存在（即无协议层限制）时输出：

- V3：由 `supplyCap=1` / `borrowingState=DISABLED` / `borrowCap=1` 决定
- V4：由 `!r.canSupply` / `!r.canBorrow` 决定（`canSupply`/`canBorrow` 来自 SDK raw response 顶层字段）

### 4.3 移除：`isFrozen` / `isPaused`

被 `reserveStatus` 替代。

### 4.4 互斥规则图示

```text
后端判断流程：

1. paused=true?
   ├── YES, frozen=true? → reserveStatus: "paused+frozen"    [不传 supplyDisabled/borrowDisabled]
   ├── YES, frozen=false → reserveStatus: "paused"            [不传 supplyDisabled/borrowDisabled]
   └── NO → 继续

2. (仅 V4) active=false?
   └── YES → reserveStatus: "inactive"                        [不传 supplyDisabled/borrowDisabled]

3. frozen=true?
   └── YES → reserveStatus: "frozen"                          [不传 supplyDisabled/borrowDisabled]

4. 均 false → 不传 reserveStatus，仅传 supplyDisabled/borrowDisabled
```

---

## 五、前端 helper（`reserveStatus.ts`）

### 5.1 `getReserveFlags()`

```ts
import type { ReserveWithSpread } from '@/types/aave';

export function getReserveFlags(reserve: ReserveWithSpread): {
  paused: boolean;
  inactive: boolean;
  frozen: boolean;
} {
  const s = reserve.reserveStatus;
  if (!s) return { paused: false, inactive: false, frozen: false };

  if (s === 'paused' || s === 'paused+frozen') {
    return { paused: true, inactive: false, frozen: s === 'paused+frozen' };
  }
  if (s === 'inactive') return { paused: false, inactive: true, frozen: false };
  // s === 'frozen'
  return { paused: false, inactive: false, frozen: true };
}
```

### 5.2 `isSupplyDisabled()` / `isBorrowDisabled()`

```ts
/** 综合 reserveStatus + supplyDisabled 的 supply gate。 */
export function isSupplyDisabled(reserve: ReserveWithSpread): boolean {
  return !!reserve.reserveStatus || reserve.supplyDisabled === true;
}

/** 综合 reserveStatus + borrowDisabled 的 borrow gate。 */
export function isBorrowDisabled(reserve: ReserveWithSpread): boolean {
  return !!reserve.reserveStatus || reserve.borrowDisabled === true;
}
```

### 5.3 原因列表和主状态

```ts
export type ReserveRestrictionReason =
  | 'paused' | 'inactive' | 'frozen' | 'supply-disabled' | 'borrow-disabled';

export function getReserveRestrictionReasons(
  reserve: ReserveWithSpread
): ReserveRestrictionReason[] {
  const { paused, inactive, frozen } = getReserveFlags(reserve);
  const reasons: ReserveRestrictionReason[] = [];
  if (paused) reasons.push('paused');
  if (inactive) reasons.push('inactive');
  if (frozen) reasons.push('frozen');
  if (!reserve.reserveStatus) {
    if (reserve.supplyDisabled) reasons.push('supply-disabled');
    if (reserve.borrowDisabled) reasons.push('borrow-disabled');
  }
  return reasons;
}

export function getPrimaryReserveStatus(
  reserve: ReserveWithSpread
): ReserveRestrictionReason | null {
  return getReserveRestrictionReasons(reserve)[0] ?? null;
}
```

### 5.4 Action 状态判断

```ts
import { getProtocolVersion } from '@/lib/protocolVersion';

export type ReserveAction =
  | 'supply' | 'borrow' | 'withdraw' | 'repay'
  | 'liquidate' | 'enable-collateral' | 'disable-collateral';

export function getReserveActionState(
  reserve: ReserveWithSpread,
  action: ReserveAction,
): { available: boolean; reasons: ReserveRestrictionReason[] } {
  const { paused, inactive, frozen } = getReserveFlags(reserve);
  const isV4 = getProtocolVersion(reserve.marketName) === 'v4';
  const reasons: ReserveRestrictionReason[] = [];

  if (paused) reasons.push('paused');
  if (inactive) reasons.push('inactive');

  switch (action) {
    case 'supply':
      if (frozen) reasons.push('frozen');
      if (isSupplyDisabled(reserve) && !paused && !inactive) reasons.push('supply-disabled');
      break;
    case 'borrow':
      if (frozen) reasons.push('frozen');
      if (isBorrowDisabled(reserve) && !paused && !inactive) reasons.push('borrow-disabled');
      break;
    case 'enable-collateral':
      if (isV4 && frozen) reasons.push('frozen');
      break;
    default:
      break;
  }

  return { available: reasons.length === 0, reasons };
}
```

### 5.5 Restricted Reserve 判定

```ts
export function isRestrictedReserve(reserve: ReserveWithSpread): boolean {
  return !!reserve.reserveStatus;
}
```

---

## 六、后端改动

### 6.1 不需要新建文件

`reserveStatus` 只是一个 `string` 字段，不需要 `protocolFlags.ts`。

### 6.2 `src/index.ts`（V3）

**类型**：`RuntimeReserveData` 移除 `isFrozen`/`isPaused`，新增 `reserveStatus?: string`。

**构建逻辑**：

```ts
const isFrozen = reserve.isFrozen === true;
const isPaused = reserve.isPaused === true;

let reserveStatus: string | undefined;
if (isPaused && isFrozen) reserveStatus = 'paused+frozen';
else if (isPaused) reserveStatus = 'paused';
else if (isFrozen) reserveStatus = 'frozen';

const hasProtocolReason = !!reserveStatus;

// cap 原因（仅在无协议层限制时有意义）
const supplyCapIsOne = supplyCapValue !== undefined && toFiniteNumber(supplyCapValue) === 1;
const isBorrowDisabledByState = reserve.borrowInfo?.borrowingState === "DISABLED" || reserve.borrowInfo === null;
const borrowCapIsOne = borrowCapValue !== undefined && toFiniteNumber(borrowCapValue) === 1;

baseDataset.push({
  // ...其他字段不变
  ...(reserveStatus ? { reserveStatus } : {}),
  ...(!hasProtocolReason && supplyCapIsOne ? { supplyDisabled: true } : {}),
  ...(!hasProtocolReason && (isBorrowDisabledByState || borrowCapIsOne) ? { borrowDisabled: true } : {}),
});
```

### 6.3 `src/v4-fetcher.ts`（V4）

```ts
const isFrozen = r.status?.frozen === true;
const isPaused = r.status?.paused === true;
const isInactive = r.status?.active === false;
const canSupply: boolean = r.canSupply ?? true;
const canBorrow: boolean = r.canBorrow ?? true;

let reserveStatus: string | undefined;
if (isPaused && isFrozen) reserveStatus = 'paused+frozen';
else if (isPaused) reserveStatus = 'paused';
else if (isInactive) reserveStatus = 'inactive';
else if (isFrozen) reserveStatus = 'frozen';

const hasProtocolReason = !!reserveStatus;

dataset.push({
  // ...其他字段不变
  ...(reserveStatus ? { reserveStatus } : {}),
  ...(!hasProtocolReason && !canSupply ? { supplyDisabled: true } : {}),
  ...(!hasProtocolReason && !canBorrow ? { borrowDisabled: true } : {}),
});
```

### 6.4 `backend/src/types/index.ts`

`MarketWithSpread`：移除 `isFrozen`/`isPaused`，新增 `reserveStatus?: string`。保留 `supplyDisabled`/`borrowDisabled`。

### 6.5 `backend/src/services/marketsApiSerialize.ts`

移除 `isFrozen`/`isPaused` 序列化，新增 `reserveStatus` 透传。`supplyDisabled`/`borrowDisabled` 保持不变透传。

### 6.6 `src/types/runtime-validation.ts`

```diff
- 'isFrozen',
- 'isPaused',
+ 'reserveStatus',
```

---

## 七、前端改动

### 7.1 类型和 Schema

`aaveapy/src/types/aave.ts`：

```diff
- isFrozen?: boolean;
- isPaused?: boolean;
+ reserveStatus?: 'paused' | 'paused+frozen' | 'inactive' | 'frozen';
  supplyDisabled?: boolean;
  borrowDisabled?: boolean;
```

`aaveapy/src/lib/apiSchemas.ts`：

```diff
- isFrozen: z.boolean().optional(),
- isPaused: z.boolean().optional(),
+ reserveStatus: z.enum(['paused', 'paused+frozen', 'inactive', 'frozen']).optional(),
```

### 7.2 新建 `aaveapy/src/lib/reserveStatus.ts`

完整实现见第五章。

### 7.3 组件改动

所有直接判断 `reserve.isFrozen`/`reserve.isPaused`/`reserve.supplyDisabled` 的地方改为走 helper：

```diff
// DesktopReserveRow.tsx L166
- const supplyBlocked = !!(reserve.isPaused || reserve.isFrozen || reserve.supplyDisabled);
+ const supplyBlocked = isSupplyDisabled(reserve);

// SimulationSubRow.tsx L199
- const isReserveLocked = Boolean(reserve.isFrozen || reserve.isPaused);
+ const isReserveLocked = !!reserve.reserveStatus;

// SimulationSubRow.tsx L219
- const supplySideBlocked = !!(reserve.isPaused || reserve.isFrozen || reserve.supplyDisabled);
+ const supplySideBlocked = isSupplyDisabled(reserve);

// Index.tsx L281
- if (!showFrozenOrPaused && (reserve.isFrozen || reserve.isPaused)) {
+ if (!showFrozenOrPaused && !!reserve.reserveStatus) {

// TopOpportunities.tsx L747
- }).filter(r => !r.isFrozen && !r.isPaused)
+ }).filter(r => !r.reserveStatus)
```

`FrozenStatusBadge.tsx` → 重命名为 `ReserveStatusBadge.tsx`，props 从 `{ isFrozen, isPaused }` 改为 `{ reserve }`，内部调用 `getReserveFlags()`。

`FilterBar.tsx`：仅改 UI label："Show frozen or paused assets" → "Show restricted assets"。

### 7.4 测试文件更新

所有 fixture 中的 `isFrozen`/`isPaused` → `reserveStatus`。涉及 9 个测试文件。

---

## 八、API 响应示例

### V3 frozen

```json
{ "reserveId": "...", "reserveStatus": "frozen", "supplyApy": 3.2 }
```

### V3 paused

```json
{ "reserveId": "...", "reserveStatus": "paused" }
```

### V3 paused+frozen

```json
{ "reserveId": "...", "reserveStatus": "paused+frozen" }
```

### V3 cap=1，无协议限制

```json
{ "reserveId": "...", "supplyDisabled": true }
```

### V3 normal

```json
{ "reserveId": "..." }
```

### V4 frozen

```json
{ "reserveId": "...", "reserveStatus": "frozen" }
```

### V4 inactive

```json
{ "reserveId": "...", "reserveStatus": "inactive" }
```

### V4 paused+frozen

```json
{ "reserveId": "...", "reserveStatus": "paused+frozen" }
```

---

## 九、改动文件清单

### 后端（5 文件，不新建文件）

| 文件 | 改动 |
|---|---|
| `src/index.ts` | 类型：移除 `isFrozen`/`isPaused`，新增 `reserveStatus`。V3 互斥构建逻辑 |
| `src/v4-fetcher.ts` | 同上，V4 增加 inactive 判定 |
| `backend/src/types/index.ts` | 类型同步 |
| `backend/src/services/marketsApiSerialize.ts` | 序列化适配 |
| `src/types/runtime-validation.ts` | 注册表更新 |

### 前端（5 文件 + 1 新建 + 9 测试）

| 文件 | 改动 |
|---|---|
| `src/types/aave.ts` | `isFrozen`/`isPaused` → `reserveStatus` |
| `src/lib/apiSchemas.ts` | zod schema |
| `src/lib/reserveStatus.ts` | **新建** |
| `FrozenStatusBadge.tsx` → `ReserveStatusBadge.tsx` | **重命名**，props → `{ reserve }` |
| `DesktopReserveRow.tsx` | gating → `isSupplyDisabled()` |
| `MobileReserveCard.tsx` | 同上 |
| `SimulationSubRow.tsx` | 同上 |
| `Index.tsx` | filter → `!!reserve.reserveStatus` |
| `TopOpportunities.tsx` | filter → `!r.reserveStatus` |
| `FilterBar.tsx` | label 更新 |
| 9 个测试文件 | fixture 更新 |

---

## 十、分阶段执行

### Phase 1：后端
1. 更新 `src/types/runtime-validation.ts`
2. 更新 `src/index.ts`（类型 + 互斥构建逻辑）
3. 更新 `src/v4-fetcher.ts`（类型 + 互斥构建逻辑）
4. 更新 `backend/src/types/index.ts`
5. 更新 `backend/src/services/marketsApiSerialize.ts`
6. `npm run build && npm --prefix backend run build && npm --prefix backend run test`

### Phase 2：前端类型 + helper + 测试
1. 更新 `aaveapy/src/types/aave.ts`
2. 更新 `aaveapy/src/lib/apiSchemas.ts`
3. 新建 `aaveapy/src/lib/reserveStatus.ts`
4. 写 `reserveStatus.test.ts` + 更新 `apiSchemas.test.ts`

### Phase 3：组件切换
1. `ReserveStatusBadge.tsx`（重命名）
2. `DesktopReserveRow.tsx` + `MobileReserveCard.tsx`
3. `SimulationSubRow.tsx`
4. `Index.tsx` + `TopOpportunities.tsx` + `FilterBar.tsx`
5. 更新 9 个测试文件
</parameter>