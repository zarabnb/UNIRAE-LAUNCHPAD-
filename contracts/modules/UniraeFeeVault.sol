// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUniraeBuybackExecutor {
    function operator() external view returns (address);
    function execute(address token, uint256 minTokensOut, uint256 deadline) external payable;
}

/// @notice Accounts native curve fees per token. Creator/platform claims are pull-based.
/// @dev Buybacks are initiated by the vault owner so untrusted callers cannot select a weak minOut.
/// @dev Configure only reviewed curve addresses. The executor's operator must be this vault.
contract UniraeFeeVault {
    uint256 private constant BPS = 10_000;
    address public owner;
    address public pendingOwner;
    address payable public immutable platformWallet;
    IUniraeBuybackExecutor public buybackExecutor;
    uint256 public immutable buybackThreshold;
    bool public buybackExecutorConfigured;
    mapping(address => bool) public authorizedCurve;
    mapping(address => bool) public authorizedFactory;
    mapping(address => mapping(address => uint256)) public creatorCredit;
    mapping(address => uint256) public platformCredit;
    mapping(address => uint256) public buybackCredit;
    uint256 private entered;

    event CurveAuthorization(address indexed curve, bool authorized);
    event FactoryAuthorization(address indexed factory, bool authorized);
    event BuybackExecutorConfigured(address indexed executor);
    event FeeDeposited(address indexed token, address indexed creator, uint256 amount, uint256 creatorAmount, uint256 buybackAmount, uint256 platformAmount);
    event CreatorClaimed(address indexed token, address indexed creator, uint256 amount);
    event PlatformClaimed(address indexed token, uint256 amount);
    event BuybackExecuted(address indexed token, uint256 nativeAmount, uint256 minTokensOut);
    event OwnershipTransferStarted(address indexed oldOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() { require(msg.sender == owner, "FEE: not owner"); _; }
    modifier nonReentrant() { require(entered == 0, "FEE: reentrant"); entered = 1; _; entered = 0; }

    constructor(address payable platformWallet_, uint256 threshold_) {
        require(platformWallet_ != address(0) && threshold_ > 0, "FEE: invalid config");
        owner = msg.sender;
        platformWallet = platformWallet_;
        buybackThreshold = threshold_;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function setBuybackExecutor(address executor) external onlyOwner {
        require(!buybackExecutorConfigured && executor != address(0) && executor.code.length > 0, "FEE: executor already set or invalid");
        require(IUniraeBuybackExecutor(executor).operator() == address(this), "FEE: executor operator mismatch");
        buybackExecutor = IUniraeBuybackExecutor(executor);
        buybackExecutorConfigured = true;
        emit BuybackExecutorConfigured(executor);
    }

    function setCurve(address curve, bool authorized) external onlyOwner {
        require(curve != address(0) && curve.code.length > 0, "FEE: invalid curve");
        authorizedCurve[curve] = authorized;
        emit CurveAuthorization(curve, authorized);
    }

    function setFactory(address factory, bool authorized) external onlyOwner {
        require(factory != address(0) && factory.code.length > 0, "FEE: invalid factory");
        authorizedFactory[factory] = authorized;
        emit FactoryAuthorization(factory, authorized);
    }

    function authorizeCurve(address curve) external {
        require(authorizedFactory[msg.sender] && curve != address(0) && curve.code.length > 0, "FEE: unauthorized factory or invalid curve");
        authorizedCurve[curve] = true;
        emit CurveAuthorization(curve, true);
    }

    function depositTradeFee(address token, address creator, uint16 creatorBps, uint16 buybackBps) external payable {
        require(authorizedCurve[msg.sender], "FEE: unauthorized curve");
        require(token != address(0) && creator != address(0) && msg.value > 0, "FEE: invalid deposit");
        require(uint256(creatorBps) + buybackBps <= BPS, "FEE: invalid allocation");
        uint256 creatorAmount = msg.value * creatorBps / BPS;
        uint256 buybackAmount = msg.value * buybackBps / BPS;
        uint256 platformAmount = msg.value - creatorAmount - buybackAmount;
        creatorCredit[token][creator] += creatorAmount;
        buybackCredit[token] += buybackAmount;
        platformCredit[token] += platformAmount;
        emit FeeDeposited(token, creator, msg.value, creatorAmount, buybackAmount, platformAmount);
    }

    function claimCreator(address token) external nonReentrant {
        uint256 amount = creatorCredit[token][msg.sender];
        require(amount > 0, "FEE: no creator credit");
        creatorCredit[token][msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "FEE: creator transfer failed");
        emit CreatorClaimed(token, msg.sender, amount);
    }

    function claimPlatform(address token) external nonReentrant {
        require(msg.sender == platformWallet, "FEE: not platform wallet");
        uint256 amount = platformCredit[token];
        require(amount > 0, "FEE: no platform credit");
        platformCredit[token] = 0;
        (bool ok,) = platformWallet.call{value: amount}("");
        require(ok, "FEE: platform transfer failed");
        emit PlatformClaimed(token, amount);
    }

    function executeBuyback(address token, uint256 minTokensOut, uint256 deadline) external onlyOwner nonReentrant {
        uint256 amount = buybackCredit[token];
        require(buybackExecutorConfigured, "FEE: executor not configured");
        require(amount >= buybackThreshold, "FEE: below threshold");
        require(token != address(0) && minTokensOut > 0, "FEE: invalid buyback");
        buybackCredit[token] = 0;
        buybackExecutor.execute{value: amount}(token, minTokensOut, deadline);
        emit BuybackExecuted(token, amount, minTokensOut);
    }

    /// @notice Starts a two-step ownership handoff to reduce accidental admin lockout.
    function transferOwnership(address next) external onlyOwner {
        require(next != address(0) && next != owner, "FEE: invalid pending owner");
        pendingOwner = next;
        emit OwnershipTransferStarted(owner, next);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "FEE: not pending owner");
        address old = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(old, msg.sender);
    }

    receive() external payable { revert("FEE: use fee deposit"); }
}
