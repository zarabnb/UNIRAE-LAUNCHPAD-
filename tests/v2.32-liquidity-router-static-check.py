from pathlib import Path
root = Path(__file__).resolve().parents[1]
coordinator = (root/'contracts/modules/UniraeV2MigrationCoordinator.sol').read_text()
config = (root/'backend/src/config.ts').read_text()
backend_env = (root/'backend/.env.example').read_text()
prod_env = (root/'.env.production.example').read_text()
readme = (root/'backend/README.md').read_text()
assert 'function addLiquidityETH' in coordinator
assert 'IMigrationRouter(router_).factory()' in coordinator
assert 'IMigrationRouter(router_).WETH()' in coordinator
assert 'v2Router: process.env[`DEX_V2_ROUTER_${envSuffix}`]' in config
for suffix in ['ETHEREUM_MAINNET','BNB_MAINNET','ROBINHOOD_MAINNET','XLAYER_MAINNET']:
    assert f'DEX_V2_ROUTER_{suffix}=' in prod_env
for suffix in ['ETHEREUM_MAINNET','BNB_MAINNET','ROBINHOOD_MAINNET','XLAYER_MAINNET','BNB_TESTNET','SEPOLIA','ROBINHOOD_TESTNET','XLAYER_TESTNET']:
    assert f'DEX_V2_ROUTER_{suffix}=' in backend_env
assert 'V3 indexing does not mean graduation currently adds V3 liquidity.' in readme
print('V2.32 liquidity-router static checks passed')
