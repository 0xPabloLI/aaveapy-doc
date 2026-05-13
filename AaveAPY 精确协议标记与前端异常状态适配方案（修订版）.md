# AaveAPY 精确协议标记与前端异常状态适配方案（修订版）
## 权限矩阵与字段设计
说明压缩为两个层次：后端传协议或 SDK 已经给出的事实 tag，前端按 V3/V4 权限矩阵派生用户可见状态和 action gating。Y 表示该状态本身不阻止操作；N 表示该状态会阻止操作；Y* 表示状态允许但仍可能受余额、健康因子、cap、用户仓位、isolation/eMode 等非状态条件限制。
### V3 tag 组合与权限
```text
Tag 组合                                      | Supply | Borrow | Withdraw | Repay | Liquidate | Enable collateral | Disable collateral | UI 状态
paused=true                                  | N      | N      | N        | N     | N         | N                 | N                  | paused
active=false（当前 raw response 不提供）       | N      | N      | N        | N     | N         | N                 | N                  | inactive
active=true/unknown, paused=false, frozen=true | N      | N      | Y*       | Y*    | Y*        | Y*                | Y*                 | frozen
active=true/unknown, paused=false, frozen=false| Y*     | Y*     | Y*       | Y*    | Y*        | Y*                | Y*                 | normal
supplyDisabled=true only                    | N      | Y*     | Y*       | Y*    | Y*        | Y*                | Y*                 | supply-disabled
borrowDisabled=true only                    | Y*     | N      | Y*       | Y*    | Y*        | Y*                | Y*                 | borrow-disabled
```
V3 关键点：frozen 只阻止新的 supply / borrow，不应在文案里无条件承诺 withdraw / repay / liquidate 一定可用；这些 exit actions 还需要 reserve active 且不 paused，并满足用户仓位、健康因子等条件。当前 V3 raw response 没有 `isActive`，所以前端不能把缺失的 active 当成 false。
### V4 tag 组合与权限
```text
Tag 组合                                      | Supply | Borrow | Withdraw | Repay | Liquidate | Enable collateral | Disable collateral | UI 状态
paused=true                                  | N      | N      | N        | N     | N         | N                 | N                  | paused
active=false                                 | N      | N      | N        | N     | N         | N                 | N                  | inactive
active=true/unknown, paused=false, frozen=true | N      | N      | Y*       | Y*    | Y*        | N                 | Y*                 | frozen
active=true/unknown, paused=false, frozen=false| Y*     | Y*     | Y*       | Y*    | Y*        | Y*                | Y*                 | normal
canSupply=false only                        | N      | Y*     | Y*       | Y*    | Y*        | Y*                | Y*                 | supply-disabled
canBorrow=false only                        | Y*     | N      | Y*       | Y*    | Y*        | Y*                | Y*                 | borrow-disabled
canUseAsCollateral=false only               | Y*     | Y*     | Y*       | Y*    | Y*        | N                 | Y*                 | collateral-disabled
```
V4 关键点：V3 frozen 对 enable collateral 不阻止，V4 frozen 会阻止 enable collateral。raw response 有 `status.active/frozen/paused` 和 `canSupply/canBorrow/canUseAsCollateral`，但没有 `halted`。V4 Hub `halted=true` 在源码中会阻止 supply / withdraw / borrow / repay，但当前数据源没有该字段，首期不把 `hub.halted` 加入 API，也不在前端伪造。
## Raw Response 字段映射依据
以下基于 `aave-protocol-analysis/data/debug/` 下的实际数据验证。
### V3 raw response (`v3-raw-sdk-response.json`)
结构：`markets[].supplyReserves[]` / `markets[].borrowReserves[]`
reserve 顶层状态字段：
* `isFrozen: boolean` — 54/291 为 true
* `isPaused: boolean` — 18/291 为 true
* 没有 `isActive`、`active`、`status` 对象
* `borrowInfo.borrowingState: "ENABLED" | "DISABLED"` — 部分 reserve `borrowInfo` 为 null
当前后端映射（`src/index.ts` `buildV3BaseDataset()`）：
* `isFrozen = reserve.isFrozen === true`
* `isPaused = reserve.isPaused === true`
* `borrowDisabled` 由 frozen / paused / borrowingState / cap 综合折算
* `supplyDisabled` 由 frozen / paused / cap 折算
### V4 raw response (`v4-raw-sdk-response.json`)
结构：`reserves[]`，每个 reserve 顶层包含：
```text
status: { active: boolean, frozen: boolean, paused: boolean }  ← 三个 flag 同级
canSupply: boolean
canBorrow: boolean
canUseAsCollateral: boolean
canSwapFrom: boolean
```
实际分布（63 reserves）：
* `status.active`: 全部 true
* `status.frozen`: 61 false, 2 true
* `status.paused`: 全部 false
* Frozen reserve 样本：`status={active:true, frozen:true, paused:false}`, `canSupply=false, canBorrow=false, canUseAsCollateral=false`
当前后端映射（`src/v4-fetcher.ts:155-160`）：
* `isFrozen = r.status?.frozen === true`
* `isPaused = r.status?.paused === true`
* `canSupply = r.canSupply ?? true` → `supplyDisabled = !canSupply`
* `canBorrow = r.canBorrow ?? true` → `borrowDisabled = !canBorrow`
* **遗漏**：`r.status?.active` 存在但当前未透传给 API
### Enriched 输出 (`v3v4-enriched-full.json`)
* 354 reserves（V3 291 + V4 63）
* 所有 reserve 都有 `borrowDisabled`；130 个有 `supplyDisabled`
* V3 truthy 时输出 `isFrozen: true`（56 个）、`isPaused: true`（18 个）
* V4 只在 frozen=true 时输出 `isFrozen: true`；非 frozen 的 V4 reserve 不含 `isFrozen` key
* 没有 `protocolFlags` 字段（待新增）
### protocolFlags 与 raw response 的映射关系
```text
protocolFlags 字段              | V3 raw 来源             | V4 raw 来源              | 说明
reserve.active                 | 无（保持 undefined）     | r.status.active          | V4 和 frozen/paused 同级
reserve.frozen                 | reserve.isFrozen        | r.status.frozen          | V4 在 status 对象里
reserve.paused                 | reserve.isPaused        | r.status.paused          | V4 在 status 对象里
sdk.canSupply                  | 无（首期不输出）         | r.canSupply              | reserve 顶层 boolean
sdk.canBorrow                  | 无（首期不输出）         | r.canBorrow              | reserve 顶层 boolean
sdk.canUseAsCollateral         | 无（首期不输出）         | r.canUseAsCollateral     | reserve 顶层 boolean
```
## 推荐后端 API Contract
不新增 `protocolVersion`，前端继续用 `src/lib/protocolVersion.ts` 的 `getProtocolVersion(marketName)` 区分 V3/V4。
新增轻量事实字段 `protocolFlags`：
```ts
protocolFlags?: {
  reserve?: {
    active?: boolean;
    frozen?: boolean;
    paused?: boolean;
  };
  sdk?: {
    canSupply?: boolean;
    canBorrow?: boolean;
    canUseAsCollateral?: boolean;
  };
};
```
字段设计用意：
* `reserve.*` 表示协议状态 tag，用来解释为什么资产是 paused / frozen / inactive，并处理 V3 与 V4 对同一个 tag 的不同权限语义。
* `reserve.active` 只在数据源明确提供时输出；V4 可映射 `r.status.active`，V3 当前 raw response 没有，保持 `undefined`，避免把 unknown 误判成 inactive。
* `reserve.frozen` 和 `reserve.paused` 统一承载 V3 `isFrozen/isPaused` 与 V4 `status.frozen/status.paused`，让前端 badge、filter、copy 不再依赖旧字段拼条件。
* `sdk.*` 表示 SDK 已经计算好的 action fact，主要补充非 paused/frozen/active 的限制；例如 cap、borrow availability、collateral eligibility 等不应都塞进 protocol tag。
* `sdk.canSupply` 对应 V4 `canSupply`，用于解释 supply-disabled；V3 首期可不输出，继续用兼容字段 `supplyDisabled`。
* `sdk.canBorrow` 对应 V4 `canBorrow`，用于解释 borrow-disabled；V3 首期可不输出，继续用兼容字段 `borrowDisabled`。
* `sdk.canUseAsCollateral` 对应 V4 `canUseAsCollateral`，用于未来 collateral UI 或 tooltip；当前 UI 可以先不消费。
明确不加入首期 contract：`protocolVersion`、V3 `borrowingEnabled`、V4 `borrowable`、`receiveSharesEnabled`、`hub.active`、`hub.halted`。这些要么前端已有判断方式，要么已被 `borrowDisabled` 覆盖，要么当前 UI 不消费，要么当前 raw response 不提供。
## 现有字段兼容策略
继续保留：
* `isFrozen`
* `isPaused`
* `supplyDisabled`
* `borrowDisabled`
兼容关系：
* `isFrozen` 继续作为前端展示的兼容字段，可由 `protocolFlags.reserve.frozen` 派生。
* `isPaused` 继续作为前端展示的兼容字段，可由 `protocolFlags.reserve.paused` 派生。
* `supplyDisabled` 继续表示当前产品场景下“新 supply 不可用”。
* `borrowDisabled` 继续表示当前产品场景下“新 borrow 不可用”。
前端新逻辑读取顺序：
* 状态 badge 优先读取 `protocolFlags.reserve.*`，缺失时 fallback 到 `isFrozen` / `isPaused`。
* supply action 优先读取 `supplyDisabled`，并结合 frozen / paused / active。
* borrow action 优先读取 `borrowDisabled`，并结合 frozen / paused / active。
* 不把未知字段当成 false；例如 V3 `active` 缺失时，不应显示 inactive。
## 后端具体改动范围
`aave-protocol-analysis/src/index.ts`
* 在 `RuntimeReserveData` 增加 `protocolFlags?: ProtocolFlags` 类型。
* V3 `buildV3BaseDataset()` 中填充：
    * `protocolFlags.reserve.frozen = reserve.isFrozen === true`
    * `protocolFlags.reserve.paused = reserve.isPaused === true`
    * 不填 `active`，因为 raw response 无字段。
    * 不填 `borrowingEnabled`，因为 raw response 无字段且已折算到 `borrowDisabled`。
`aave-protocol-analysis/src/v4-fetcher.ts`
* 在 `V4FormattedReserveData` 增加 `protocolFlags?: ProtocolFlags`。
* V4 映射中填充：
    * `protocolFlags.reserve.active = r.status?.active`。
    * `protocolFlags.reserve.frozen = r.status?.frozen`。
    * `protocolFlags.reserve.paused = r.status?.paused`。
    * `protocolFlags.sdk.canSupply = r.canSupply`。
    * `protocolFlags.sdk.canBorrow = r.canBorrow`。
    * `protocolFlags.sdk.canUseAsCollateral = r.canUseAsCollateral`。
    * 不填 `halted`。
    * 不填 `receiveSharesEnabled`。
    * 不填 `borrowable`。
`aave-protocol-analysis/backend/src/services/marketsApiSerialize.ts`
* 在 `serializeReserveForApi()` 中透传 `protocolFlags`。
`aave-protocol-analysis/backend/src/types/index.ts`
* `MarketWithSpread` 增加 `protocolFlags?: ProtocolFlags`。
`aave-protocol-analysis/src/types/runtime-validation.ts`
* `EXPECTED_RUNTIME_FIELDS` 增加 `protocolFlags`。
## 前端具体适配范围
`aaveapy/src/types/aave.ts`
* `ReserveWithSpread` 增加 `protocolFlags?: ProtocolFlags`。
* 不增加 `protocolVersion`。
`aaveapy/src/lib/apiSchemas.ts`
* `ReserveWithSpreadSchema` 增加 `protocolFlags` schema。
* schema 允许 `reserve.active/frozen/paused` 和 `sdk.canSupply/canBorrow/canUseAsCollateral` 为 optional boolean。
`aaveapy/src/lib/reserveStatus.ts` 新增 helper。
建议导出：
```ts
export type ReserveRestrictionReason =
  | 'paused'
  | 'frozen'
  | 'inactive'
  | 'supply-disabled'
  | 'borrow-disabled';
export type ReserveAction = 'supply' | 'borrow' | 'withdraw' | 'repay' | 'liquidate' | 'enable-collateral' | 'disable-collateral';
export function getReserveFlags(reserve: ReserveWithSpread) { ... }
export function getReserveRestrictionReasons(reserve: ReserveWithSpread): ReserveRestrictionReason[] { ... }
export function isRestrictedReserve(reserve: ReserveWithSpread): boolean { ... }
export function getReserveActionState(reserve: ReserveWithSpread, action: ReserveAction): { available: boolean | 'unknown'; reasons: ReserveRestrictionReason[] } { ... }
export function getPrimaryReserveStatus(reserve: ReserveWithSpread): ReserveRestrictionReason | null { ... }
```
`getReserveFlags()` 归一化规则：
* `frozen = protocolFlags.reserve.frozen ?? reserve.isFrozen ?? false`
* `paused = protocolFlags.reserve.paused ?? reserve.isPaused ?? false`
* `active = protocolFlags.reserve.active`，仅在明确为 false 时产生 inactive reason。
* `canSupply = protocolFlags.sdk.canSupply`，仅作为辅助事实；当前 UI gating 仍优先保留 `supplyDisabled`。
* `canBorrow = protocolFlags.sdk.canBorrow`，仅作为辅助事实；当前 UI gating 仍优先保留 `borrowDisabled`。
## 前端 action 派生规则
`getReserveActionState()` 按上方 V3/V4 权限矩阵实现，并继续用现有 `getProtocolVersion(marketName)` 区分协议版本。
核心规则：
* paused 和 active=false 是最高优先级，阻止当前 UI 展示的主要 actions。
* V3 frozen 只阻止 supply / borrow；V4 frozen 阻止 supply / borrow / enable collateral。
* `supplyDisabled` / `borrowDisabled` 继续作为当前产品的兼容 gating 字段；`protocolFlags.sdk.canSupply/canBorrow` 用于补充解释原因。
* active 缺失时保持 unknown，不显示 inactive，也不把 exit actions 文案写成无条件可用。
* 当前没有 collateral UI，collateral 规则先放在 helper 和测试中覆盖，组件可暂不消费。
## 异常状态与视觉优先级
Primary status 优先级：
1. `paused`：使用现有 paused amber 样式。
2. `inactive`：建议使用 muted/destructive 边界样式，首期如果没有设计资源可先复用 paused 的高严重度背景但文案不同。
3. `frozen`：继续使用 sky 样式。
4. `supply-disabled` / `borrow-disabled`：不一定改变整行背景，可在 simulation banner / tooltip 中解释。
多状态时：
* 行/卡片背景取最高优先级。
* badge tooltip / mobile sheet 列出全部 reason。
* 如果同时 paused + frozen，仍以 paused 背景为主，但 tooltip 同时列 paused 和 frozen。
## Show Restricted Assets 行为
把 UI 文案从 “Show frozen or paused assets” 改为 “Show restricted assets”。
`isRestrictedReserve()` 首期定义：
* true if paused。
* true if frozen。
* true if active === false。
* 可选：true if supplyDisabled && borrowDisabled。
不纳入首期：
* hub halted，因为 API 没有数据。
* receiveSharesEnabled，因为当前 UI 不关心。
默认隐藏 restricted assets。
开启后显示 restricted assets，并通过状态 badge 标记异常原因。
Top Opportunities 不受该 toggle 影响，始终过滤掉对应 action 不可用的资产。
## 具体组件适配
`src/components/dashboard/FrozenStatusBadge.tsx`
* 建议改名为 `ReserveStatusBadge`，或保留组件名但内部改为 `ReserveStatusContent`。
* props 从 `{ isFrozen, isPaused }` 演进为 `{ reserve }` 或 `{ reasons }`。
* Frozen 文案改为条件式：不再写 “can still be repaid, withdrawn, and liquidated”。
`src/components/dashboard/DesktopReserveRow.tsx`
* 替换 `reserve.isPaused` / `reserve.isFrozen` 的背景判断为 `getPrimaryReserveStatus(reserve)`。
* `supplyBlocked` / `borrowBlocked` 改为 `getReserveActionState(reserve, 'supply'/'borrow')`。
`src/components/dashboard/MobileReserveCard.tsx`
* `isReserveLocked`、`supplyLocked`、`borrowLocked` 改为使用 helper。
* mobile status badge 和 bottom sheet 使用 `getReserveRestrictionReasons()` 和 copy helper。
`src/components/dashboard/SimulationSubRow.tsx`
* `supplySideBlocked` / `borrowSideBlocked` 改为 action state。
* disabled banner 文案根据 primary reason 输出 paused / frozen / inactive / supply disabled / borrow disabled。
`src/pages/Index.tsx`
* `showFrozenOrPaused` 可以先保留 state 名以减少 diff，但 UI label 改成 “Show restricted assets”。
* filter 逻辑改为 `if (!showFrozenOrPaused && isRestrictedReserve(reserve)) return false`。
* 后续可重命名 state 为 `showRestrictedAssets`。
`src/components/dashboard/TopOpportunities.tsx`
* `reservesWithTotals.filter(r => !r.isFrozen && !r.isPaused)` 改为 action-based filtering。
* Supply 榜用 `getReserveActionState(reserve, 'supply').available === true`。
* Looping 榜用 supply 和 borrow 都 true。
* 当前没有独立 Borrow 榜时，borrow state 主要影响 looping。
## Tooltip 文案建议
Paused：
“Paused: reserve actions are halted. Deposits, borrows, repays, withdrawals, collateral changes, and liquidations are blocked.”
Frozen：
“Frozen: new deposits and borrows are disabled. Exit actions may remain available when the reserve is active and not paused.”
Inactive：
“Inactive: the reserve is not active. Most protocol actions are unavailable.”
Supply disabled：
“Supply disabled: new deposits are unavailable for this reserve.”
Borrow disabled：
“Borrow disabled: new borrows are unavailable for this reserve.”
如果多个状态同时存在，按优先级逐段展示。
## 测试策略
后端：
* `marketsApiSerialize.test.ts` 增加 `protocolFlags` 透传测试。
* V4 fixture 测试确认 `status.active/frozen/paused` 和 `canSupply/canBorrow/canUseAsCollateral` 被映射。
* V3 fixture 测试确认 `isFrozen/isPaused` 被映射到 `protocolFlags.reserve`，且不会伪造 `active`。
前端：
* `apiSchemas.test.ts` 验证 `protocolFlags` 被接受。
* 新增 `reserveStatus.test.ts` 覆盖 paused、frozen、inactive、supplyDisabled、borrowDisabled、多状态、V3/V4 collateral 差异。
* `TopOpportunities.test.tsx` 更新为 action-state 过滤。
* `DesktopReserveRow.test.tsx` / `MobileReserveCard.test.tsx` 覆盖 inactive primary status 和多状态 badge。
* `useRateSimulation.test.ts` 或 `SimulationSubRow` 相关测试覆盖 inactive / frozen / paused 下 after 值被锁住。
## 分阶段落地
第一阶段：后端输出 `protocolFlags`。
* 只输出当前 data 已证实存在的字段。
* 不输出 protocolVersion、borrowable、receiveSharesEnabled、hub halted。
第二阶段：前端类型和 schema 接入。
* 加 `ProtocolFlags` 类型和 zod schema。
* 新增 `reserveStatus.ts` 和单元测试。
第三阶段：UI 消费 helper。
* Badge / row background / mobile sheet / simulation gating / Top Opportunities / table filter 逐步切换到 helper。
第四阶段：可选补充 Hub halted。
* 如果未来需要展示 Hub halted，需要后端新增链上读取 `IHub.getSpokeConfig(assetId, spoke)` 或等待 SDK 暴露。
* 一旦后端有该字段，前端只需在 `reserveStatus.ts` 增加 reason，不需要改各组件。
## 推荐决策
采用“后端透传精确且当前数据源已支持的 flags，前端基于 helper 派生异常状态”的方案。
首期后端只加 `protocolFlags.reserve.active/frozen/paused` 和 `protocolFlags.sdk.canSupply/canBorrow/canUseAsCollateral`。
不新增 `protocolVersion`，因为前端已有 `getProtocolVersion(marketName)`。
不新增 V3 `borrowingEnabled` / V4 `borrowable`，因为当前 `borrowDisabled` 已覆盖产品所需的 borrow 可用性。
不新增 `receiveSharesEnabled`，因为当前 UI 不消费。
不新增 `hub.halted`，因为当前 V4 raw response 没有该字段；只在方案中记录它对 reserve 操作的真实影响和后续补齐路径。