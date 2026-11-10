// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Operator-maintained registry for issuer-authorized tokenized equity instruments.
/// @dev Registration is an administrative attestation, not a determination of legal compliance,
///      shareholder rights, custody, transfer-agent status, or suitability in any jurisdiction.
contract AuthorizedEquityRegistry {
    struct Asset {
        address issuer;
        bytes32 instrumentId;
        bytes32 disclosureHash;
        uint64 validUntil;
        bool active;
    }

    address public owner;
    address public pendingOwner;
    mapping(address => Asset) public assets;
    event AssetRegistered(address indexed token, address indexed issuer, bytes32 indexed instrumentId, bytes32 disclosureHash, uint64 validUntil);
    event AssetRevoked(address indexed token, address indexed issuer);
    event OwnershipTransferStarted(address indexed oldOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() { require(msg.sender == owner, "EQUITY: not owner"); _; }

    constructor() { owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }

    function registerAsset(address token, address issuer, bytes32 instrumentId, bytes32 disclosureHash, uint64 validUntil) external onlyOwner {
        require(token != address(0) && issuer != address(0), "EQUITY: zero address");
        require(instrumentId != bytes32(0) && disclosureHash != bytes32(0), "EQUITY: missing evidence");
        require(validUntil > block.timestamp, "EQUITY: expired authorization");
        assets[token] = Asset(issuer, instrumentId, disclosureHash, validUntil, true);
        emit AssetRegistered(token, issuer, instrumentId, disclosureHash, validUntil);
    }

    function revokeAsset(address token) external onlyOwner {
        Asset storage a = assets[token];
        require(a.issuer != address(0), "EQUITY: unknown asset");
        a.active = false;
        emit AssetRevoked(token, a.issuer);
    }

    function isEligible(address token) public view returns (bool) {
        Asset memory a = assets[token];
        return a.active && a.issuer != address(0) && a.instrumentId != bytes32(0)
            && a.disclosureHash != bytes32(0) && block.timestamp < a.validUntil;
    }

    function canPair(address assetA, address assetB) external view returns (bool) {
        return assetA != assetB && isEligible(assetA) && isEligible(assetB);
    }

    function transferOwnership(address next) external onlyOwner {
        require(next != address(0) && next != owner, "EQUITY: invalid pending owner");
        pendingOwner = next;
        emit OwnershipTransferStarted(owner, next);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "EQUITY: not pending owner");
        address old = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(old, msg.sender);
    }
}
