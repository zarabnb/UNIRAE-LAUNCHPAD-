// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UniraeBuybackExecutor} from "../../contracts/modules/UniraeBuybackExecutor.sol";

interface VmBuyback { function deal(address, uint256) external; function expectRevert() external; }

contract MockBuybackToken {
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
}

contract MockBuybackRouter {
    address public immutable wrapped;
    MockBuybackToken public immutable token;
    bool public deliver;
    constructor(address wrapped_, MockBuybackToken token_, bool deliver_) {
        wrapped = wrapped_; token = token_; deliver = deliver_;
    }
    function WETH() external view returns (address) { return wrapped; }
    function swapExactETHForTokens(uint256 minOut, address[] calldata path, address to, uint256)
        external payable returns (uint256[] memory amounts)
    {
        require(path.length == 2 && path[0] == wrapped && path[1] == address(token), "path");
        if (deliver) token.mint(to, minOut);
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = minOut;
    }
}

contract MockWrappedNative {}

contract MockBuybackOperator {
    function run(UniraeBuybackExecutor executor, address token, uint256 minOut, uint256 deadline)
        external payable
    {
        executor.execute{value: msg.value}(token, minOut, deadline);
    }
}

contract UniraeBuybackExecutorTest {
    VmBuyback constant vm = VmBuyback(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant BURN = 0x000000000000000000000000000000000000dEaD;
    address private wrapped;
    receive() external payable {}
    function _wrapped() internal returns(address) { if(wrapped==address(0)) wrapped=address(new MockWrappedNative()); return wrapped; }

    function testRequiresRealTokenDeliveryToBurnSink() public {
        MockBuybackToken token = new MockBuybackToken();
        MockBuybackRouter router = new MockBuybackRouter(_wrapped(), token, true);
        MockBuybackOperator operator = new MockBuybackOperator();
        UniraeBuybackExecutor executor = new UniraeBuybackExecutor(address(operator), address(router), BURN);
        vm.deal(address(this), 1 ether);
        vm.expectRevert();
        executor.execute{value: 0.1 ether}(address(token), 100, block.timestamp + 60);
        require(token.balanceOf(BURN) == 0, "unauthorized call delivered tokens");
    }

    function testOperatorExecutionVerifiesActualDelivery() public {
        MockBuybackToken token = new MockBuybackToken();
        MockBuybackRouter router = new MockBuybackRouter(_wrapped(), token, true);
        UniraeBuybackExecutor executor = new UniraeBuybackExecutor(address(this), address(router), BURN);
        vm.deal(address(this), 1 ether);
        executor.execute{value: 0.1 ether}(address(token), 100, block.timestamp + 60);
        require(token.balanceOf(BURN) == 100, "burn sink did not receive output");
    }

    function testRejectsNonCanonicalBurnSink() public {
        MockBuybackToken token = new MockBuybackToken();
        MockBuybackRouter router = new MockBuybackRouter(_wrapped(), token, true);
        MockBuybackOperator operator = new MockBuybackOperator();
        vm.expectRevert();
        new UniraeBuybackExecutor(address(operator), address(router), address(0xB0A0));
    }

    function testRejectsWrappedNativeWithoutCode() public {
        MockBuybackToken token = new MockBuybackToken();
        MockBuybackRouter router = new MockBuybackRouter(address(0xBEEF), token, true);
        MockBuybackOperator operator = new MockBuybackOperator();
        vm.expectRevert();
        new UniraeBuybackExecutor(address(operator), address(router), BURN);
    }

    function testRejectsRouterThatFakesReturnedAmounts() public {
        MockBuybackToken token = new MockBuybackToken();
        MockBuybackRouter router = new MockBuybackRouter(_wrapped(), token, false);
        UniraeBuybackExecutor executor = new UniraeBuybackExecutor(address(this), address(router), BURN);
        vm.deal(address(this), 1 ether);
        vm.expectRevert();
        executor.execute{value: 0.1 ether}(address(token), 100, block.timestamp + 60);
    }
}
