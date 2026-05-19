# URL Registry

All URLs used across **aaveapy** (frontend + backend), centralized for cross-repo reference and maintenance.

> Repo scope: this doc lives in the shared `aaveapy-doc/` repo so both `aaveapy/` (frontend) and `aave-protocol-analysis/` (backend) can reference and update it.

## 1. Deployment Domains

| Environment | Backend API | Frontend | CI Branch |
|---|---|---|---|
| production | `https://api.aaveapy.com` | `https://aaveapy.com` | `main` |
| staging | `https://staging-api.aaveapy.com` | `https://staging.aaveapy.com` | `railway` |
| lovable preview | — | `https://aaveapy.lovable.app` | — |
| local dev | `http://localhost:3001` | `http://localhost:8080` | — |

- Source: `.github/scripts/deployment-smoke-test-helpers.mjs`, `docs/ci-security-automation.md`
- Healthcheck: `curl https://staging-api.aaveapy.com/health`
- Frontend dev server default port: **8080** (configured in `aaveapy/vite.config.ts` L52)

## 2. Backend API Routes

| Path | Method | Handler | Auth |
|---|---|---|---|
| `/health` | GET | inline | none |
| `/api/health` | GET | inline | none |
| `/api/markets` | GET | `routes/markets.ts` | none |
| `/api/meta/side-data` | GET | `routes/meta.ts` | none |
| `/api/seo/status` | GET | `routes/seo.ts` | SEO auth |
| `/api/seo/gsc` | GET | `routes/seo.ts` | SEO auth |
| `/api/seo/semrush` | GET | `routes/seo.ts` | SEO auth |
| `/api/seo/semrush` | POST | `routes/seo.ts` | SEO auth |
| `/api/seo/semrush/batch` | POST | `routes/seo.ts` | SEO auth |
| `/api/seo/semrush/:id` | DELETE | `routes/seo.ts` | SEO auth |
| `/api/persistence-status` | GET | inline | none |
| `/.well-known/security.txt` | GET | inline | none |

- Source: `backend/src/server.ts`
- Full docs: `docs/api/api-documentation.md`, `docs/api/seo-api-documentation.md`

## 3. External Data Sources (Upstream APIs)

### Incentive Protocols

| Service | URL | Used In |
|---|---|---|
| Merit APR | `https://apps.aavechan.com/api/merit/aprs` | `packages/aave-fetcher/src/merit-api.ts` |
| Merit Activity | `https://apps.aavechan.com/merit/{key}` | `packages/aave-fetcher/src/merit-api.ts` |
| Merkl API V4 | `https://api.merkl.xyz/v4` | `packages/aave-fetcher/src/merkl-api.ts`, `backend/src/services/merklForecastService.ts` |
| Merkl Campaign | `https://api.merkl.xyz/v4/campaigns/{campaignId}` | `packages/aave-fetcher/src/merkl-api.ts` |
| Merkl Opportunities | `https://api.merkl.xyz/v4/opportunities?mainProtocolId=aave` | `packages/aave-fetcher/src/merkl-api.ts` |
| Merkl Frontend | `https://app.merkl.xyz/opportunities/{chain}/{type}/{id}` | `packages/aave-fetcher/src/merkl-api.ts` |
| Brevis Frontend | `https://incentra.brevis.network` | `packages/aave-fetcher/src/brevis-api.ts` |
| Brevis gRPC | `https://incentra-prd.brevis.network` | `packages/aave-fetcher/src/brevis-api.ts` |
| Brevis Campaign Link | `https://incentra.brevis.network/campaign/?pool_id={id}&type={type}&chainId={chainId}` | `docs/api/brevis-supplement.md` |

### Price & Market Data

| Service | URL | Used In |
|---|---|---|
| CoinGecko API | `https://api.coingecko.com/api/v3` | `packages/aave-fetcher/src/token-price-resolver.ts` |
| CoinGecko Markets | `https://api.coingecko.com/api/v3/coins/markets` | `backend/src/controllers/coingeckoController.ts` |
| CoinGecko Asset Platforms | `https://api.coingecko.com/api/v3/asset_platforms` | `packages/aave-fetcher/src/generated/coingecko-platform-by-chain-id.ts` |
| CoinMarketCap | `https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest` | `backend/src/controllers/coingeckoController.ts` |

### External Docs

| Resource | URL |
|---|---|
| Merkl Mechanisms | `https://docs.merkl.xyz/merkl-mechanisms/incentive-mechanisms` |
| Merkl Distributions | `https://docs.merkl.xyz/merkl-mechanisms/distributions` |
| Merkl Integrate | `https://docs.merkl.xyz/integrate-merkl/app` |
| Brevis Docs | `https://incentra-docs.brevis.network` |
| Brevis SDK | `https://incentra-docs.brevis.network/developer-sdk/get-campaigns` |
| Cloudflare Browser Rendering | `https://developers.cloudflare.com/browser-rendering/limits/` |

## 4. RPC Endpoints

Full list in `docs/backend/rpc-endpoints.md` and `packages/aave-shared-config/index.js`.

### Public RPCs (selected)

| Chain | chainId | Primary RPC |
|---|---|---|
| Ethereum | 1 | `ethereum-rpc.publicnode.com` |
| Polygon | 137 | `polygon-bor-rpc.publicnode.com` |
| Avalanche | 43114 | `api.avax.network/ext/bc/C/rpc` |
| Arbitrum | 42161 | `arb1.arbitrum.io/rpc` |
| Base | 8453 | `base.publicnode.com` |
| Optimism | 10 | `optimism-rpc.publicnode.com` |
| Metis | 1088 | `andromeda.metis.io/?owner=1088` |
| Gnosis | 100 | `gnosis-rpc.publicnode.com` |
| BNB | 56 | `bsc.publicnode.com` |
| Scroll | 534352 | `rpc.scroll.io` |
| zkSync | 324 | `mainnet.era.zksync.io` |
| Linea | 59144 | `rpc.linea.build` |
| Sonic | 146 | `rpc.soniclabs.com` |
| Celo | 42220 | `forno.celo.org` |
| Soneium | 1868 | `rpc.soneium.org` |
| Mantle | 5000 | `rpc.mantle.xyz` |
| Berachain | 80094 | `rpc.berachain.com` |

### Private RPC Templates

- Infura: `https://mainnet.infura.io/v3/${INFURA_PROJECT_ID}`
- Alchemy: `https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}`

## 5. Frontend Deeplinks (Aave UI)

| Target | URL Pattern | Source |
|---|---|---|
| V3 Reserve | `https://app.aave.com` + path | `docs/changes/pro-aave-v4-deeplinks.md` |
| V4 Hub | `https://pro.aave.com/explore/hub/{hubId}` | `docs/api/FRONTEND-SYNC-CHANGES.md` |
| V4 Reserve | `https://pro.aave.com/explore/reserve/{aaveProReserveId}` | `docs/api/FRONTEND-SYNC-CHANGES.md` |
| V4 Asset | `https://pro.aave.com/explore/asset/{chainId}/{address}` | `docs/changes/pro-aave-v4-deeplinks.md` |

## 6. SEO / i18n Page Routes

| Locale | Path | Language |
|---|---|---|
| default (US) | `/` | en |
| Brazil | `/pt-br` | pt-BR |
| France | `/fr` | fr |
| Turkey | `/tr` | tr |
| Germany (planned) | `/de` | de |

- Source: `docs/plans/keyword-plan.md`
- security.txt: `https://aaveapy.com/.well-known/security.txt`

## 7. CORS Allowed Origins

| Environment Variable | Typical Value | Purpose |
|---|---|---|
| `FRONTEND_URL` | `https://aaveapy.com` (prod), `https://staging.aaveapy.com` (staging) | Primary frontend |
| `SEO_ALLOWED_ORIGINS` | `https://aaveapy.lovable.app` | SEO admin (Lovable) |
| `ALLOWED_DEV_ORIGINS` | `http://localhost:5173`, `http://localhost:8080` | Local dev |

- Source: `backend/src/middleware/cors.ts`, `backend/src/middleware/corsOrigin.ts`

## 8. Developer Tooling URLs (Frontend)

Implemented in `aaveapy/` (sibling frontend repo).

| Page | URL | Description |
|---|---|---|
| Swagger UI (API docs) | `http://localhost:8080/swagger.html` | OpenAPI 3.1 spec rendered via swagger-ui-dist |
| OpenAPI JSON spec | `http://localhost:8080/openapi.json` | Auto-generated from Zod schemas |
| Production Swagger UI | `https://aaveapy.com/swagger.html` | Same page, production deployment |
| Staging Swagger UI | `https://staging.aaveapy.com/swagger.html` | Same page, staging deployment |

- Source: `aaveapy/public/swagger.html`, `aaveapy/public/openapi.json`, `aaveapy/scripts/generate-openapi.ts`
- Zod schemas in `aaveapy/src/lib/apiSchemas.ts` → `generate-openapi.ts` → `public/openapi.json` → Swagger UI
- CI check: `npm run openapi:check` — regenerates and diffs to detect schema drift

## 9. Infrastructure URLs

| Resource | URL / Pattern | Source |
|---|---|---|
| Railway GraphQL API | `${RAILWAY_API_URL}` | `.github/workflows/deployment-smoke-test.yml` |
| R2 Backup Endpoint | `${R2_ENDPOINT}` (e.g. `https://<account-id>.r2.cloudflarestorage.com`) | `.github/workflows/db-backup.yml` |
| Cloudflare Worker | `${CLOUDFLARE_WORKER_URL}` | `docs/deploy/cloudflare-complete-guide.md` |
| Vercel Deployments API | `https://api.vercel.com/v6/deployments` | `.github/workflows/deployment-smoke-test.yml` |
| Vercel Rollback API | `https://api.vercel.com/v1/projects/{id}/rollback/{id}` | `.github/workflows/deployment-smoke-test.yml` |
| Cloudflare API v4 | `https://api.cloudflare.com/client/v4` | `scripts/sync-cloudflare-gh-actions-allowlist.mjs` |
| GitHub API Meta | `https://api.github.com/meta` | `scripts/sync-cloudflare-gh-actions-allowlist.mjs` |

## 10. Block Explorer URLs

| Chain | Explorer Base URL | Source |
|---|---|---|
| Ethereum | `https://etherscan.io` | `src/lib/poolExplorerLinks.ts` |
| Arbitrum | `https://arbiscan.io` | `src/lib/poolExplorerLinks.ts` |
| Optimism | `https://optimistic.etherscan.io` | `src/lib/poolExplorerLinks.ts` |
| Polygon | `https://polygonscan.com` | `src/lib/poolExplorerLinks.ts` |
| Base | `https://basescan.org` | `src/lib/poolExplorerLinks.ts` |
| Gnosis | `https://gnosisscan.io` | `src/lib/poolExplorerLinks.ts` |
| BNB | `https://bscscan.com` | `src/lib/poolExplorerLinks.ts` |
| Avalanche | `https://snowscan.xyz` | `src/lib/poolExplorerLinks.ts` |
| Linea | `https://lineascan.build` | `src/lib/poolExplorerLinks.ts` |
| Scroll | `https://scrollscan.com` | `src/lib/poolExplorerLinks.ts` |
| zkSync | `https://zksync.blockscout.com` | `src/lib/poolExplorerLinks.ts` |
| zkSync (alt) | `https://explorer.zksync.io` | `src/lib/multiExplorerSupport.ts` |
| Metis | `https://metisscan.info` | `src/lib/poolExplorerLinks.ts` |
| Sonic | `https://sonicscan.org` | `src/lib/poolExplorerLinks.ts` |
| Celo | `https://celoscan.io` | `src/lib/poolExplorerLinks.ts` |
| MegaEth | `https://mega.etherscan.io` | `src/lib/poolExplorerLinks.ts` |
| Plasma | `https://plasmascan.to` | `src/lib/poolExplorerLinks.ts` |
| Mantle | `https://mantlescan.xyz` | `src/lib/poolExplorerLinks.ts` |
| Soneium | `https://soneium.blockscout.com` | `src/lib/poolExplorerLinks.ts` |
| Ink | `https://explorer.inkonchain.com` | `src/lib/poolExplorerLinks.ts` |
| X Layer | `https://www.oklink.com` | `src/lib/poolExplorerLinks.ts` |

## 11. Upstream Sync URLs (Raw GitHub)

| Resource | URL Pattern | Source |
|---|---|---|
| Aave Interface networksConfig | `https://raw.githubusercontent.com/aave/interface/main/src/ui-config/networksConfig.ts` | `scripts/sync-chain-icon-map-upstream.mjs` |
| Aave Interface marketsConfig | `https://raw.githubusercontent.com/aave/interface/main/src/ui-config/marketsConfig.tsx` | `scripts/sync-market-name-map-upstream.mjs` |
| Aave Interface reservePatches | `https://raw.githubusercontent.com/aave/interface/main/src/ui-config/reservePatches.ts` | `scripts/sync-reserve-patches-upstream.mjs` |
| Aave Interface public dir | `https://raw.githubusercontent.com/aave/interface/main/public` | `scripts/sync-chain-network-icons-upstream.mjs` |
| Aave Interface token icons | `https://raw.githubusercontent.com/aave/interface/main/public/icons/tokens` | `scripts/sync-token-icons.mjs` |
| Aave Address Book | `https://raw.githubusercontent.com/aave-dao/aave-address-book/main/src` | `scripts/sync-pool-addresses-upstream.mjs` |

## 12. Frontend CDN Dependencies

| Resource | URL | Source |
|---|---|---|
| Google Fonts API (preconnect) | `https://fonts.googleapis.com` | `index.html` |
| Google Fonts Static (preconnect) | `https://fonts.gstatic.com` | `index.html` |
| Source Sans Pro | `https://fonts.googleapis.com/css2?family=Source+Sans+Pro:wght@...` | `index.html` |
| Source Code Pro | `https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@...` | `index.html` |
| Swagger UI CSS | `https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css` | `public/swagger.html` |
| Swagger UI JS | `https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js` | `public/swagger.html` |
| shadcn/ui Schema | `https://ui.shadcn.com/schema.json` | `components.json` |

## 13. Social / Community Links

| Platform | URL | Source |
|---|---|---|
| Twitter (author) | `https://twitter.com/silenlee` | `src/pages/Index.tsx` |
| Twitter (project) | `https://twitter.com/AAVE_APY` | `index.html` (structured data) |
| Telegram | `https://t.me/aaveapy` | `src/pages/Index.tsx` |
| GitHub (repo) | `https://github.com/0xPabloLI/aaveapy` | `src/pages/Index.tsx` |
| Ink announcement | `https://x.com/inkfndhq/status/1934991370957033888` | `src/components/dashboard/InkAprCalculator.tsx` |

## 14. External Frontend Links

| Service | URL Pattern | Source |
|---|---|---|
| CoinMarketCap Currencies | `https://coinmarketcap.com/currencies/{slug}` | `src/components/dashboard/InkAprCalculator.tsx` |
| CoinGecko Search API | `https://api.coingecko.com/api/v3/search` | `src/hooks/useCoingeckoTokenImage.ts` |
| Tydro App | `https://app.tydro.com` | `src/lib/tydroLinks.ts` |

## 15. Test / Dev URLs (non-production)

| Resource | URL | Source |
|---|---|---|
| Playwright base URL | `http://127.0.0.1:4173` | `playwright.config.ts` |
| Vite dev server (default) | `http://localhost:5173` | CORS allowlist, `public/expand-icon-preview.html` |
