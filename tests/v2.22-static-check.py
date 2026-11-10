from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
factory=(ROOT/'contracts/v1_1/UniraeFactoryV11.sol').read_text()
curve=(ROOT/'contracts/v1_1/UniraeBondingCurve.sol').read_text()
test=(ROOT/'contract-tests/v1_1/UniraeV11.t.sol').read_text()
ui=(ROOT/'frontend/UNIRAE-Premium-UI-v2.27.html').read_text()
assert 'UniraeFullMath.mulDiv(initialMarketCapUsdE8, 1 ether, priceDenominator)' in factory
assert 'initialMarketCapUsdE8 * 1e36' not in factory
assert 'return currentPriceX18();' in curve
assert 'UniraeFullMath.mulDiv(currentPriceX18(), token.totalSupply(), WAD)' in curve
assert 'UniraeFullMath.mulDiv(nativeMarketValueWei, nativeUsdE8, WAD)' in curve
assert 'UniraeFullMath.mulDiv(initialPriceX18, amount, WAD)' in curve
assert 'UniraeFullMath.mulDiv(slopeX18, squareTerm, 2 * WAD * WAD)' in curve
assert 'initialPriceX18() == 833333333333334' in test
assert 'oneTokenCost > 800_000_000_000_000' in test
assert 'marketCapUsdE8() == 20_000 * 1e8' in test
assert 'data-sort="watchlist"' in ui and 'toggleWatch' in ui
assert 'Launch readiness' in ui and 'updateLaunchReadiness' in ui
assert "e.key==='/" in ui and "e.key.toLowerCase()==='c'" in ui
json.loads((ROOT/'backend/package.json').read_text())
json.loads((ROOT/'vercel/vercel.json').read_text())
print('V2.22 UI and curve static checks passed')
