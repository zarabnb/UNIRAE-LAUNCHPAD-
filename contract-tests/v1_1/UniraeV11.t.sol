// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UniraeFactoryV11} from "../../contracts/v1_1/UniraeFactoryV11.sol";
import {UniraeTokenV11} from "../../contracts/v1_1/UniraeTokenV11.sol";
import {UniraeBondingCurve} from "../../contracts/v1_1/UniraeBondingCurve.sol";
import {UniraeFeeVault} from "../../contracts/modules/UniraeFeeVault.sol";
import {UniraeBuybackExecutor} from "../../contracts/modules/UniraeBuybackExecutor.sol";

interface VmV11 {
    function deal(address, uint256) external;
    function prank(address) external;
    function expectRevert() external;
    function warp(uint256) external;
}

contract MockWrappedNativeV11 {}

contract MockV2RouterForTest {
    address public immutable wrapped;
    constructor(address wrapped_) { wrapped=wrapped_; }
    function WETH() external view returns(address) { return wrapped; }
    function swapExactETHForTokens(uint256 minOut,address[] calldata path,address recipient,uint256) external payable returns(uint256[] memory amounts) {
        (bool ok, bytes memory data) = path[1].call(abi.encodeWithSignature("transfer(address,uint256)", recipient, minOut));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "mock transfer failed");
        amounts = new uint256[](2); amounts[0] = msg.value; amounts[1] = minOut;
    }
    receive() external payable {}
}

contract MockUsdFeed {
    int256 public answer = 600e8;
    uint8 public decimals = 8;
    uint256 public updatedAt = block.timestamp;
    function setAnswer(int256 next) external { answer = next; updatedAt = block.timestamp; }
    function setUpdatedAt(uint256 next) external { updatedAt = next; }
    function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract MockMigrationCoordinatorMarker {
    address public immutable curve;
    address public immutable token;
    address public immutable router;
    address public immutable locker;
    constructor(address curve_,address token_) { curve=curve_; token=token_; router=address(new MockAmmPairMarker()); locker=address(new MockAmmPairMarker()); }
    function registerPair(UniraeTokenV11 token_, address pair) external { token_.registerAmmPair(pair); }
}
contract MockAmmPairMarker {}

contract UniraeV11Test {
    VmV11 private constant vm = VmV11(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant PLATFORM = 0xB6Cb72B580555EB27cf96504C3Ef89DaD1D2DA32;
    address private constant CREATOR_FEES = address(0xCAFE);
    address private constant ALICE = address(0xA11CE);
    MockUsdFeed private feed;
    UniraeFactoryV11 private factory;
    UniraeFeeVault private feeVault;
    MockV2RouterForTest private buybackRouter;

    receive() external payable {}

    function _configureFeeVault(UniraeFactoryV11 target) internal returns (UniraeFeeVault vault) {
        vault = new UniraeFeeVault(payable(PLATFORM), 1);
        MockWrappedNativeV11 wrapped = new MockWrappedNativeV11();
        MockV2RouterForTest router = new MockV2RouterForTest(address(wrapped));
        buybackRouter = router;
        UniraeBuybackExecutor executor = new UniraeBuybackExecutor(address(vault), address(router), address(0x000000000000000000000000000000000000dEaD));
        vault.setBuybackExecutor(address(executor));
        vault.setFactory(address(target), true);
        target.setDefaultFeeVault(address(vault), 5_000, 2_500);
    }

    function setUp() public {
        feed = new MockUsdFeed();
        factory = new UniraeFactoryV11(
            payable(PLATFORM), address(feed), 5 * 1e8, 500 * 1e8,
            20_000 * 1e8, 50, 8_000, 1 days
        );
        feeVault = _configureFeeVault(factory);
        vm.deal(address(this), 100 ether);
        vm.deal(ALICE, 10 ether);
    }

    function _launch() internal returns (UniraeTokenV11 token, UniraeBondingCurve curve) {
        (address tokenAddress, address curveAddress) = factory.createToken{value: 8333333333333334}(
            "Curve Token", "CURVE", 1_000, CREATOR_FEES, 0, 0, 0, 10_000, 0
        );
        token = UniraeTokenV11(tokenAddress);
        curve = UniraeBondingCurve(payable(curveAddress));
    }

    function testLaunchCreatesCurveAndSplitsSupply() public {
        (UniraeTokenV11 token, UniraeBondingCurve curve) = _launch();
        require(token.totalSupply() == 1_000 ether, "supply");
        require(token.balanceOf(address(curve)) == 800 ether, "curve allocation");
        require(token.balanceOf(address(this)) == 200 ether, "creator allocation");
        require(token.isTaxExempt(address(curve)), "curve exempt");
        require(token.bondingCurve() == address(curve), "curve reference");
        require(PLATFORM.balance == 8333333333333334, "USD launch fee routed");
    }

    function testOnlyDeveloperWalletGetsLaunchFeeExemption() public {
        require(factory.launchFeeFor(PLATFORM) == 0, "developer fee should be zero");
        require(factory.launchFeeFor(ALICE) == factory.launchFee(), "user must pay standard fee");
        vm.deal(PLATFORM, 1 ether);
        vm.prank(PLATFORM);
        (address tokenAddress,) = factory.createToken(
            "Developer Token", "DEV", 1_000, CREATOR_FEES, 0, 0, 0, 10_000, 0
        );
        require(tokenAddress != address(0), "developer launch failed");
        require(PLATFORM.balance == 1 ether, "developer launch fee should not be charged");
    }

    function testFactoryRequiresFeeVaultBeforeLaunch() public {
        UniraeFactoryV11 unconfigured = new UniraeFactoryV11(
            payable(PLATFORM), address(feed), 5 * 1e8, 500 * 1e8,
            20_000 * 1e8, 50, 8_000, 1 days
        );
        vm.expectRevert();
        unconfigured.createToken{value: 8333333333333334}(
            "No Vault", "NOVLT", 1_000, CREATOR_FEES, 0, 0, 0, 10_000, 0
        );
    }

    function testOrdinaryUserCannotSkipLaunchFee() public {
        vm.prank(ALICE);
        vm.expectRevert();
        factory.createToken("No Fee", "NOFEE", 1_000, CREATOR_FEES, 0, 0, 0, 10_000, 0);
    }

    function testLaunchFeeIsFiveUsdAndRequotesInNativeAsset() public {
        require(factory.launchFee() == 8333333333333334, "five dollars at 600 USD/native");
        feed.setAnswer(300e8);
        require(factory.launchFee() == 16666666666666667, "requoted five dollars at 300 USD/native");
    }

    function testInitialFullyDilutedMarketCapUsesSupplyAndOracle() public {
        (, UniraeBondingCurve curve) = _launch();
        require(curve.initialPriceX18() == 833333333333334, "per-token price must use 1e18 scaling");
        require(curve.currentPriceWei() == 833333333333334, "price getter must return wei per token");
        require(curve.marketCapUsdE8() == 500 * 1e8, "initial FDV target");
        (uint256 oneTokenCost,,) = curve.quoteBuy(1 ether);
        require(oneTokenCost > 800_000_000_000_000 && oneTokenCost < 900_000_000_000_000, "one-token quote must be native wei");
    }

    function testGraduationUsdMarketCapUsesCorrectDecimalScaling() public {
        (, UniraeBondingCurve curve) = _launch();
        require(curve.marketCapUsdE8() == 500 * 1e8, "initial USD FDV must be $500");
        (,, uint256 fullCurveCost) = curve.quoteBuy(800 ether);
        require(fullCurveCost > 13 ether && fullCurveCost < 14 ether, "full-curve quote must be native wei scale");
        curve.buy{value: fullCurveCost}(800 ether, fullCurveCost);
        require(curve.marketCapUsdE8() == 20_000 * 1e8, "full curve USD FDV must be $20,000");
        require(curve.graduated(), "graduation must trigger at configured USD target");
    }

    function testCurveTradesAreExemptButWalletTransfersCanBeTaxed() public {
        (UniraeTokenV11 token, UniraeBondingCurve curve) = _launch();
        token.setTaxRates(1_000, 1_000, 1_000);
        uint256 amount = 1 ether;
        (,, uint256 total) = curve.quoteBuy(amount);
        curve.buy{value: total}(amount, total);
        require(token.balanceOf(address(this)) == 201 ether, "curve buy is not token-taxed");
        token.transfer(ALICE, 1 ether);
        require(token.balanceOf(ALICE) == 0.9 ether, "wallet transfer tax applied");
        require(token.balanceOf(PLATFORM) == 0.01 ether, "10% of collected tax routed to platform");
        require(token.claimableCreatorFees(CREATOR_FEES) == 0.09 ether, "remaining tax credited to creator");
    }

    function testBuyAndSellRoundTrip() public {
        (UniraeTokenV11 token, UniraeBondingCurve curve) = _launch();
        uint256 amount = 10 ether;
        (uint256 cost, uint256 fee, uint256 total) = curve.quoteBuy(amount);
        require(cost > 0 && fee > 0 && total == cost + fee, "buy quote");
        vm.prank(ALICE);
        curve.buy{value: total}(amount, total);
        require(token.balanceOf(ALICE) == amount, "tokens received");
        require(curve.sold() == amount, "sold updated");
        vm.prank(ALICE);
        token.approve(address(curve), 5 ether);
        (,, uint256 net) = curve.quoteSell(5 ether);
        uint256 before = ALICE.balance;
        vm.prank(ALICE);
        curve.sell(5 ether, net);
        require(ALICE.balance == before + net, "native returned");
        require(curve.sold() == 5 ether, "sold reduced");
    }

    function testMigrationCoordinatorIsExemptAndRegistersAmmPairBeforeLiquidity() public {
        (UniraeTokenV11 token, UniraeBondingCurve curve) = _launch();
        MockMigrationCoordinatorMarker coordinator = new MockMigrationCoordinatorMarker(address(curve),address(token));
        MockAmmPairMarker pair = new MockAmmPairMarker();
        factory.setMigrationCoordinator(address(curve), address(coordinator));
        require(token.migrationCoordinator() == address(coordinator), "coordinator recorded");
        require(token.isTaxExempt(address(coordinator)), "coordinator exempt for initial liquidity");
        coordinator.registerPair(token, address(pair));
        require(token.isAmmPair(address(pair)), "AMM pair registered");
        MockAmmPairMarker unauthorizedPair = new MockAmmPairMarker();
        vm.expectRevert();
        token.registerAmmPair(address(unauthorizedPair));
    }

    function testFactoryRejectsCoordinatorBoundToDifferentLaunch() public {
        (UniraeTokenV11 tokenA,UniraeBondingCurve curveA)=_launch();
        (UniraeTokenV11 tokenB,UniraeBondingCurve curveB)=_launch();
        MockMigrationCoordinatorMarker wrong = new MockMigrationCoordinatorMarker(address(curveB),address(tokenB));
        vm.expectRevert();
        factory.setMigrationCoordinator(address(curveA),address(wrong));
    }

    function testCurveTradeFeesFundCreatorPlatformAndBuyback() public {
        (UniraeTokenV11 token, UniraeBondingCurve curve) = _launch();
        (,, uint256 total) = curve.quoteBuy(10 ether);
        vm.prank(ALICE);
        curve.buy{value: total}(10 ether, total);
        require(feeVault.creatorCredit(address(token), CREATOR_FEES) > 0, "creator credit funded");
        require(feeVault.buybackCredit(address(token)) > 0, "buyback reserve funded");
        require(feeVault.platformCredit(address(token)) > 0, "platform credit funded");
    }

    function testBuybackExecutorConsumesOnlyAccruedReserve() public {
        (UniraeTokenV11 token, UniraeBondingCurve curve) = _launch();
        (,, uint256 total) = curve.quoteBuy(10 ether);
        vm.prank(ALICE);
        curve.buy{value: total}(10 ether, total);
        uint256 reserve = feeVault.buybackCredit(address(token));
        require(reserve > 0, "reserve exists");
        require(token.transfer(address(buybackRouter), 1), "fund mock router");
        feeVault.executeBuyback(address(token), 1, block.timestamp + 60);
        require(feeVault.buybackCredit(address(token)) == 0, "reserve consumed");
    }

    function testCurveExemptionCannotBeRemoved() public {
        (UniraeTokenV11 token, UniraeBondingCurve curve) = _launch();
        curve;
        vm.expectRevert();
        token.setTaxExempt(address(curve), false);
    }

    function testTokenOwnershipHandoffRequiresAcceptance() public {
        (UniraeTokenV11 token,) = _launch();
        address nextOwner = address(0xA11CE);
        token.transferOwnership(nextOwner);
        require(token.owner() == address(this), "token owner changed before acceptance");
        require(token.pendingOwner() == nextOwner, "token pending owner missing");
        vm.expectRevert(); token.acceptOwnership();
        vm.prank(nextOwner); token.acceptOwnership();
        require(token.owner() == nextOwner && token.pendingOwner() == address(0), "token ownership handoff failed");
    }

    function testTokenTaxBuybackRemainsDisabled() public {
        (UniraeTokenV11 token,) = _launch();
        vm.expectRevert();
        token.setFeeAllocations(9_000, 1_000, 0);
    }

    function testCanonicalBuybackSinkIsPermanentlyTaxExempt() public {
        (UniraeTokenV11 token,) = _launch();
        MockAmmPairMarker pair = new MockAmmPairMarker();
        token.setAmmPair(address(pair), true);
        token.setTaxRates(1_000,1_000,1_000);
        require(token.transfer(address(pair),10 ether),"seed pair");
        require(token.balanceOf(address(pair))==9 ether,"sell tax applied on pair seed");
        address burnSink=token.BUYBACK_BURN_SINK();
        vm.prank(address(pair));
        require(token.transfer(burnSink,1 ether),"buyback output transfer");
        require(token.balanceOf(burnSink)==1 ether,"buyback output was taxed");
        vm.expectRevert(); token.setTaxExempt(burnSink,false);
    }

    function testOracleGraduationLocksTradingAndBlocksCreatorReserveWithdrawal() public {
        // The supply-scaled curve starts at $500 FDV and reaches the $20,000 target at full curve inventory.
        UniraeFactoryV11 highPriceFactory = new UniraeFactoryV11(
            payable(PLATFORM), address(feed), 5 * 1e8, 500 * 1e8, 20_000 * 1e8, 50, 8_000, 1 days
        );
        _configureFeeVault(highPriceFactory);
        (address tokenAddress, address curveAddress) = highPriceFactory.createToken{value: 8333333333333334}(
            "Graduating", "GRAD", 1_000, CREATOR_FEES, 0, 0, 0, 10_000, 0
        );
        UniraeBondingCurve curve = UniraeBondingCurve(payable(curveAddress));
        (,, uint256 fullCurveCost) = curve.quoteBuy(800 ether);
        require(fullCurveCost > 13 ether && fullCurveCost < 14 ether, "full-curve quote must be native wei scale");
        curve.buy{value: fullCurveCost}(800 ether, fullCurveCost);
        require(curve.graduated(), "graduated at threshold");
        uint256 soldAtGraduation = curve.sold();
        uint256 balanceBeforeNoOp = address(this).balance;
        curve.buy{value: 1 ether}(1 ether, 1 ether);
        require(curve.sold() == soldAtGraduation, "graduated buy is a no-op");
        require(address(this).balance == balanceBeforeNoOp, "graduated buy refunds native input");
        vm.expectRevert();
        curve.migrateGraduation();
        require(!curve.reservesWithdrawn(), "reserves remain locked until migration is configured");
        require(UniraeTokenV11(tokenAddress).balanceOf(address(this)) == 1_000 ether, "creator retains bought and allocated supply");
    }

    function testStaleOracleDoesNotFreezeTradingOrTriggerGraduation() public {
        (UniraeTokenV11 token, UniraeBondingCurve curve) = _launch();
        vm.warp(10 days);
        feed.setUpdatedAt(block.timestamp - 2 days);
        (,, uint256 total) = curve.quoteBuy(1 ether);
        vm.prank(ALICE);
        curve.buy{value: total}(1 ether, total);
        require(token.balanceOf(ALICE) == 1 ether, "stale oracle must not freeze buy");
        require(!curve.graduated(), "stale oracle cannot graduate");
        vm.prank(ALICE);
        token.approve(address(curve), 1 ether);
        (,, uint256 net) = curve.quoteSell(1 ether);
        vm.prank(ALICE);
        curve.sell(1 ether, net);
        require(curve.sold() == 0, "stale oracle must not freeze sell");
    }

    function testFutureOracleTimestampDoesNotFreezeTrading() public {
        (UniraeTokenV11 token, UniraeBondingCurve curve) = _launch();
        feed.setUpdatedAt(block.timestamp + 1 hours);
        (,, uint256 total) = curve.quoteBuy(1 ether);
        vm.prank(ALICE);
        curve.buy{value: total}(1 ether, total);
        require(token.balanceOf(ALICE) == 1 ether, "future timestamp must not freeze buy");
        require(!curve.graduated(), "future timestamp cannot graduate");
    }
}
