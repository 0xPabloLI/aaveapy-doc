# V3/V4 Incentive 匹配问题分析

**文档版本**: 2026-05-23  
**状态**: Merkl 已解决（protocolVersion 推导已实现），Merit/Brevis 暂时仅 V3

---

## 1. 问题背景

系统从三个外部源获取 incentive 数据（Merit、Merkl、Brevis），然后在 `enrichDatasetWithIncentiveData()` 中匹配到对应的 reserve。当 V4 上线后，**同一链上同一 token 可能同时存在于 V3 和 V4 market**，需要将 incentive 正确匹配到对应版本的 market。

核心问题：**三个外部源都不显式返回协议版本（v3/v4）**。

---

## 2. 各 incentive 源的匹配机制与 V3/V4 区分能力

### 2.1 Merit

| 项目 | 详情 |
|------|------|
| **API** | `https://apps.aavechan.com/api/merit/aprs` |
| **key 格式** | `{chain}-{action}-{token}`，如 `ethereum-supply-weth` |
| **匹配方式** | `getMeritDataFromMarket()` 用 `marketName` → `chainKey` 映射 + `tokenSymbol` |
| **V3/V4 区分** | ❌ key 中无版本信息 |

**分析**：Merit raw key 只有 chain + action + token，无法区分同链同 token 的 V3/V4。如果 V4 上线 Merit，除非 Aave 团队在 key 中加版本标识（如 `ethereum-v4-supply-weth`），否则无法区分。

**当前风险**：低。目前 Merit API 返回的所有 key 均对应 V3 markets（截至 2026-04-23 验证，无任何 V4 相关 key）。但这只是因为 V4 尚未上线 Merit，而非 Merit 设计上只支持 V3。

### 2.2 Merkl ✅ 已解决

| 项目 | 详情 |
|------|------|
| **API** | `https://api.merkl.xyz/v4/opportunities?mainProtocolId=aave` |
| **匹配方式** | `findMatchingMerklOpportunities()` 用 `chainId` + `explorerAddress` + `protocolVersion` |
| **V3/V4 区分** | ✅ 通过 4-step protocolVersion 推导（ADR-0018） |

**分析 (2026-05-23 更新，基于 117 条 live opportunities 验证)**：

#### explorerAddress 的结构差异是核心区分手段

| 协议版本 | Opportunity 类型 | explorerAddress | 示例 |
|----------|-----------------|-----------------|------|
| V3 | Lend / Borrow | **aToken / vToken 地址** | `aHorRwaRLUSD`, `aPlaUSDT0` |
| V4 Spoke | Supply | **Spoke 地址** | `0x94e7...`（多 token 共享） |
| V4 Hub | Supply | **Underlying token 地址** | USDG=`0xe343...` |

**关键发现**：V3 的 explorerAddress 永远是 aToken/vToken，**从不使用 underlying token**。这意味着 V3 和 V4 的 explorerAddress 空间天然分离。

#### Protocol Version 推导的 4-Step 优先级 (ADR-0018)

```
1. type 以 AAVE_V4_ 开头 → v4           (零成本，Merkl 的权威命名约定)
2. 无歧义地址反查 (aToken/vToken/spoke) → v3/v4  (精确，地址空间不相交)
3. V4 underlying token 反查 → v4        (仅 V4 Hub Supply 走这里)
4. 默认 → v3                             (保守兜底，V3 不吃 V4 campaign)
```

两端查找表从 `baseDataset` 构建，每条 reserve 插入 2-3 条记录，<150 条 reserve，总内存 <10KB。

#### 匹配时的版本过滤

`findMatchingMerklOpportunities()` 接收 `protocolVersion` 参数，只返回匹配版本的 opportunities。调用方根据 reserve 的 `marketName` 前缀（`AaveV4`→`v4`）决定传入哪个版本。

#### Merkl API 返回的可用字段总结

| 字段 | V3/V4 区分能力 | 可靠性 |
|------|--------------|--------|
| `type` | `AAVE_V4_` 前缀可区分 | ✅ Merkl 自己的分类体系 |
| `explorerAddress` | 结构差异（见上表） | ✅ 地址空间不相交 |
| `name` | 偶尔含版本名 | ❌ 自由文本，不可靠 |
| `protocol.id` | 无 | ❌ 统一为 `"aave"` |

### 2.3 Brevis

| 项目 | 详情 |
|------|------|
| **API** | gRPC (`brevis-campaign.uw.r.appspot.com`) |
| **匹配方式** | `fetchBrevisAprs()` 用 `{chainId}-{tokenAddress}`（underlying token 地址）索引 |
| **V3/V4 区分** | ❌ 当前索引方式丢弃了版本信息 |

**分析**：

- Brevis 的 `protocol` 对象包含 `id`（pool 合约地址）和 `name`（如 `"Lend or Borrow USDC from Aave on Linea"`），**pool 地址天然能区分 V3/V4**
- 但当前代码在构建索引时只用了 `{chainId}-{tokenAddress}`（underlying），**丢弃了 `protocol.id`**
- 如果同链同 token 在 V3 和 V4 都有 Brevis campaign，当前逻辑会**合并到同一个 index entry**，导致两个版本的 reserve 获得相同的 Brevis incentive

---

## 3. 当前数据验证结果（2026-05-23 更新）

| 源 | 是否有 V4 数据 | 验证方式 |
|---|---|---|
| Merit | ❌ 无 (仅 v3) | `protocolVersion` 写死为 `'v3'` |
| Merkl | ✅ 有 (4 条 V4, 113 条 V3) | type 前缀 `AAVE_V4_` + explorerAddress 结构验证 |
| Brevis | ❌ 无 (仅 v3) | `protocolVersion` 写死为 `'v3'`，且活动目前仅限 Linear |

**结论：Merkl 的 V3/V4 匹配已通过 protocolVersion 推导解决（ADR-0018）。Merit/Brevis 目前无 V4 数据，预留了 `protocolVersion` 字段供未来使用。**

### Merkl V4 数据明细（2026-05-23）

| Opportunity | Type | explorerAddress 结构 |
|------------|------|---------------------|
| Supply USDG to Aave V4 Core | `AAVE_V4_HUB_SUPPLY` | underlying token |
| Supply frxUSD to Aave V4 Core | `AAVE_V4_HUB_SUPPLY` | underlying token |
| Supply USDG to Aave V4 Main Spoke | `AAVE_V4_SPOKE_SUPPLY` | spoke address |
| Supply frxUSD to Aave V4 Main Spoke | `AAVE_V4_SPOKE_SUPPLY` | spoke address |

---

## 4. V4 上线后的预期风险（2026-05-23 更新）

| 风险等级 | 源 | 场景 | 影响 | 状态 |
|----------|---|------|------|------|
| 🟢 已解决 | Merkl | V4 campaign 错配到 V3 reserve | 重复 incentive | ✅ protocolVersion 推导 |
| 🟡 中 | Merit | V4 campaign 使用相同 key 格式 | V4 incentive 被错配到 V3 market | ⏳ 预留 protocolVersion |
| 🟡 中 | Brevis | 同链同 token 在 V3+V4 都有 campaign | 两个 reserve 获得相同 incentive | ⏳ 预留 protocolVersion |

### 反查模式的复用价值

本次 Merkl 中建立的 `chainId:address → reserve version` 反向查表模式，可以直接复用于 Brevis。Brevis 同样只用 `chainId + tokenAddress` 匹配，没有版本区分。未来 Brevis 上 V4 时，只需在 `fetchBrevisAprs()` 中构建同样的反查表即可。

### Net Position Constraint 的反查与 resolve（2026-05-25 补充）

Net position constraint（`AAVE_NET_LENDING` / `AAVE_NET_BORROWING`）的 offset reserve 解析依赖两步反查：

**Step 1 — explorerAddress → reserveId 反查**

`tokenAddrToReserveId` Map 为每个 reserve 注册 4 种地址映射（`tokenAddress` / `aTokenAddress` / `vTokenAddress` / `spokeAddress`），用 `chainId:address` 作为 key。V3 opportunity 的 `explorerAddress` 通常是 aToken/vToken，V4 通常是 spoke 或 underlying token，因此 4 种映射覆盖了所有场景。

**Step 2 — offset token address → offsetReserveIds resolve**

`resolveOffsetReserveIds(oppReserveId, offsetTokenAddr, reserveIdSet)` 的核心约束：**offset reserve 必须与 source reserve 在同一 pool/spoke 内**。

| 版本 | resolve 逻辑 | 结果 |
|------|-------------|------|
| V3 | `chainId:poolAddress:offsetTokenAddr` → 唯一匹配 | 单个 reserveId |
| V4 | `chainId:hubAddress:offsetTokenAddr:*` → 前缀匹配 | 可能多个 spoke 下的 reserveId |

V4 返回多个 reserveId 的原因：同一 asset 在不同 spoke 上有不同 reserveId（如 `57073:hub:gho:spokeA` 和 `57073:hub:gho:spokeB`），都是合法的 offset。

**V3/V4 差异总结**：

| 维度 | V3 | V4 |
|------|----|----|
| reserveId 格式 | `chainId:pool:token`（三段） | `chainId:hub:asset:spoke...`（四段+） |
| offset resolve | 唯一匹配 | 前缀匹配，可能多 spoke |
| explorerAddress 通常 | aToken / vToken | spoke 地址 或 underlying token |
| 反查 Map 命中 | 主要靠 aToken/vToken 映射 | 主要靠 spoke/underlying 映射 |

---

## 5. 建议改进方案（2026-05-23 更新）

### 5.1 已完成 ✅

1. **给 CampaignGroup 加 `protocolVersion` 字段**（`'v3' | 'v4'`）
   - Merit: 固定 `'v3'`（`merit-api.ts`）
   - Merkl: 通过 4-step 优先级推导（`merkl-api.ts` → `deriveProtocolVersion()`）
   - Brevis: 固定 `'v3'`（`brevis-api.ts`）

2. **Merkl protocolVersion 推导（ADR-0018）**
   - `buildProtocolVersionLookup()` 从 `baseDataset` 构建无歧义地址 + V4 underlying 反查表
   - `findMatchingMerklOpportunities()` 按 `protocolVersion` 过滤匹配
   - 调用方 (`index.ts`) 根据 `marketName` 前缀判断 reserve 版本

3. **所有激励源统一 `protocolVersion` 字段**
   - 为 Merit 和 Brevis 也预留了 `protocolVersion: 'v3'`，确保未来扩展时有统一基础

### 5.2 后续待做

1. **Brevis 索引改进**（当 Brevis 出现 V4 campaign 时）
   - 可复用 Merkl 中的反查表模式：构建 `chainId:protocolId → version` 映射
   - 当前 `protocolVersion` 字段已预留，只需更新推导逻辑

2. **Merit 观察**
   - 等 V4 campaign 出现后，分析 key 格式是否有变化
   - 如有版本标识，更新 `getMeritDataFromMarket()` 的 chainKey 映射；否则需找其他区分手段

---

## 6. 相关代码位置

| 功能 | 文件 | 函数 |
|------|------|------|
| Incentive enrichment 主逻辑 | `packages/aave-fetcher/src/index.ts` | `enrichDatasetWithIncentiveData()` |
| Merit 匹配 | `packages/aave-fetcher/src/merit-api.ts` | `getMeritDataFromMarket()` |
| Merkl 匹配 | `packages/aave-fetcher/src/merkl-api.ts` | `findMatchingMerklOpportunities()` |
| Merkl protocolVersion 推导 | `packages/aave-fetcher/src/merkl-api.ts` | `deriveProtocolVersion()`, `buildProtocolVersionLookup()` |
| Brevis 索引构建 | `packages/aave-fetcher/src/brevis-api.ts` | `fetchBrevisAprs()` 内部 |
| V4 数据获取 | `packages/aave-fetcher/src/v4-fetcher.ts` | `fetchAaveV4Reserves()` |
| 统一数据集 | `packages/aave-fetcher/src/index.ts` | `buildMarketsBaseDataset()` |

## 7. 相关文档

- ADR-0018 Merkl protocolVersion 推导: `docs/adr/0018-merkl-campaigngroup-protocol-version.md`
- CONTEXT.md glossary (CampaignGroup, protocolVersion): `CONTEXT.md`
- API 总览：`docs/api/api-documentation.md`
- Brevis 补充：`docs/api/brevis-supplement.md`
- 缓存架构：`docs/merkl-merit-cache-architecture.md`
