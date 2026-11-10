from pathlib import Path
root = Path(__file__).resolve().parents[1]
migrator = (root / "contracts/modules/UniraeV2MigrationCoordinator.sol").read_text()
factory = (root / "contracts/v1_1/UniraeFactoryV11.sol").read_text()
fee_vault = (root / "contracts/modules/UniraeFeeVault.sol").read_text()
test = (root / "contract-tests/v1_2/UniraeV2MigrationCoordinator.t.sol").read_text()
token = (root / "contracts/v1_1/UniraeTokenV11.sol").read_text()
buyback = (root / "contracts/modules/UniraeBuybackExecutor.sol").read_text()
assert "IMigrationPair(pair).balanceOf(address(this))" in migrator
assert "MIGRATE: LP mint mismatch" in migrator
assert "MIGRATE: reserve/balance mismatch" in migrator
assert "IMigrationAsset(wrappedNative).transfer(beneficiary,wrappedDust)" in migrator
assert "IMigrationPair(pair).skim(address(this))" in migrator
assert "IMigrationPair(pair).totalSupply()==0" in migrator
assert "IFactoryMigrationCoordinator(coordinator).curve() == curveAddress" in factory
assert "IFactoryMigrationCoordinator(coordinator).token() == address(UniraeBondingCurve(curveAddress).token())" in factory
assert "function acceptFactoryOwnership()" in factory
assert "function acceptOwnership()" in fee_vault
assert "BUYBACK_BURN_SINK" in token and "buyback sink exemption is permanent" in token
assert "REQUIRED_BURN_SINK" in buyback and "wrappedNative.code.length > 0" in buyback
assert "external onlyOwner nonReentrant" in fee_vault[fee_vault.index("function executeBuyback"):fee_vault.index("function transferOwnership")]
assert "address public pendingOwner" in token and "function acceptOwnership()" in token
registry = (root / "contracts/modules/AuthorizedEquityRegistry.sol").read_text()
assert "address public pendingOwner" in registry and "function acceptOwnership()" in registry
for scenario in ["testFreshPairMigrationLocksRealLpAndMovesReserves", "testExistingEmptyPairWithUnSyncedDonationsIsCleanedAndRefunded", "testRejectsRouterThatLiesAboutLpMint", "testRejectsPairThatAlreadyHasLiquidity"]:
    assert scenario in test
v11_test = (root / "contract-tests/v1_1/UniraeV11.t.sol").read_text()
assert "testFactoryRejectsCoordinatorBoundToDifferentLaunch" in v11_test
assert "testCanonicalBuybackSinkIsPermanentlyTaxExempt" in v11_test
assert "testTokenOwnershipHandoffRequiresAcceptance" in v11_test
assert "testOwnershipHandoffRequiresAcceptance" in (root / "contract-tests/v1_2/AuthorizedEquityRegistry.t.sol").read_text()
assert "unauthorized caller cannot consume reserve" in (root / "contract-tests/v1_2/UniraeFeeVault.t.sol").read_text()
print("V2.34 graduation integrity and admin-handoff static checks passed")
