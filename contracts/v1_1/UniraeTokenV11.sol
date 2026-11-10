// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice UNIRAE launch token. The bonding curve is permanently tax-exempt.
/// @dev Creator retains disclosed tax/ownership controls; buyback is disabled until an executor is audited.
contract UniraeTokenV11 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;
    address public pendingOwner;
    address public immutable creatorFeeWallet;
    address public immutable platformTaxWallet;
    uint16 public immutable platformTaxShareBps;
    address public immutable bondingCurve;
    address public migrationCoordinator;
    uint16 public buyTaxBps;
    uint16 public sellTaxBps;
    uint16 public transferTaxBps;
    uint16 public creatorShareBps;
    uint16 public buybackShareBps;
    uint16 public burnShareBps;
    mapping(address => bool) public isAmmPair;
    mapping(address => bool) public isTaxExempt;
    mapping(address => uint256) public claimableCreatorFees;
    uint256 public buybackReserve;

    uint16 public constant MAX_TAX_BPS = 1_000;
    uint16 private constant BPS = 10_000;
    /// @notice Canonical irrecoverable sink used by native-asset buybacks.
    address public constant BUYBACK_BURN_SINK = 0x000000000000000000000000000000000000dEaD;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferStarted(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TaxRatesUpdated(uint16 buyTaxBps, uint16 sellTaxBps, uint16 transferTaxBps);
    event FeeAllocationUpdated(uint16 creatorShareBps, uint16 buybackShareBps, uint16 burnShareBps);
    event AmmPairUpdated(address indexed pair, bool enabled);
    event CreatorFeesClaimed(address indexed wallet, uint256 amount);
    event TaxExemptionUpdated(address indexed account, bool exempt);
    event TaxCollected(address indexed from, address indexed to, uint256 tax, uint256 platformAmount, uint256 creatorAmount, uint256 burned);

    modifier onlyOwner() { require(msg.sender == owner, "UNIRAE: not owner"); _; }

    constructor(
        string memory name_, string memory symbol_, uint256 initialSupply_,
        uint16 curveSupplyBps_, address creatorOwner_, address creatorFeeWallet_, address curve_,
        uint16 buyTaxBps_, uint16 sellTaxBps_, uint16 transferTaxBps_,
        uint16 creatorShareBps_, uint16 buybackShareBps_, uint16 burnShareBps_, address platformTaxWallet_, uint16 platformTaxShareBps_
    ) {
        require(bytes(name_).length > 0 && bytes(name_).length <= 32, "UNIRAE: invalid name");
        require(bytes(symbol_).length >= 2 && bytes(symbol_).length <= 10, "UNIRAE: invalid symbol");
        require(initialSupply_ > 0 && initialSupply_ <= 1_000_000_000_000, "UNIRAE: invalid supply");
        require(curveSupplyBps_ > 0 && curveSupplyBps_ < BPS, "UNIRAE: invalid curve allocation");
        require(creatorOwner_ != address(0) && creatorFeeWallet_ != address(0) && curve_ != address(0) && platformTaxWallet_ != address(0), "UNIRAE: zero address");
        require(platformTaxShareBps_ <= 2_000, "UNIRAE: platform tax share above 20%");
        require(buybackShareBps_ == 0, "UNIRAE: buyback executor not enabled");
        name = name_; symbol = symbol_; owner = creatorOwner_;
        creatorFeeWallet = creatorFeeWallet_; platformTaxWallet = platformTaxWallet_; platformTaxShareBps = platformTaxShareBps_; bondingCurve = curve_;
        _setTaxRates(buyTaxBps_, sellTaxBps_, transferTaxBps_);
        _setAllocations(creatorShareBps_, buybackShareBps_, burnShareBps_);
        isTaxExempt[address(this)] = true;
        isTaxExempt[curve_] = true;
        // Buyback output must arrive in full; charging buy tax on the sink would
        // make an otherwise successful native-asset buyback revert its delivery check.
        isTaxExempt[BUYBACK_BURN_SINK] = true;
        uint256 supply = initialSupply_ * 1 ether;
        uint256 curveAmount = supply * curveSupplyBps_ / BPS;
        _mint(curve_, curveAmount);
        _mint(creatorOwner_, supply - curveAmount);
        emit OwnershipTransferred(address(0), creatorOwner_);
    }

    function transfer(address to, uint256 amount) external returns (bool) { _transfer(msg.sender, to, amount); return true; }
    function approve(address spender, uint256 amount) external returns (bool) { allowance[msg.sender][spender] = amount; emit Approval(msg.sender, spender, amount); return true; }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; require(allowed >= amount, "UNIRAE: allowance exceeded");
        if (allowed != type(uint256).max) { allowance[from][msg.sender] = allowed - amount; emit Approval(from, msg.sender, allowance[from][msg.sender]); }
        _transfer(from, to, amount); return true;
    }

    function setTaxRates(uint16 buy_, uint16 sell_, uint16 transfer_) external onlyOwner { _setTaxRates(buy_, sell_, transfer_); }
    function setFeeAllocations(uint16 creator_, uint16 buyback_, uint16 burn_) external onlyOwner { _setAllocations(creator_, buyback_, burn_); }
    /// @notice The bonding curve can set exactly one migration coordinator before graduation.
    /// The coordinator is tax-exempt only for initial liquidity provisioning.
    function configureMigrationCoordinator(address coordinator) external {
        require(msg.sender == bondingCurve, "UNIRAE: only bonding curve");
        require(migrationCoordinator == address(0) && coordinator != address(0) && coordinator.code.length > 0, "UNIRAE: invalid migration coordinator");
        migrationCoordinator = coordinator;
        isTaxExempt[coordinator] = true;
        emit TaxExemptionUpdated(coordinator, true);
    }

    /// @notice Only the configured migration coordinator may register the freshly created AMM pair.
    function registerAmmPair(address pair) external {
        require(msg.sender == migrationCoordinator && pair != address(0) && pair.code.length > 0, "UNIRAE: unauthorized AMM pair");
        isAmmPair[pair] = true;
        emit AmmPairUpdated(pair, true);
    }

    function setAmmPair(address pair, bool enabled) external onlyOwner {
        require(pair != address(0) && pair != address(this) && pair != bondingCurve, "UNIRAE: invalid pair");
        isAmmPair[pair] = enabled; emit AmmPairUpdated(pair, enabled);
    }
    function setTaxExempt(address account, bool exempt) external onlyOwner {
        require(account != address(0), "UNIRAE: zero account");
        require(account != bondingCurve || exempt, "UNIRAE: curve exemption is permanent");
        require(account != BUYBACK_BURN_SINK || exempt, "UNIRAE: buyback sink exemption is permanent");
        isTaxExempt[account] = exempt; emit TaxExemptionUpdated(account, exempt);
    }
    /// @notice Starts a two-step owner handoff; the proposed creator/admin must accept.
    function transferOwnership(address next) external onlyOwner {
        require(next != address(0) && next != owner, "UNIRAE: invalid pending owner");
        pendingOwner = next;
        emit OwnershipTransferStarted(owner, next);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "UNIRAE: not pending owner");
        address old = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(old, msg.sender);
    }
    function claimCreatorFees() external {
        require(msg.sender == creatorFeeWallet, "UNIRAE: not creator fee wallet");
        uint256 amount = claimableCreatorFees[msg.sender]; require(amount != 0, "UNIRAE: nothing to claim");
        claimableCreatorFees[msg.sender] = 0; _rawTransfer(address(this), msg.sender, amount); emit CreatorFeesClaimed(msg.sender, amount);
    }

    function _setTaxRates(uint16 b, uint16 s, uint16 t) internal {
        require(b <= MAX_TAX_BPS && s <= MAX_TAX_BPS && t <= MAX_TAX_BPS, "UNIRAE: tax above 10%");
        buyTaxBps = b; sellTaxBps = s; transferTaxBps = t; emit TaxRatesUpdated(b, s, t);
    }
    function _setAllocations(uint16 c, uint16 bb, uint16 burn_) internal {
        require(uint256(c) + bb + burn_ == BPS && bb == 0, "UNIRAE: invalid allocations or buyback disabled");
        creatorShareBps = c; buybackShareBps = bb; burnShareBps = burn_; emit FeeAllocationUpdated(c, bb, burn_);
    }
    function _mint(address to, uint256 amount) internal { totalSupply += amount; balanceOf[to] += amount; emit Transfer(address(0), to, amount); }
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "UNIRAE: zero address"); require(balanceOf[from] >= amount, "UNIRAE: insufficient balance");
        uint16 rate;
        if (!isTaxExempt[from] && !isTaxExempt[to]) {
            if (isAmmPair[from]) rate = buyTaxBps; else if (isAmmPair[to]) rate = sellTaxBps; else rate = transferTaxBps;
        }
        uint256 tax = amount * rate / BPS;
        if (tax == 0) { _rawTransfer(from, to, amount); return; }
        uint256 net = amount - tax; balanceOf[from] -= amount; balanceOf[to] += net; emit Transfer(from, to, net);
        balanceOf[address(this)] += tax; emit Transfer(from, address(this), tax);
        uint256 platformAmount = tax * platformTaxShareBps / BPS;
        uint256 distributable = tax - platformAmount;
        uint256 creatorAmount = distributable * creatorShareBps / BPS;
        uint256 burnAmount = distributable - creatorAmount;
        if (platformAmount != 0) _rawTransfer(address(this), platformTaxWallet, platformAmount);
        if (creatorAmount != 0) claimableCreatorFees[creatorFeeWallet] += creatorAmount;
        if (burnAmount != 0) { balanceOf[address(this)] -= burnAmount; totalSupply -= burnAmount; emit Transfer(address(this), address(0), burnAmount); }
        emit TaxCollected(from, to, tax, platformAmount, creatorAmount, burnAmount);
    }
    function _rawTransfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "UNIRAE: zero address"); require(balanceOf[from] >= amount, "UNIRAE: insufficient balance");
        balanceOf[from] -= amount; balanceOf[to] += amount; emit Transfer(from, to, amount);
    }
}
