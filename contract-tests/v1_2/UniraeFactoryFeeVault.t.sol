// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {UniraeFactoryV11} from "../../contracts/v1_1/UniraeFactoryV11.sol";
import {UniraeBondingCurve} from "../../contracts/v1_1/UniraeBondingCurve.sol";

contract MockFeeVaultForFactory {
    mapping(address=>bool) public authorizedFactory;
    mapping(address=>bool) public authorizedCurve;
    bool public buybackExecutorConfigured = true;
    address public platformWallet;
    address public lastToken;
    address public lastCreator;
    uint16 public lastCreatorBps;
    uint16 public lastBuybackBps;
    uint256 public totalReceived;
    constructor(address platform_) { platformWallet=platform_; }
    function setFactory(address factory,bool yes) external { authorizedFactory[factory]=yes; }
    function authorizeCurve(address curve) external { require(authorizedFactory[msg.sender], "factory"); authorizedCurve[curve]=true; }
    function depositTradeFee(address token,address creator,address tokenCreator,uint16 creatorBps,uint16 buybackBps) external payable {
        require(authorizedCurve[msg.sender], "curve"); lastToken=token;lastCreator=creator;lastCreatorBps=creatorBps;lastBuybackBps=buybackBps;totalReceived+=msg.value;
    }
}
contract MockFactoryFeed {
    function decimals() external pure returns(uint8){return 8;}
    function latestRoundData() external view returns(uint80,int256,uint256,uint256,uint80){return(1,600e8,block.timestamp,block.timestamp,1);}
}
interface VmFactoryFee { function deal(address,uint256) external; function prank(address) external; function expectRevert() external; }
contract UniraeFactoryFeeVaultTest {
    VmFactoryFee constant vm=VmFactoryFee(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant PLATFORM=0xB6Cb72B580555EB27cf96504C3Ef89DaD1D2DA32;
    address constant CREATOR_FEES=address(0xCAFE);
    receive() external payable {}
    function testFactoryOwnershipHandoffRequiresAcceptance() public {
        MockFactoryFeed feed=new MockFactoryFeed();
        UniraeFactoryV11 factory=new UniraeFactoryV11(payable(PLATFORM),address(feed),5e8,500e8,20_000e8,50,8_000,1 days);
        address nextOwner=address(0xA11CE);
        factory.transferFactoryOwnership(nextOwner);
        require(factory.owner()==address(this),"factory owner changed too early");
        require(factory.pendingOwner()==nextOwner,"factory pending owner missing");
        vm.expectRevert(); factory.acceptFactoryOwnership();
        vm.prank(nextOwner); factory.acceptFactoryOwnership();
        require(factory.owner()==nextOwner && factory.pendingOwner()==address(0),"factory handoff failed");
    }
    function testFactoryAuthorizesCurveAndRoutesCreatorFeeWallet() public {
        vm.deal(address(this), 1 ether);
        MockFactoryFeed feed=new MockFactoryFeed();
        UniraeFactoryV11 factory=new UniraeFactoryV11(payable(PLATFORM),address(feed),5e8,500e8,20_000e8,50,8_000,1 days);
        MockFeeVaultForFactory vault=new MockFeeVaultForFactory(PLATFORM);
        vault.setFactory(address(factory),true);
        factory.setDefaultFeeVault(address(vault),4_000,2_000);
        (address token,address curveAddress)=factory.createToken{value:8333333333333334}("Vault Test","VLT",1_000,CREATOR_FEES,0,0,0,10_000,0);
        UniraeBondingCurve curve=UniraeBondingCurve(payable(curveAddress));
        require(curve.feeVault()==address(vault),"curve fee vault");
        require(vault.authorizedCurve(curveAddress),"curve authorized");
        (,,uint256 total)=curve.quoteBuy(1 ether);
        curve.buy{value:total}(1 ether,total);
        require(vault.lastToken()==token,"token attribution");
        require(vault.lastCreator()==CREATOR_FEES,"creator fee wallet attribution");
        require(vault.lastCreatorBps()==4_000 && vault.lastBuybackBps()==2_000,"fee split");
        require(vault.totalReceived()>0,"fee deposited");
    }
}
