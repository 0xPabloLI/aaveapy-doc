# Handoff: TARGET_TOTAL_APR 前端适配

**日期**: 2026-06-14
**来源**: 后端 TARGET_TOTAL_APR 实现已部署 (commit `46fbd5a`)
**对接人**: 前端 session
**父 Issue**: AAV-833

---

## 1. 后端已完成的部分

### 1.1 API 输出当前状态

TARGET_TOTAL_APR campaign 的 breakdown 已出现在 `/api/markets` 响应中：

```json
{
  "campaignApr": 4.7,
  "campaignStartedAt": "2026-06-08T12:00:00.000Z",
  "campaignEndedAt": "2026-06-15T12:00:00.000Z",
  "campaignId": "13116567236794890552",
  "whitelistOnly": false,
  "campaignType": "TARGET_TOTAL_APR",
  "totalBudget": 448506.567296102,
  "aprCap": 4.7,
  "latestTvl": 568482827.0171667,
  "plannedDaily": 64072.366756586,
  "budgetBoundMode": "MAX_APR"
}
```

### 1.2 已完成的映射

7 种 `distributionMethod` 全部映射到 `TARGET_TOTAL_APR`：

| distributionMethod | → campaignType | Aave lending 相关 |
|---|---|---|
| `AAVE_NET_APR` | TARGET_TOTAL_APR | ✅ V3 |
| `AAVE_V4_NET_APR` | TARGET_TOTAL_APR | ✅ V4 |
| `ERC4626_APR` | TARGET_TOTAL_APR | ❌ vault-based |
| `ERC4626_SPREAD_CAPPED` | TARGET_TOTAL_APR | ❌ vault-based |
| `ERC4626_TARGET_APR_WITH_MERKL` | TARGET_TOTAL_APR | ❌ vault-based |
| `SOFR_SPREAD_RATCHET` | TARGET_TOTAL_APR | ❌ vault-based |
| `DEEL_DISTRIBUTION` | TARGET_TOTAL_APR | ❌ vault-based |

映射表全部保留（防御性设计，Merkl 未来可能新增类型），但 **Aave lending 场景只有前两种**。后 5 种经 Merkl 官方 Schema API 确认全部是 ERC4626 vault-based（官方描述中明确写了 "ERC4626 vault" / "vault holders" / "vault-tracking campaign"），不适用于 lending protocol。

### 1.3 aprCap 语义

| campaignType | aprCap 含义 | 来源字段 |
|---|---|---|
| MAX_REWARD_VALUE_PER_LIQUIDITY_VALUE | Merkl 实付 APR 上限 | `distributionSettings.apr` |
| FIX_REWARD_VALUE_PER_LIQUIDITY_VALUE | Merkl 实付 APR 上限 | `distributionSettings.apr` |
| **TARGET_TOTAL_APR** | **总 APR 目标 (targetAPR)** | `distributionSettings.targetAPR` |
| DUTCH_AUCTION | 无 APR cap | N/A |

**关键区别**：TARGET_TOTAL_APR 的 `aprCap` 是"用户应得的总 APR"，不是"Merkl 支付的部分"。但后端已自动将 `campaignApr` 转换为 Merkl 实付 APR，前端无需手动计算。

### 1.3.1 campaignApr 语义（2026-06-15 更新）

| campaignType | campaignApr 含义 | 前端使用方式 |
|---|---|---|
| MAX / FIX / DUTCH | Merkl 实付 APR | 直接使用 |
| **TARGET_TOTAL_APR** | **Merkl 实付 APR**（后端已计算） | **直接使用，无需手动减 nativeAPY** |

后端在序列化时已将 TARGET_TOTAL_APR 的 `campaignApr` 从 `targetAPR` 转换为实付 APR：

```
targetAPY = convertAprToApy(targetAPR)     // APR→APY (月复利 n=12)
incentiveAPY = targetAPY - nativeAPY       // supply; borrow 侧 = nativeAPY - targetAPY
campaignApr = apyToApr(max(incentiveAPY, 0)) // APY→APR，输出与 MAX/FIX 统一格式
```

转换公式与前端 `rateCalculations.ts` 完全一致（月复利 n=12）。`aprCap` 字段仍保留原始 `targetAPR`，供前端展示"目标 APR"。

### 1.4 budgetBoundMode 链路状态（已接通）

`budgetBoundMode` 是 TARGET_TOTAL_APR 的正交维度，决定 budget 用尽后的行为。链路已完全接通（2026-06-15 修复）：

| 环节 | 状态 | 代码位置 |
|---|---|---|
| Merkl API 返回 `distributionSettings.mode` | ✅ 有数据 | campaign params |
| Fetcher 提取为 `rawMode` 写入 lite 文件 | ✅ 已提取 | `merkl-api.ts:663-665`, `:687`, `:700` |
| Fetcher breakdown 构建时赋值 budgetBoundMode | ✅ 已赋值 | `merkl-api.ts:1278`（从 rawMode 读取，仅 TARGET_TOTAL_APR） |
| Backend 读取 lite 文件 | ✅ 提取 rawMode | `merklForecastService.ts` |
| `CampaignOpportunityMeta` 接口 | ✅ 含 rawMode | `merklForecastService.ts` |
| Forecast 计算 | ✅ 区分 MAX_APR / FIX_APR mode | `merklApiContract.ts`（field rules 动态化） |
| `MerklCampaignBreakdown.budgetBoundMode` | ✅ 运行时赋值 | fetcher `merkl-api.ts` |
| `ApiMerklBreakdown` | ✅ 等于 `MerklCampaignBreakdown`（Pick 列表已移除） | `shared-contracts/src/index.ts` |
| API 序列化输出 | ✅ 输出 budgetBoundMode | TARGET_TOTAL_APR 时包含，FIX_APR 时省略 plannedDaily |

**Forecast metrics 与 mode 的关系（已修复 2026-06-15）**：

`plannedDaily` = `totalBudget / totalDays` 是"预算均匀日耗"假设。对 MAX 模式有意义（budget 可能花不完，plannedDaily 是消耗上限参考）。对 FIX 模式**无意义**——FIX 的 cost ∝ TVL，实际消耗可能远超 plannedDaily，budget 提前用完 campaign 就结束。

代码已根据 `budgetBoundMode` 动态选择 field rules：
- `BREAKDOWN_FIELD_RULES`: FIX → `omit: ['plannedDaily']`；MAX → 输出 plannedDaily
- `FORECAST_FIELD_RULES`: FIX → `mode: 'fix'`, `includeRequiredDaily: false`；MAX → `mode: 'max'`, `includeRequiredDaily: true`
- TARGET_TOTAL_APR 根据 breakdown 上的 `budgetBoundMode` 自动选择 FIX/MAX 规则（不再硬编码 `mode: 'max'`）

### 1.5 各 distributionMethod 的官方定义与特定参数

来源：Merkl Schema API (`/v4/schemas/distributionMethod`)，2026-06-14 查询。

| distributionMethod | 官方描述 | Aave lending | 特定参数 |
|---|---|---|---|
| `AAVE_NET_APR` | Automatically tops up Aave native APR to reach a target APR | ✅ | `targetAPR`, `assetId` |
| `AAVE_V4_NET_APR` | Tops up Aave V4 native APR to reach a target total APR | ✅ | `targetAPR`, `assetId`, `hubAddress`, `side` |
| `ERC4626_APR` | Tops up ERC4626 vault APR to reach a target total APR | ❌ vault | `targetAPR` |
| `ERC4626_SPREAD_CAPPED` | Pays the spread between a target APR and the ERC4626 vault native APR, capped at a maximum Merkl-paid APR. Merkl APR = min(max(targetAPR - vaultAPR, 0), cap) | ❌ vault | `targetAPR`, `cap` |
| `ERC4626_TARGET_APR_WITH_MERKL` | Tops up an ERC4626 vault's native APR and the existing Merkl opportunity APR to reach a target total APR. Merkl APR = max(targetAPR - vaultAPR - merklOpportunityAPR, 0). Designed to run on top of a vault-tracking campaign (e.g. MORPHOVAULT, ERC20LOGPROCESSOR). | ❌ vault | `targetAPR`（merklOppAPR 来自运行时） |
| `SOFR_SPREAD_RATCHET` | Tops up an ERC4626 vault's native APR to a TVL-tiered target (live SOFR + a spread that tightens as campaign-tracked TVL grows, held by a one-way ratchet). Merkl APR = max(SOFR + spread(maxTVL) - vaultAPR, 0). Designed to run on top of a vault-tracking campaign (e.g. MORPHOVAULT, ERC20LOGPROCESSOR). | ❌ vault | spread tier table（动态 target） |
| `DEEL_DISTRIBUTION` | DEEL split distribution: tops up vault holders to 2.5% effective APR (net of Merkl opportunity APR and the vault native APR) and routes a SOFR-derived treasury skim to a target address. Designed to run on top of a vault-tracking campaign (e.g. MORPHOVAULT, ERC20LOGPROCESSOR) — uses the time-weighted TVL implicit in the per-user scores. | ❌ vault | 固定 target 2.5%（treasury skim 不影响用户 APR） |

**所有 7 种的 budgetBoundMode**：`MAX_APR` 或 `FIX_APR`（从 `distributionSettings.mode` 读取）。ERC4626_SPREAD_CAPPED 已验证为 `FIX_APR`，AAVE_NET_APR/AAVE_V4_NET_APR 已验证为 `MAX_APR`，其余待验证。

**vault-based 判定依据**：后 5 种的官方描述中包含 "ERC4626 vault"、"vault holders"、"vault-tracking campaign (e.g. MORPHOVAULT, ERC20LOGPROCESSOR)"，公式中减的是 `vaultAPR` 而非 `nativeAPR`。

**spreadCap 参数**：仅 `ERC4626_SPREAD_CAPPED` 拥有。已从代码中移除（YAGNI — 后端无法获取 vaultAPR，无消费者）。**Vault 模式预留**：未来支持 ERC4626 vault 时需重新引入 `spreadCap`（来源 `distributionSettings.cap`）以及 `vaultAPR` 数据源。

---

## 2. 前端核心变更

### 2.1 新增 TARGET_TOTAL_APR 到前端 campaign type 联合类型

### 2.2 APR 计算（2026-06-15 更新：后端已完成，前端无需计算）

**后端已将 `campaignApr` 转换为 Merkl 实付 APR**，前端对 TARGET_TOTAL_APR 的 `campaignApr` 可与 MAX/FIX 完全相同的方式使用，**无需手动减 nativeAPY**。

`aprCap` 仍保留原始 `targetAPR`，前端可用于展示"目标 APR = X%"。

**为什么不需要 `rawDistributionMethod`**：

Aave lending 场景只有 `AAVE_NET_APR` 和 `AAVE_V4_NET_APR`，两者的公式完全相同：`max(targetAPR - nativeAPR, 0)`。`nativeAPR` 就是 reserve 自身的 APY，前端已有。`campaignType = TARGET_TOTAL_APR` 足以区分计算逻辑，不需要再展开子类型。

**ERC4626 系列为什么不处理**：

经 Merkl 官方 Schema API (`/v4/schemas/distributionMethod`) 确认，ERC4626_APR / ERC4626_SPREAD_CAPPED / ERC4626_TARGET_APR_WITH_MERKL / SOFR_SPREAD_RATCHET / DEEL_DISTRIBUTION 全部是 vault-based（公式中减的是 `vaultAPR` 而非 `nativeAPR`，且 Merkl 官方描述为 "tops up ERC4626 vault APR" / "vault-tracking campaign"）。后端当前无法获取 vaultAPR（Merkl API 不提供），因此这些类型短期不可实现。映射表保留（防御性），但前端不需要处理。

### 2.3 Budget-bound 行为与 Simulation

`budgetBoundMode` 透传后（P1），前端 simulation 需要区分：

| budgetBoundMode | budget 充足时 | budget 不足时 | simulation 公式 |
|---|---|---|---|
| `MAX_APR` | `max(aprCap - nativeAPR, 0)` | APR 被 TVL 稀释降到 target 以下 | `min(max(aprCap - nativeAPR, 0), remainingBudgetRate / TVL × 365)` |
| `FIX_APR` | `max(aprCap - nativeAPR, 0)` | campaign 提前结束 | `max(aprCap - nativeAPR, 0)`（固定直到 budget 耗尽） |

**不是 DUTCH_AUCTION 模式**。TARGET_TOTAL_APR 与 MAX/FIX 同族——有 cap（targetAPR），budget 不足时的行为取决于 budgetBoundMode。

当前 3 个活跃 campaign 的 budgetBoundMode 全部是 `MAX_APR`。

### 2.4 Forecast

forecast API 返回 `requiredDaily`、`remainingBudget` 等，TARGET_TOTAL_APR 的 forecast 逻辑与 MAX 完全一致（budget 估算，不做 dilutive 计算）。前端无需额外处理。

---

## 3. 后端需要补充的工作

### P1: 透传 budgetBoundMode — ✅ 已完成 (2026-06-15)

所有断路点已修复，field rules 已动态化。详见 Section 1.4。

### 暂不处理

| 字段 | 原因 |
|---|---|
| `spreadCap` | 已移除（YAGNI）。Vault 模式预留：未来 ERC4626 支持时需重新引入 `spreadCap`（来源 `distributionSettings.cap`）+ `vaultAPR` 数据源 |
| `rawDistributionMethod` | Aave lending 场景只有 AAVE_NET_APR / AAVE_V4_NET_APR，公式相同，不需要区分子类型 |
| `vaultAPR` | Merkl API 不提供，无法透传 |
| `merklOppAPR` | 需聚合同 reserve 上其他 opportunity，当前未实现 |

---

## 4. 当前 Aave 活跃的 TARGET_TOTAL_APR Campaign

| campaignId | distributionMethod | reserve | side | targetAPR (aprCap) | budgetBoundMode |
|---|---|---|---|---|---|
| 13116567236794890552 | AAVE_NET_APR | 4326:0x7e32...c28 | supply | 4.7% | MAX_APR |
| 12662496063613214537 | AAVE_V4_NET_APR | 1:0x973a...e29:0xcca8...6c9 | supply | 5.83% | MAX_APR |
| 8647796357084493685 | AAVE_V4_NET_APR | 1:0x6540...1dc:0xcca8...6c9 | supply | 7.7% | MAX_APR |

全部是 `AAVE_NET_APR` / `AAVE_V4_NET_APR`，budgetBoundMode 全部为 `MAX_APR`。

---

## 5. 建议的前端实施顺序

1. **P0**: 新增 TARGET_TOTAL_APR 到前端类型；`merklActualAPR = max(aprCap - nativeAPR, 0)`
2. **P1**: 后端透传 `budgetBoundMode`；前端据此区分 dilutive vs early-end simulation 逻辑
3. **P2（defer）**: ERC4626 子类型支持（需要 vaultAPR 数据源，当前不可用）

---

## 6. 术语澄清

### campaignType vs distributionMethod vs budgetBoundMode — 三个正交维度

| 维度 | 字段 | 语义 | 前端用途 |
|---|---|---|---|
| 一级分类 | `campaignType` | APR cap 语义 + 计算逻辑族 | 选择 APR 计算方式 |
| 二级分类 | `distributionMethod` | 具体公式（被减数来源） | Aave lending 不需要区分 |
| budget 行为 | `budgetBoundMode` | budget 用尽后的 fallback 策略 | simulation 模式选择 |

Aave lending 场景下：`campaignType = TARGET_TOTAL_APR` 已足够区分计算逻辑，不需要透传 `distributionMethod`。`budgetBoundMode` 是正交维度，影响 simulation。

### aprCap 语义差异（重申）

| campaignType | aprCap 含义 | 前端计算 merklActualAPR |
|---|---|---|
| MAX | Merkl 实付上限 | `min(aprCap, budget_rate / TVL × 365)` |
| FIX | Merkl 实付固定值 | `aprCap`（固定） |
| **TARGET_TOTAL_APR** | **总 APR 目标** | **`max(aprCap - nativeAPR, 0)`** |
| DUTCH_AUCTION | 无 cap | `budget_rate / TVL × 365` |

---

## 7. 共享文档

- **`aaveapy-doc/merkl-distribution-types.md`** — 4 大 Family + 7 种子类型 + budget-bound mode + APR 公式 + dilutive 示例
- **`docs/adr/0024-merkl-campaign-type-multi-level-mapping.md`** — 映射表 + APR cap 语义差异
- **Merkl 官方文档** — https://docs.merkl.xyz/merkl-mechanisms/distributions
- **Merkl Schema API** — https://api.merkl.xyz/v4/schemas/distributionMethod
