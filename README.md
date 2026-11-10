# UNIRAE V2.34 — EVM-only development release

UNIRAE is a multichain EVM token launchpad targeting Ethereum, BNB Chain, Robinhood Chain, and X Layer.

This is a development release, not production certification. Static validation and source-level regression tests are included, but Solidity compilation, Foundry runtime tests, backend dependency-backed tests/build, live testnet graduation, chain-specific router/oracle verification, multisig handoff, and independent security review remain release gates.

## V2.34 security and graduation updates

- Graduation migration validates both pair tokens on new and pre-existing pair paths.
- Unsolicited token/Wrapped Native balances on an otherwise empty V2 pair are swept before seeding and returned to the configured beneficiary.
- The coordinator checks actual LP-token mint deltas and post-migration pair balances against recorded reserves.
- Leftover Wrapped Native is returned rather than left in the coordinator.
- The factory checks that a migration coordinator is bound to the exact token and curve being configured.
- Factory and fee-vault admin ownership now uses two-step acceptance.
- The canonical buyback sink is permanently tax-exempt on newly launched tokens; the executor enforces that sink and checks that Wrapped Native has code.

See `docs/V2.34-GRADUATION-INTEGRITY-AND-ADMIN-HANDOFF.md` for implementation notes and verification limits.

## Graduation liquidity venue

Graduation uses a configurable Uniswap-V2-compatible router through `UniraeV2MigrationCoordinator`; it is not hard-coded to a named DEX. Each chain's `DEX_V2_ROUTER_*`, Wrapped Native token, router factory, LP locker, and oracle must be independently verified before deployment. V3 pool indexing is a separate backend feature and is not the graduation liquidity path. See `docs/V2.32-LIQUIDITY-POOL-ARCHITECTURE.md`.

## Local validation

Run:

```bash
python3 tests/v2.17-static-check.py
python3 tests/v2.19-static-check.py
python3 tests/v2.20-static-check.py
python3 tests/v2.22-static-check.py
python3 tests/v2.26-ui-static-check.py
python3 tests/v2.31-buyback-static-check.py
python3 tests/v2.32-liquidity-router-static-check.py
python3 tests/v2.33-empty-pair-griefing-static-check.py
python3 tests/v2.34-migration-integrity-static-check.py
node scripts/check-inline-js.mjs
bash tests/production-preflight.test.sh
```

The full release gate is `bash scripts/release-gate.sh`; it requires Node.js 22+, npm, Foundry, backend dependencies, production environment configuration, and a working Solidity compiler.
