// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UniraeFullMath} from "../libraries/UniraeFullMath.sol";

interface IERC20Curve {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function totalSupply() external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function configureMigrationCoordinator(address coordinator) external;
}
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80);
}

interface IUniraeMigrationCoordinator {
    function migrate(address token, uint256 tokenAmount) external payable;
}
interface IUniraeFeeVault {
    function depositTradeFee(address token, address creator, uint16 creatorBps, uint16 buybackBps) external payable;
}

/// @notice Native-asset linear bonding curve with a Chainlink USD graduation check.
/// @dev Graduation is a reserve hand-off, not an automatic DEX liquidity migration.
contract UniraeBondingCurve {
    uint256 private constant WAD = 1 ether;
    uint256 private constant BPS = 10_000;
    address public immutable factory;
    address public immutable creator;
    address public immutable creatorFeeWallet;
    address payable public immutable platformFeeWallet;
    IAggregatorV3 public immutable nativeUsdFeed;
    uint256 public immutable initialPriceX18;
    uint256 public immutable slopeX18;
    uint256 public immutable graduationTargetUsdE8;
    uint16 public immutable tradeFeeBps;
    uint256 public immutable maxOracleAge;
    uint256 public sold;
    IERC20Curve public token;
    bool public initialized;
    bool public graduated;
    bool public reservesWithdrawn;
    address public migrationCoordinator;
    address public feeVault;
    uint16 public creatorFeeShareBps;
    uint16 public buybackFeeShareBps;
    uint256 private entered;

    event Initialized(address indexed token, uint256 curveInventory);
    event Bought(address indexed buyer, uint256 tokenAmount, uint256 curveCost, uint256 fee);
    event Sold(address indexed seller, uint256 tokenAmount, uint256 grossNative, uint256 fee, uint256 netNative);
    event Graduated(uint256 marketCapUsdE8, uint256 timestamp);
    event MigrationCoordinatorConfigured(address indexed coordinator);
    event FeeVaultConfigured(address indexed vault, uint16 creatorBps, uint16 buybackBps);
    event GraduationMigrated(address indexed coordinator, uint256 nativeAmount, uint256 tokenAmount);

    modifier onlyFactory() { require(msg.sender == factory, "UNIRAE: only factory"); _; }
    modifier nonReentrant() { require(entered == 0, "UNIRAE: reentrant"); entered = 1; _; entered = 0; }

    constructor(
        address creator_, address creatorFeeWallet_, address payable platformWallet_, address feed_,
        uint256 initialPriceX18_, uint256 slopeX18_, uint256 graduationTargetUsdE8_,
        uint16 tradeFeeBps_, uint256 maxOracleAge_
    ) {
        require(creator_ != address(0) && creatorFeeWallet_ != address(0) && platformWallet_ != address(0) && feed_ != address(0), "UNIRAE: zero address");
        require(initialPriceX18_ > 0 && initialPriceX18_ <= 1e36 && slopeX18_ <= 1e40, "UNIRAE: invalid curve parameters");
        require(graduationTargetUsdE8_ > 0 && tradeFeeBps_ <= 500 && maxOracleAge_ > 0, "UNIRAE: invalid config");
        require(IAggregatorV3(feed_).decimals() <= 18, "UNIRAE: unsupported oracle decimals");
        factory = msg.sender; creator = creator_; creatorFeeWallet = creatorFeeWallet_; platformFeeWallet = platformWallet_; nativeUsdFeed = IAggregatorV3(feed_);
        initialPriceX18 = initialPriceX18_; slopeX18 = slopeX18_; graduationTargetUsdE8 = graduationTargetUsdE8_;
        tradeFeeBps = tradeFeeBps_; maxOracleAge = maxOracleAge_;
    }

    function initialize(address token_) external onlyFactory {
        require(!initialized && token_ != address(0), "UNIRAE: already initialized or zero token");
        token = IERC20Curve(token_); initialized = true;
        require(token.balanceOf(address(this)) > 0, "UNIRAE: no curve inventory");
        emit Initialized(token_, token.balanceOf(address(this)));
    }

    function currentPriceX18() public view returns (uint256) { return initialPriceX18 + (slopeX18 * sold / WAD); }
    /// @notice Current native-asset price per whole token, denominated in wei.
    /// @dev currentPriceX18 is already 1e18-scaled native coin per token, i.e. wei/token.
    function currentPriceWei() public view returns (uint256) { return currentPriceX18(); }
    function quoteBuy(uint256 amount) public view returns (uint256 cost, uint256 fee, uint256 total) {
        require(initialized && !graduated && amount > 0 && amount <= token.balanceOf(address(this)), "UNIRAE: invalid buy amount");
        require(sold + amount <= token.totalSupply(), "UNIRAE: supply cap");
        cost = _area(sold, amount); fee = UniraeFullMath.mulDiv(cost, tradeFeeBps, BPS); total = cost + fee;
    }
    function quoteSell(uint256 amount) public view returns (uint256 gross, uint256 fee, uint256 net) {
        require(initialized && !graduated && amount > 0 && amount <= sold, "UNIRAE: invalid sell amount");
        gross = _area(sold - amount, amount); fee = UniraeFullMath.mulDiv(gross, tradeFeeBps, BPS); net = gross - fee;
    }

    function buy(uint256 tokenAmount, uint256 maxTotalCost) external payable nonReentrant {
        if (_syncGraduation()) {
            if (msg.value > 0) _pay(payable(msg.sender), msg.value);
            return;
        }
        (uint256 cost, uint256 fee, uint256 total) = quoteBuy(tokenAmount);
        require(total <= maxTotalCost && msg.value >= total, "UNIRAE: slippage or payment");
        sold += tokenAmount;
        require(token.transfer(msg.sender, tokenAmount), "UNIRAE: token transfer failed");
        _distributeFee(fee);
        if (msg.value > total) _pay(payable(msg.sender), msg.value - total);
        emit Bought(msg.sender, tokenAmount, cost, fee);
        _syncGraduation();
    }

    function sell(uint256 tokenAmount, uint256 minNetNative) external nonReentrant {
        if (_syncGraduation()) return;
        (uint256 gross, uint256 fee, uint256 net) = quoteSell(tokenAmount);
        require(net >= minNetNative, "UNIRAE: slippage");
        sold -= tokenAmount;
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "UNIRAE: token transfer failed");
        _distributeFee(fee);
        _pay(payable(msg.sender), net);
        emit Sold(msg.sender, tokenAmount, gross, fee, net);
    }

    function syncGraduation() external { require(initialized, "UNIRAE: not initialized"); _syncGraduation(); }

    function marketCapUsdE8() public view returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = nativeUsdFeed.latestRoundData();
        require(answer > 0 && updatedAt != 0 && updatedAt <= block.timestamp && block.timestamp - updatedAt <= maxOracleAge, "UNIRAE: stale oracle");
        require(answeredInRound >= roundId, "UNIRAE: incomplete oracle round");
        uint8 feedDecimals = nativeUsdFeed.decimals();
        require(feedDecimals <= 18, "UNIRAE: unsupported oracle decimals");
        uint256 nativeUsdE8 = uint256(answer);
        if (feedDecimals < 8) nativeUsdE8 *= 10 ** (8 - feedDecimals);
        else if (feedDecimals > 8) nativeUsdE8 /= 10 ** (feedDecimals - 8);
        // currentPriceX18 is wei per whole token; totalSupply is raw token units.
        // Divide by WAD once to obtain native wei, then convert wei to USD-E8.
        // Converting to whole native coins first would truncate fractional reserves
        // (e.g. an initial FDV below 1 native coin) and break the graduation check.
        uint256 nativeMarketValueWei = UniraeFullMath.mulDiv(currentPriceX18(), token.totalSupply(), WAD);
        return UniraeFullMath.mulDiv(nativeMarketValueWei, nativeUsdE8, WAD);
    }

    /// @notice Factory configures the shared fee vault before enabling trading for this launch.
    function configureFeeVault(address vault, uint16 creatorBps, uint16 buybackBps) external onlyFactory {
        require(feeVault == address(0) && vault != address(0), "UNIRAE: fee vault already set or zero");
        require(uint256(creatorBps) + buybackBps <= BPS, "UNIRAE: invalid fee allocation");
        feeVault = vault;
        creatorFeeShareBps = creatorBps;
        buybackFeeShareBps = buybackBps;
        emit FeeVaultConfigured(vault, creatorBps, buybackBps);
    }

    function _distributeFee(uint256 fee) internal {
        if (fee == 0) return;
        if (feeVault == address(0)) {
            _pay(platformFeeWallet, fee);
        } else {
            IUniraeFeeVault(feeVault).depositTradeFee{value: fee}(
                address(token), creatorFeeWallet, creatorFeeShareBps, buybackFeeShareBps
            );
        }
    }

    /// @notice Factory wires a dedicated, curve-specific coordinator before graduation.
    function configureMigrationCoordinator(address coordinator) external onlyFactory {
        require(migrationCoordinator == address(0) && coordinator != address(0), "UNIRAE: coordinator already set or zero");
        migrationCoordinator = coordinator;
        token.configureMigrationCoordinator(coordinator);
        emit MigrationCoordinatorConfigured(coordinator);
    }

    /// @notice Atomically hands curve reserves to the configured DEX migrator.
    /// @dev There is deliberately no creator withdrawal path after graduation.
    function migrateGraduation() external nonReentrant {
        require(graduated && !reservesWithdrawn, "UNIRAE: not ready");
        address coordinator = migrationCoordinator;
        require(coordinator != address(0), "UNIRAE: migration not configured");
        reservesWithdrawn = true;
        uint256 tokenAmount = token.balanceOf(address(this));
        uint256 nativeAmount = address(this).balance;
        if (tokenAmount > 0) require(token.approve(coordinator, tokenAmount), "UNIRAE: approve failed");
        IUniraeMigrationCoordinator(coordinator).migrate{value: nativeAmount}(address(token), tokenAmount);
        emit GraduationMigrated(coordinator, nativeAmount, tokenAmount);
    }

    function _syncGraduation() internal returns (bool) {
        if (graduated) return true;
        // Oracle outages, stale rounds, and future timestamps must not freeze
        // ordinary buys or sells. Graduation is simply deferred until a valid
        // round is available; marketCapUsdE8() remains strict for direct reads.
        try this.marketCapUsdE8() returns (uint256 cap) {
            if (cap >= graduationTargetUsdE8) {
                graduated = true;
                emit Graduated(cap, block.timestamp);
            }
        } catch {
            return false;
        }
        return graduated;
    }
    function _area(uint256 fromSold, uint256 amount) internal view returns (uint256) {
        // Integral of p(x)=initialPrice+slope*x, returned in native wei.
        // Price is wei per whole token; amount/fromSold are raw 1e18 token units.
        uint256 linear = UniraeFullMath.mulDiv(initialPriceX18, amount, WAD);
        // The integral of the linear slope term is slope*(2*x*dx+dx^2)/(2*WAD^2).
        // FullMath protects the 512-bit intermediate for large supplies.
        uint256 squareTerm = 2 * fromSold * amount + amount * amount;
        uint256 curveComponent = UniraeFullMath.mulDiv(slopeX18, squareTerm, 2 * WAD * WAD);
        return linear + curveComponent;
    }
    function _pay(address payable recipient, uint256 amount) internal {
        (bool ok,) = recipient.call{value: amount}(""); require(ok, "UNIRAE: native transfer failed");
    }
    receive() external payable {}
}
