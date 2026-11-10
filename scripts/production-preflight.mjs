#!/usr/bin/env node
import fs from 'node:fs';

const envPath = process.argv[2] || '.env.production';
const text = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';
const env = { ...process.env };
for (const line of text.split(/\r?\n/)) {
  const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
  if (m && !m[2].startsWith('#') && env[m[1]] === undefined) env[m[1]] = m[2].replace(/^(["'])(.*)\1$/, '$2');
}
const networks = [
  ['ETHEREUM_MAINNET', 1], ['BNB_MAINNET', 56],
  ['ROBINHOOD_MAINNET', 4663], ['XLAYER_MAINNET', 196],
];
const required = ['RPC','FACTORY','NATIVE_USD_FEED','WRAPPED_NATIVE','FEE_VAULT','FEE_VAULT_START_BLOCK'];
const address = /^0x[a-fA-F0-9]{40}$/;
const errors = [];
if (!env.DATABASE_URL || !/^postgres(ql)?:\/\//.test(env.DATABASE_URL)) errors.push('DATABASE_URL must be a PostgreSQL connection string');
if (!env.CORS_ORIGINS || env.CORS_ORIGINS.includes('localhost') || env.CORS_ORIGINS.includes('YOUR-')) errors.push('CORS_ORIGINS must contain the real production origin(s)');
for (const [suffix, chainId] of networks) {
  for (const key of required) {
    const name = `${key}_${suffix}`; const value = env[name];
    if (!value || value.includes('YOUR-') || value.includes('0xYOUR')) errors.push(`${name} is missing`);
    else if (['FACTORY','NATIVE_USD_FEED','WRAPPED_NATIVE','FEE_VAULT'].includes(key) && !address.test(value)) errors.push(`${name} must be a 20-byte EVM address`);
    else if (key === 'RPC' && !/^https:\/\//.test(value)) errors.push(`${name} must use HTTPS`);
    else if (key === 'FEE_VAULT_START_BLOCK' && !/^\d+$/.test(value)) errors.push(`${name} must be a non-negative block number`);
  }
  const confirmations = env[`CONFIRMATIONS_${suffix}`];
  if (confirmations !== undefined && (!/^\d+$/.test(confirmations) || Number(confirmations) < 1)) errors.push(`CONFIRMATIONS_${suffix} must be a positive integer`);
}
if (errors.length) {
  console.error(`PRODUCTION PREFLIGHT FAILED (${errors.length} issue(s))`);
  for (const e of errors) console.error(` - ${e}`);
  process.exit(1);
}
console.log(`Production configuration shape passed for ${networks.length} EVM networks (chain IDs: ${networks.map(x=>x[1]).join(', ')}).`);
console.log('This check does not prove contract bytecode, oracle freshness, router correctness, ownership, or RPC availability.');
