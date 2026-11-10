from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
locker = (ROOT / 'contracts/modules/UniraeLpLocker.sol').read_text()
test = (ROOT / 'contract-tests/v1_2/UniraeLpLocker.t.sol').read_text()
assert 'modifier nonReentrant()' in locker
assert 'external nonReentrant returns(uint256 id)' in locker
assert 'external nonReentrant {' in locker
assert 'lpToken.code.length > 0' in locker
assert 'inexact LP receipt' in locker
assert 'inexact LP debit' in locker
assert 'inexact LP delivery' in locker
assert 'testRejectsFeeOnTransferLpAtDeposit' in test
assert 'testRejectsNonContractLp' in test
print('V2.20 LP-locker hardening static checks passed')
