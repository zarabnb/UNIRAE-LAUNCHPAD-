// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UniraeV2MigrationCoordinator} from "../../contracts/modules/UniraeV2MigrationCoordinator.sol";

interface VmMigration { function deal(address account,uint256 balance) external; function expectRevert() external; }

contract MockMigrationAsset {
    mapping(address=>uint256) public balanceOf;
    mapping(address=>mapping(address=>uint256)) public allowance;
    address public coordinator;
    function setCoordinator(address c) external { coordinator=c; }
    function mint(address to,uint256 amount) external { balanceOf[to]+=amount; }
    function approve(address spender,uint256 amount) external returns(bool) { allowance[msg.sender][spender]=amount; return true; }
    function transfer(address to,uint256 amount) external returns(bool) {
        require(balanceOf[msg.sender]>=amount,"balance"); balanceOf[msg.sender]-=amount; balanceOf[to]+=amount; return true;
    }
    function transferFrom(address from,address to,uint256 amount) external returns(bool) {
        uint256 a=allowance[from][msg.sender]; require(a>=amount,"allowance");
        if(a!=type(uint256).max) allowance[from][msg.sender]=a-amount;
        require(balanceOf[from]>=amount,"balance"); balanceOf[from]-=amount; balanceOf[to]+=amount; return true;
    }
    function registerAmmPair(address pair) external { require(msg.sender==coordinator,"not coordinator"); require(pair.code.length>0,"bad pair"); }
}

contract MockMigrationPair {
    address public immutable token0;
    address public immutable token1;
    uint256 public totalSupply;
    mapping(address=>uint256) public balanceOf;
    mapping(address=>mapping(address=>uint256)) public allowance;
    uint112 private reserve0;
    uint112 private reserve1;
    constructor(address a,address b) {
        if (a<b) { token0=a; token1=b; } else { token0=b; token1=a; }
    }
    function getReserves() external view returns(uint112,uint112,uint32) { return(reserve0,reserve1,uint32(block.timestamp)); }
    function setReserves(uint112 a,uint112 b) external { reserve0=a; reserve1=b; }
    function mintLp(address to,uint256 amount) external { totalSupply+=amount; balanceOf[to]+=amount; }
    function approve(address s,uint256 n) external returns(bool) { allowance[msg.sender][s]=n; return true; }
    function transfer(address to,uint256 n) external returns(bool) { require(balanceOf[msg.sender]>=n,"lp balance"); balanceOf[msg.sender]-=n; balanceOf[to]+=n; return true; }
    function transferFrom(address f,address t,uint256 n) external returns(bool) {
        uint256 a=allowance[f][msg.sender]; require(a>=n,"lp allowance"); allowance[f][msg.sender]=a-n;
        require(balanceOf[f]>=n,"lp balance"); balanceOf[f]-=n; balanceOf[t]+=n; return true;
    }
    function skim(address to) external {
        uint256 b0=MockMigrationAsset(token0).balanceOf(address(this));
        uint256 b1=MockMigrationAsset(token1).balanceOf(address(this));
        require(b0>=reserve0 && b1>=reserve1,"negative skim");
        uint256 e0=b0-reserve0; uint256 e1=b1-reserve1;
        if(e0>0) require(MockMigrationAsset(token0).transfer(to,e0),"skim0");
        if(e1>0) require(MockMigrationAsset(token1).transfer(to,e1),"skim1");
    }
}

contract MockMigrationPairFactory {
    mapping(bytes32=>address) private pairs;
    function _key(address a,address b) internal pure returns(bytes32) { return a<b?keccak256(abi.encode(a,b)):keccak256(abi.encode(b,a)); }
    function getPair(address a,address b) external view returns(address) { return pairs[_key(a,b)]; }
    function createPair(address a,address b) external returns(address p) {
        require(pairs[_key(a,b)]==address(0),"exists"); p=address(new MockMigrationPair(a,b)); pairs[_key(a,b)]=p;
    }
}

contract MockMigrationRouter {
    address public immutable factory;
    address public immutable WETH;
    bool public lieAboutLiquidity;
    constructor(address f,address w) { factory=f; WETH=w; }
    function setLie(bool v) external { lieAboutLiquidity=v; }
    function addLiquidityETH(address token,uint amountTokenDesired,uint,uint,address to,uint)
        external payable returns(uint amountToken,uint amountETH,uint liquidity)
    {
        address pair=MockMigrationPairFactory(factory).getPair(token,WETH);
        require(MockMigrationAsset(token).transferFrom(msg.sender,pair,amountTokenDesired),"token transfer");
        MockMigrationAsset(WETH).mint(pair,msg.value);
        MockMigrationPair p=MockMigrationPair(pair);
        uint256 b0=MockMigrationAsset(p.token0()).balanceOf(pair);
        uint256 b1=MockMigrationAsset(p.token1()).balanceOf(pair);
        p.setReserves(uint112(b0),uint112(b1));
        liquidity=amountTokenDesired+msg.value;
        p.mintLp(to,lieAboutLiquidity?liquidity+1:liquidity);
        return(amountTokenDesired,msg.value,liquidity);
    }
    receive() external payable {}
}

contract MockMigrationLocker {
    uint256 public nextId;
    uint256 public lockedAmount;
    function lock(address lp,address,uint256 amount,uint64) external returns(uint256 id) {
        require(MockMigrationPair(lp).transferFrom(msg.sender,address(this),amount),"LP pull");
        lockedAmount+=amount; id=++nextId;
    }
}

contract MockMigrationCurve {
    function migrate(address coordinator,address token,uint256 tokenAmount) external payable {
        require(MockMigrationAsset(token).approve(coordinator,tokenAmount),"approve");
        UniraeV2MigrationCoordinator(payable(coordinator)).migrate{value:address(this).balance}(token,tokenAmount);
    }
    receive() external payable {}
}

contract UniraeV2MigrationCoordinatorTest {
    VmMigration private constant vm=VmMigration(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant BENEFICIARY=address(0xBEEF);

    function _deploy(bool precreate,bool contaminate,bool lie)
        internal returns(MockMigrationAsset token,MockMigrationAsset weth,MockMigrationPair pair,
            MockMigrationLocker locker,MockMigrationCurve curve,UniraeV2MigrationCoordinator coordinator,
            MockMigrationPairFactory pairFactory)
    {
        token=new MockMigrationAsset(); weth=new MockMigrationAsset();
        pairFactory=new MockMigrationPairFactory();
        MockMigrationRouter router=new MockMigrationRouter(address(pairFactory),address(weth));
        if(lie) router.setLie(true);
        locker=new MockMigrationLocker(); curve=new MockMigrationCurve();
        coordinator=new UniraeV2MigrationCoordinator(
            address(curve),address(token),address(router),address(locker),BENEFICIARY,uint64(block.timestamp+30 days),200
        );
        token.setCoordinator(address(coordinator));
        token.mint(address(curve),1_000 ether);
        if(precreate) {
            pair=MockMigrationPair(pairFactory.createPair(address(token),address(weth)));
            if(contaminate) { token.mint(address(pair),7); weth.mint(address(pair),9); }
        }
        vm.deal(address(curve),1 ether);
    }

    function testFreshPairMigrationLocksRealLpAndMovesReserves() public {
        (MockMigrationAsset token,MockMigrationAsset weth,MockMigrationPair unusedPair,MockMigrationLocker locker,
            MockMigrationCurve curve,UniraeV2MigrationCoordinator coordinator,
            MockMigrationPairFactory pairFactory)=_deploy(false,false,false);
        unusedPair;
        curve.migrate{value:0}(address(coordinator),address(token),1_000 ether);
        // The pair is created inside the coordinator; the lock's exact LP amount
        // and the absence of stranded assets prove the migration completed atomically.
        require(coordinator.migrated(),"not migrated");
        require(coordinator.lockId()==1,"LP lock not recorded");
        require(locker.lockedAmount()==1 ether+1_000 ether,"actual LP amount locked");
        require(token.balanceOf(address(coordinator))==0 && weth.balanceOf(address(coordinator))==0,"no asset dust stranded");
        address pairAddress=pairFactory.getPair(address(token),address(weth));
        MockMigrationPair createdPair=MockMigrationPair(pairAddress);
        (uint112 r0,uint112 r1,)=createdPair.getReserves();
        require(r0>0 && r1>0,"pair reserves not initialized");
        require(MockMigrationAsset(createdPair.token0()).balanceOf(pairAddress)==r0,"token0 reserve mismatch");
        require(MockMigrationAsset(createdPair.token1()).balanceOf(pairAddress)==r1,"token1 reserve mismatch");
    }

    function testExistingEmptyPairWithUnSyncedDonationsIsCleanedAndRefunded() public {
        (MockMigrationAsset token,MockMigrationAsset weth,MockMigrationPair pair,MockMigrationLocker locker,
            MockMigrationCurve curve,UniraeV2MigrationCoordinator coordinator,
            MockMigrationPairFactory unusedFactory)=_deploy(true,true,false);
        unusedFactory;
        curve.migrate{value:0}(address(coordinator),address(token),1_000 ether);
        require(token.balanceOf(BENEFICIARY)==7,"token donation returned to beneficiary");
        require(weth.balanceOf(BENEFICIARY)==9,"wrapped-native donation returned to beneficiary");
        require(pair.totalSupply()==1_001 ether,"LP minted after donation sweep");
        require(locker.lockedAmount()==1_001 ether,"all actual LP locked");
    }

    function testRejectsPairThatAlreadyHasLiquidity() public {
        (MockMigrationAsset token,MockMigrationAsset weth,MockMigrationPair pair,MockMigrationLocker unusedLocker,
            MockMigrationCurve curve,UniraeV2MigrationCoordinator coordinator,
            MockMigrationPairFactory unusedFactory)=_deploy(true,false,false);
        unusedLocker; unusedFactory;
        pair.setReserves(1,1);
        vm.expectRevert();
        curve.migrate{value:0}(address(coordinator),address(token),1_000 ether);
    }

    function testRejectsRouterThatLiesAboutLpMint() public {
        (MockMigrationAsset token,MockMigrationAsset unusedWeth,MockMigrationPair unusedPair,
            MockMigrationLocker unusedLocker,MockMigrationCurve curve,
            UniraeV2MigrationCoordinator coordinator,MockMigrationPairFactory unusedFactory)=_deploy(false,false,true);
        unusedWeth; unusedPair; unusedLocker; unusedFactory;
        vm.expectRevert();
        curve.migrate{value:0}(address(coordinator),address(token),1_000 ether);
    }
}
