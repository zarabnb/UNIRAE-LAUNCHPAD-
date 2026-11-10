// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {UniraeFeeVault} from "../../contracts/modules/UniraeFeeVault.sol";

interface VmFee { function deal(address,uint256) external; function prank(address) external; function expectRevert() external; }
contract MockBuybackExecutor {
    uint256 public received;
    address public lastToken;
    address public immutable operator;
    constructor(address operator_) { operator=operator_; }
    function execute(address token,uint256,uint256) external payable { received += msg.value; lastToken = token; }
}
contract UniraeFeeVaultTest {
    VmFee constant vm = VmFee(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant CREATOR = address(0xCAFE);
    address constant PLATFORM = address(0xFEE);
    address constant TOKEN = address(0xBEEF);
    UniraeFeeVault vault;
    MockBuybackExecutor executor;
    receive() external payable {}
    function setUp() public {
        vault = new UniraeFeeVault(payable(PLATFORM), 1 ether);
        executor = new MockBuybackExecutor(address(vault));
        vault.setBuybackExecutor(address(executor));
        vault.setCurve(address(this), true);
        vm.deal(address(this), 20 ether);
    }
    function testFeeDistributionAndCreatorClaim() public {
        vault.depositTradeFee{value: 2 ether}(TOKEN, CREATOR, 4_000, 2_000);
        require(vault.creatorCredit(TOKEN, CREATOR) == 0.8 ether, "creator share");
        require(vault.buybackCredit(TOKEN) == 0.4 ether, "buyback share");
        require(vault.platformCredit(TOKEN) == 0.8 ether, "platform remainder");
        uint256 before = CREATOR.balance;
        vm.prank(CREATOR); vault.claimCreator(TOKEN);
        require(CREATOR.balance == before + 0.8 ether, "creator claim");
        require(vault.creatorCredit(TOKEN, CREATOR) == 0, "credit cleared");
    }
    function testBuybackThresholdAndExecution() public {
        vault.depositTradeFee{value: 5 ether}(TOKEN, CREATOR, 0, 2_000);
        vm.expectRevert(); vm.prank(address(0xBAD));
        vault.executeBuyback(TOKEN, 1, block.timestamp + 60);
        require(vault.buybackCredit(TOKEN) == 1 ether, "unauthorized caller cannot consume reserve");
        vault.executeBuyback(TOKEN, 1, block.timestamp + 60);
        require(executor.received() == 1 ether, "buyback sent");
        require(executor.lastToken() == TOKEN, "token selected");
        require(vault.buybackCredit(TOKEN) == 0, "reserve cleared");
    }
    function testUnauthorizedCurveCannotDeposit() public {
        vm.expectRevert(); vm.prank(address(0xBAD));
        vault.depositTradeFee{value: 1 ether}(TOKEN, CREATOR, 5_000, 0);
    }
    function testAllocationsCannotExceedOneHundredPercent() public {
        vm.expectRevert(); vault.depositTradeFee{value: 1 ether}(TOKEN, CREATOR, 8_000, 3_000);
    }
    function testOwnershipHandoffRequiresAcceptance() public {
        address nextOwner=address(0xA11CE);
        vault.transferOwnership(nextOwner);
        require(vault.owner()==address(this),"owner changed before acceptance");
        require(vault.pendingOwner()==nextOwner,"pending owner not recorded");
        vm.prank(nextOwner); vault.acceptOwnership();
        require(vault.owner()==nextOwner,"new owner did not accept");
        require(vault.pendingOwner()==address(0),"pending owner not cleared");
    }
}
