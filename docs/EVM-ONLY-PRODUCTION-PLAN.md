# EVM production plan

1. Compile and fuzz factory, token, bonding curve, fee vault, buyback executor, migration coordinator, LP locker and equity registry with Foundry.
2. Prove buy/sell quotes, reserve solvency, slippage bounds, reentrancy protection, tax caps, allocation conservation, oracle freshness and graduation boundary behavior.
3. Verify fee accounting: platform receives 10% of collected token tax; remaining tax is allocated according to creator/burn settings. Trade-fee vault splits must conserve all native assets.
4. Exercise graduation on a fork and testnet: migrate curve reserves atomically, verify DEX pair/pool assets and liquidity amounts, lock LP receipts, and test failure/retry/reorg paths.
5. Run PostgreSQL migrations, backend unit/integration tests, indexer replay/reorg tests, API auth/rate-limit tests and chart consistency checks.
6. Pair only issuer-authorized, legally eligible tokenized equities; otherwise keep the registry disabled.
7. Deploy to each testnet, verify bytecode/config/oracles, run wallet-to-indexer end-to-end tests, obtain independent audit and formal sign-off before mainnet.
