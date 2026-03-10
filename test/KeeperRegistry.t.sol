// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {KeeperRegistry} from "../src/KeeperRegistry.sol";

contract KeeperRegistryTest is Test {
    KeeperRegistry public registry;

    address public owner = makeAddr("owner");
    address public keeper1 = makeAddr("keeper1");
    address public keeper2 = makeAddr("keeper2");
    address public merchant = makeAddr("merchant");
    address public stranger = makeAddr("stranger");

    function setUp() public {
        registry = new KeeperRegistry(owner, keeper1);

        vm.label(address(registry), "KeeperRegistry");
        vm.label(owner, "Owner");
        vm.label(keeper1, "Keeper1");
        vm.label(keeper2, "Keeper2");
        vm.label(merchant, "Merchant");
        vm.label(stranger, "Stranger");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    function test_Constructor_SetsOwner() public view {
        assertEq(registry.owner(), owner);
    }

    function test_Constructor_RegistersInitialKeeper() public view {
        address[] memory keepers = registry.getGlobalKeepers();
        assertEq(keepers.length, 1);
        assertEq(keepers[0], keeper1);
    }

    function test_Constructor_NoInitialKeeper() public {
        KeeperRegistry r = new KeeperRegistry(owner, address(0));
        assertEq(r.getGlobalKeepers().length, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // addKeeper
    // ─────────────────────────────────────────────────────────────────────────

    function test_AddKeeper_Success() public {
        vm.prank(owner);
        registry.addKeeper(keeper2);

        address[] memory keepers = registry.getGlobalKeepers();
        assertEq(keepers.length, 2);
        assertTrue(registry.isAuthorised(keeper2, merchant));
    }

    function test_AddKeeper_Reverts_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        registry.addKeeper(keeper2);
    }

    function test_AddKeeper_Reverts_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(KeeperRegistry.ZeroAddress.selector);
        registry.addKeeper(address(0));
    }

    function test_AddKeeper_Reverts_AlreadyRegistered() public {
        // keeper1 was registered in constructor
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(KeeperRegistry.AlreadyRegistered.selector, keeper1));
        registry.addKeeper(keeper1);
    }

    function test_AddKeeper_Reverts_Blacklisted() public {
        vm.prank(owner);
        registry.blacklistKeeper(keeper2);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(KeeperRegistry.KeeperIsBlacklisted.selector, keeper2));
        registry.addKeeper(keeper2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // removeKeeper
    // ─────────────────────────────────────────────────────────────────────────

    function test_RemoveKeeper_Success() public {
        vm.prank(owner);
        registry.removeKeeper(keeper1);

        assertFalse(registry.isAuthorised(keeper1, merchant));
        assertEq(registry.getGlobalKeepers().length, 0);
    }

    function test_RemoveKeeper_Reverts_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        registry.removeKeeper(keeper1);
    }

    function test_RemoveKeeper_Reverts_NotRegistered() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(KeeperRegistry.NotRegistered.selector, keeper2));
        registry.removeKeeper(keeper2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // blacklistKeeper
    // ─────────────────────────────────────────────────────────────────────────

    function test_BlacklistKeeper_BlocksIsAuthorised() public {
        assertTrue(registry.isAuthorised(keeper1, merchant));

        vm.prank(owner);
        registry.blacklistKeeper(keeper1);

        assertFalse(registry.isAuthorised(keeper1, merchant));
        assertTrue(registry.isBlacklisted(keeper1));
    }

    function test_BlacklistKeeper_RemovesFromGlobalSet() public {
        vm.prank(owner);
        registry.blacklistKeeper(keeper1);

        assertEq(registry.getGlobalKeepers().length, 0);
    }

    function test_BlacklistKeeper_NonRegistered_Succeeds() public {
        // Blacklisting an address not in the global set should still succeed
        vm.prank(owner);
        registry.blacklistKeeper(keeper2);

        assertTrue(registry.isBlacklisted(keeper2));
    }

    function test_BlacklistKeeper_Reverts_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(KeeperRegistry.ZeroAddress.selector);
        registry.blacklistKeeper(address(0));
    }

    function test_BlacklistKeeper_Reverts_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        registry.blacklistKeeper(keeper1);
    }

    function test_BlacklistKeeper_PreventsReAdd() public {
        vm.prank(owner);
        registry.blacklistKeeper(keeper1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(KeeperRegistry.KeeperIsBlacklisted.selector, keeper1));
        registry.addKeeper(keeper1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Merchant Keeper Management
    // ─────────────────────────────────────────────────────────────────────────

    function test_MerchantKeeper_AddAndAuthorise() public {
        vm.prank(merchant);
        registry.addMerchantKeeper(keeper2);

        assertTrue(registry.isAuthorised(keeper2, merchant));
        assertFalse(registry.isAuthorised(keeper2, makeAddr("otherMerchant")));

        address[] memory mKeepers = registry.getMerchantKeepers(merchant);
        assertEq(mKeepers.length, 1);
        assertEq(mKeepers[0], keeper2);
    }

    function test_MerchantKeeper_RemoveRevokesAuth() public {
        vm.prank(merchant);
        registry.addMerchantKeeper(keeper2);
        assertTrue(registry.isAuthorised(keeper2, merchant));

        vm.prank(merchant);
        registry.removeMerchantKeeper(keeper2);
        assertFalse(registry.isAuthorised(keeper2, merchant));
    }

    function test_MerchantKeeper_Reverts_AlreadyRegistered() public {
        vm.prank(merchant);
        registry.addMerchantKeeper(keeper2);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(KeeperRegistry.AlreadyRegistered.selector, keeper2));
        registry.addMerchantKeeper(keeper2);
    }

    function test_MerchantKeeper_Reverts_ZeroAddress() public {
        vm.prank(merchant);
        vm.expectRevert(KeeperRegistry.ZeroAddress.selector);
        registry.addMerchantKeeper(address(0));
    }

    function test_MerchantKeeper_Reverts_Blacklisted() public {
        vm.prank(owner);
        registry.blacklistKeeper(keeper2);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(KeeperRegistry.KeeperIsBlacklisted.selector, keeper2));
        registry.addMerchantKeeper(keeper2);
    }

    function test_MerchantKeeper_Remove_Reverts_NotRegistered() public {
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(KeeperRegistry.NotRegistered.selector, keeper2));
        registry.removeMerchantKeeper(keeper2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // isAuthorised
    // ─────────────────────────────────────────────────────────────────────────

    function test_IsAuthorised_GlobalKeeper_ReturnsTrue() public {
        assertTrue(registry.isAuthorised(keeper1, merchant));
        // Global keepers authorised for any merchant
        address anyMerchant = makeAddr("anyMerchant");
        assertTrue(registry.isAuthorised(keeper1, anyMerchant));
    }

    function test_IsAuthorised_NonKeeper_ReturnsFalse() public view {
        assertFalse(registry.isAuthorised(stranger, merchant));
    }

    function test_IsAuthorised_BlacklistedKeeper_ReturnsFalse() public {
        vm.prank(owner);
        registry.blacklistKeeper(keeper1);
        assertFalse(registry.isAuthorised(keeper1, merchant));
    }

    function test_IsAuthorised_BlacklistedMerchantKeeper_ReturnsFalse() public {
        // Add keeper2 as merchant keeper, then blacklist it
        vm.prank(merchant);
        registry.addMerchantKeeper(keeper2);
        assertTrue(registry.isAuthorised(keeper2, merchant));

        vm.prank(owner);
        registry.blacklistKeeper(keeper2);
        // Blacklist overrides merchant authorisation
        assertFalse(registry.isAuthorised(keeper2, merchant));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // isBlacklisted
    // ─────────────────────────────────────────────────────────────────────────

    function test_IsBlacklisted_ReturnsFalse_ForNonBlacklisted() public view {
        assertFalse(registry.isBlacklisted(keeper1));
        assertFalse(registry.isBlacklisted(stranger));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Ownable2Step
    // ─────────────────────────────────────────────────────────────────────────

    function test_Ownable2Step_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        registry.transferOwnership(newOwner);

        // Still the old owner until accepted
        assertEq(registry.owner(), owner);
        assertEq(registry.pendingOwner(), newOwner);

        vm.prank(newOwner);
        registry.acceptOwnership();

        assertEq(registry.owner(), newOwner);
        assertEq(registry.pendingOwner(), address(0));
    }

    function test_Ownable2Step_OnlyPendingOwner_CanAccept() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        registry.transferOwnership(newOwner);

        vm.prank(stranger);
        vm.expectRevert();
        registry.acceptOwnership();
    }
}
