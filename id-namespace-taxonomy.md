# Aave V4 ID 命名空间与层级关系

---

## 一、ID 分配规则

| ID | 所属合约 | 分配方式 | 唯一性范围 | 递增计数器 |
|----|---------|---------|-----------|-----------|
| `assetId` | Hub | `uint256 assetId = _assetCount++` | **per Hub**：同一 Hub 内唯一，不同 Hub 各自编号 | `Hub._assetCount` |
| `reserveId` | Spoke | `uint256 reserveId = _reserveCount++` | **per Spoke**：同一 Spoke 内唯一，不同 Spoke 各自编号 | `Spoke._reserveCount` |
| `spoke` | — | 使用合约地址 | **全局**：spoke 地址本身就是标识 | — |
| `hub` | — | 使用合约地址 | **全局**：hub 地址本身就是标识 | — |

**去重约束**：

| 约束 | 合约检查 | 含义 |
|------|---------|------|
| `isUnderlyingListed(underlying)` | Hub.addAsset | 同一 Hub 内，同一 underlying token 只能添加一次 → 同一 Hub 内 underlying ↔ assetId 一一对应 |
| `_isAssetIdListed(hub, assetId, ...)` | Spoke.addReserve | 同一 Spoke 内，同一 (hub, assetId) 只能添加一次 → 同一 Spoke 内 (hub, assetId) ↔ reserveId 一一对应 |
| `isSpokeListed(assetId, spoke)` | Hub.addSpoke | 同一 assetId 下，同一 spoke 只能注册一次 |

---

## 二、层级关系图

```
Hub A (hubAddress_A)
 ├── assetId=0 (WETH)  ← _assets[0]
 │    ├── Spoke S1 (spokeAddress_S1) → _spokes[0][S1].deficitRay, ...
 │    ├── Spoke S2 (spokeAddress_S2) → _spokes[0][S2].deficitRay, ...
 │    └── Spoke S3 (spokeAddress_S3) → _spokes[0][S3].deficitRay, ...
 ├── assetId=1 (USDC)  ← _assets[1]
 │    ├── Spoke S1 → _spokes[1][S1]
 │    └── Spoke S2 → _spokes[1][S2]
 └── assetId=2 (WBTC)  ← _assets[2]
      └── Spoke S1 → _spokes[2][S1]

Hub B (hubAddress_B)
 ├── assetId=0 (WETH)  ← _assets[0]  ← ⚠️ 与 Hub A 的 assetId=0 不同！
 │    └── Spoke S4 → _spokes[0][S4]
 └── assetId=1 (GHO)  ← _assets[1]
      └── Spoke S4 → _spokes[1][S4]

Spoke S1 (spokeAddress_S1)
 ├── reserveId=0 → (hub=A, assetId=0, underlying=WETH)  ← _reserves[0]
 ├── reserveId=1 → (hub=A, assetId=1, underlying=USDC)  ← _reserves[1]
 └── reserveId=2 → (hub=A, assetId=2, underlying=WBTC)  ← _reserves[2]

Spoke S2 (spokeAddress_S2)
 ├── reserveId=0 → (hub=A, assetId=0, underlying=WETH)  ← ⚠️ 与 S1 的 reserveId=0 不同！
 └── reserveId=1 → (hub=A, assetId=1, underlying=USDC)

Spoke S4 (spokeAddress_S4)
 ├── reserveId=0 → (hub=B, assetId=0, underlying=WETH)
 └── reserveId=1 → (hub=B, assetId=1, underlying=GHO)
```

---

## 三、穷举场景：同一 token 在不同层级下的 ID 表现

以 **WETH** 为例，穷举所有出现方式（√ = 该组合存在，— = 不存在）：

### 3.1 场景总表

| 场景 | Hub | Hub 中 WETH 的 assetId | Spoke | Spoke 中 WETH 的 reserveId | 说明 |
|------|-----|----------------------|-------|--------------------------|------|
| A | CORE_HUB | 0 | MAIN_SPOKE | 0 | CORE 市场主 Spoke 的 WETH |
| B | CORE_HUB | 0 | BLUECHIP_SPOKE | 0 | CORE 市场蓝筹 Spoke 的 WETH（**同 assetId，不同 reserveId 空间**） |
| C | CORE_HUB | 0 | LIDO_E_SPOKE | 0 | CORE 市场 Lido Spoke 的 WETH（**同 assetId，又一个独立 reserveId 空间**） |
| D | CORE_HUB | 0 | ETHERFI_E_SPOKE | ? | CORE 市场 EtherFi Spoke 的 WETH（若已上架） |
| E | PRIME_HUB | ? | LOMBARD_BTC_SPOKE | ? | PRIME 市场的 WETH（**assetId 重新编号，与 CORE_HUB 的 assetId 无关**） |
| F | PLUS_HUB | ? | ETHENA_CORRELATED_SPOKE | — | PLUS 市场**无 WETH**（— 表示不存在） |

### 3.2 关键推演

| 问题 | 答案 |
|------|------|
| 同一 Hub 同一 token 的 assetId 是否唯一？ | **是**，同一 Hub 内 underlying ↔ assetId 一一对应 |
| 不同 Hub 同一 token 的 assetId 是否相同？ | **不一定**，各 Hub 独立编号（`_assetCount++` 从 0 开始） |
| 同一 Spoke 同一 (hub, assetId) 的 reserveId 是否唯一？ | **是**，同一 Spoke 内 (hub, assetId) ↔ reserveId 一一对应 |
| 不同 Spoke 同一 (hub, assetId) 的 reserveId 是否相同？ | **不一定**，各 Spoke 独立编号（`_reserveCount++` 从 0 开始），但巧合时常发生（同为 0） |
| 同一 Spoke 能否连接多个 Hub？ | **能**，Spoke 通过 `addReserve(hub, assetId, ...)` 连接任意 Hub |
| 同一 Spoke 同一 Hub 的同一 token 能否有多个 reserveId？ | **不能**，`_isAssetIdListed(hub, assetId)` 去重 |

---

## 四、以 USDC 为例：跨 Hub 跨 Spoke 穷举

USDC 在多个 Hub 和 Spoke 中上架：

| Hub | Hub 中 USDC 的 assetId | Spoke | Spoke 中 USDC 的 reserveId | 备注 |
|-----|----------------------|-------|--------------------------|------|
| CORE_HUB | ?_core | MAIN_SPOKE | ? | CORE 主市场 |
| CORE_HUB | ?_core | BLUECHIP_SPOKE | ? | CORE 蓝筹市场 |
| PLUS_HUB | ?_plus | ETHENA_ECOSYSTEM_SPOKE | ? | PLUS Ethena 生态市场 |
| PLUS_HUB | ?_plus | FOREX_SPOKE | ? | PLUS 外汇市场 |
| PLUS_HUB | ?_plus | GOLD_SPOKE | ? | PLUS 黄金市场 |
| PRIME_HUB | ?_prime | — | — | PRIME 是否有 USDC 取决于部署配置 |

**注意**：`?_core` ≠ `?_plus` ≠ `?_prime`（各 Hub 独立编号），但底层 underlying 地址相同（`0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`）。

---

## 五、ID 查询路径

| 已知 | 查询目标 | 方法 |
|------|---------|------|
| underlying + Hub | assetId | `Hub.getAssetId(underlying)` |
| assetId | underlying + decimals | `Hub.getAssetUnderlyingAndDecimals(assetId)` |
| hub address + assetId + Spoke | reserveId | `Spoke.getReserveId(hub, assetId)` |
| reserveId | hub + assetId + underlying | `Spoke.getReserve(reserveId)` → `.hub`, `.assetId`, `.underlying` |
| assetId | 该 asset 下所有 spoke 地址 | `Hub.getSpokeCount(assetId)` + `Hub.getSpokeAddress(assetId, index)` 遍历 |

---

## 六、Spoke 到 Hub 的连接机制

Spoke **不存储 hubId / spokeId 数值**，而是存储合约地址：

```solidity
// SpokeStorage.sol
mapping(uint256 reserveId => ISpoke.Reserve) internal _reserves;
// 其中 Reserve.hub 是 IHubBase 类型（即 Hub 合约地址）

// HubStorage.sol
mapping(uint256 assetId => mapping(address spoke => IHub.SpokeData)) internal _spokes;
// spoke 键即 Spoke 合约地址
```

| 概念 | 合约中存储方式 | 前端/SDK 使用 |
|------|-------------|-------------|
| hubId | Hub 合约地址 | SDK 可映射为短名（如 `CORE_HUB`、`PLUS_HUB`） |
| spokeId | Spoke 合约地址 | SDK 可映射为短名（如 `MAIN_SPOKE`） |
| assetId | uint256，per Hub 自增 | 跨 Hub 时无全局意义，需配合 hub 地址 |
| reserveId | uint256，per Spoke 自增 | 跨 Spoke 时无全局意义，需配合 spoke 地址 |

---

## 七、实际部署拓扑（Ethereum Mainnet）

### 7.1 Hub → Spoke 归属

| Hub | 关联 Spoke | Spoke 数量 |
|-----|-----------|-----------|
| CORE_HUB | MAIN_SPOKE, BLUECHIP_SPOKE, LIDO_E_SPOKE, ETHERFI_E_SPOKE, KELP_E_SPOKE | 5 |
| PLUS_HUB | ETHENA_CORRELATED_SPOKE, ETHENA_ECOSYSTEM_SPOKE, FOREX_SPOKE, GOLD_SPOKE | 4 |
| PRIME_HUB | LOMBARD_BTC_SPOKE | 1 |

### 7.2 Token → Hub 分布

| Token | CORE_HUB | PLUS_HUB | PRIME_HUB | 说明 |
|-------|:--------:|:--------:|:---------:|------|
| WETH | ✓ | — | ✓ | CORE + PRIME 共享同一 underlying，但 assetId 各自独立 |
| wstETH | ✓ | — | ✓ | 同上 |
| WBTC | ✓ | — | ✓ | 同上 |
| cbBTC | ✓ | — | ✓ | 同上 |
| LBTC | — | — | ✓ | PRIME 独有 |
| USDC | ✓ | ✓ | ✓ | 三个 Hub 均有，各自 assetId 独立 |
| USDT | ✓ | ✓ | ✓ | 同 USDC |
| GHO | ✓ | ✓ | ✓ | 同 USDC |
| weETH | ✓ | — | — | CORE 独有 |
| rsETH | ✓ | — | — | CORE 独有 |
| AAVE | ✓ | — | — | CORE 独有 |
| LINK | ✓ | — | — | CORE 独有 |
| sUSDe | — | ✓ | — | PLUS 独有 |
| USDe | — | ✓ | — | PLUS 独有 |
| PT_sUSDE_7MAY2026 | — | ✓ | — | PLUS 独有 |
| PT_USDe_7MAY2026 | — | ✓ | — | PLUS 独有 |
| RLUSD | ✓ | — | — | CORE 独有 |
| USDG | ✓ | — | — | CORE 独有 |
| frxUSD | ✓ | — | — | CORE 独有 |
| EURC | ✓ | — | — | CORE 独有 |
| XAUt | — | — | ✓ | PRIME 独有 |

### 7.3 Hub → Token → Spoke 三维矩阵（有 ✓ 表示该 Spoke 上架了该 token）

**CORE_HUB 的 token × Spoke 矩阵**：

| Token \ Spoke | MAIN | BLUECHIP | LIDO_E | ETHERFI_E | KELP_E |
|---------------|:----:|:--------:|:------:|:---------:|:------:|
| WETH | ✓ | ✓ | ✓ | ✓ | ✓ |
| wstETH | ✓ | ✓ | ✓ | — | — |
| weETH | ✓ | — | — | ✓ | — |
| rsETH | ✓ | — | — | — | ✓ |
| USDC | ✓ | ✓ | — | — | — |
| USDT | ✓ | ✓ | — | — | — |
| GHO | ✓ | ✓ | — | ✓ | — |
| WBTC | ✓ | ✓ | — | — | — |
| cbBTC | ✓ | ✓ | — | — | — |
| AAVE | ✓ | — | — | — | — |
| LINK | ✓ | — | — | — | — |
| RLUSD | ✓ | — | — | ✓ | — |
| USDG | ✓ | — | — | ✓ | — |
| frxUSD | ✓ | ✓ | — | ✓ | — |
| EURC | ✓ | — | — | ✓ | — |

**PLUS_HUB 的 token × Spoke 矩阵**：

| Token \ Spoke | ETHENA_CORRELATED | ETHENA_ECOSYSTEM | FOREX | GOLD |
|---------------|:-----------------:|:----------------:|:-----:|:----:|
| USDC | — | ✓ | ✓ | ✓ |
| USDT | — | ✓ | ✓ | ✓ |
| GHO | — | ✓ | ✓ | ✓ |
| sUSDe | ✓ | ✓ | — | — |
| USDe | ✓ | ✓ | — | — |
| PT_sUSDE_7MAY2026 | ✓ | ✓ | — | — |
| PT_USDe_7MAY2026 | ✓ | ✓ | — | — |
| frxUSD | — | ✓ | ✓ | ✓ |
| EURC | — | — | ✓ | ✓ |
| RLUSD | — | — | ✓ | ✓ |
| USDG | — | — | ✓ | ✓ |

**PRIME_HUB 的 token × Spoke 矩阵**：

| Token \ Spoke | LOMBARD_BTC |
|---------------|:-----------:|
| WETH | ✓ |
| wstETH | ✓ |
| WBTC | ✓ |
| cbBTC | ✓ |
| LBTC | ✓ |
| USDC | ✓ |
| USDT | ✓ |
| GHO | ✓ |
| XAUt | ✓ |

---

## 八、跨 Hub 同 token 的 ID 冲突示意

以 **WETH**（underlying = `0xC02a...6Cc2`）为例：

```
                  WETH (0xC02a...6Cc2)
                  ┌──────────────────────────────────┐
                  │                                  │
          CORE_HUB                               PRIME_HUB
     assetId = 0¹                            assetId = ?²
     (假设首个添加的 asset)                   (取决于添加顺序)
          │                                       │
     ┌────┼────┬────┬────┐                   ┌────┘
     │    │    │    │    │                   │
  MAIN  BLUE LIDO ETH KELP              LOMBARD
  SPOKE CHIP E    FI   P                BTC
     │    │    │    │    │                   │
  resId resId resId resId resId           resId
  =0³  =0⁴  =0⁵  =?   =?                =0⁶
```

**脚注**：

| 标记 | 说明 |
|------|------|
| ¹ | CORE_HUB 中 WETH 的 assetId，由 `_assetCount++` 决定 |
| ² | PRIME_HUB 中 WETH 的 assetId，与 ¹ **无关**（独立计数器） |
| ³~⁶ | 各 Spoke 中 WETH 的 reserveId，各自独立从 0 开始，巧合时相同但**无全局唯一性** |

**结论**：assetId 和 reserveId 都是**局部 ID**，只在所属合约（Hub / Spoke）内有意义。跨合约引用时必须携带所属合约地址（hub address / spoke address）。
