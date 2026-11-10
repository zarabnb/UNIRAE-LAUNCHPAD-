from pathlib import Path
root = Path(__file__).resolve().parents[1]
executor = (root / 'contracts/modules/UniraeBuybackExecutor.sol').read_text()
test = (root / 'contract-tests/v1_2/UniraeBuybackExecutor.t.sol').read_text()
assert 'balanceOf(burnSink)' in executor
assert 'uint256 delivered = balanceAfter - balanceBefore;' in executor
assert 'delivered >= minTokensOut' in executor
assert 'emit BuybackExecuted(token, msg.value, delivered, minTokensOut);' in executor
assert 'testOperatorExecutionVerifiesActualDelivery' in test
assert 'testRejectsRouterThatFakesReturnedAmounts' in test
assert 'testRequiresRealTokenDeliveryToBurnSink' in test
assert 'testRejectsNonCanonicalBurnSink' in test
assert 'testRejectsWrappedNativeWithoutCode' in test
assert 'REQUIRED_BURN_SINK' in executor
assert 'wrappedNative.code.length > 0' in executor
print('V2.31 buyback delivery hardening static checks passed')
