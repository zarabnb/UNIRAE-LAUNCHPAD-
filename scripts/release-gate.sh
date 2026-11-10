#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
missing=()
for tool in node npm forge; do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool"); done
if ((${#missing[@]})); then
  printf 'RELEASE GATE BLOCKED — missing required tool(s): %s\n' "${missing[*]}"
  echo 'Install Node.js 22+, npm and Foundry, then rerun scripts/release-gate.sh.'
  exit 2
fi
node --version; npm --version; forge --version
python3 "$ROOT/tests/v2.17-static-check.py"
python3 "$ROOT/tests/v2.19-static-check.py"
python3 "$ROOT/tests/v2.20-static-check.py"
python3 "$ROOT/tests/v2.22-static-check.py"
python3 "$ROOT/tests/v2.26-ui-static-check.py"
python3 "$ROOT/tests/v2.31-buyback-static-check.py"
python3 "$ROOT/tests/v2.32-liquidity-router-static-check.py"
python3 "$ROOT/tests/v2.33-empty-pair-griefing-static-check.py"
python3 "$ROOT/tests/v2.34-migration-integrity-static-check.py"
node "$ROOT/scripts/check-inline-js.mjs"
node "$ROOT/scripts/production-preflight.mjs" "$ROOT/.env.production"
bash "$ROOT/tests/production-preflight.test.sh"
( cd "$ROOT/backend"; npm install --no-audit --no-fund; npx prisma validate; npx prisma generate; npm test; npm run build )
( cd "$ROOT"; forge test -vvv )
echo 'Local EVM/backend gates passed. This is not an audit, live testnet verification, or production certification.'
