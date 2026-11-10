# UNIRAE V2.17 Backend / Indexers

## Included

- PostgreSQL/Prisma schema for EVM networks, launches, token transfers, curve and DEX trades, V2 pairs, V3 pools, fee-vault events, wallet nonces, indexer cursors and canonical raw events.
- Express API for health, configured networks, verified launches, candle data, native/USD quotes, fee-vault event windows, read-only EVM portfolio balances and wallet-session authentication.
- EVM indexer processes: registered-token `Transfer` indexing, factory launch discovery, curve trade/graduation indexing, graduation-verified V2 pair discovery and swap indexing, manually registered V3 pool indexing, and fee-vault accounting events.
- Reorg-aware cursors, confirmation-depth processing, duplicate-safe event keys and canonical log filtering.
- Docker Compose for local PostgreSQL.

## Supported EVM networks

Mainnet entries: Ethereum (1), BNB Smart Chain (56), Robinhood Chain (4663), X Layer (196).

Testnet entries: Ethereum Sepolia (11155111), BNB Chain Testnet (97), Robinhood Chain Testnet (46630), X Layer Testnet (1952).

Only networks with an RPC URL configured in the environment are activated by the API and indexers. Mainnet RPCs, factory addresses, native/USD feeds, V2 graduation routers, wrapped-native assets, V3 DEX factory addresses and fee-vault addresses are intentionally blank in `.env.example`.

## Run locally

1. Install Node.js 22+ and Docker Compose.
2. Copy `.env.example` to `.env`; replace local database credentials and set a random `SESSION_SECRET` of at least 32 characters.
3. `docker compose up -d postgres`
4. `npm install`
5. `npm run db:generate`
6. `npm run db:migrate`
7. `npm run db:seed`
8. Start the API: `npm run dev:api`.
9. Start each required indexer in a separate process: `npm run dev:indexer`, `npm run dev:factory-indexer`, `npm run dev:dex-indexer`, and `npm run dev:fee-indexer`.
10. Health check: `GET /health`.

## Required operator configuration

- Set `RPC_<NETWORK>` for each enabled network.
- Set the verified factory address and exact factory deployment block in `FACTORY_<NETWORK>` and `FACTORY_START_BLOCK_<NETWORK>`.
- Keep the exact deployed `TokenLaunched` event signature in `FACTORY_EVENT_ABI_<NETWORK>`.
- Set `NATIVE_USD_FEED_<NETWORK>` only to the verified native/USD oracle for that chain. Configure `ORACLE_MAX_AGE_SECONDS` conservatively.
- Set `DEX_V2_ROUTER_<NETWORK>` to the chain-specific, verified Uniswap-V2-compatible router used by `UniraeV2MigrationCoordinator`; verify its `factory()` and `WETH()` responses and ensure its factory can create the token/wrapped-native pair. This is the graduation LP venue.
- Set `WRAPPED_NATIVE_<NETWORK>` and the verified V3 factory separately before enabling V3 pool indexing. V3 indexing does not mean graduation currently adds V3 liquidity.
- Set `FEE_VAULT_<NETWORK>` and its exact deployment block before starting fee indexing.
- Register a V3 pool only through `npm run register:v3-pool` after its factory, pair tokens, fee tier and wrapped-native quote have been independently verified.

Never reuse testnet addresses or feeds on mainnet. Never expose RPC credentials, database credentials or session secrets in the frontend.

## Register an existing token for transfer indexing

`npm run register-token -- <chainId> <tokenAddress> <creatorAddress> "Token Name" TICKER 18 <creationTxHash>`

Only register independently verified deployed contracts. The CLI's `verified` flag records explicit operator action; it is not an audit of the bytecode.

## API endpoints

- `GET /health`
- `GET /v1/chains`
- `GET /v1/indexer/status`
- `GET /v1/tokens?chainId=<id>&limit=30&cursor=<id>`
- `GET /v1/portfolio/0x...`
- `GET /v1/transactions/0x...`
- `GET /v1/fees/:chainId/:tokenAddress`
- `GET /v1/prices/native-usd/:chainId`
- `GET /v1/tokens/:chainId/:address/candles?interval=5m&range=24h`

The fee endpoint reports the latest 100 indexed fee-vault events and totals over that same window, not lifetime accounting. Candle coverage depends on indexed trades and registered pools; incomplete history is reported as incomplete. USD conversion is only enabled when a fresh configured oracle quote is available.

## Known release limitations

- Backend package installation, Prisma validation, Vitest and full TypeScript build must pass in CI before release.
- The V3 indexer requires explicit operator registration of each pool; it does not discover every V3 pool automatically.
- Transfer-based portfolio reconstruction may be inaccurate for rebasing, fee-on-transfer, nonstandard or malicious tokens. The API performs live balance reads where configured; do not treat inferred P&L as authoritative.
- Rate limiting in the API process is a safety net, not a replacement for a production API gateway/WAF, distributed rate limiting, observability and alerting.
- Admin audit tables are present, but privileged admin workflows/MFA are not exposed by this API.
- The equity registry is only an issuer-authorization primitive; it does not provide regulated issuance, custody, redemption, broker-dealer services or jurisdictional eligibility checks.
