from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
ui=(ROOT/'frontend/UNIRAE-Premium-UI-v2.27.html').read_text()
factory=(ROOT/'contracts/v1_1/UniraeFactoryV11.sol').read_text()
migrator=(ROOT/'contracts/modules/UniraeV2MigrationCoordinator.sol').read_text()
config=(ROOT/'backend/src/config.ts').read_text()
seed=(ROOT/'backend/prisma/seed.ts').read_text()
assert ui.count('data-chain=') == 5  # All networks + four supported EVM chains
assert 'uniraeEvmProvider' in ui and 'window.ethereum' in ui
assert "!['Ethereum','BNB Chain','Robinhood Chain','X Layer'].includes(d.chain)" in ui
assert 'uint256 standardLaunchFee = msg.sender == DEVELOPER_WALLET ? 0 : launchFee();' in factory
assert 'defaultFeeVault != address(0)' in factory and 'buybackExecutorConfigured()' in factory
assert 'defaultFeeVault() view returns (address)' in ui and 'buybackExecutorConfigured()' in ui
assert '_createOrValidateEmptyPair' in migrator and 'msg.sender==router' in migrator
assert 'reserve0==0 && reserve1==0' in migrator and 'IMigrationPair(pair).token0()' in migrator
assert migrator.index('createPair(token,wrappedNative)') < migrator.index(').addLiquidityETH')
token=(ROOT/'contracts/v1_1/UniraeTokenV11.sol').read_text()
curve=(ROOT/'contracts/v1_1/UniraeBondingCurve.sol').read_text()
assert 'registerAmmPair(pair)' in migrator and 'token.configureMigrationCoordinator(coordinator)' in curve
assert 'UniraeFullMath.mulDiv(currentPriceX18(), token.totalSupply(), WAD)' in curve
assert 'UniraeFullMath.mulDiv(nativeMarketValueWei, nativeUsdE8, WAD)' in curve
assert 'isTaxExempt[coordinator] = true' in token and 'msg.sender == migrationCoordinator' in token
for chain_id in ['4663','196','56','1']:
    assert chain_id in config and chain_id in seed
json.loads((ROOT/'backend/package.json').read_text())
json.loads((ROOT/'vercel/vercel.json').read_text())
print('EVM-only static guard passed')

# No references to retired non-EVM ecosystems may remain in shipped source.
for path in ROOT.rglob('*'):
    if not path.is_file() or any(part in {'node_modules','.git','out','cache'} for part in path.parts):
        continue
    try: body=path.read_text(errors='ignore')
    except OSError: continue
    assert ('sol' + 'ana') not in body.lower(), f'retired ecosystem reference remains: {path.relative_to(ROOT)}'
