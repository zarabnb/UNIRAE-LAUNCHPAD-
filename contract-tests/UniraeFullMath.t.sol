// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UniraeFullMath} from "../contracts/libraries/UniraeFullMath.sol";

contract UniraeFullMathHarness {
    function mulDiv(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return UniraeFullMath.mulDiv(x, y, d);
    }
}

interface VmMathTest { function expectRevert() external; }

contract UniraeFullMathTest {
    VmMathTest private constant vm = VmMathTest(address(uint160(uint256(keccak256("hevm cheat code")))));
    UniraeFullMathHarness private harness;

    function setUp() public { harness = new UniraeFullMathHarness(); }

    function testMulDivExactAndFractional() external view {
        require(harness.mulDiv(10, 20, 4) == 50, "exact division");
        require(harness.mulDiv(10, 20, 6) == 33, "floor division");
    }

    function testMulDivHandles512BitIntermediate() external view {
        uint256 x = type(uint256).max / 2;
        uint256 y = 3;
        uint256 d = 3;
        require(harness.mulDiv(x, y, d) == x, "512-bit intermediate");
    }

    function testMulDivRejectsOverflow() external {
        vm.expectRevert();
        harness.mulDiv(type(uint256).max, type(uint256).max, 1);
    }

    function testMulDivRejectsZeroDenominator() external {
        vm.expectRevert();
        harness.mulDiv(1, 1, 0);
    }
}
