// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {AuthorizedEquityRegistry} from "../../contracts/modules/AuthorizedEquityRegistry.sol";
interface VmEq { function warp(uint256) external; function expectRevert() external; function prank(address) external; }
contract AuthorizedEquityRegistryTest {
    VmEq constant vm = VmEq(address(uint160(uint256(keccak256("hevm cheat code")))));
    function testOnlyRegisteredUnexpiredAssetsCanPair() public {
        AuthorizedEquityRegistry r = new AuthorizedEquityRegistry();
        address a = address(0xA1); address b = address(0xB2); address issuer = address(0x15);
        r.registerAsset(a, issuer, keccak256("ISIN-A"), keccak256("disclosure-A"), uint64(block.timestamp + 1 days));
        r.registerAsset(b, issuer, keccak256("ISIN-B"), keccak256("disclosure-B"), uint64(block.timestamp + 1 days));
        require(r.canPair(a,b), "eligible pair");
        require(!r.canPair(a,a), "no self pair");
        vm.warp(block.timestamp + 2 days);
        require(!r.canPair(a,b), "expired authorization");
    }
    function testOwnershipHandoffRequiresAcceptance() public {
        AuthorizedEquityRegistry r = new AuthorizedEquityRegistry();
        address nextOwner = address(0xA11CE);
        r.transferOwnership(nextOwner);
        require(r.owner() == address(this), "registry owner changed before acceptance");
        require(r.pendingOwner() == nextOwner, "registry pending owner missing");
        vm.expectRevert(); r.acceptOwnership();
        vm.prank(nextOwner); r.acceptOwnership();
        require(r.owner() == nextOwner && r.pendingOwner() == address(0), "registry handoff failed");
    }

    function testNonOwnerCannotRegister() public {
        AuthorizedEquityRegistry r = new AuthorizedEquityRegistry();
        vm.expectRevert(); vm.prank(address(0xBAD));
        r.registerAsset(address(1), address(2), bytes32(uint256(1)), bytes32(uint256(2)), uint64(block.timestamp + 1 days));
    }
}
