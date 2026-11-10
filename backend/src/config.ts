import 'dotenv/config';
export const config = {
  port: Number(process.env.PORT || 4100),
  corsOrigins: (process.env.CORS_ORIGINS || 'http://localhost:3000,http://127.0.0.1:5500').split(',').map(s => s.trim()),
  pollMs: Number(process.env.INDEXER_POLL_MS || 5000),
  batchSize: BigInt(process.env.INDEXER_BATCH_SIZE || 500),
};
const commonEventAbi = process.env.FACTORY_EVENT_ABI || 'event TokenLaunched(address indexed token, address indexed curve, address indexed creator, string name, string symbol, uint256 supply)';
const makeChain = (id: number, slug: string, name: string, envSuffix: string, confirmations: number) => ({
  id, slug, name, envSuffix, confirmations: Number(process.env[`CONFIRMATIONS_${envSuffix}`] || confirmations),
  rpc: process.env[`RPC_${envSuffix}`],
  factory: process.env[`FACTORY_${envSuffix}`],
  nativeUsdFeed: process.env[`NATIVE_USD_FEED_${envSuffix}`],
  wrappedNative: process.env[`WRAPPED_NATIVE_${envSuffix}`],
  // V2-compatible router used by the Solidity graduation coordinator.
  v2Router: process.env[`DEX_V2_ROUTER_${envSuffix}`],
  v3Factory: process.env[`UNISWAP_V3_FACTORY_${envSuffix}`],
  feeVault: process.env[`FEE_VAULT_${envSuffix}`],
  feeVaultStartBlock: process.env[`FEE_VAULT_START_BLOCK_${envSuffix}`],
  factoryEventAbi: process.env[`FACTORY_EVENT_ABI_${envSuffix}`] || commonEventAbi,
});

// Production and test networks are explicit separate entries. Only networks with
// configured RPC endpoints are activated by the API/indexers.
export const chainConfigs = [
  makeChain(1, 'ethereum-mainnet', 'Ethereum', 'ETHEREUM_MAINNET', 12),
  makeChain(56, 'bnb-mainnet', 'BNB Smart Chain', 'BNB_MAINNET', 15),
  makeChain(4663, 'robinhood-mainnet', 'Robinhood Chain', 'ROBINHOOD_MAINNET', 12),
  makeChain(196, 'xlayer-mainnet', 'X Layer', 'XLAYER_MAINNET', 12),
  makeChain(97, 'bnb-testnet', 'BNB Chain Testnet', 'BNB_TESTNET', 8),
  makeChain(11155111, 'sepolia', 'Ethereum Sepolia', 'SEPOLIA', 12),
  makeChain(46630, 'robinhood-testnet', 'Robinhood Chain Testnet', 'ROBINHOOD_TESTNET', 8),
  makeChain(1952, 'xlayer-testnet', 'X Layer Testnet', 'XLAYER_TESTNET', 8),
].filter(c => !!c.rpc);
