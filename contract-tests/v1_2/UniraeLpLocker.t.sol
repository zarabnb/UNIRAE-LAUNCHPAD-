// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {UniraeLpLocker} from "../../contracts/modules/UniraeLpLocker.sol";
interface VmLock { function warp(uint256) external; function expectRevert() external; }
contract MockLP {
 mapping(address=>uint256) public balanceOf; mapping(address=>mapping(address=>uint256)) public allowance;
 function mint(address a,uint256 n) external { balanceOf[a]+=n; }
 function approve(address s,uint256 n) external returns(bool){allowance[msg.sender][s]=n;return true;}
 function transferFrom(address f,address t,uint256 n) external returns(bool){require(allowance[f][msg.sender]>=n);allowance[f][msg.sender]-=n;balanceOf[f]-=n;balanceOf[t]+=n;return true;}
 function transfer(address t,uint256 n) external returns(bool){balanceOf[msg.sender]-=n;balanceOf[t]+=n;return true;}
}
contract FeeOnTransferLP {
 mapping(address=>uint256) public balanceOf; mapping(address=>mapping(address=>uint256)) public allowance;
 function mint(address a,uint256 n) external {balanceOf[a]+=n;}
 function approve(address s,uint256 n) external returns(bool){allowance[msg.sender][s]=n;return true;}
 function transferFrom(address f,address t,uint256 n) external returns(bool){require(allowance[f][msg.sender]>=n);allowance[f][msg.sender]-=n;balanceOf[f]-=n;balanceOf[t]+=n-1;return true;}
 function transfer(address t,uint256 n) external returns(bool){balanceOf[msg.sender]-=n;balanceOf[t]+=n-1;return true;}
}
contract UniraeLpLockerTest {
 VmLock constant vm=VmLock(address(uint160(uint256(keccak256("hevm cheat code")))));
 function testLockAndWithdrawAfterUnlock() public { UniraeLpLocker l=new UniraeLpLocker();MockLP lp=new MockLP();lp.mint(address(this),100);lp.approve(address(l),100);uint256 id=l.lock(address(lp),address(this),100,uint64(block.timestamp+1 days));require(lp.balanceOf(address(l))==100);vm.warp(block.timestamp+1 days);l.withdraw(id);require(lp.balanceOf(address(this))==100); }
 function testCannotWithdrawEarly() public { UniraeLpLocker l=new UniraeLpLocker();MockLP lp=new MockLP();lp.mint(address(this),10);lp.approve(address(l),10);uint256 id=l.lock(address(lp),address(this),10,uint64(block.timestamp+1 days));vm.expectRevert();l.withdraw(id); }
 function testRejectsFeeOnTransferLpAtDeposit() public { UniraeLpLocker l=new UniraeLpLocker();FeeOnTransferLP lp=new FeeOnTransferLP();lp.mint(address(this),10);lp.approve(address(l),10);vm.expectRevert();l.lock(address(lp),address(this),10,uint64(block.timestamp+1 days)); }
 function testRejectsNonContractLp() public { UniraeLpLocker l=new UniraeLpLocker();vm.expectRevert();l.lock(address(0x1234),address(this),1,uint64(block.timestamp+1 days)); }
}
