// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMigrationToken {
    function transferFrom(address from,address to,uint256 amount) external returns(bool);
    function approve(address spender,uint256 amount) external returns(bool);
    function transfer(address to,uint256 amount) external returns(bool);
    function balanceOf(address account) external view returns(uint256);
    function registerAmmPair(address pair) external;
}
interface IMigrationRouter {
    function factory() external view returns(address);
    function WETH() external view returns(address);
    function addLiquidityETH(address token,uint amountTokenDesired,uint amountTokenMin,uint amountETHMin,address to,uint deadline)
        external payable returns(uint amountToken,uint amountETH,uint liquidity);
}
interface IMigrationPairFactory {
    function getPair(address tokenA,address tokenB) external view returns(address);
    function createPair(address tokenA,address tokenB) external returns(address);
}
interface IMigrationPair {
    function token0() external view returns(address);
    function token1() external view returns(address);
    function totalSupply() external view returns(uint256);
    function balanceOf(address account) external view returns(uint256);
    function getReserves() external view returns(uint112 reserve0,uint112 reserve1,uint32 blockTimestampLast);
    function skim(address to) external;
}
interface IMigrationAsset {
    function balanceOf(address account) external view returns(uint256);
    function transfer(address to,uint256 amount) external returns(bool);
}
interface IMigrationLocker { function lock(address lpToken,address beneficiary,uint256 amount,uint64 unlockAt) external returns(uint256); }

/// @notice One-shot atomic graduation migration for a single curve/token pair.
/// @dev Deploy per launch. The curve is the only caller; LP is immediately time-locked.
contract UniraeV2MigrationCoordinator {
    address public immutable curve;
    address public immutable token;
    address public immutable router;
    address public immutable locker;
    address public immutable beneficiary;
    uint64 public immutable unlockAt;
    uint16 public immutable maxSlippageBps;
    bool public migrated;
    uint256 public lockId;

    event Migrated(address indexed token,address indexed pair,uint256 tokenUsed,uint256 nativeUsed,uint256 liquidity,uint256 lockId);

    constructor(address curve_,address token_,address router_,address locker_,address beneficiary_,uint64 unlockAt_,uint16 maxSlippageBps_) {
        require(curve_!=address(0)&&token_!=address(0)&&router_!=address(0)&&locker_!=address(0)&&beneficiary_!=address(0),"MIGRATE: zero address");
        require(unlockAt_>block.timestamp && maxSlippageBps_<=2_000,"MIGRATE: invalid config");
        require(curve_.code.length>0 && token_.code.length>0 && router_.code.length>0 && locker_.code.length>0,"MIGRATE: dependency has no code");
        address routerFactory=IMigrationRouter(router_).factory();
        address wrappedNative=IMigrationRouter(router_).WETH();
        require(routerFactory!=address(0) && routerFactory.code.length>0 && wrappedNative!=address(0) && wrappedNative.code.length>0,"MIGRATE: invalid router");
        curve=curve_; token=token_; router=router_; locker=locker_; beneficiary=beneficiary_; unlockAt=unlockAt_; maxSlippageBps=maxSlippageBps_;
    }

    function migrate(address token_,uint256 tokenAmount) external payable {
        require(msg.sender==curve && token_==token && !migrated,"MIGRATE: unauthorized or complete");
        require(tokenAmount>0 && msg.value>0,"MIGRATE: empty reserves");
        address pairFactory=IMigrationRouter(router).factory();
        address wrappedNative=IMigrationRouter(router).WETH();
        // A third party can permissionlessly pre-create a V2 pair after the token
        // address becomes known. Requiring getPair()==0 would let anyone permanently
        // grief graduation with an empty pair. Reuse an existing pair only when its
        // token identities are correct and both reserves are zero; never seed a
        // pre-priced/pre-funded pool from the curve.
        migrated=true;
        address pair=_createOrValidateEmptyPair(pairFactory,wrappedNative);
        (uint256 tokenUsed,uint256 nativeUsed,uint256 liquidity)=_provideLiquidity(pair,wrappedNative,tokenAmount);
        require(IMigrationPairFactory(pairFactory).getPair(token,wrappedNative)==pair,"MIGRATE: pair mismatch");
        uint256 id=_lockLiquidity(pair,liquidity);
        lockId=id;
        _refundDust();
        emit Migrated(token,pair,tokenUsed,nativeUsed,liquidity,id);
    }

    function _createOrValidateEmptyPair(address pairFactory,address wrappedNative) internal returns(address pair) {
        pair=IMigrationPairFactory(pairFactory).getPair(token,wrappedNative);
        if (pair == address(0)) {
            pair=IMigrationPairFactory(pairFactory).createPair(token,wrappedNative);
        }
        require(pair!=address(0) && pair.code.length>0,"MIGRATE: pair creation failed");

        // Validate the returned pair on both the existing-pair and new-pair path.
        // A factory returning a different pair must never receive curve reserves.
        address t0=IMigrationPair(pair).token0();
        address t1=IMigrationPair(pair).token1();
        bool tokenIs0 = t0 == token && t1 == wrappedNative;
        bool tokenIs1 = t1 == token && t0 == wrappedNative;
        require(tokenIs0 || tokenIs1,"MIGRATE: pair token mismatch");
        (uint112 reserve0,uint112 reserve1,)=IMigrationPair(pair).getReserves();
        require(reserve0==0 && reserve1==0 && IMigrationPair(pair).totalSupply()==0,"MIGRATE: pair is already initialized");

        // V2 pairs can hold unsolicited token balances before `sync()`, even while
        // both reserves are zero. Sweep those donations to this coordinator so they
        // cannot skew the launch price or poison the initial LP accounting. The
        // swept assets are returned to the beneficiary by _refundDust().
        IMigrationPair(pair).skim(address(this));
        require(
            IMigrationAsset(token).balanceOf(pair)==0 && IMigrationAsset(wrappedNative).balanceOf(pair)==0,
            "MIGRATE: pair contamination remains"
        );
        // Register before initial liquidity is transferred. The coordinator is
        // already tax-exempt, so this seed transfer is not taxed.
        IMigrationToken(token).registerAmmPair(pair);
    }

    function _provideLiquidity(address pair,address wrappedNative,uint256 tokenAmount)
        internal returns(uint256 tokenUsed,uint256 nativeUsed,uint256 liquidity)
    {
        uint256 tokenBefore=IMigrationToken(token).balanceOf(address(this));
        require(IMigrationToken(token).transferFrom(curve,address(this),tokenAmount),"MIGRATE: token pull failed");
        require(IMigrationToken(token).balanceOf(address(this))-tokenBefore==tokenAmount,"MIGRATE: inexact token pull");
        require(IMigrationToken(token).approve(router,0),"MIGRATE: reset approval failed");
        require(IMigrationToken(token).approve(router,tokenAmount),"MIGRATE: approve failed");

        uint256 lpBefore=IMigrationPair(pair).balanceOf(address(this));
        uint256 minToken=tokenAmount*(10_000-maxSlippageBps)/10_000;
        uint256 minNative=msg.value*(10_000-maxSlippageBps)/10_000;
        (tokenUsed,nativeUsed,liquidity)=IMigrationRouter(router).addLiquidityETH{value:msg.value}(
            token,tokenAmount,minToken,minNative,address(this),block.timestamp+300
        );
        require(liquidity>0 && tokenUsed>0 && nativeUsed>0,"MIGRATE: no liquidity");
        require(tokenUsed<=tokenAmount && nativeUsed<=msg.value,"MIGRATE: router over-reported usage");
        uint256 lpAfter=IMigrationPair(pair).balanceOf(address(this));
        require(lpAfter>=lpBefore && lpAfter-lpBefore==liquidity,"MIGRATE: LP mint mismatch");

        // Confirm that actual pair balances and stored reserves agree after the
        // router call. This catches dishonest return values and malformed routers.
        (uint112 reserve0,uint112 reserve1,)=IMigrationPair(pair).getReserves();
        require(reserve0>0 && reserve1>0,"MIGRATE: empty post-migration reserves");
        uint256 tokenPairBalance=IMigrationAsset(token).balanceOf(pair);
        uint256 wrappedPairBalance=IMigrationAsset(wrappedNative).balanceOf(pair);
        if (IMigrationPair(pair).token0()==token) {
            require(tokenPairBalance==reserve0 && wrappedPairBalance==reserve1,"MIGRATE: reserve/balance mismatch");
        } else {
            require(tokenPairBalance==reserve1 && wrappedPairBalance==reserve0,"MIGRATE: reserve/balance mismatch");
        }
    }

    function _lockLiquidity(address pair,uint256 liquidity) internal returns(uint256) {
        require(IMigrationToken(pair).approve(locker,liquidity),"MIGRATE: LP approve failed");
        return IMigrationLocker(locker).lock(pair,beneficiary,liquidity,unlockAt);
    }

    function _refundDust() internal {
        uint256 tokenDust=IMigrationToken(token).balanceOf(address(this));
        if (tokenDust>0) require(IMigrationToken(token).transfer(beneficiary,tokenDust),"MIGRATE: token dust refund failed");
        address wrappedNative=IMigrationRouter(router).WETH();
        uint256 wrappedDust=IMigrationAsset(wrappedNative).balanceOf(address(this));
        if (wrappedDust>0) require(IMigrationAsset(wrappedNative).transfer(beneficiary,wrappedDust),"MIGRATE: wrapped native dust refund failed");
        uint256 nativeDust=address(this).balance;
        if (nativeDust>0) { (bool refunded,)=payable(beneficiary).call{value:nativeDust}(""); require(refunded,"MIGRATE: native dust refund failed"); }
    }
    // V2 routers refund unused native currency to msg.sender during addLiquidityETH.
    // Accept only those router refunds; arbitrary direct deposits remain disabled.
    receive() external payable { require(msg.sender==router,"MIGRATE: direct deposits disabled"); }
}
