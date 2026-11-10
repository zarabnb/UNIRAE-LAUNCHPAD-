// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Buyback {
    function balanceOf(address account) external view returns (uint256);
}
interface IV2RouterBuyback {
    function WETH() external view returns(address);
    function swapExactETHForTokens(uint256,address[] calldata,address,uint256) external payable returns(uint256[] memory);
}

/// @notice Timelock-free, ownerless buyback executor controlled by an immutable authorized caller.
/// @dev The authorized caller must be a reviewed fee vault. Output is sent directly to a burn sink.
contract UniraeBuybackExecutor {
    address public constant REQUIRED_BURN_SINK = 0x000000000000000000000000000000000000dEaD;
    address public immutable operator;
    address public immutable router;
    address public immutable burnSink;
    event BuybackExecuted(address indexed token,uint256 nativeIn,uint256 tokensOut,uint256 minTokensOut);
    constructor(address operator_,address router_,address burnSink_) {
        require(operator_ != address(0) && router_ != address(0) && burnSink_ == REQUIRED_BURN_SINK, "BUYBACK: invalid operator, router or burn sink");
        require(operator_.code.length > 0 && router_.code.length > 0, "BUYBACK: dependency has no code");
        address wrappedNative = IV2RouterBuyback(router_).WETH();
        require(wrappedNative != address(0) && wrappedNative.code.length > 0, "BUYBACK: invalid wrapped native");
        operator=operator_; router=router_; burnSink=burnSink_;
    }
    function execute(address token,uint256 minTokensOut,uint256 deadline) external payable {
        require(msg.sender == operator, "BUYBACK: unauthorized");
        require(token != address(0) && msg.value > 0 && deadline >= block.timestamp && deadline <= block.timestamp + 10 minutes, "BUYBACK: invalid params");
        require(token.code.length > 0, "BUYBACK: token has no code");
        address[] memory path = new address[](2);
        path[0] = IV2RouterBuyback(router).WETH();
        path[1] = token;

        // Never trust a router's returned `amounts` array as proof of delivery.
        // Measure the burn sink's real token balance before and after the swap.
        uint256 balanceBefore = IERC20Buyback(token).balanceOf(burnSink);
        uint256[] memory amounts = IV2RouterBuyback(router).swapExactETHForTokens{value: msg.value}(
            minTokensOut, path, burnSink, deadline
        );
        uint256 balanceAfter = IERC20Buyback(token).balanceOf(burnSink);
        require(balanceAfter >= balanceBefore, "BUYBACK: burn balance decreased");
        uint256 delivered = balanceAfter - balanceBefore;
        require(
            amounts.length == 2 && amounts[0] == msg.value &&
            amounts[1] >= minTokensOut && delivered >= minTokensOut,
            "BUYBACK: output not delivered"
        );
        emit BuybackExecuted(token, msg.value, delivered, minTokensOut);
    }
    receive() external payable {}
}
