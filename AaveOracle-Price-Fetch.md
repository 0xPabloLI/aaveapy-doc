# AaveOracle V3 & V4 — 批量获取所有 Reserve Oracle 价格

> **版本：Aave V3 + Aave V4（Hub-and-Spoke 架构）** | **日期：2026-05-05**

本文档整合 Aave V3 与 V4 链上 Oracle 合约的价格读取方案，覆盖合约接口、部署地址、批量查询策略及多链调用流程。

---

## V3 vs V4 核心差异速查

| 概念 | Aave V3 | Aave V4 |
|------|---------|---------|
| Oracle 粒度 | 每个 Pool 一个 AaveOracle | 每个 Spoke 一个 AaveOracle |
| 批量接口 | `getAssetsPrices(address[])` | `getReservesPrices(uint256[])` |
| 索引方式 | ERC20 资产地址 | 整数 `reserveId`（0, 1, 2...） |
| 价格架构 | 全局统一（同一链所有 reserve 同一 Oracle） | Per-Spoke 独立（同一资产不同 Spoke 价格可能不同） |
| 获取资产列表 | `Pool.getReservesList()` | `Spoke.getReserveCount()` + `Spoke.getReserve(reserveId)` |
| 部署范围 | 18 条链 + Ethereum 4 实例 = 24 个 | Ethereum 10 Spokes（其他链待部署） |
| 数据结构 | Flat：asset → price | 三维：(chainId, spoke, reserveId) → price |
| RPC 调用次数 | 每条链 2 次（1次列表 + 1次价格） | 每个 Spoke 1 次（直接批量价格） |

---

# Part 1：Aave V3

> 合约：`AaveOracle.sol` | 源路径：`aave-v3-origin/src/contracts/misc/AaveOracle.sol`

## 1. 核心架构理解

### 1.1 价格读取链路

```
外部调用者
    ↓
IPriceOracleGetter.getAssetPrice(asset)
    ↓
AaveOracle.getAssetPrice(asset)          ← 唯一入口
    ├── asset == BASE_CURRENCY → 返回 BASE_CURRENCY_UNIT (1e8)
    ├── 无 Chainlink 数据源     → 调用 fallbackOracle.getAssetPrice(asset)
    └── 有 Chainlink 数据源     → source.latestAnswer()
        ├── price > 0          → 返回 Chainlink 价格
        └── price <= 0         → 调用 fallbackOracle.getAssetPrice(asset)
```

### 1.2 关键常量

| 常量 | 值 | 说明 |
|---|---|---|
| `BASE_CURRENCY` | `address(0)` | `0x0` 代表 USD |
| `BASE_CURRENCY_UNIT` | `10 ** 8 = 100000000` (1e8) | Chainlink USD 价格精度为 8 位小数 |
| `oracleDecimals` | `8` | 部署配置源：`DefaultMarketInput.sol:L25` |

### 1.3 精度说明：为什么是 8 位而不是 6 位？

| 对比维度 | ERC20 USDT | Chainlink Price Feed | AaveOracle |
|---|---|---|---|
| 精度 | 6 decimals | 8 decimals | 8 decimals |
| 单位 | 1 USDT = 1e6 | 1 USD = 1e8 | 1 USD = 1e8 |

AaveOracle 对接的是 **Chainlink Aggregator**，Chainlink 价格 Feed 统一使用 **8 位小数**表示 USD 价格，与 ERC20 Token 的 decimals 无关。

转换公式：`USD 价格 = rawPrice / 1e8`

## 2. API 方法

### 2.1 批量获取价格（推荐，一次 RPC 调用）

```solidity
function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory)
```

```json
[{
  "inputs": [{"internalType": "address[]", "name": "assets", "type": "address[]"}],
  "name": "getAssetsPrices",
  "outputs": [{"internalType": "uint256[]", "name": "", "type": "uint256[]"}],
  "stateMutability": "view",
  "type": "function"
}]
```

### 2.2 单个资产价格

```solidity
function getAssetPrice(address asset) public view returns (uint256)
```

### 2.3 查询 Chainlink 数据源

```solidity
function getSourceOfAsset(address asset) external view returns (address)
```

### 2.4 查询 Fallback Oracle

```solidity
function getFallbackOracle() external view returns (address)
```

## 3. 获取资产地址列表

通过 Pool 合约的 `getReservesList()`：

```solidity
function getReservesList() external view returns (address[] memory)
```

```json
[{
  "inputs": [],
  "name": "getReservesList",
  "outputs": [{"internalType": "address[]", "name": "", "type": "address[]"}],
  "stateMutability": "view",
  "type": "function"
}]
```

## 4. 所有 Aave V3 部署清单（共 24 个实例）

### 4.1 完整表

| # | 链名 | Chain ID | AaveOracle 地址 | Pool 地址 |
|---|---|---|---|---|
| 1 | Ethereum (Core) | 1 | `0x54586bE62E3c3580375aE3723C145253060Ca0C2` | `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2` |
| 2 | Ethereum (Lido) | 1 | `0xE3C061981870C0C7b1f3C4F4bB36B95f1F260BE6` | `0x4e033931ad43597d96D6bcc25c280717730B58B1` |
| 3 | Ethereum (EtherFi) | 1 | `0x43b64f28A678944E0655404B0B98E443851cC34F` | `0x0AA97c284e98396202b6A04024F5E2c65026F3c0` |
| 4 | Ethereum (Horizon) | 1 | `0x985BcfAB7e0f4EF2606CC5b64FC1A16311880442` | `0xAe05Cd22df81871bc7cC2a04BeCfb516bFe332C8` |
| 5 | Arbitrum | 42161 | `0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7` | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |
| 6 | Avalanche | 43114 | `0xEBd36016B3eD09D4693Ed4251c67Bd858c3c7C9C` | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |
| 7 | Base | 8453 | `0x2Cc0Fc26eD4563A5ce5e8bdcfe1A2878676Ae156` | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` |
| 8 | BNB Chain | 56 | `0x39bc1bfDa2130d6Bb6DBEfd366939b4c7aa7C697` | `0x6807dc923806fE8Fd134338EABCA509979a7e0cB` |
| 9 | Celo | 42220 | `0x1e693D088ceFD1E95ba4c4a5F7EeA41a1Ec37e8b` | `0x3E59A31363E2ad014dcbc521c4a0d5757d9f3402` |
| 10 | Gnosis | 100 | `0xeb0a051be10228213BAEb449db63719d6742F7c4` | `0xb50201558B00496A145fE76f7424749556E326D8` |
| 11 | Linea | 59144 | `0xCFDAdA7DCd2e785cF706BaDBC2B8Af5084d595e9` | `0xc47b8C00b0f69a36fa203Ffeac0334874574a8Ac` |
| 12 | Mantle | 5000 | `0x47a063CfDa980532267970d478EC340C0F80E8df` | `0x458F293454fE0d67EC0655f3672301301DD51422` |
| 13 | MegaETH | 4326 | `0x421117D7319E96d831972b3F7e970bbfe29C4F21` | `0x7e324AbC5De01d112AfC03a584966ff199741C28` |
| 14 | Metis | 1088 | `0x38D36e85E47eA6ff0d18B0adF12E5fC8984A6f8e` | `0x90df02551bB792286e8D4f13E0e357b4Bf1D6a57` |
| 15 | Optimism | 10 | `0xD81eb3728a631871a7eBBaD631b5f424909f0c77` | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |
| 16 | Polygon POS | 137 | `0xb023e699F5a33916Ea823A16485e259257cA8Bd1` | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |
| 17 | Plasma | 9745 | `0x33E0b3fc976DC9C516926BA48CfC0A9E10a2aAA5` | `0x925a2A7214Ed92428B5b1B090F80b25700095e12` |
| 18 | Scroll | 534352 | `0x04421D8C506E2fA2371a08EfAaBf791F624054F3` | `0x11fCfe756c05AD438e312a7fd934381537D3cFfe` |
| 19 | Soneium | 1868 | `0x20040a64612555042335926d72B4E5F667a67fA1` | `0xDd3d7A7d03D9fD9ef45f3E587287922eF65CA38B` |
| 20 | Sonic | 146 | `0xD63f7658C66B2934Bd234D79D06aEF5290734B30` | `0x5362dBb1e601abF3a4c14c22ffEdA64042E5eAA3` |
| 21 | XLayer | 196 | `0x91FC11136d5615575a0fC5981Ab5C0C54418E2C6` | `0xE3F3Caefdd7180F884c01E57f65Df979Af84f116` |
| 22 | zkSync Era | 324 | `0xC7F58Fca663a8d377B6D0c9703C697f56dC40088` | `0x78e30497a3c7527d953c6B1E3541b021A98Ac43c` |
| 23 | Harmony ONE | 1666600000 | `0x3C90887Ede8D65ccb2777A5d577beAb2548280AD` | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |
| 24 | Ink | 57073 | `0x4758213271BFdC72224A7a8742dC865fC97756e1` | `0x2816cf15F6d2A220E789aA011D5EE4eB6c47FEbA` |

### 4.2 按 Chain ID 分组

| Chain ID | 实例数 | 实例列表 |
|---|---|---|
| 1 (Ethereum) | 4 | Core, Lido, EtherFi, Horizon |
| 10 (Optimism) | 1 | Optimism |
| 56 (BNB) | 1 | BNB Chain |
| 100 (Gnosis) | 1 | Gnosis |
| 137 (Polygon) | 1 | Polygon POS |
| 146 (Sonic) | 1 | Sonic |
| 196 (XLayer) | 1 | XLayer |
| 324 (zkSync) | 1 | zkSync Era |
| 1088 (Metis) | 1 | Metis |
| 1868 (Soneium) | 1 | Soneium |
| 4326 (MegaETH) | 1 | MegaETH |
| 5000 (Mantle) | 1 | Mantle |
| 9745 (Plasma) | 1 | Plasma |
| 8453 (Base) | 1 | Base |
| 42161 (Arbitrum) | 1 | Arbitrum |
| 43114 (Avalanche) | 1 | Avalanche |
| 534352 (Scroll) | 1 | Scroll |
| 59144 (Linea) | 1 | Linea |
| 57073 (Ink) | 1 | Ink |
| 42220 (Celo) | 1 | Celo |
| 1666600000 (Harmony) | 1 | Harmony ONE |

## 5. V3 后端查询伪代码

```python
# 每条链只需 2 次 RPC 调用！
for chain in chains:
    w3 = Web3(Web3.HTTPProvider(chain["rpc"]))

    # 第1步: 获取资产列表
    pool = w3.eth.contract(address=chain["pool"], abi=POOL_ABI)
    assets = pool.functions.getReservesList().call()

    # 第2步: 批量获取所有资产价格（一次 RPC 调用！）
    oracle = w3.eth.contract(address=chain["oracle"], abi=BATCH_ORACLE_ABI)
    prices_raw = oracle.functions.getAssetsPrices(assets).call()

    # 第3步: 转换价格 (除以 1e8)
    for addr, raw in zip(assets, prices_raw):
        price_usd = raw / 1e8  # 8 位精度，非 6 位
```

### V3 RPC 调用次数

```
每条独立 Market: 2 次 RPC (1次 getReservesList + 1次 getAssetsPrices)
24 个 Market × 2 = 48 次 RPC (可完全并发)
```

---

# Part 2：Aave V4

> 合约：AaveOracle V4 (Solidity 0.8.28) | 架构：Hub-and-Spoke

## 1. 核心架构理解

### 1.1 价格是 Per-Spoke 的，不是全局的

```
       ┌─────────────────────────────────────────────┐
       │              同一链 (如 Ethereum)             │
       │                                             │
       │  Spoke A (BLUECHIP)    →  AaveOracle_A      │
       │  Spoke B (MAIN)        →  AaveOracle_B      │
       │  Spoke C (FOREX)       →  AaveOracle_C      │
       │  ...                                       │
       └─────────────────────────────────────────────┘
```

**关键认知：**

- 每个 Spoke 拥有独立的 `AaveOracle` 实例（不可变，`Spoke.ORACLE()` 返回）。
- **同一个底层资产（同一个 Hub + 同一个 assetId）如果被多个 Spoke 引用，在不同 Spoke 下的 Oracle 价格理论上可能不同**，因为每个 AaveOracle 可以独立配置各自的 `IPriceFeed` 价格源（例如 USDC 在 BLUECHIP_SPOKE 和 MAIN_SPOKE 各有自己的价格源绑定）。
- 因此价格读取必须以 **(chainId, spokeAddress)** 为单位进行，不存在全局的价格表。

### 1.2 多链架构

```
                     Aave V4 Protocol
                          │
          ┌───────────────┼───────────────┐
          │               │               │
     Ethereum          Arbitrum         Base
     (chainId=1)       (未来上线)        (未来上线)
          │
   ┌──────┼──────┬──────┐
   │      │      │      │
 BLUECHIP MAIN  FOREX  GOLD   ... (每个链上有各自的 Spoke 集合)
```

- Aave V4 在不同链上独立部署，每条链有自己的一组 Spoke + AaveOracle 合约。
- 后端需要**按 `(chainId, spokeAddress)` 维度**去拉取价格。
- **当前 (2026-05) 已部署 V4 的链仅 Ethereum Mainnet。** 未来其他链上线后，各链的 Spoke/Oracle 地址将收录到 `aave-address-book` 仓库。

### 1.3 批量读取是 Per-Spoke 的

`AaveOracle.getReservesPrices(uint256[] reserveIds)` 调用的是**某一个具体的 AaveOracle 合约实例**，返回该 Oracle（即该 Spoke）下所有 reserve 的价格。要获取全协议价格，需**遍历所有链上的所有 Spoke**，对每个 Spoke 各调用一次批量接口。

```
总 RPC 调用 = Σ(每条链的 Spoke 数量)

Ethereum 当前: 10 Spokes → 10 次 eth_call (各 1 次 getReservesPrices)
```

## 2. 已部署合约地址

### 2.1 Ethereum Mainnet (Chain ID: 1)

> 来源：[aave-address-book/src/AaveV4Ethereum.sol](file:///Users/pabloli/Documents/code/aave-address-book/src/AaveV4Ethereum.sol)

| # | Spoke 名称 | Spoke 地址 | AaveOracle 地址 |
|---|-----------|-----------|----------------|
| 1 | BLUECHIP_SPOKE | `0x973a023A77420ba610f06b3858aD991Df6d85A08` | `0xdA1266a7b8620819dAE3F8bd6B546Da36e505bB8` |
| 2 | MAIN_SPOKE | `0x94e7A5dCbE816e498b89aB752661904E2F56c485` | `0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127` |
| 3 | ETHENA_CORRELATED_SPOKE | `0x58131E79531caB1d52301228d1f7b842F26B9649` | `0x9b91a0943CADf554742E8Fb358B1cC4ae4F85F01` |
| 4 | ETHENA_ECOSYSTEM_SPOKE | `0xba1B3D55D249692b669A164024A838309B7508AF` | `0xc390dbe9fc00D6db73C52d375642b47008C33c90` |
| 5 | ETHERFI_E_SPOKE | `0xbF10BDfE177dE0336aFD7fcCF80A904E15386219` | `0xd8B153FaAA8f2b1bC774916FEd333A4F3dE48792` |
| 6 | LIDO_E_SPOKE | `0xe1900480ac69f0B296841Cd01cC37546d92F35Cd` | `0x664D73b6C3591333Fd79510f7ce9ef81228824F5` |
| 7 | KELP_E_SPOKE | `0x3131FE68C4722e726fe6B2819ED68e514395B9a4` | `0x37C316996C714Bf906743071e04E62220b3271ac` |
| 8 | FOREX_SPOKE | `0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1` | `0xB3CE6E7b6d389a66eA4a3777bA07219d00FB3a9D` |
| 9 | GOLD_SPOKE | `0x65407b940966954b23dfA3caA5C0702bB42984DC` | `0x0083421fd178749af2201ddA5A7C3feB5790B80c` |
| 10 | LOMBARD_BTC_SPOKE | `0x7EC68b5695e803e98a21a9A05d744F28b0a7753D` | `0x198Cac7f54FFc7d709Ac0FEc4B6454CE73e21D3D` |

### 2.2 其他链（待部署）

> V4 尚未在其他链上线。上线后在此补充各链 `AaveV4{Network}.sol` 中的地址。

## 3. 合约接口

### 3.1 Spoke → 获取 Oracle 地址 & Reserve 列表

| 函数 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `ORACLE()` | 无 | `address` | AaveOracle 地址 (Spoke 不可变) |
| `getReserveCount()` | 无 | `uint256` | Reserve 总数, reserveId 范围 [0, N-1] |
| `getReserve(reserveId)` | `uint256` | `Reserve` 结构体 | Reserve 详情 (underlying, hub, assetId, decimals...) |

#### Reserve 结构体

```
underlying       address   : 底层 ERC20 资产地址
hub              address   : 所属 Hub 合约地址
assetId          uint16    : Hub 内资产 ID (跨 Spoke 唯一标识同一资产)
decimals         uint8     : 底层资产精度
collateralRisk   uint24    : 抵押品风险 (BPS)
flags            uint8     : 状态 (paused/frozen/borrowable/receiveSharesEnabled)
dynamicConfigKey uint32    : 动态配置键
```

### 3.2 AaveOracle → 读取价格

| 函数 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getReservesPrices(reserveIds)` | `uint256[]` | `uint256[]` | **批量获取 (推荐)**，1 次 RPC |
| `getReservePrice(reserveId)` | `uint256` | `uint256` | 单个获取 (兜底用) |
| `getReserveSource(reserveId)` | `uint256` | `address` | 底层 PriceFeed 地址 (调试用) |

> 所有函数均为 `view`，使用 `eth_call` 零 gas 成本。

## 4. V4 多链调用流程（伪代码）

```python
def fetch_all_oracle_prices(config):
    """
    config: {
      "chains": [
        {
          "chainId": 1,
          "rpcUrl": "...",
          "spokes": [
            {"name": "MAIN_SPOKE",  "address": "0x...", "oracle": "0x..."},
            {"name": "BLUECHIP_SPOKE", "address": "0x...", "oracle": "0x..."},
            ...
          ]
        },
        ...
      ]
    }
    """
    results = {}
    for chain in config["chains"]:
        chain_id = chain["chainId"]
        results[chain_id] = {}
        for spoke in chain["spokes"]:
            spoke_name = spoke["name"]
            oracle_addr = spoke["oracle"]

            # 步骤 1: 获取 reserve 总数
            reserve_count = spoke_contract(chain["rpcUrl"], spoke["address"]) \
                .getReserveCount()

            # 步骤 2: 批量拉取所有价格 (1 次 RPC)
            reserve_ids = list(range(reserve_count))
            prices = oracle_contract(chain["rpcUrl"], oracle_addr) \
                .getReservesPrices(reserve_ids)

            # 步骤 3: 组装结果
            results[chain_id][spoke_name] = {
                "spoke": spoke["address"],
                "oracle": oracle_addr,
                "prices": dict(zip(reserve_ids, prices))
            }
    return results
```

**V4 RPC 调用次数：**

```
每条链每个 Spoke = 1 次 getReservesPrices
Ethereum: 10 Spokes → 10 次 eth_call
未来多链: N 个 Spoke → N 次 eth_call (可并行)
```

---

# 价格格式（通用）

## 精度：统一 8 位小数

```
price = 200000000000  →  2000.00000000 USD
price = 100000000     →  1.00000000 USD
```

AaveOracle 对接 **Chainlink Aggregator**，价格 Feed 统一使用 **8 位小数**表示 USD 价格，与 ERC20 Token 的 decimals 无关。

转换公式：**`USD 价格 = rawPrice / 1e8`**

## 价值换算

```solidity
Value = amount * price * 10^(18 - assetDecimals)
```

| 资产 | decimals | price (1.00 USD) | amount | → Value (WAD, 18位) |
|------|----------|-----------------|--------|---------------------|
| WETH | 18 | 200000000000 | 1e18 | 200000000000000000000 |
| USDC | 6 | 100000000 | 1e6 | 100000000000000000000 |
| WBTC | 8 | 600000000000 | 1e8 | 600000000000000000000 |

## 异常处理

| 版本 | Revert | 含义 | 处理 |
|------|--------|------|------|
| V3 | `price == 0` | 价格过期/异常 | 调用方 try-catch |
| V4 | `InvalidSource(reserveId)` | 未配置价格源 | 跳过该 reserve |
| V4 | `InvalidPrice(reserveId)` | 价格 ≤ 0 (过期/异常) | 跳过并告警 |

> ⚠️ V4 `getReservesPrices()` 是**全有或全无**的批量调用，任意一个 reserveId 异常会导致整个数组返回失败。建议对问题 reserve 使用单独的 `getReservePrice()` + try-catch 兜底。

---

# V4 多链配置文件格式

```json
{
  "version": "v4",
  "updatedAt": "2026-05-05",
  "chains": [
    {
      "chainId": 1,
      "name": "Ethereum",
      "rpcUrl": "https://eth-mainnet.g.alchemy.com/v2/...",
      "spokes": [
        {"name": "MAIN_SPOKE",            "address": "0x94e7A5dCbE816e498b89aB752661904E2F56c485", "oracle": "0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127"},
        {"name": "BLUECHIP_SPOKE",        "address": "0x973a023A77420ba610f06b3858aD991Df6d85A08", "oracle": "0xdA1266a7b8620819dAE3F8bd6B546Da36e505bB8"},
        {"name": "ETHENA_CORRELATED_SPOKE","address": "0x58131E79531caB1d52301228d1f7b842F26B9649", "oracle": "0x9b91a0943CADf554742E8Fb358B1cC4ae4F85F01"},
        {"name": "ETHENA_ECOSYSTEM_SPOKE", "address": "0xba1B3D55D249692b669A164024A838309B7508AF", "oracle": "0xc390dbe9fc00D6db73C52d375642b47008C33c90"},
        {"name": "ETHERFI_E_SPOKE",       "address": "0xbF10BDfE177dE0336aFD7fcCF80A904E15386219", "oracle": "0xd8B153FaAA8f2b1bC774916FEd333A4F3dE48792"},
        {"name": "LIDO_E_SPOKE",          "address": "0xe1900480ac69f0B296841Cd01cC37546d92F35Cd", "oracle": "0x664D73b6C3591333Fd79510f7ce9ef81228824F5"},
        {"name": "KELP_E_SPOKE",          "address": "0x3131FE68C4722e726fe6B2819ED68e514395B9a4", "oracle": "0x37C316996C714Bf906743071e04E62220b3271ac"},
        {"name": "FOREX_SPOKE",           "address": "0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1", "oracle": "0xB3CE6E7b6d389a66eA4a3777bA07219d00FB3a9D"},
        {"name": "GOLD_SPOKE",            "address": "0x65407b940966954b23dfA3caA5C0702bB42984DC", "oracle": "0x0083421fd178749af2201ddA5A7C3feB5790B80c"},
        {"name": "LOMBARD_BTC_SPOKE",     "address": "0x7EC68b5695e803e98a21a9A05d744F28b0a7753D", "oracle": "0x198Cac7f54FFc7d709Ac0FEc4B6454CE73e21D3D"}
      ]
    }
  ]
}
```

---

# 所需 ABI（V4 最小集合）

```json
[
  {
    "name": "ORACLE",
    "outputs": [{"type": "address"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "name": "getReserveCount",
    "outputs": [{"type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "name": "getReserve",
    "inputs": [{"type": "uint256", "name": "reserveId"}],
    "outputs": [
      {"name": "underlying", "type": "address"},
      {"name": "hub", "type": "address"},
      {"name": "assetId", "type": "uint16"},
      {"name": "decimals", "type": "uint8"},
      {"name": "collateralRisk", "type": "uint24"},
      {"name": "flags", "type": "uint8"},
      {"name": "dynamicConfigKey", "type": "uint32"}
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "name": "getReservesPrices",
    "inputs": [{"type": "uint256[]", "name": "reserveIds"}],
    "outputs": [{"type": "uint256[]"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "name": "getReservePrice",
    "inputs": [{"type": "uint256", "name": "reserveId"}],
    "outputs": [{"type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "name": "getReserveSource",
    "inputs": [{"type": "uint256", "name": "reserveId"}],
    "outputs": [{"type": "address"}],
    "stateMutability": "view",
    "type": "function"
  }
]
```

---

# 刷新策略

| 数据 | 频率 | 说明 |
|------|------|------|
| 多链配置 (chain/spoke 列表) | 启动时 + 监听部署事件 | 偶尔新增链/Spoke |
| Reserve 列表 (每个 Spoke) | 启动时缓存 + 监听 `AddReserve` 事件 | 偶尔新增 reserve |
| Oracle 价格 | **30s ~ 60s 定时轮询** 或按需 | 实时变化 |

---

# Ethereum 底层资产 & PriceFeed 参考

## Chainlink PriceFeed 地址

| Feed | PriceFeed (Chainlink) |
|------|----------------------|
| WETH / USD | `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419` |
| WBTC / USD | `0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c` |
| wstETH / USD | `0x869C9Ae2C8fbe82a8b0F768b9F791f89E083222C` |
| weETH / USD | `0xf112aF6F0A332B815fbEf3Ff932c057E570b62d3` |
| rsETH / USD | `0x47F52B2e43D0386cF161e001835b03Ad49889e3b` |
| AAVE / USD | `0x547a514d5e3769680Ce22B2361c10Ea13619e8a9` |
| LINK / USD | `0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c` |
| USDC / USD | `0x581b8Bc9d6104F71ad6da1f483B67500968C5994` |
| USDT / USD | `0x260326c220E469358846b187eE53328303Efe19C` |
| EURC / USD | `0xa6aB031A4d189B24628EC9Eb155F0a0f1A0E55a3` |
| GHO / USD | `0xD110cac5d8682A3b045D5524a9903E031d70FCCd` |
| RLUSD / USD | `0xf0eaC18E908B34770FDEe46d069c846bDa866759` |
| USDG / USD | `0xF29b1e3b68Fd59DD0a413811fD5d0AbaE653216d` |
| frxUSD / USD | `0x25DEd2f9aE6ae9416693AB63Abe3aB25493861FD` |
| LBTC / USD | `0x5C1771583dbbAE5AFEd71ACD2BfC0eA4029EBB04` |
| XAUt / USD | `0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6` |
| sUSDe / USD | `0x42bc86f2f08419280a99d8fbEa4672e7c30a86ec` |
| USDe / USD | `0xC26D4a1c46d884cfF6dE9800B6aE7A8Cf48B4Ff8` |
| PT_USDe_7MAY2026 / USD | `0x0a72df02CE3E4185b6CEDf561f0AE651E9BeE235` |
| PT_sUSDE_7MAY2026 / USD | `0xa0dc0249c32fa79e8B9b17c735908a60b1141B40` |

## 底层资产地址

| 资产 | Underlying | Decimals |
|------|-----------|----------|
| WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` | 18 |
| wstETH | `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` | 18 |
| weETH | `0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee` | 18 |
| rsETH | `0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7` | 18 |
| USDT | `0xdAC17F958D2ee523a2206206994597C13D831ec7` | 6 |
| USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | 6 |
| GHO | `0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f` | 18 |
| RLUSD | `0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD` | 18 |
| USDG | `0xe343167631d89B6Ffc58B88d6b7fB0228795491D` | 6 |
| frxUSD | `0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29` | 18 |
| EURC | `0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c` | 6 |
| WBTC | `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599` | 8 |
| cbBTC | `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` | 8 |
| LBTC | `0x8236a87084f8B84306f72007F36F2618A5634494` | 8 |
| XAUt | `0x68749665FF8D2d112Fa859AA293F07A622782F38` | 6 |
| AAVE | `0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9` | 18 |
| LINK | `0x514910771AF9Ca656af840dff83E8264EcF986CA` | 18 |
| PT_sUSDE_7MAY2026 | `0x3de0ff76E8b528C092d47b9DaC775931cef80F49` | 18 |
| PT_USDe_7MAY2026 | `0xAeBf0Bb9f57E89260d57f31AF34eB58657d96Ce0` | 18 |
| sUSDe | `0x9D39A5DE30e57443BfF2A8307A4256c8797A3497` | 18 |
| USDe | `0x4c9EDD5852cd905f086C759E8383e09bff1E68B3` | 18 |

---

# 关键注意事项

1. **所有价格查询是 `view` 函数**，`eth_call` 零 gas 成本。
2. 价格精度统一 **8 位小数**，与底层 ERC20 decimals 无关，遵循 Chainlink 标准。
3. **V3**：`getAssetsPrices(address[])` 是最优方案，每条链仅需 2 次 RPC（1 次列表 + 1 次价格）。价格为 0 时会 **revert**，调用方需处理异常。
4. **V4**：同一资产 (hub+assetId) 在不同 Spoke 下价格可能不同，后端需保留 `(chain, spoke, reserveId)` 三维的价格数据，不能按 `(hub, assetId)` 去重合并。
5. **V4**：批量查询 (`getReservesPrices`) 是全有或全无的，建议对个别异常的 reserve 用 `getReservePrice` + try-catch 兜底。
6. **多链 RPC 调用可完全并行**，互不依赖，注意 RPC 限流。
7. **Ethereum 主网**：V3 有 4 个独立实例（Core / Lido / EtherFi / Horizon），V4 有 10 个 Spoke。
8. **V3 全量**：18 条独立链 + 4 个 Ethereum 实例 = **共 24 个 Oracle 实例**。

---

# 相关源文件

| 文件 | 作用 |
|---|---|
| `aave-v3-origin/src/contracts/misc/AaveOracle.sol` | V3 Oracle 合约实现 |
| `aave-v3-origin/src/contracts/interfaces/IPriceOracleGetter.sol` | V3 价格读取接口 |
| `aave-address-book/src/AaveV3*.sol` | V3 各链部署地址 |
| `aave-address-book/src/ts/AaveV3*.ts` | V3 各链 Chain ID |
| `aave-address-book/src/AaveV4Ethereum.sol` | V4 Ethereum 部署地址 |

---

*数据来源：aave-address-book 最新版 + aave-v3-origin + aave-v4*
