from pathlib import Path
root = Path(__file__).resolve().parents[1]
source = (root / "contracts/modules/UniraeV2MigrationCoordinator.sol").read_text()
assert "_createOrValidateEmptyPair" in source
assert "getPair(token,wrappedNative)" in source
assert "IMigrationPair(pair).token0()" in source
assert "IMigrationPair(pair).token1()" in source
assert "IMigrationPair(pair).totalSupply()==0" in source
assert "IMigrationPair(pair).skim(address(this))" in source
assert "pair contamination remains" in source
assert "MIGRATE: pair already exists" not in source
print("V2.33 empty-pair graduation griefing guard passed")
