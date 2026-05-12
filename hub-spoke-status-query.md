# Hub Spoke 状态 (active/halted) 查询方案

---

## 一、背景：active 与 halted 的状态组合

Aave V4 Hub 中，每个 Spoke 在每个 Asset 下有两个独立的状态开关：

| 字段 | 类型 | 含义 |
|------|------|------|
| `active` | bool | 是否允许执行**任何**操作（包括 bad debt 管理） |
| `halted` | bool | 是否禁止**即时改变流动性**的操作（add/remove/draw/restore/transfer） |

两者**独立控制**，形成以下四种状态组合：

| active | halted | Spoke 状态 | 允许的操作 |
|--------|--------|-----------|-----------|
| `true` | `false` | **正常** | 所有操作（add/remove/draw/restore/transfer/reportDeficit/eliminateDeficit/payFeeShares/refreshPremium） |
| `true` | `true` | **暂停流动性** | 仅 bad debt 管理（reportDeficit/eliminateDeficit/payFeeShares/refreshPremium），禁止 add/remove/draw/restore/transferShares |
| `false` | `false` | **完全关停** | 无，所有操作均 revert |
| `false` | `true` | **完全关停** | 无，所有操作均 revert |

> **关键结论**：`active=true && halted=true` 是一个**有效的运行状态**，用于紧急情况下冻结流动性但不阻断坏账处理。

---

## 二、查询入口：Hub 合约方法

所有方法均为 `view` 函数，Gas 免费。Hub 合约地址见 §六。

### 2.1 核心查询方法

| 方法 | 输入参数 | 返回值 | 说明 |
|------|----------|--------|------|
| `getSpokeConfig(assetId, spoke)` | `uint256 assetId, address spoke` | `SpokeConfig { addCap, drawCap, riskPremiumThreshold, active, halted }` | **推荐**：直接获取 active/halted |
| `getSpoke(assetId, spoke)` | `uint256 assetId, address spoke` | `SpokeData { drawnShares, premiumShares, ..., active, halted, deficitRay }` | 获取完整 SpokeData（含仓位数据和状态） |

### 2.2 辅助遍历方法

| 方法 | 输入参数 | 返回值 | 说明 |
|------|----------|--------|------|
| `getAssetCount()` | 无 | `uint256` | Hub 中所有 Asset 的数量 |
| `getSpokeCount(assetId)` | `uint256 assetId` | `uint256` | 某 Asset 下所有 Spoke 的数量 |
| `getSpokeAddress(assetId, index)` | `uint256 assetId, uint256 index` | `address` | 某 Asset 下第 index 个 Spoke 的地址 |
| `isSpokeListed(assetId, spoke)` | `uint256 assetId, address spoke` | `bool` | 检查 Spoke 是否已注册到该 Asset |

### 2.3 状态变更事件

可通过监听以下事件追踪状态变化：

```solidity
event UpdateSpokeConfig(
    uint256 indexed assetId,
    address indexed spoke,
    SpokeConfig config   // 包含最新的 active/halted
);

event AddSpoke(
    uint256 indexed assetId,
    address indexed spoke
);
```

---

## 三、批量查询方案

### 3.1 遍历全部 Asset + Spoke（推荐 Python/TypeScript 后端）

```
1. 调用 hub.getAssetCount() → 得到 assetCount
2. for assetId in 0..assetCount-1:
     a. 调用 hub.getSpokeCount(assetId) → 得到 spokeCount
     b. for i in 0..spokeCount-1:
          - spokeAddress = hub.getSpokeAddress(assetId, i)
          - config = hub.getSpokeConfig(assetId, spokeAddress)
          - 记录 (assetId, spokeAddress, config.active, config.halted)
```

### 3.2 定点查询某个 Spoke 在所有 Asset 下的状态

```
1. 调用 hub.getAssetCount() → 得到 assetCount
2. for assetId in 0..assetCount-1:
     a. if hub.isSpokeListed(assetId, targetSpoke):
          - config = hub.getSpokeConfig(assetId, targetSpoke)
          - 记录 (assetId, config.active, config.halted)
```

### 3.3 定点查询某个 Spoke 在某个 Asset 下的状态

```
1. 调用 hub.getSpokeConfig(assetId, targetSpoke)
2. 返回 SpokeConfig.active, SpokeConfig.halted
```

---

## 四、跨链查询方案（多 Hub + 多 Spoke）

Aave V4 部署了多个 Hub 和多个 Spoke（见 §六地址表），完整的跨链/跨市场状态快照需要遍历所有 Hub。

### 4.1 查询流程

```
对每个 Hub（CORE_HUB / PLUS_HUB / PRIME_HUB）：
  1. hub.getAssetCount()
  2. hub.getSpokeCount(assetId)
  3. hub.getSpokeConfig(assetId, spoke)  → active, halted
```

### 4.2 输出格式建议

```json
{
  "hub": "CORE_HUB",
  "hubAddress": "0x...",
  "timestamp": 1715000000,
  "assets": [
    {
      "assetId": 0,
      "underlying": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "spokes": [
        { "spoke": "MAIN_SPOKE",   "address": "0x...", "active": true,  "halted": false },
        { "spoke": "BLUECHIP_SPOKE","address": "0x...", "active": true,  "halted": false }
      ]
    }
  ]
}
```

---

## 五、代码示例

### 5.1 Solidity 合约查询

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IHubSpokeQuery {
    struct SpokeConfig {
        uint40 addCap;
        uint40 drawCap;
        uint24 riskPremiumThreshold;
        bool active;
        bool halted;
    }

    function getAssetCount() external view returns (uint256);
    function getSpokeCount(uint256 assetId) external view returns (uint256);
    function getSpokeAddress(uint256 assetId, uint256 index) external view returns (address);
    function getSpokeConfig(uint256 assetId, address spoke) external view returns (SpokeConfig memory);
    function isSpokeListed(uint256 assetId, address spoke) external view returns (bool);
}

contract HubStatusMonitor {
    struct SpokeStatus {
        uint256 assetId;
        address spoke;
        bool active;
        bool halted;
    }

    /// @notice 获取某个 Hub 中所有 Spoke 的 active/halted 状态
    function getAllSpokeStatuses(address hub) external view returns (SpokeStatus[] memory) {
        IHubSpokeQuery h = IHubSpokeQuery(hub);
        uint256 assetCount = h.getAssetCount();

        // 先计算总数
        uint256 totalSpokes;
        for (uint256 a = 0; a < assetCount; a++) {
            totalSpokes += h.getSpokeCount(a);
        }

        SpokeStatus[] memory results = new SpokeStatus[](totalSpokes);
        uint256 idx;

        for (uint256 a = 0; a < assetCount; a++) {
            uint256 spokeCount = h.getSpokeCount(a);
            for (uint256 s = 0; s < spokeCount; s++) {
                address spoke = h.getSpokeAddress(a, s);
                IHubSpokeQuery.SpokeConfig memory c = h.getSpokeConfig(a, spoke);
                results[idx++] = SpokeStatus({
                    assetId: a,
                    spoke: spoke,
                    active: c.active,
                    halted: c.halted
                });
            }
        }

        return results;
    }

    /// @notice 判断某个 Spoke 对某 Asset 的可用级别
    function getSpokeAvailability(
        address hub,
        uint256 assetId,
        address spoke
    ) external view returns (string memory) {
        IHubSpokeQuery h = IHubSpokeQuery(hub);
        IHubSpokeQuery.SpokeConfig memory c = h.getSpokeConfig(assetId, spoke);

        if (!c.active) return "DISABLED";
        if (c.halted)  return "HALTED";
        return "ACTIVE";
    }
}
```

### 5.2 TypeScript (ethers v6)

```typescript
import { ethers } from 'ethers';

const HUB_ABI = [
  'function getAssetCount() external view returns (uint256)',
  'function getSpokeCount(uint256 assetId) external view returns (uint256)',
  'function getSpokeAddress(uint256 assetId, uint256 index) external view returns (address)',
  'function getSpokeConfig(uint256 assetId, address spoke) external view returns (tuple(uint40 addCap, uint40 drawCap, uint24 riskPremiumThreshold, bool active, bool halted))',
  'function isSpokeListed(uint256 assetId, address spoke) external view returns (bool)',
];

interface SpokeConfig {
  addCap: bigint;
  drawCap: bigint;
  riskPremiumThreshold: number;
  active: boolean;
  halted: boolean;
}

interface SpokeStatus {
  assetId: number;
  spoke: string;
  active: boolean;
  halted: boolean;
}

async function getAllSpokeStatuses(
  hubAddress: string,
  provider: ethers.Provider
): Promise<SpokeStatus[]> {
  const hub = new ethers.Contract(hubAddress, HUB_ABI, provider);

  const assetCount = Number(await hub.getAssetCount());
  const results: SpokeStatus[] = [];

  for (let assetId = 0; assetId < assetCount; assetId++) {
    const spokeCount = Number(await hub.getSpokeCount(assetId));

    for (let i = 0; i < spokeCount; i++) {
      const spoke = await hub.getSpokeAddress(assetId, i);
      const config: SpokeConfig = await hub.getSpokeConfig(assetId, spoke);

      results.push({
        assetId,
        spoke,
        active: config.active,
        halted: config.halted,
      });
    }
  }

  return results;
}

// 使用 multicall 优化（推荐生产环境）
async function getAllSpokeStatusesMulticall(
  hubAddress: string,
  provider: ethers.Provider
): Promise<SpokeStatus[]> {
  const hub = new ethers.Contract(hubAddress, HUB_ABI, provider);
  const assetCount = Number(await hub.getAssetCount());

  // 第一阶段：批量获取所有 spokeCount
  const countCalls = Array.from({ length: assetCount }, (_, i) => ({
    target: hubAddress,
    allowFailure: true,
    callData: hub.interface.encodeFunctionData('getSpokeCount', [i]),
  }));

  // 如果使用 Multicall3，可一次获取全部 spokeCount 和 spoke 地址
  // 此处展示分步方案
  const results: SpokeStatus[] = [];

  for (let assetId = 0; assetId < assetCount; assetId++) {
    const spokeCount = Number(await hub.getSpokeCount(assetId));
    for (let i = 0; i < spokeCount; i++) {
      const spoke = await hub.getSpokeAddress(assetId, i);
      const config: SpokeConfig = await hub.getSpokeConfig(assetId, spoke);
      results.push({ assetId, spoke, active: config.active, halted: config.halted });
    }
  }

  return results;
}
```

### 5.3 TypeScript (viem)

```typescript
import { createPublicClient, http, getContract } from 'viem';
import { mainnet } from 'viem/chains';

const HUB_ABI = [
  {
    name: 'getAssetCount',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'getSpokeCount',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'assetId', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'getSpokeAddress',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'assetId', type: 'uint256' },
      { name: 'index', type: 'uint256' },
    ],
    outputs: [{ type: 'address' }],
  },
  {
    name: 'getSpokeConfig',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'assetId', type: 'uint256' },
      { name: 'spoke', type: 'address' },
    ],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'addCap', type: 'uint40' },
          { name: 'drawCap', type: 'uint40' },
          { name: 'riskPremiumThreshold', type: 'uint24' },
          { name: 'active', type: 'bool' },
          { name: 'halted', type: 'bool' },
        ],
      },
    ],
  },
] as const;

async function getAllSpokeStatuses(
  hubAddress: `0x${string}`,
  rpcUrl: string
) {
  const client = createPublicClient({
    chain: mainnet,
    transport: http(rpcUrl),
  });

  const assetCount = await client.readContract({
    address: hubAddress,
    abi: HUB_ABI,
    functionName: 'getAssetCount',
  });

  const results: {
    assetId: number;
    spoke: string;
    active: boolean;
    halted: boolean;
  }[] = [];

  for (let assetId = 0; assetId < Number(assetCount); assetId++) {
    const spokeCount = await client.readContract({
      address: hubAddress,
      abi: HUB_ABI,
      functionName: 'getSpokeCount',
      args: [BigInt(assetId)],
    });

    for (let i = 0; i < Number(spokeCount); i++) {
      const spoke = await client.readContract({
        address: hubAddress,
        abi: HUB_ABI,
        functionName: 'getSpokeAddress',
        args: [BigInt(assetId), BigInt(i)],
      });

      const config = await client.readContract({
        address: hubAddress,
        abi: HUB_ABI,
        functionName: 'getSpokeConfig',
        args: [BigInt(assetId), spoke],
      });

      results.push({
        assetId,
        spoke: spoke.toLowerCase(),
        active: config.active,
        halted: config.halted,
      });
    }
  }

  return results;
}
```

---

## 六、以太坊主网已部署合约地址

### 6.1 Hub 合约

| 名称 | 地址 |
|------|------|
| CORE_HUB | `0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9` |
| PLUS_HUB | `0x06002e9c4412CB7814a791eA3666D905871E536A` |
| PRIME_HUB | `0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931` |

### 6.2 Spoke 合约

| 名称 | 地址 | 关联 Hub |
|------|------|----------|
| MAIN_SPOKE | `0x94e7A5dCbE816e498b89aB752661904E2F56c485` | CORE_HUB |
| BLUECHIP_SPOKE | `0x973a023A77420ba610f06b3858aD991Df6d85A08` | CORE_HUB |
| LIDO_E_SPOKE | `0xe1900480ac69f0B296841Cd01cC37546d92F35Cd` | CORE_HUB |
| ETHERFI_E_SPOKE | `0xbF10BDfE177dE0336aFD7fcCF80A904E15386219` | CORE_HUB |
| KELP_E_SPOKE | `0x3131FE68C4722e726fe6B2819ED68e514395B9a4` | CORE_HUB |
| ETHENA_CORRELATED_SPOKE | `0x58131E79531caB1d52301228d1f7b842F26B9649` | PLUS_HUB |
| ETHENA_ECOSYSTEM_SPOKE | `0xba1B3D55D249692b669A164024A838309B7508AF` | PLUS_HUB |
| FOREX_SPOKE | `0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1` | PLUS_HUB |
| GOLD_SPOKE | `0x65407b940966954b23dfA3caA5C0702bB42984DC` | PLUS_HUB |
| LOMBARD_BTC_SPOKE | `0x7EC68b5695e803e98a21a9A05d744F28b0a7753D` | PRIME_HUB |
| TREASURY_SPOKE | `0xB9B0b8616f6Bf6841972a52058132BE08d723155` | — |

---

## 七、源码参考

| 组件 | 文件路径 |
|------|---------|
| SpokeData 结构体定义 | [src/hub/interfaces/IHub.sol#L77-L91](file:///Users/pabloli/Documents/code/aave-v4/src/hub/interfaces/IHub.sol#L77-L91) |
| SpokeConfig 结构体定义 | [src/hub/interfaces/IHub.sol#L94-L100](file:///Users/pabloli/Documents/code/aave-v4/src/hub/interfaces/IHub.sol#L94-L100) |
| Hub storage（`_spokes` 映射） | [src/hub/HubStorage.sol#L19](file:///Users/pabloli/Documents/code/aave-v4/src/hub/HubStorage.sol#L19) |
| getSpokeConfig 实现 | [src/hub/Hub.sol#L672-L685](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L672-L685) |
| getSpoke 实现 | [src/hub/Hub.sol#L667-L669](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L667-L669) |
| active/halted 校验逻辑 | [src/hub/Hub.sol#L813-L918](file:///Users/pabloli/Documents/code/aave-v4/src/hub/Hub.sol#L813-L918) |
| HubConfigurator 状态管理 | [src/hub/HubConfigurator.sol#L134-L282](file:///Users/pabloli/Documents/code/aave-v4/src/hub/HubConfigurator.sol#L134-L282) |

---

## 八、监控建议

### 8.1 轮询频率

- **正常场景**：每 5 分钟轮询一次，使用 `getSpokeConfig()` 即可
- **紧急场景**：监听 `UpdateSpokeConfig` 事件，无需轮询

### 8.2 告警规则

```
IF active == false:
  告警级别: CRITICAL
  消息: "Spoke {spoke} on Asset {assetId} has been DEACTIVATED"

IF halted == true AND active == true:
  告警级别: WARNING
  消息: "Spoke {spoke} on Asset {assetId} has been HALTED (liquidity ops blocked)"
```

### 8.3 与 Spoke 层状态的整合

前端/API 判断用户是否能执行某操作时，需**同时检查 Hub 层和 Spoke 层**状态：

```
canSupply = hub.active && !hub.halted && !spoke.paused
canBorrow = hub.active && !hub.halted && !spoke.paused && spoke.borrowable
```
