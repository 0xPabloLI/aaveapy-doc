# isActive 字段实施计划

> **状态**：✅ 后端已实施 | ✅ 前端已实施 | 文档待归档

## 一、字段简化分析

### 1.1 现有字段审计

| 字段 | 语义 | 来源 | 消费者 | 是否可简化 |
|---|---|---|---|---|
| `isFrozen` | 协议冻结（阻止新 supply/borrow） | V3: `reserve.isFrozen` / V4: `status.frozen` | Badge、行背景色、Simulation lock | **否** — V3/V4 对 frozen 的 collateral 权限不同，前端需独立读取来区分 |
| `isPaused` | 协议暂停（阻止所有 action） | V3: `reserve.isPaused` / V4: `status.paused` | Badge、行背景色、Simulation lock、gating | **否** — 最高优先级状态，需独立判断 |
| `supplyDisabled` | 综合 supply 不可用（含 frozen+paused+cap） | V3: 后端计算 / V4: `!r.canSupply` | 按钮 gating、simulation banner、TopOpportunities filter | **否** — 为消费便利预计算的值，避免前端重复组合判断 |
| `borrowDisabled` | 综合 borrow 不可用（含 frozen+paused+borrowingState） | V3: 后端计算 / V4: `!r.canBorrow` | 按钮 gating、simulation banner | **否** — 同上 |

**结论**：现有 4 个字段各司其职，不存在冗余。不合并、不删除。

### 1.2 新增字段

```ts
isActive?: false;  // 只在 V4 且 status.active === false 时出现
```

| 属性 | 说明 |
|---|---|
| 类型 | `boolean`，只输出 `false`，不输出 `true` |
| 出现协议 | **仅 V4**（V3 raw response 无此字段） |
| 出现条件 | V4 `r.status?.active === false` |
| 语义 | Reserve 不活跃，所有 protocol action 不可用 |
| 互斥关系 | `isActive=false` ≤ `isPaused=true`（paused 优先级更高） |

### 1.3 为什么不输出 `isActive: true`

正常活跃的资产占 99%，传 `isActive: true` 对前端无消费价值，徒增带宽。遵循「不传就是 true」的 convention。

---

## 二、后端改动（极简）

### 2.1 `src/v4-fetcher.ts`（V4）

在 `isFrozen`/`isPaused`/`canSupply`/`canBorrow` 判定之后，应用互斥规则：

```ts
const isFrozen = r.status?.frozen === true;
const isPaused = r.status?.paused === true;
const isInactive = r.status?.active === false;
const canSupply: boolean = r.canSupply ?? true;
const canBorrow: boolean = r.canBorrow ?? true;

// 互斥规则：有协议层原因 → 省略 supplyDisabled/borrowDisabled
const hasProtocolReason = isPaused || isInactive || isFrozen;

dataset.push({
  // ...其他字段不变
  ...(isPaused ? { isPaused: true } : {}),
  ...(isFrozen ? { isFrozen: true } : {}),
  ...(isInactive ? { isActive: false as const } : {}),
  ...(!hasProtocolReason && !canSupply ? { supplyDisabled: true } : {}),
  ...(!hasProtocolReason && !canBorrow ? { borrowDisabled: true } : {}),
});
```

### 2.2 `src/index.ts`（V3）

同样应用互斥规则 — `isFrozen`/`isPaused` 存在时不输出 `supplyDisabled`/`borrowDisabled`（即使 cap=1 也不输出，协议层原因优先）：

```ts
const hasProtocolReason = isPaused || isFrozen;

baseDataset.push({
  // ...其他字段不变
  ...(isPaused ? { isPaused: true } : {}),
  ...(isFrozen ? { isFrozen: true } : {}),
  ...(!hasProtocolReason && supplyCapIsOne ? { supplyDisabled: true } : {}),
  ...(!hasProtocolReason && isBorrowDisabled ? { borrowDisabled: true } : {}),
});
```

### 2.3 其余后端文件

`backend/src/types/index.ts` 加 `isActive?: false`，序列化和注册表各加一行 `isActive` 透传/注册。

---

## 三、前端实现策略

### 3.1 数据层

#### 类型定义（`aaveapy/src/types/aave.ts`）

```ts
// ReserveWithSpread 内新增一行
isActive?: false;  // 只在 false 时存在
```

#### Zod Schema（`aaveapy/src/lib/apiSchemas.ts`）

```ts
isActive: z.literal(false).optional(),
```

#### 新建 helper（`aaveapy/src/lib/reserveStatus.ts`）

```ts
import type { ReserveWithSpread } from '@/types/aave';

/**
 * 是否有协议层限制（frozen / paused / inactive）。
 * 存在时 supplyDisabled/borrowDisabled 不会被后端输出，
 * 所以这里直接返回 true 即可。
 */
function hasProtocolRestriction(reserve: ReserveWithSpread): boolean {
  return !!reserve.isPaused || reserve.isActive === false || !!reserve.isFrozen;
}

/** 综合 supply 是否被禁用。协议层限制 + cap 限制。 */
export function isSupplyDisabled(reserve: ReserveWithSpread): boolean {
  return hasProtocolRestriction(reserve) || reserve.supplyDisabled === true;
}

/** 综合 borrow 是否被禁用。协议层限制 + borrowingState/cap 限制。 */
export function isBorrowDisabled(reserve: ReserveWithSpread): boolean {
  return hasProtocolRestriction(reserve) || reserve.borrowDisabled === true;
}

/** 获取 primary restriction reason，用于行背景色和主 badge。 */
export function getPrimaryReserveStatus(reserve: ReserveWithSpread): string | null {
  if (reserve.isPaused) return 'paused';
  if (reserve.isActive === false) return 'inactive';
  if (reserve.isFrozen) return 'frozen';
  return null;
}

/** 是否属于 restricted asset（默认隐藏，需手动开启 Show restricted assets）。 */
export function isRestrictedReserve(reserve: ReserveWithSpread): boolean {
  return hasProtocolRestriction(reserve);
}
```

### 3.2 UI/UX 设计规格

| 状态 | 背景色 | Badge 图标 | Badge 文案 | Tooltip |
|---|---|---|---|---|
| `isPaused=true` | `ds-bg-paused`（amber）| `PauseCircle` | Paused | "Paused: all reserve actions are halted." |
| **`isActive=false`** | **`ds-bg-paused`**（复用 paused 样式）| **`AlertTriangle`** 或 **`Ban`** | **Inactive** | **"Inactive: the reserve is not active. Most protocol actions are unavailable."** |
| `isFrozen=true` | `ds-bg-sky-500-8`（sky）| `Snowflake` | Frozen | "Frozen: new deposits and borrows are disabled." |

**设计决策**：`isActive=false` 复用 `isPaused=true` 的 amber 背景色，但 icon 和文案不同，以区分为两种状态。

### 3.3 状态管理

`isActive` 来自 API 响应，是 **只读的服务器状态**，不需要前端状态管理（useState/useReducer）。

- 数据流：API → zod parse → `ReserveWithSpread.isActive` → helper → 组件渲染
- 无用户交互可改变此值
- 无 form 关联（`isActive` 不是表单字段）

---

## 四、字段组合处理

### 4.1 所有可能组合

以实际可能出现的组合为限（V4 数据源已验证 `status.paused` 全为 `false`，但逻辑上保留）：

| # | isPaused | isActive | isFrozen | 出现场景 | Primary Status | 行背景 |
|---|---|---|---|---|---|---|
| 1 | true | true/false | * | V3/V4 pause | `paused` | amber |
| 2 | false | **false** | * | **V4 inactive** | **`inactive`** | **amber** |
| 3 | false | true | true | V3/V4 frozen | `frozen` | sky |
| 4 | false | true | false | 正常 | _(none)_ | default |

### 4.2 条件渲染规则

```ts
// Badge 组件
const showBadge = isRestrictedReserve(reserve);

// 行背景色（DesktopReserveRow / MobileReserveCard）
const primary = getPrimaryReserveStatus(reserve);
rowClass = primary === 'paused' || primary === 'inactive' ? 'ds-bg-paused'
         : primary === 'frozen' ? 'ds-bg-sky-500-8'
         : '';

// Supply gating → 不用再手动拼 isPaused || isFrozen || supplyDisabled
const supplyBlocked = isSupplyDisabled(reserve);
const borrowBlocked = isBorrowDisabled(reserve);

// TopOpportunities filter
.filter(r => !isRestrictedReserve(r))

// Simulation locked
const isReserveLocked = isRestrictedReserve(reserve);
```

### 4.3 边界情况

| 边界情况 | 处理 |
|---|---|
| `isActive` 字段缺失（V3 / V4 正常） | 视为 `true`（active），不显示 inactive |
| `isActive=false` 但 `isPaused=true`（理论可能，实际 V4 数据未见） | `isPaused` 优先，primary = `paused` |
| `isActive=false` 但 `isFrozen=true`（理论可能） | `isActive` 优先（比 frozen 严重），primary = `inactive` |
| `isActive=false` 与 `supplyDisabled` 同时出现 | 互斥规则下**不会发生** — `isActive=false` 时后端不输出 `supplyDisabled`。若意外同时出现，`isSupplyDisabled()` 仍然返回 `true` |

### 4.4 错误处理

`isActive` 是后端透传的 `boolean`，不存在格式错误。唯一防御：

```ts
// zod schema 确保类型安全
isActive: z.literal(false).optional(),
// 如果 API 返回 isActive: true 或其他值，zod parse 会抛出 ZodError
```

---

## 五、改动组件清单

| 组件 | 改动行数 | 改动内容 |
|---|---|---|
| `FrozenStatusBadge.tsx` | ~10 行 | 新增 `isActive === false` 判断分支，渲染 Ban/AlertTriangle icon + Inactive 文案 |
| `DesktopReserveRow.tsx` | ~5 行 | `isReserveLocked` 加 `reserve.isActive === false`；行背景色加 `inactive` 分支 |
| `MobileReserveCard.tsx` | ~5 行 | 同上 |
| `SimulationSubRow.tsx` | ~5 行 | `isReserveLocked` + `supplySideBlocked`/`borrowSideBlocked` 加 `isActive === false` |
| `Index.tsx` | ~3 行 | filter 加 `reserve.isActive === false` |
| `TopOpportunities.tsx` | ~3 行 | filter 加 `r.isActive !== false` |
| `FilterBar.tsx` | ~3 行 | label "Frozen or paused" → "Restricted" |
| 9 个测试文件 | ~50 行 | fixture 加 `isActive: false` 用例 |

**总计：约 80 行改动。**

---

## 六、实施时间线与里程碑

| 阶段 | 任务 | 工时 | 产出 |
|---|---|---|---|
| **Day 1 上午** | 后端 4 文件改一行 | 0.5h | API 输出 `isActive: false` |
| **Day 1 上午** | 后端测试验证 | 0.5h | `marketsApiSerialize.test.ts` 通过 |
| **Day 1 下午** | 前端类型 + Schema + helper | 1h | `reserveStatus.ts` 就绪 |
| **Day 1 下午** | Badge 组件适配 | 1h | `FrozenStatusBadge` 支持 Inactive |
| **Day 2 上午** | 其余 5 组件适配 | 2h | 全组件 inactive 感知 |
| **Day 2 下午** | 9 个测试文件更新 | 2h | CI 全绿 |
| **Day 2 下午** | Code review + 部署 | 1h | Staging 验证 |

**总计：2 个工作日。**

---

## 七、测试要求

### 7.1 后端测试

```ts
// marketsApiSerialize.test.ts 新增

it('V4 inactive reserve: outputs isActive: false', () => {
  const reserve = { isActive: false, isFrozen: false, isPaused: false };
  const result = serializeReserveForApi(reserve);
  expect(result.isActive).toBe(false);
  expect(result.isFrozen).toBeUndefined();
  expect(result.isPaused).toBeUndefined();
});

it('V4 active reserve: does NOT output isActive', () => {
  const reserve = { isActive: true };
  const result = serializeReserveForApi(reserve);
  expect(result).not.toHaveProperty('isActive');
});

it('V3 reserve: never outputs isActive', () => {
  const reserve = {}; // V3 reserve, 无 isActive
  const result = serializeReserveForApi(reserve);
  expect(result).not.toHaveProperty('isActive');
});
```

### 7.2 前端单元测试（`reserveStatus.test.ts`）

覆盖率要求 100%：

| 测试用例 | 验证点 |
|---|---|
| `getPrimaryReserveStatus({ isPaused: true })` | 返回 `'paused'` |
| `getPrimaryReserveStatus({ isActive: false })` | 返回 `'inactive'` |
| `getPrimaryReserveStatus({ isFrozen: true })` | 返回 `'frozen'` |
| `getPrimaryReserveStatus({})` | 返回 `null` |
| `isRestrictedReserve` 对以上 4 种情况 | 前 3 种 `true`，第 4 种 `false` |
| V3 无 `isActive` 字段 | `isInactive()` 返回 `false` |

### 7.3 组件渲染测试

每个受影响组件需要新增一个 `isActive: false` 的测试用例：

| 组件 | 测试 | 验证点 |
|---|---|---|
| `FrozenStatusBadge` | `isActive: false` reserve | 渲染 Inactive badge + Ban icon |
| `DesktopReserveRow` | `isActive: false` reserve | 行背景 `ds-bg-paused` |
| `MobileReserveCard` | `isActive: false` reserve | 卡片背景 amber + status badge |
| `SimulationSubRow` | `isActive: false` reserve | Supply/Borrow 两侧均被锁定；disabled notice 显示 "Inactive" |
| `Index.tsx` | `isActive: false` reserve | 默认隐藏；开启 "Show restricted" 后显示且带 badge |
| `TopOpportunities` | `isActive: false` reserve | 不出现 |

### 7.4 集成测试

- 用 staging API 的 V4 frozen reserve 样本（2 个：`status={active:true, frozen:true}`）验证 frozen 不受影响
- 手动模拟 `isActive: false` 的 mock 数据验证 inactive 路径

---

## 八、开发文档

### 8.1 给前端开发者的 Quick Reference

```ts
// ✅ 正确：用 helper
import { getPrimaryReserveStatus, isRestrictedReserve } from '@/lib/reserveStatus';

const primary = getPrimaryReserveStatus(reserve);
const isLocked = isRestrictedReserve(reserve);

// ❌ 错误：直接拼接条件（容易漏 isActive）
const isLocked = reserve.isFrozen || reserve.isPaused; // 忘了 isActive!

// ✅ 正确：filter restricted assets
if (!showRestricted && isRestrictedReserve(reserve)) return false;

// ✅ 正确：isActive 只在 false 时出现
if (reserve.isActive === false) { /* inactive logic */ }
// 不能写 if (!reserve.isActive) — V3 没有此字段，!undefined === true 误判
```

### 8.2 字段备忘卡

```
优先级   isActive: false | isPaused: true   → 所有 actions 不可用
        isActive=false: amber bg + Ban icon, "Inactive"
        isPaused=true:  amber bg + PauseCircle icon, "Paused"

次级     isFrozen: true                      → 仅 supply/borrow 不可用
        sky bg + Snowflake icon, "Frozen"

(以上三种状态存在时，supplyDisabled/borrowDisabled 不会被后端输出)

底层     supplyDisabled                      → supply button disabled（仅 cap 原因）
        borrowDisabled                      → borrow button disabled（仅 borrowingState/cap 原因）
        (仅在无 isPaused/isFrozen/isActive=false 时输出)
```

### 8.3 互斥规则总结

```text
后端输出：
  hasProtocolRestriction?
    YES → 输出 isPaused / isFrozen / isActive
         不输出 supplyDisabled / borrowDisabled（隐含禁用）
    NO  → 不输出 isPaused / isFrozen / isActive
         输出 supplyDisabled / borrowDisabled（cap/state 原因）

前端消费：
  isSupplyDisabled() = hasProtocolRestriction || reserve.supplyDisabled
  isBorrowDisabled()  = hasProtocolRestriction || reserve.borrowDisabled
```

---

## 九、改动文件汇总

### 后端（4 文件，每文件 +1 行）

| 文件 | 改动 |
|---|---|
| `src/v4-fetcher.ts` | 输出对象加 `isActive: false` |
| `backend/src/types/index.ts` | `isActive?: false` |
| `backend/src/services/marketsApiSerialize.ts` | 透传 `isActive` |
| `src/types/runtime-validation.ts` | 注册 `'isActive'` |

### 前端（5 文件改 + 1 新建 + 9 测试）

| 文件 | 改动 |
|---|---|
| `src/types/aave.ts` | `isActive?: false` |
| `src/lib/apiSchemas.ts` | `z.literal(false).optional()` |
| `src/lib/reserveStatus.ts` | **新建** — 3 个 helper |
| `FrozenStatusBadge.tsx` | 加 inactive 分支 |
| `DesktopReserveRow.tsx` | 加 `isActive === false` 判断 |
| `MobileReserveCard.tsx` | 同上 |
| `SimulationSubRow.tsx` | 同上 |
| `Index.tsx` | filter 加条件 |
| `TopOpportunities.tsx` | filter 加条件 |
| `FilterBar.tsx` | label "Show restricted assets" |
| 9 个测试文件 | fixture 更新 |
</write_to_fil