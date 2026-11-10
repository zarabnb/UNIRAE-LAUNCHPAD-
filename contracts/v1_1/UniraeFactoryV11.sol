// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UniraeTokenV11} from "./UniraeTokenV11.sol";
import {UniraeBondingCurve} from "./UniraeBondingCurve.sol";
import {UniraeFullMath} from "../libraries/UniraeFullMath.sol";

interface IUniraeFeeVaultAdmin {
    function authorizedFactory(address factory) external view returns (bool);
    function platformWallet() external view returns (address);
    function buybackExecutorConfigured() external view returns (bool);
    function authorizeCurve(address curve) external;
}

interface IFactoryMigrationCoordinator {
    function curve() external view returns(address);
    function token() external view returns(address);
    function router() external view returns(address);
    function locker() external view returns(address);
}

interface IFactoryUsdFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80);
}

/// @notice Deploys a token plus its native-asset bonding curve as one atomic launch.
contract UniraeFactoryV11 {
    address payable public immutable platformFeeWallet;
    address public immutable nativeUsdFeed;
    uint256 public immutable launchFeeUsdE8;
    address public constant OFFICIAL_PLATFORM_WALLET = 0xB6Cb72B580555EB27cf96504C3Ef89DaD1D2DA32;
    /// @notice Developer launch-fee exemption; does not exempt trading taxes or gas.
    address public constant DEVELOPER_WALLET = 0xB6Cb72B580555EB27cf96504C3Ef89DaD1D2DA32;
    uint256 public immutable initialMarketCapUsdE8;
    uint256 public immutable graduationTargetUsdE8;
    uint256 public immutable maxOracleAge;
    uint16 public immutable tradeFeeBps;
    uint16 public immutable curveSupplyBps;
    uint256 private entered;
    address public owner;
    address public pendingOwner;
    address public defaultFeeVault;
    uint16 public defaultCreatorFeeShareBps;
    uint16 public defaultBuybackFeeShareBps;

    modifier nonReentrant() { require(entered == 0, "UNIRAE: reentrant"); entered = 1; _; entered = 0; }

    event MigrationCoordinatorSet(address indexed curve, address indexed coordinator);
    event DefaultFeeVaultConfigured(address indexed vault, uint16 creatorBps, uint16 buybackBps);
    event TokenLaunched(address indexed token, address indexed curve, address indexed creator, string name, string symbol, uint256 supply);
    event DeveloperLaunchFeeWaived(address indexed developer, address indexed token, uint256 waivedUsdE8);
    event FactoryOwnershipTransferStarted(address indexed oldOwner,address indexed pendingOwner);
    event FactoryOwnershipTransferred(address indexed oldOwner,address indexed newOwner);

    constructor(
        address payable platformWallet_, address feed_, uint256 launchFeeUsdE8_,
        uint256 initialMarketCapUsdE8_, uint256 graduationTargetUsdE8_,
        uint16 tradeFeeBps_, uint16 curveSupplyBps_, uint256 maxOracleAge_
    ) {
        require(platformWallet_ == OFFICIAL_PLATFORM_WALLET && feed_ != address(0), "UNIRAE: invalid platform wallet or feed");
        require(launchFeeUsdE8_ == 5e8, "UNIRAE: launch fee must be $5 USD");
        require(initialMarketCapUsdE8_ > 0 && initialMarketCapUsdE8_ < graduationTargetUsdE8_, "UNIRAE: invalid initial market cap");
        require(graduationTargetUsdE8_ > 0 && tradeFeeBps_ <= 500 && curveSupplyBps_ > 0 && curveSupplyBps_ < 10_000 && maxOracleAge_ > 0, "UNIRAE: invalid config");
        require(IFactoryUsdFeed(feed_).decimals() <= 18, "UNIRAE: unsupported oracle decimals");
        owner = msg.sender;
        platformFeeWallet = platformWallet_; nativeUsdFeed = feed_; launchFeeUsdE8 = launchFeeUsdE8_;
        initialMarketCapUsdE8 = initialMarketCapUsdE8_; graduationTargetUsdE8 = graduationTargetUsdE8_;
        tradeFeeBps = tradeFeeBps_; curveSupplyBps = curveSupplyBps_; maxOracleAge = maxOracleAge_;
    }


    function setMigrationCoordinator(address curveAddress, address coordinator) external {
        require(msg.sender == owner, "UNIRAE: not factory owner");
        require(curveAddress != address(0) && coordinator != address(0), "UNIRAE: zero address");
        require(UniraeBondingCurve(payable(curveAddress)).factory() == address(this), "UNIRAE: foreign curve");
        require(coordinator.code.length > 0, "UNIRAE: coordinator has no code");
        require(
            IFactoryMigrationCoordinator(coordinator).curve() == curveAddress &&
            IFactoryMigrationCoordinator(coordinator).token() == address(UniraeBondingCurve(payable(curveAddress)).token()),
            "UNIRAE: coordinator launch mismatch"
        );
        require(
            IFactoryMigrationCoordinator(coordinator).router().code.length > 0 &&
            IFactoryMigrationCoordinator(coordinator).locker().code.length > 0,
            "UNIRAE: coordinator dependency missing"
        );
        UniraeBondingCurve(payable(curveAddress)).configureMigrationCoordinator(coordinator);
        emit MigrationCoordinatorSet(curveAddress, coordinator);
    }

    function setDefaultFeeVault(address vault, uint16 creatorBps, uint16 buybackBps) external {
        require(msg.sender == owner, "UNIRAE: not factory owner");
        require(uint256(creatorBps) + buybackBps <= 10_000, "UNIRAE: invalid fee allocation");
        require(vault != address(0) && vault.code.length > 0, "UNIRAE: fee vault required");
        require(IUniraeFeeVaultAdmin(vault).authorizedFactory(address(this)), "UNIRAE: factory not authorized by vault");
        require(IUniraeFeeVaultAdmin(vault).platformWallet() == platformFeeWallet, "UNIRAE: fee vault platform wallet mismatch");
        if (buybackBps > 0) require(IUniraeFeeVaultAdmin(vault).buybackExecutorConfigured(), "UNIRAE: buyback executor required");
        defaultFeeVault = vault;
        defaultCreatorFeeShareBps = creatorBps;
        defaultBuybackFeeShareBps = buybackBps;
        emit DefaultFeeVaultConfigured(vault, creatorBps, buybackBps);
    }

    function setFeeVaultForCurve(address curveAddress, address vault, uint16 creatorBps, uint16 buybackBps) external {
        require(msg.sender == owner, "UNIRAE: not factory owner");
        require(curveAddress != address(0) && vault != address(0), "UNIRAE: zero address");
        require(UniraeBondingCurve(payable(curveAddress)).factory() == address(this), "UNIRAE: foreign curve");
        require(IUniraeFeeVaultAdmin(vault).authorizedFactory(address(this)), "UNIRAE: factory not authorized by vault");
        require(IUniraeFeeVaultAdmin(vault).platformWallet() == platformFeeWallet, "UNIRAE: fee vault platform wallet mismatch");
        if (buybackBps > 0) require(IUniraeFeeVaultAdmin(vault).buybackExecutorConfigured(), "UNIRAE: buyback executor required");
        IUniraeFeeVaultAdmin(vault).authorizeCurve(curveAddress);
        UniraeBondingCurve(payable(curveAddress)).configureFeeVault(vault, creatorBps, buybackBps);
    }

    /// @notice Begins a two-step factory-admin handoff. The recipient must accept.
    function transferFactoryOwnership(address next) external {
        require(msg.sender == owner && next != address(0) && next != owner, "UNIRAE: invalid pending owner");
        pendingOwner = next;
        emit FactoryOwnershipTransferStarted(owner,next);
    }

    function acceptFactoryOwnership() external {
        require(msg.sender == pendingOwner, "UNIRAE: not pending owner");
        address old=owner;
        owner=msg.sender;
        pendingOwner=address(0);
        emit FactoryOwnershipTransferred(old,msg.sender);
    }

    /// @notice Current native-asset amount required for the USD-denominated launch fee.
    /// @dev For EVM networks, configure a fresh Chainlink native/USD feed; $5 is represented as 5e8.
    function launchFee() public view returns (uint256) {
        if (launchFeeUsdE8 == 0) return 0;
        (uint256 nativeUsdE8,,) = _readNativeUsdE8();
        uint256 numerator = launchFeeUsdE8 * 1 ether;
        uint256 amount = numerator / nativeUsdE8;
        if (numerator % nativeUsdE8 != 0) amount += 1;
        return amount;
    }

    /// @notice Returns the caller-specific fee; only the fixed developer wallet is exempt.
    function launchFeeFor(address creator) public view returns (uint256) {
        return creator == DEVELOPER_WALLET ? 0 : launchFee();
    }

    function quoteLaunchFee() external view returns (uint256 nativeAmount, uint256 nativeUsdE8, uint256 updatedAt) {
        if (launchFeeUsdE8 == 0) return (0, 0, block.timestamp);
        (nativeUsdE8, updatedAt,) = _readNativeUsdE8();
        uint256 numerator = launchFeeUsdE8 * 1 ether;
        nativeAmount = numerator / nativeUsdE8;
        if (numerator % nativeUsdE8 != 0) nativeAmount += 1;
    }

    function createToken(
        string calldata name_, string calldata symbol_, uint256 initialSupply_, address creatorFeeWallet_,
        uint16 buyTaxBps_, uint16 sellTaxBps_, uint16 transferTaxBps_, uint16 creatorShareBps_, uint16 burnShareBps_
    ) external payable nonReentrant returns (address tokenAddress, address curveAddress) {
        require(defaultFeeVault != address(0), "UNIRAE: fee vault not configured");
        // Do not query the launch-fee oracle for the exempt developer wallet.
        // Curve pricing still independently requires a valid native/USD feed.
        uint256 standardLaunchFee = msg.sender == DEVELOPER_WALLET ? 0 : launchFee();
        uint256 requiredLaunchFee = standardLaunchFee;
        require(msg.value == requiredLaunchFee, "UNIRAE: incorrect launch fee");
        require(bytes(name_).length > 0 && bytes(symbol_).length > 0 && creatorFeeWallet_ != address(0), "UNIRAE: invalid metadata");
        if (msg.value != 0) {
            (bool paid,) = platformFeeWallet.call{value: msg.value}("");
            require(paid, "UNIRAE: fee transfer failed");
        }

        (uint256 initialPriceX18, uint256 slopeX18) = _curveParameters(initialSupply_);
        UniraeBondingCurve curve = new UniraeBondingCurve(
            msg.sender, creatorFeeWallet_, platformFeeWallet, nativeUsdFeed, initialPriceX18, slopeX18,
            graduationTargetUsdE8, tradeFeeBps, maxOracleAge
        );
        UniraeTokenV11 token = new UniraeTokenV11(
            name_, symbol_, initialSupply_, curveSupplyBps, msg.sender, creatorFeeWallet_, address(curve),
            buyTaxBps_, sellTaxBps_, transferTaxBps_, creatorShareBps_, 0, burnShareBps_, platformFeeWallet, 1_000
        );
        curve.initialize(address(token));
        if (defaultFeeVault != address(0)) {
            IUniraeFeeVaultAdmin(defaultFeeVault).authorizeCurve(address(curve));
            curve.configureFeeVault(defaultFeeVault, defaultCreatorFeeShareBps, defaultBuybackFeeShareBps);
        }
        tokenAddress = address(token); curveAddress = address(curve);
        emit TokenLaunched(tokenAddress, curveAddress, msg.sender, name_, symbol_, token.totalSupply());
        if (msg.sender == DEVELOPER_WALLET) emit DeveloperLaunchFeeWaived(msg.sender, tokenAddress, launchFeeUsdE8);
    }

    function _readNativeUsdE8() internal view returns (uint256 nativeUsdE8, uint256 updatedAt, uint80 roundId) {
        int256 answer;
        uint80 answeredInRound;
        (roundId, answer,, updatedAt, answeredInRound) = IFactoryUsdFeed(nativeUsdFeed).latestRoundData();
        require(answer > 0 && updatedAt != 0 && updatedAt <= block.timestamp && block.timestamp - updatedAt <= maxOracleAge, "UNIRAE: stale oracle");
        require(answeredInRound >= roundId, "UNIRAE: incomplete oracle round");
        uint8 feedDecimals = IFactoryUsdFeed(nativeUsdFeed).decimals();
        nativeUsdE8 = uint256(answer);
        if (feedDecimals < 8) nativeUsdE8 *= 10 ** (8 - feedDecimals);
        else if (feedDecimals > 8) nativeUsdE8 /= 10 ** (feedDecimals - 8);
        require(nativeUsdE8 > 0, "UNIRAE: invalid oracle price");
    }

    function _curveParameters(uint256 supplyWholeTokens) internal view returns (uint256 initialPriceX18, uint256 slopeX18) {
        require(supplyWholeTokens > 0 && supplyWholeTokens <= 1_000_000_000_000, "UNIRAE: invalid supply");
        (uint256 nativeUsdE8,,) = _readNativeUsdE8();

        // p0 = (initial FDV / native USD price / whole-token supply), scaled by 1e18.
        // Both oracle values are USD-E8, so their decimals cancel. Multiplying by 1e36
        // here overstates every token price by 1e18 and makes the curve economically invalid.
        uint256 priceDenominator = supplyWholeTokens * nativeUsdE8;
        initialPriceX18 = UniraeFullMath.mulDiv(initialMarketCapUsdE8, 1 ether, priceDenominator);
        if (mulmod(initialMarketCapUsdE8, 1 ether, priceDenominator) != 0) initialPriceX18 += 1;

        uint256 curveInventory = supplyWholeTokens * 1 ether * curveSupplyBps / 10_000;
        require(curveInventory > 0, "UNIRAE: zero curve inventory");
        // At the end of the curve, linear price growth reaches the configured FDV.
        // Two rounded-up mulDiv operations avoid overflowing a three-factor numerator.
        uint256 terminalPriceDeltaX18 = UniraeFullMath.mulDiv(
            initialPriceX18, graduationTargetUsdE8 - initialMarketCapUsdE8, initialMarketCapUsdE8
        );
        if (mulmod(initialPriceX18, graduationTargetUsdE8 - initialMarketCapUsdE8, initialMarketCapUsdE8) != 0) {
            terminalPriceDeltaX18 += 1;
        }
        slopeX18 = UniraeFullMath.mulDiv(terminalPriceDeltaX18, 1 ether, curveInventory);
        if (mulmod(terminalPriceDeltaX18, 1 ether, curveInventory) != 0) slopeX18 += 1;
        require(initialPriceX18 > 0 && initialPriceX18 <= 1e36 && slopeX18 <= 1e40, "UNIRAE: unsupported supply curve");
    }

}
