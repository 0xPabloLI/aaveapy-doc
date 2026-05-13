# AaveAPY 精确协议标记与前端异常状态适配 — 实现方案

> 基于实际代码的逐文件修改指南。目标：新增 `protocolFlags` 统一 V3/V4 协议 tag，移除分散的 `isFrozen`/`isPaused`，维持 `supplyDisabled`/`borrowDisabled` 不变。

---

## 一、类型定义

```ts
// 路径：aave-protocol-analysis/src/types/protocolFlags.ts（新建）

export interface ProtocolFlags {
  reserve: {
    active?: boolean;   // V4 从 r.status.active 映射；V3 不输出
    frozen: boolean;    // V3: isFrozen, V4: status.frozen
    paused: boolean;    // V3: isPaused, V4: status.paused
  };
}
```

---

## 二、后端改动（aave-protocol-analysis）

### 2.1 `src/index.ts` — RuntimeReserveData 类型

**当前代码**：[src/index.ts:L66-L70](file:///Users/pabloli/Documents/code/aave-protocol-analysis/src/index.ts#L66-L70)

```diff
  supplyDisabled?: boolean;
- isFrozen?: boolean;
- isPaused?: boolean;
+ protocolFlags?: ProtocolFlags;
  borrowApy?: number;
  borrowDisabled?: boolean;
```

### 2.2 `src/index.ts` — buildV3BaseDataset() 构建逻辑

**当前代码**：[src/index.ts:L403-L424](file:///Users/pabloli/Documents/code/aave-protocol-analysis/src/index.ts#L403-L424)

在 freeze/pause 判定后新增 protocolFlags 构建：

```diff
  const isFrozen = reserve.isFrozen === true;
  const isPaused = reserve.isPaused === true;
+ const protocolFlags: ProtocolFlags = {
+   reserve: {
+     frozen: isFrozen,
+     paused: isPaused,
+     // active 不填 — V3 raw response 无此字段
+   },
+ };
```

**当前代码**：[src/index.ts:L479-L484](file:///Users/pabloli/Documents/code/aave-protocol-analysis/src/index.ts#L479-L484)

输出对象中移除 isFrozen/isPaused，加入 protocolFlags：

```diff
  baseDataset.push({
    // ... 其他字段不变 ...
    supplyApy,
-   ...(isSupplyDisabled ? { supplyDisabled: true } : {}),
-   ...(isFrozen ? { isFrozen: true } : {}),
-   ...(isPaused ? { isPaused: true } : {}),
+   ...(isSupplyDisabled ? { supplyDisabled: true } : {}),  // 保持不变
+   protocolFlags,
    borrowApy,
-   ...(isBorrowDisabled ? { borrowDisabled: true } : {}),
+   ...(isBorrowDisabled ? { borrowDisabled: true } : {}),  // 保持不变
```

### 2.3 `src/v4-fetcher.ts` — V4FormattedReserveData 类型

**当前代码**：[src/v4-fetcher.ts:L39-L43](file:///Users/pabloli/Documents/code/aave-protocol-analysis/src/v4-fetcher.ts#L39-L43)

```diff
  supplyDisabled?: boolean;
- isFrozen?: boolean;
- isPaused?: boolean;
+ protocolFlags?: ProtocolFlags;
  borrowApy: number | undefined;
  borrowDisabled?: boolean;
```

### 2.4 `src/v4-fetcher.ts` — V4 映射逻辑

**当前代码**：[src/v4-fetcher.ts:L155-L160](file:///Users/pabloli/Documents/code/aave-protocol-analysis/src/v4-fetcher.ts#L155-L160)

```diff
  const isFrozen = r.status?.frozen === true;
  const isPaused = r.status?.paused === true;
  const canSupply: boolean = r.canSupply ?? true;
  const canBorrow: boolean = r.canBorrow ?? true;
  const supplyDisabled = !canSupply;
  const borrowDisabled = !canBorrow;
+ const protocolFlags: ProtocolFlags = {
+   reserve: {
+     active: r.status?.active,
+     frozen: isFrozen,
+     paused: isPaused,
+   },
+ };
```

**当前代码**：[src/v4-fetcher.ts:L201-L205](file:///Users/pabloli/Documents/code/aave-protocol-analysis/src/v4-fetcher.ts#L201-L205)

输出对象：

```diff
  dataset.push({
    // ... 其他字段不变 ...
    supplyApy,
-   ...(supplyDisabled ? { supplyDisabled: true } : {}),
-   ...(isFrozen ? { isFrozen: true } : {}),
-   ...(isPaused ? { isPaused: true } : {}),
+   ...(supplyDisabled ? { supplyDisabled: true } : {}),  // 保持不变
+   protocolFlags,
    borrowApy,
-   ...(borrowDisabled ? { borrowDisabled: true } : {}),
+   ...(borrowDisabled ? { borrowDisabled: true } : {}),  // 保持不变
```

### 2.5 `backend/src/types/index.ts` — MarketWithSpread

**当前代码**：[backend/src/types/index.ts:L37-L41](file:///Users/pabloli/Documents/code/aave-protocol-analysis/backend/src/types/index.ts#L37-L41)

```diff
  supplyDisabled?: boolean;
- isFrozen?: boolean;
- isPaused?: boolean;
+ protocolFlags?: ProtocolFlags;
  borrowApy?: number | null;
  borrowDisabled?: boolean;
```

### 2.6 `backend/src/services/marketsApiSerialize.ts` — 序列化

**当前代码**：[backend/src/services/marketsApiSerialize.ts:L75-L79](file:///Users/pabloli/Documents/code/aave-protocol-analysis/backend/src/services/marketsApiSerialize.ts#L75-L79)

```diff
    ...(reserve.supplyDisabled ? { supplyDisabled: true } : {}),
-   ...(reserve.isFrozen ? { isFrozen: true } : {}),
-   ...(reserve.isPaused ? { isPaused: true } : {}),
+   ...(reserve.protocolFlags ? { protocolFlags: reserve.protocolFlags } : {}),
    ...(reserve.borrowApy !== undefined ? { borrowApy: reserve.borrowApy * 100 } : {}),
    ...(reserve.borrowDisabled ? { borrowDisabled: true } : {}),
```

### 2.7 `src/types/runtime-validation.ts` — 字段注册表

**当前代码**：[src/types/runtime-validation.ts:L21-L25](file:///Users/pabloli/Documents/code/aave-protocol-analysis/src/types/runtime-validation.ts#L21-L25)

```diff
  'supplyDisabled',
- 'isFrozen',
- 'isPaused',
+ 'protocolFlags',
  'borrowApy',
  'borrowDisabled',
```

### 2.8 新建 `src/types/protocolFlags.ts`

```ts
export interface ProtocolFlags {
  reserve: {
    active?: boolean;
    frozen: boolean;
    paused: boolean;
  };
}
```

后端各文件的 import 需新增：
```ts
import type { ProtocolFlags } from '../types/protocolFlags.js';
```

---

## 三、前端改动（aaveapy）

### 3.1 `src/types/aave.ts` — ReserveWithSpread 类型

**当前代码**：[src/types/aave.ts:L118-L121](file:///Users/pabloli/Documents/code/aaveapy/src/types/aave.ts#L118-L121)

```diff
  supplyDisabled?: boolean;
- isFrozen?: boolean;
- isPaused?: boolean;
+ protocolFlags?: {
+   reserve: {
+     active?: boolean;
+     frozen: boolean;
+     paused: boolean;
+   };
+ };
  borrowDisabled?: boolean;
```

### 3.2 `src/lib/apiSchemas.ts` — Zod Schema

**当前代码**：[src/lib/apiSchemas.ts:L129-L131](file:///Users/pabloli/Documents/code/aaveapy/src/lib/apiSchemas.ts#L129-L131)

```diff
  supplyDisabled: z.boolean().optional(),
- isFrozen: z.boolean().optional(),
- isPaused: z.boolean().optional(),
+ protocolFlags: z.object({
+   reserve: z.object({
+     active: z.boolean().optional(),
+     frozen: z.boolean(),
+     paused: z.boolean(),
+   }),
+ }).optional(),
  aTokenAddress: z.string().nullish(),
```

### 3.3 新建 `src/lib/reserveStatus.ts` — 唯一的状态派生入口

```ts
import type { ReserveWithSpread } from '@/types/aave';
import { getProtocolVersion } from '@/lib/protocolVersion';

export type ReserveRestrictionReason =
  | 'paused'
  | 'frozen'
  | 'inactive'
  | 'supply-disabled'
  | 'borrow-disabled';

export type ReserveAction =
  | 'supply' | 'borrow' | 'withdraw' | 'repay'
  | 'liquidate' | 'enable-collateral' | 'disable-collateral';

/**
 * 归一化读取协议 tag — 直接从 protocolFlags 取值。
 * V3 没有 active 字段时返回 undefined。
 */
export function getReserveFlags(reserve: ReserveWithSpread): {
  frozen: boolean;
  paused: boolean;
  active: boolean | undefined;
} {
  const flags = reserve.protocolFlags?.reserve;
  return {
    frozen: flags?.frozen ?? false,
    paused: flags?.paused ?? false,
    active: flags?.active, // undefined = unknown (V3)
  };
}

/**
 * 列出当前 reserve 的所有限制原因（按优先级排序）。
 */
export function getReserveRestrictionReasons(
  reserve: ReserveWithSpread
): ReserveRestrictionReason[] {
  const { frozen, paused, active } = getReserveFlags(reserve);
  const reasons: ReserveRestrictionReason[] = [];

  if (paused) reasons.push('paused');
  if (active === false) reasons.push('inactive');
  if (frozen) reasons.push('frozen');
  if (reserve.supplyDisabled) reasons.push('supply-disabled');
  if (reserve.borrowDisabled) reasons.push('borrow-disabled');

  return reasons;
}

/**
 * 最高优先级的限制原因（用于行背景色、主 badge）。
 */
export function getPrimaryReserveStatus(
  reserve: ReserveWithSpread
): ReserveRestrictionReason | null {
  return getReserveRestrictionReasons(reserve)[0] ?? null;
}

/**
 * 该资产是否被视为「受限制资产」（默认隐藏，需用户手动开启 Show restricted assets）。
 */
export function isRestrictedReserve(reserve: ReserveWithSpread): boolean {
  const { frozen, paused, active } = getReserveFlags(reserve);
  return paused || frozen || active === false;
}

/**
 * 按 V3/V4 权限矩阵，判断指定 action 是否可用。
 */
export function getReserveActionState(
  reserve: ReserveWithSpread,
  action: ReserveAction,
): { available: boolean | 'unknown'; reasons: ReserveRestrictionReason[] } {
  const { frozen, paused, active } = getReserveFlags(reserve);
  const protocolVersion = getProtocolVersion(reserve.marketName);
  const isV4 = protocolVersion === 'v4';
  const reasons: ReserveRestrictionReason[] = [];

  // paused / inactive 阻止一切
  if (paused) reasons.push('paused');
  if (active === false) reasons.push('inactive');

  switch (action) {
    case 'supply':
      if (frozen) reasons.push('frozen');
      if (reserve.supplyDisabled) reasons.push('supply-disabled');
      break;
    case 'borrow':
      if (frozen) reasons.push('frozen');
      if (reserve.borrowDisabled) reasons.push('borrow-disabled');
      break;
    case 'enable-collateral':
      if (isV4 && frozen) reasons.push('frozen');
      // V3 frozen 不阻止 enable collateral
      break;
    // withdraw / repay / liquidate / disable-collateral:
    // paused/inactive 已在上方捕获，其余无 protocol-level 阻止
    default:
      break;
  }

  return {
    available: reasons.length === 0 ? true : false,
    reasons,
  };
}
```

### 3.4 `src/components/dashboard/FrozenStatusBadge.tsx` → 重命名为 `ReserveStatusBadge.tsx`

**当前代码**：[src/components/dashboard/FrozenStatusBadge.tsx](file:///Users/pabloli/Documents/code/aaveapy/src/components/dashboard/FrozenStatusBadge.tsx)

核心改动：
- Props 从 `{ isFrozen, isPaused }` 改为 `{ reserve: ReserveWithSpread }`
- 内部调用 `getReserveRestrictionReasons()` 和 `getPrimaryReserveStatus()`
- Frozen tooltip 文案不再写 "can still be repaid, withdrawn, and liquidated"，改为条件式

```diff
-interface FrozenStatusBadgeProps {
-  isFrozen?: boolean;
-  isPaused?: boolean;
-}
-
-export function FrozenStatusBadge({ isFrozen, isPaused }: FrozenStatusBadgeProps) {
-  const [open, setOpen] = useState(false);
-  if (!isFrozen && !isPaused) return null;
-
-  const labels: string[] = [];
-  if (isFrozen) labels.push('Frozen');
-  if (isPaused) labels.push('Paused');
+import { getReserveRestrictionReasons, getPrimaryReserveStatus } from '@/lib/reserveStatus';
+import type { ReserveWithSpread } from '@/types/aave';
+
+export function ReserveStatusBadge({ reserve }: { reserve: ReserveWithSpread }) {
+  const [open, setOpen] = useState(false);
+  const reasons = getReserveRestrictionReasons(reserve);
+  const primary = getPrimaryReserveStatus(reserve);
+  if (reasons.length === 0) return null;
+
+  const labels: string[] = [];
+  if (reasons.includes('paused')) labels.push('Paused');
+  if (reasons.includes('inactive')) labels.push('Inactive');
+  if (reasons.includes('frozen')) labels.push('Frozen');

-  return (
-    <Tooltip open={open} onOpenChange={setOpen} delayDuration={0}>
-      <TooltipTrigger asChild>
-        <button ...>
-          {isFrozen && <Snowflake ... />}
-          {isPaused && <PauseCircle ... />}
-        </button>
-      </TooltipTrigger>
-      <TooltipContent>
-        <FrozenStatusContent isFrozen={isFrozen} isPaused={isPaused} />
-      </TooltipContent>
-    </Tooltip>
-  );
+  return (
+    <Tooltip ...>
+      <TooltipTrigger ...>
+        <button ...>
+          {reasons.includes('frozen') && <Snowflake ... />}
+          {reasons.includes('paused') && <PauseCircle ... />}
+        </button>
+      </TooltipTrigger>
+      <TooltipContent>
+        <ReserveStatusContent reasons={reasons} />
+      </TooltipContent>
+    </Tooltip>
+  );
```

`FrozenStatusContent` 改为 `ReserveStatusContent`，接受 reasons 数组，文案改为条件式：

- **Paused**："Paused: all reserve actions are halted."
- **Inactive**："Inactive: the reserve is not active."
- **Frozen**："Frozen: new deposits and borrows are disabled."（不再承诺 exit actions 一定可用）
- **Supply disabled** / **Borrow disabled**：对应文案

### 3.5 `src/components/dashboard/DesktopReserveRow.tsx`

**当前代码**：[src/components/dashboard/DesktopReserveRow.tsx](file:///Users/pabloli/Documents/code/aaveapy/src/components/dashboard/DesktopReserveRow.tsx)

**(a) L163-L166 — supplyBlocked / borrowBlocked：**

```diff
+import { getPrimaryReserveStatus, getReserveActionState } from '@/lib/reserveStatus';

- const supplyBlocked = !!(reserve.isPaused || reserve.isFrozen || reserve.supplyDisabled);
- const borrowBlocked = !!(reserve.isPaused || reserve.isFrozen || reserve.borrowDisabled);
+ const supplyBlocked = getReserveActionState(reserve, 'supply').available === false;
+ const borrowBlocked = getReserveActionState(reserve, 'borrow').available === false;
```

**(b) L233-L237 — 行背景色：**

```diff
+ const primaryStatus = getPrimaryReserveStatus(reserve);
```

将 `reserve.isPaused` / `reserve.isFrozen` 条件替换为 `primaryStatus`：

```diff
- isExpanded && reserve.isPaused && '[&_td]:ds-bg-paused',
- isExpanded && !reserve.isPaused && reserve.isFrozen && '[&_td]:ds-bg-sky-500-8',
- (reserve.isPaused || reserve.isFrozen) && 'bg-card',
- reserve.isPaused && 'ds-bg-paused',
- (!reserve.isPaused && reserve.isFrozen) && 'ds-bg-sky-500-8',
+ isExpanded && primaryStatus === 'paused' && '[&_td]:ds-bg-paused',
+ isExpanded && primaryStatus === 'inactive' && '[&_td]:ds-bg-paused',
+ isExpanded && primaryStatus === 'frozen' && '[&_td]:ds-bg-sky-500-8',
+ (primaryStatus === 'paused' || primaryStatus === 'frozen') && 'bg-card',
+ primaryStatus === 'paused' && 'ds-bg-paused',
+ primaryStatus === 'inactive' && 'ds-bg-paused',
+ primaryStatus === 'frozen' && 'ds-bg-sky-500-8',
```

**(c) L6 + L270 — import 和 JSX：**

```diff
-import { FrozenStatusBadge } from './FrozenStatusBadge';
+import { ReserveStatusBadge } from './ReserveStatusBadge';

-<FrozenStatusBadge isFrozen={reserve.isFrozen} isPaused={reserve.isPaused} />
+<ReserveStatusBadge reserve={reserve} />
```

**(d) `reserve.supplyDisabled` / `reserve.borrowDisabled` 直接读取 — 保持不变。**

### 3.6 `src/components/dashboard/MobileReserveCard.tsx`

**当前代码**：[src/components/dashboard/MobileReserveCard.tsx](file:///Users/pabloli/Documents/code/aaveapy/src/components/dashboard/MobileReserveCard.tsx)

**(a) L504 — isReserveLocked：**

```diff
+import { getReserveFlags, getReserveRestrictionReasons, getPrimaryReserveStatus } from '@/lib/reserveStatus';

- const isReserveLocked = Boolean(reserve.isFrozen || reserve.isPaused);
+ const { frozen, paused } = getReserveFlags(reserve);
+ const isReserveLocked = frozen || paused;
```

**(b) L626 — card background：**

```diff
+ const primaryStatus = getPrimaryReserveStatus(reserve);
```

将 `reserve.isPaused` / `reserve.isFrozen` 替换为 `primaryStatus`。

**(c) L637-L669 — status badge：**

将 `reserve.isFrozen` → `frozen`，`reserve.isPaused` → `paused`（已在上方从 `getReserveFlags()` 解构）。

**(d) L115 — FrozenStatusContent：**

```diff
- <FrozenStatusContent isFrozen={reserve.isFrozen} isPaused={reserve.isPaused} />
+ <ReserveStatusContent reasons={getReserveRestrictionReasons(reserve)} />
```

### 3.7 `src/components/dashboard/SimulationSubRow.tsx`

**当前代码**：[src/components/dashboard/SimulationSubRow.tsx](file:///Users/pabloli/Documents/code/aaveapy/src/components/dashboard/SimulationSubRow.tsx)

**(a) L199 — isReserveLocked：**

```diff
+import { getReserveFlags, getPrimaryReserveStatus } from '@/lib/reserveStatus';

- const isReserveLocked = Boolean(reserve.isFrozen || reserve.isPaused);
+ const { frozen, paused } = getReserveFlags(reserve);
+ const isReserveLocked = frozen || paused;
```

**(b) L200-L209 — disabled notice text：**

```diff
+ const primaryStatus = getPrimaryReserveStatus(reserve);

- const supplyDisabledNotice = isReserveLocked
-   ? (reserve.isPaused ? 'Paused' : 'Frozen')
-   : reserve.supplyDisabled
-     ? 'Supply unavailable'
-     : null;
+ const supplyDisabledNotice = primaryStatus === 'paused' ? 'Paused'
+   : primaryStatus === 'inactive' ? 'Inactive'
+   : primaryStatus === 'frozen' ? 'Frozen'
+   : reserve.supplyDisabled ? 'Supply unavailable'
+   : null;
```

`borrowDisabledNotice` 同理。

**(c) L219-L220 — supplySideBlocked / borrowSideBlocked：**

```diff
- const supplySideBlocked = !!(reserve.isPaused || reserve.isFrozen || reserve.supplyDisabled);
- const borrowSideBlocked = !!(reserve.isPaused || reserve.isFrozen || reserve.borrowDisabled);
+ const supplySideBlocked = isReserveLocked || Boolean(reserve.supplyDisabled);
+ const borrowSideBlocked = isReserveLocked || Boolean(reserve.borrowDisabled);
```

**(d) L1294-L1317 — disabled banner 条件：**

将 `reserve.isPaused` → `primaryStatus === 'paused'`，`reserve.isFrozen` → `primaryStatus === 'frozen'`。

### 3.8 `src/pages/Index.tsx`

**当前代码**：[src/pages/Index.tsx](file:///Users/pabloli/Documents/code/aaveapy/src/pages/Index.tsx)

**(a) L52 — state：**

```diff
  const [showFrozenOrPaused, setShowFrozenOrPaused] = useState(false);
+ // TODO: 后续重命名为 showRestrictedAssets
```

**(b) L281 — filter 逻辑：**

```diff
+import { isRestrictedReserve } from '@/lib/reserveStatus';

- if (!showFrozenOrPaused && (reserve.isFrozen || reserve.isPaused)) {
+ if (!showFrozenOrPaused && isRestrictedReserve(reserve)) {
    return false;
  }
```

### 3.9 `src/components/dashboard/TopOpportunities.tsx`

**当前代码**：[src/components/dashboard/TopOpportunities.tsx](file:///Users/pabloli/Documents/code/aaveapy/src/components/dashboard/TopOpportunities.tsx)

**L747 — reservesWithTotals filter：**

```diff
- }).filter(r => !r.isFrozen && !r.isPaused), [whitelistMerklCampaignIds, reserves, tydroPointToUsdRate]);
+ }).filter(r => !r.supplyDisabled), [whitelistMerklCampaignIds, reserves, tydroPointToUsdRate]);
```

`supplyDisabled` 已综合 frozen/paused/cap，语义等价且更精确。

### 3.10 `src/components/dashboard/FilterBar.tsx`

**文件**：[src/components/dashboard/FilterBar.tsx](file:///Users/pabloli/Documents/code/aaveapy/src/components/dashboard/FilterBar.tsx)

**仅改 UI 文案**（L353,L356,L380,L383）：

```diff
- 'Frozen or paused assets shown'
+ 'Restricted assets shown'

- 'Show frozen or paused assets'
+ 'Show restricted assets'
```

### 3.11 测试文件更新

所有测试中直接访问 `reserve.isFrozen` / `reserve.isPaused` 的地方统一改为通过 `protocolFlags`：

```ts
const mockReserve = {
  protocolFlags: {
    reserve: { frozen: true, paused: false },
  },
  supplyDisabled: false,
  borrowDisabled: false,
  // ...
};
```

涉及文件（共 9 个）：
- `DesktopReserveRow.test.tsx`
- `MobileReserveCard.test.tsx`
- `TopOpportunities.test.tsx`
- `SimulationSubRow.render.test.tsx`
- `SimulationSubRow.compact.render.test.tsx`
- `SimulationSubRow.frozen-html-compare.test.tsx`
- `useRateSimulation.test.ts`
- `IncentiveTooltip.test.tsx`
- `IncentiveTooltip.mobile.test.tsx`

---

## 四、改动文件清单

### 后端（5 文件 + 1 新建）

| 文件 | 改动类型 |
|---|---|
| `src/index.ts` | 类型移除 `isFrozen`/`isPaused`，增加 `protocolFlags`；V3 构建逻辑填充 protocolFlags，移除旧字段输出 |
| `src/v4-fetcher.ts` | 同上 |
| `src/types/protocolFlags.ts` | **新建** |
| `backend/src/types/index.ts` | 移除 `isFrozen`/`isPaused`，增加 `protocolFlags` |
| `backend/src/services/marketsApiSerialize.ts` | 移除 `isFrozen`/`isPaused` 序列化，增加 `protocolFlags` 透传 |
| `src/types/runtime-validation.ts` | 字段注册表替换 |

### 前端（6 文件 + 1 新建 + 9 测试更新）

| 文件 | 改动类型 |
|---|---|
| `src/types/aave.ts` | 移除 `isFrozen`/`isPaused`，增加 `protocolFlags` |
| `src/lib/apiSchemas.ts` | zod schema 替换 |
| `src/lib/reserveStatus.ts` | **新建** — 所有状态派生 helper |
| `src/components/dashboard/FrozenStatusBadge.tsx` → `ReserveStatusBadge.tsx` | **重命名** — Props 改为 `{ reserve }` |
| `src/components/dashboard/DesktopReserveRow.tsx` | 行背景/gating 改用 helper |
| `src/components/dashboard/MobileReserveCard.tsx` | 同上 |
| `src/components/dashboard/SimulationSubRow.tsx` | locked/disabled banner 改用 helper |
| `src/pages/Index.tsx` | filter 改用 `isRestrictedReserve()` |
| `src/components/dashboard/TopOpportunities.tsx` | filter 改用 `supplyDisabled` |
| `src/components/dashboard/FilterBar.tsx` | UI label 改为 "Show restricted assets" |
| 9 个测试文件 | fixture 数据更新 |

---

## 五、API 响应变化摘要

```diff
// reserve JSON 输出
{
  "reserveId": "...",
- "isFrozen": true,        // 移除
- "isPaused": false,       // 移除
+ "protocolFlags": {
+   "reserve": {
+     "active": true,       // V4 有，V3 无此 key
+     "frozen": true,
+     "paused": false
+   }
+ },
  "supplyDisabled": true,   // 保持不变
  "borrowDisabled": true,   // 保持不变
  ...
}
```

---

## 六、分阶段执行

### Phase 1：后端 `protocolFlags` 输出
1. 新建 `src/types/protocolFlags.ts`
2. 更新 `src/index.ts`（类型 + buildV3BaseDataset）
3. 更新 `src/v4-fetcher.ts`（类型 + 映射）
4. 更新 `src/types/runtime-validation.ts`
5. 更新 `backend/src/types/index.ts`
6. 更新 `backend/src/services/marketsApiSerialize.ts`
7. `npm run build && npm --prefix backend run build && npm --prefix backend run test`

### Phase 2：前端类型 + Schema + helper + 测试
1. 更新 `aaveapy/src/types/aave.ts`
2. 更新 `aaveapy/src/lib/apiSchemas.ts`
3. 新建 `aaveapy/src/lib/reserveStatus.ts`
4. 写 `reserveStatus.test.ts` 单元测试
5. 更新 `apiSchemas.test.ts`

### Phase 3：组件逐一切换（按依赖顺序）
1. `ReserveStatusBadge.tsx`（重命名 + 重构）— 被其他组件引用
2. `DesktopReserveRow.tsx`
3. `MobileReserveCard.tsx`
4. `SimulationSubRow.tsx`
5. `Index.tsx` + `FilterBar.tsx`
6. `TopOpportunities.tsx`
7. 更新所有 9 个测试文件，确保 CI 通过
</parameter>