// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Lock {
    function balanceOf(address) external view returns (uint256);
    function transferFrom(address,address,uint256) external returns (bool);
    function transfer(address,uint256) external returns (bool);
}

/// @notice Non-custodial-by-policy LP time-lock. Deposits are irreversible until unlockAt.
/// @dev This module does not perform a DEX migration; a separately reviewed migrator must
///      add liquidity and transfer the resulting LP tokens here.
contract UniraeLpLocker {
    struct Lock { address token; address beneficiary; uint128 amount; uint64 unlockAt; bool withdrawn; }
    uint256 public nextLockId;
    mapping(uint256 => Lock) public locks;
    uint256 private entered;

    modifier nonReentrant() {
        require(entered == 0, "LOCK: reentrant");
        entered = 1;
        _;
        entered = 0;
    }
    event Locked(uint256 indexed id,address indexed lpToken,address indexed beneficiary,uint256 amount,uint64 unlockAt);
    event Withdrawn(uint256 indexed id,address indexed beneficiary,uint256 amount);

    function lock(address lpToken,address beneficiary,uint256 amount,uint64 unlockAt) external nonReentrant returns(uint256 id) {
        require(lpToken != address(0) && lpToken.code.length > 0 && beneficiary != address(0), "LOCK: invalid address");
        require(amount > 0 && amount <= type(uint128).max, "LOCK: invalid amount");
        require(unlockAt > block.timestamp, "LOCK: unlock must be future");
        IERC20Lock lp = IERC20Lock(lpToken);
        uint256 balanceBefore = lp.balanceOf(address(this));
        require(lp.transferFrom(msg.sender,address(this),amount), "LOCK: transfer failed");
        require(lp.balanceOf(address(this)) - balanceBefore == amount, "LOCK: inexact LP receipt");
        id = ++nextLockId;
        locks[id] = Lock(lpToken,beneficiary,uint128(amount),unlockAt,false);
        emit Locked(id,lpToken,beneficiary,amount,unlockAt);
    }
    function withdraw(uint256 id) external nonReentrant {
        Lock storage l = locks[id];
        require(l.beneficiary == msg.sender, "LOCK: not beneficiary");
        require(!l.withdrawn && block.timestamp >= l.unlockAt, "LOCK: locked or withdrawn");
        l.withdrawn = true;
        IERC20Lock lp = IERC20Lock(l.token);
        uint256 lockerBefore = lp.balanceOf(address(this));
        uint256 beneficiaryBefore = lp.balanceOf(msg.sender);
        require(lp.transfer(msg.sender,l.amount), "LOCK: transfer failed");
        require(lockerBefore - lp.balanceOf(address(this)) == l.amount, "LOCK: inexact LP debit");
        require(lp.balanceOf(msg.sender) - beneficiaryBefore == l.amount, "LOCK: inexact LP delivery");
        emit Withdrawn(id,msg.sender,l.amount);
    }
}
