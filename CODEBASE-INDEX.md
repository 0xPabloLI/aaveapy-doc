# AaveAPY 代码库索引

> 基准路径：`~/Documents/code/`

## 项目总览

| 项目 | 路径 | 技术栈 | 说明 |
|------|------|--------|------|
| 前端 Dashboard | `aaveapy/` | React + Vite + Tailwind + Supabase | Aave V3/V4 APY 看板 |
| 后端 Data Fetcher | `aave-protocol-analysis/` | TypeScript (tsx) | 使用 `@aave/client` V3 + V4 SDK 抓取链上数据 |
| 后端 API Server | `aave-protocol-analysis/backend/` | Express + TypeScript | `aave-dashboard-backend`，为前端提供 REST API |
| V4 SDK | `aave-v4-sdk/` | TypeScript (pnpm monorepo) | `aave-sdk`，含 client/core/graphql/react/types 包 |
| V3 合约 (Origin) | `aave-v3-origin/` | Solidity + Foundry | `@aave-dao/aave-v3-origin` v3.6.0 |
| V4 合约 | `aave-v4/` | Solidity + Foundry | `aave-v4` v0.5.11，Hub-and-Spoke 架构 |
| Address Book | `aave-address-book/` | TypeScript | `@aave-dao/aave-address-book` v4.49.9 |
| Subgraphs | `protocol-subgraphs/` | GraphQL + TypeScript | Aave V2/V3 subgraph |

## 目录结构速查

### 前端 `aaveapy/`
```
aaveapy/
├── src/           # React 源码 (App.tsx, components/, hooks/, pages/, lib/)
├── supabase/      # Supabase 配置
├── e2e/           # Playwright E2E 测试
├── docs/          # 前端专属文档 (conventions/, design/, specs/)
├── aaveapy-doc/   # 协议文档 (symlink → code/aaveapy-doc/)
└── dist/          # 构建产物
```

### 后端 `aave-protocol-analysis/`
```
aave-protocol-analysis/
├── packages/
│   ├── aave-shared-contracts/  # 类型定义、字段注册表、验证
│   ├── aave-fetcher/           # fetchMarketsData + SDK 客户端 + 激励适配器
│   └── aave-shared-config/     # 静态配置常量
├── src/           # 纯 re-export 层 (从 @internal/* 引用)
├── backend/       # API Server
│   └── src/       # controllers/, routes/, services/, middleware/
├── workers/       # Cloudflare Workers
├── aaveapy-doc/   # 协议文档 (symlink → code/aaveapy-doc/)
└── data/          # 抓取数据
```

### V4 SDK `aave-v4-sdk/`
```
aave-v4-sdk/
├── packages/
│   ├── client/    # API 客户端 (V3 + V4)
│   ├── core/      # 核心逻辑
│   ├── graphql/   # GraphQL 查询
│   ├── react/     # React hooks
│   ├── types/     # 类型定义
│   ├── cli/       # CLI 工具
│   └── spec/      # OpenAPI spec
└── examples/
```

### V3 合约 `aave-v3-origin/`
```
aave-v3-origin/
├── src/contracts/
│   ├── protocol/  # Pool, PoolConfigurator, Logic 库
│   ├── extensions/
│   ├── interfaces/
│   ├── rewards/
│   └── treasury/
└── deployments/
```

### V4 合约 `aave-v4/`
```
aave-v4/
├── src/
│   ├── hub/            # Hub 合约 (Pool, PoolConfigurator)
│   ├── spoke/          # Spoke 合约
│   ├── position-manager/
│   ├── interfaces/
│   ├── libraries/
│   └── config-engine/
└── deployments/
```

## SDK 依赖关系

```
前端 (aaveapy)
├── @aave/client        (V3 SDK — 通过后端 API 间接使用)
├── @aave/client-v4     (V4 SDK — 通过后端 API 间接使用)
└── Supabase            (实时数据)

后端 (aave-protocol-analysis)
├── @aave/client        ^0.6.1  (V3 数据抓取)
├── @aave/client-v4     ^4.1.1  (V4 数据抓取)
└── @aave-dao/aave-address-book  ^4.49.9  (合约地址)

后端 API (aave-protocol-analysis/backend)
├── @aave-dao/aave-address-book  ^4.49.9
└── @aave/contract-helpers  ^1.37.1
```

## 文档仓库

本目录 (`code/aaveapy-doc/`) 存放**协议知识类文档**（跨项目通用），不存放项目专属实现文档。

> **分界规则**：协议原理/语义/公式/对比 → `aaveapy-doc/`；项目具体实现/how-to/配置 → 留在各自项目 `docs/` 中。两者可互相引用。

| 文档 | 类型 | 说明 |
|------|------|------|
| `frozen-paused-semantics.md` | 知识 | V3/V4 frozen/paused/active/halted 完整语义对比（合约源码 + SDK 响应 + UI 规范 + 两个 active 字段的混淆 + Hub/Spoke 级联关系 + Spoke/TokenizationSpoke 并列共存） |
| `aave-supply-borrow-rate-formula.md` | 知识 | V3/V4 Supply/Borrow Rate 换算公式 |
| `AaveOracle-Price-Fetch.md` | 知识 | V3/V4 Oracle 价格批量获取方案 |
| `deficit-analysis.md` | 知识 | V4 Hub & Spoke 参数与查询手册（含 deficit 双层追踪机制） |
| `field-glossary.md` | 知识 | API 字段 → 前端展示概念对照表 |
| `v3-v4-sdk-field-mapping.md` | 知识 | V3/V4 SDK 字段来源 → API 输出映射 |
| `v3-v4-incentive-matching.md` | 知识 | V3/V4 激励匹配问题分析 |

## 本地开发环境

三个 repo 通过 symlink 共享文档：

```
some-directory/
├── aaveapy/aaveapy-doc                  → ../aaveapy-doc (symlink)
├── aave-protocol-analysis/aaveapy-doc   → ../aaveapy-doc (symlink)
└── aaveapy-doc/                          ← 文档源
```

**一键克隆**：运行 `./clone-all.sh [目标目录]` 即可同时克隆三个 repo。

```bash
cd aaveapy-doc && ./clone-all.sh ~/code
```

## 跨项目文档引用

以下文档分散在各项目中，属于**项目专属实现文档**，不集中到 aaveapy-doc，但存在知识重叠：

| 位置 | 文件 | 说明 |
|------|------|------|
| `aave-protocol-analysis/docs/api/api-documentation.md` | API 完整定义 | 后端项目专属，→ 知识参考 `field-glossary.md` |
| `aave-protocol-analysis/docs/api/native-apr-calculation.md` | Native APR 计算 | 后端项目专属，→ 知识参考 `aave-supply-borrow-rate-formula.md` |
| `aave-protocol-analysis/docs/backend/oracle-price-service.md` | Oracle 价格服务 | 后端项目专属，→ 知识参考 `AaveOracle-Price-Fetch.md` |
| `aave-protocol-analysis/docs/backend/data-precision-comparison.md` | SDK vs RPC 精度对比 | 后端项目专属，→ 参考 CODEBASE-INDEX 精度统一摘要 |
| `aave-protocol-analysis/docs/changes/v4-sdk-embedded-rewards.md` | V4 SDK 内嵌奖励说明 | 后端项目专属 |
| `aave-protocol-analysis/docs/changes/pro-aave-v4-deeplinks.md` | V4 Deeplink 生成 | 后端项目专属 |
| `aave-v4/docs/overview.md` | V4 协议架构总览 | 合约项目专属 |
| `aave-v3-origin/docs/terminology-and-formulas.md` | V3 术语与公式 | 合约项目专属 |
| `aaveapy/CONTEXT.md` | 前端领域术语正名 (opinionated glossary) | 前端项目专属，→ 知识参考 `field-glossary.md` + `v3-v4-sdk-field-mapping.md` |
| `aave-protocol-analysis/CONTEXT.md` | 后端领域术语正名 (opinionated glossary) | 后端项目专属，→ 知识参考 `field-glossary.md` + `v3-v4-sdk-field-mapping.md` |
