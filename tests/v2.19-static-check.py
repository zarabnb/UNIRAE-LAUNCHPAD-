from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
curve = (ROOT / 'contracts/v1_1/UniraeBondingCurve.sol').read_text()
math = (ROOT / 'contracts/libraries/UniraeFullMath.sol').read_text()
test = (ROOT / 'contract-tests/UniraeFullMath.t.sol').read_text()
assert 'UniraeFullMath.mulDiv(initialPriceX18, amount, WAD)' in curve
assert 'UniraeFullMath.mulDiv(slopeX18, squareTerm, 2 * WAD * WAD)' in curve
assert 'UniraeFullMath.mulDiv(cost, tradeFeeBps, BPS)' in curve
assert 'UniraeFullMath.mulDiv(gross, tradeFeeBps, BPS)' in curve
assert '512-bit' in math and 'MulDivOverflow' in math and 'DivisionByZero' in math
for marker in ['testMulDivExactAndFractional', 'testMulDivHandles512BitIntermediate', 'testMulDivRejectsOverflow', 'testMulDivRejectsZeroDenominator']:
    assert marker in test
print('V2.19 full-precision arithmetic static checks passed')
