from pathlib import Path
import re, json, zipfile
root=Path(__file__).resolve().parents[1]
curve=(root/'contracts/v1_1/UniraeBondingCurve.sol').read_text()
factory=(root/'contracts/v1_1/UniraeFactoryV11.sol').read_text()
migrator=(root/'contracts/modules/UniraeV2MigrationCoordinator.sol').read_text()
assert 'function withdrawGraduationReserves' not in curve
assert 'function migrateGraduation()' in curve
assert 'require(graduated && !reservesWithdrawn' in curve
assert 'IUniraeMigrationCoordinator(coordinator).migrate{value: nativeAmount}' in curve
assert 'function setMigrationCoordinator' in factory and 'UNIRAE: not factory owner' in factory
assert 'addLiquidityETH' in migrator and '.lock(pair,beneficiary,liquidity,unlockAt)' in migrator
assert 'maxSlippageBps_<=2_000' in migrator
for p in [root/'contracts/v1_1/UniraeBondingCurve.sol',root/'contracts/v1_1/UniraeFactoryV11.sol',root/'contracts/modules/UniraeV2MigrationCoordinator.sol']:
    s=p.read_text()
    # Lightweight delimiter sanity only; not a Solidity parser/compiler.
    for a,b in [('(',')'),('{','}'),('[',']')]: assert s.count(a)==s.count(b), f'{p}: unbalanced {a}{b}'
html=(root/'frontend/UNIRAE-Premium-UI-v2.27.html').read_text()
scripts=re.findall(r'<script(?:\s[^>]*)?>([\s\S]*?)</script>',html,re.I)
Path('/tmp/unirae-v28-inline.js').write_text('\n'.join(x for x in scripts if x.strip()))
print('V2.8 static invariants: PASS')
print(f'Frontend inline script blocks: {len(scripts)}')
print('NOTE: delimiter checks are not Solidity compilation; no EVM execution performed.')
