// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title KeeperRegistry
/// @author Cadence Protocol
/// @notice Manages the whitelist of addresses authorised to call collectPayment() on
///         SubscriptionManager contracts.
/// @dev Two tiers of keepers are supported:
///      - **Global keepers** (managed by the contract owner): typically the Cadence
///        Automation Service. Authorised to collect payments for any subscription on
///        any SubscriptionManager that references this registry.
///      - **Per-merchant custom keepers** (managed by each merchant): allow protocols
///        to run their own automation infrastructure without depending on Cadence.
///      A blacklist provides an emergency brake to permanently block a compromised keeper
///      without requiring a contract upgrade.
///      SubscriptionManager calls isAuthorised(caller, merchant) for every collectPayment().
/// @custom:security-contact security@cadenceprotocol.build
contract KeeperRegistry is Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ─────────────────────────────────────────────
    // Custom Errors
    // ─────────────────────────────────────────────

    /// @notice Thrown when registering an address that is already registered
    /// @param keeper The duplicate address
    error AlreadyRegistered(address keeper);

    /// @notice Thrown when removing or operating on an address that is not registered
    /// @param keeper The unregistered address
    error NotRegistered(address keeper);

    /// @notice Thrown when attempting to register a blacklisted keeper
    /// @param keeper The blacklisted address
    error KeeperIsBlacklisted(address keeper);

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    /// @notice Emitted when a global keeper is added
    /// @param keeper    Address of the keeper
    /// @param timestamp Block timestamp of the addition
    event KeeperAdded(address indexed keeper, uint256 timestamp);

    /// @notice Emitted when a global keeper is removed
    /// @param keeper    Address of the keeper
    /// @param timestamp Block timestamp of the removal
    event KeeperRemoved(address indexed keeper, uint256 timestamp);

    /// @notice Emitted when a keeper is permanently blacklisted
    /// @param keeper    Address of the keeper
    /// @param timestamp Block timestamp of the blacklist action
    event KeeperBlacklisted(address indexed keeper, uint256 timestamp);

    /// @notice Emitted when a merchant registers a custom keeper
    /// @param merchant Address of the merchant
    /// @param keeper   Address of the keeper being added
    event MerchantKeeperAdded(address indexed merchant, address indexed keeper);

    /// @notice Emitted when a merchant removes a custom keeper
    /// @param merchant Address of the merchant
    /// @param keeper   Address of the keeper being removed
    event MerchantKeeperRemoved(address indexed merchant, address indexed keeper);

    // ─────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────

    /// @dev Set of globally-authorised keeper addresses (Cadence Automation Service)
    EnumerableSet.AddressSet private _globalKeepers;

    /// @dev Per-merchant sets of custom keeper addresses
    mapping(address => EnumerableSet.AddressSet) private _merchantKeepers;

    /// @dev Permanent blacklist — a blacklisted address can never be authorised again
    mapping(address => bool) private _blacklisted;

    // ─────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────

    /// @notice Deploy the KeeperRegistry
    /// @param initialOwner   Address that will own the contract (must call acceptOwnership()
    ///                       if transferred via Ownable2Step)
    /// @param initialKeeper  Optional initial global keeper. Pass address(0) to skip.
    constructor(address initialOwner, address initialKeeper) Ownable(initialOwner) {
        if (initialKeeper != address(0)) {
            _globalKeepers.add(initialKeeper);
            emit KeeperAdded(initialKeeper, block.timestamp);
        }
    }

    // ─────────────────────────────────────────────
    // Global Keeper Management (owner only)
    // ─────────────────────────────────────────────

    /// @notice Add a global keeper, authorised to collect payments for any subscription.
    /// @dev Only callable by the contract owner. Reverts if the address is already
    ///      registered or is blacklisted.
    ///      Emits {KeeperAdded}.
    /// @param keeper Address to register as a global keeper
    function addKeeper(address keeper) external onlyOwner {
        if (keeper == address(0)) revert ZeroAddress();
        if (_blacklisted[keeper]) revert KeeperIsBlacklisted(keeper);
        if (!_globalKeepers.add(keeper)) revert AlreadyRegistered(keeper);
        emit KeeperAdded(keeper, block.timestamp);
    }

    /// @notice Remove a global keeper.
    /// @dev Only callable by the contract owner. Reverts if the address is not registered.
    ///      Emits {KeeperRemoved}.
    /// @param keeper Address to deregister
    function removeKeeper(address keeper) external onlyOwner {
        if (!_globalKeepers.remove(keeper)) revert NotRegistered(keeper);
        emit KeeperRemoved(keeper, block.timestamp);
    }

    /// @notice Permanently blacklist a keeper, preventing it from ever being authorised.
    /// @dev Emergency brake for compromised keeper addresses. The keeper is removed from
    ///      the global set (if present) and can never be re-added. Does not iterate over
    ///      merchant keeper sets — merchants must remove their own blacklisted keepers.
    ///      Only callable by the contract owner.
    ///      Emits {KeeperBlacklisted}.
    /// @param keeper Address to blacklist
    function blacklistKeeper(address keeper) external onlyOwner {
        if (keeper == address(0)) revert ZeroAddress();
        _blacklisted[keeper] = true;
        // Remove from global set if present (ignore return value — may not be registered)
        _globalKeepers.remove(keeper);
        emit KeeperBlacklisted(keeper, block.timestamp);
    }

    // ─────────────────────────────────────────────
    // Merchant Custom Keeper Management
    // ─────────────────────────────────────────────

    /// @notice Register a custom keeper for the calling merchant.
    /// @dev Any address may call this to manage keepers for their own merchant account.
    ///      The registered keeper can collect payments only for subscriptions where
    ///      msg.sender is the merchant. Reverts if the keeper is blacklisted or already
    ///      registered for this merchant.
    ///      Emits {MerchantKeeperAdded}.
    /// @param keeper Address to register as a custom keeper for msg.sender
    function addMerchantKeeper(address keeper) external {
        if (keeper == address(0)) revert ZeroAddress();
        if (_blacklisted[keeper]) revert KeeperIsBlacklisted(keeper);
        if (!_merchantKeepers[msg.sender].add(keeper)) revert AlreadyRegistered(keeper);
        emit MerchantKeeperAdded(msg.sender, keeper);
    }

    /// @notice Remove a custom keeper for the calling merchant.
    /// @dev Reverts if the keeper is not registered for msg.sender.
    ///      Emits {MerchantKeeperRemoved}.
    /// @param keeper Address to deregister
    function removeMerchantKeeper(address keeper) external {
        if (!_merchantKeepers[msg.sender].remove(keeper)) revert NotRegistered(keeper);
        emit MerchantKeeperRemoved(msg.sender, keeper);
    }

    // ─────────────────────────────────────────────
    // Authorisation Check
    // ─────────────────────────────────────────────

    /// @notice Check whether a caller is authorised to collect payments for a given merchant.
    /// @dev Called by SubscriptionManager.collectPayment() on every invocation.
    ///      Returns true if ALL of the following hold:
    ///        1. `caller` is not blacklisted, AND
    ///        2. `caller` is a global keeper OR a custom keeper registered by `merchant`.
    ///      The check is a pure view with no state changes.
    /// @param caller   Address attempting to collect the payment
    /// @param merchant Merchant address associated with the subscription
    /// @return         True if the caller is authorised; false otherwise
    function isAuthorised(address caller, address merchant) external view returns (bool) {
        if (_blacklisted[caller]) return false;
        return _globalKeepers.contains(caller) || _merchantKeepers[merchant].contains(caller);
    }

    /// @notice Global-only authorisation check (no merchant context).
    /// @dev Satisfies the single-parameter IKeeperRegistry interface used by
    ///      SubscriptionManager. Only checks global keepers; per-merchant custom
    ///      keepers are not visible through this function.
    ///      Returns true if `caller` is not blacklisted AND is a registered global keeper.
    /// @param caller Address attempting to collect the payment
    /// @return       True if the caller is a global keeper; false otherwise
    function isAuthorized(address caller) external view returns (bool) {
        if (_blacklisted[caller]) return false;
        return _globalKeepers.contains(caller);
    }

    // ─────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────

    /// @notice Return all currently registered global keepers.
    /// @dev The returned array is a snapshot; it may change between blocks.
    /// @return Array of global keeper addresses
    function getGlobalKeepers() external view returns (address[] memory) {
        return _globalKeepers.values();
    }

    /// @notice Return all custom keepers registered for a given merchant.
    /// @param merchant Merchant address to query
    /// @return         Array of keeper addresses
    function getMerchantKeepers(address merchant) external view returns (address[] memory) {
        return _merchantKeepers[merchant].values();
    }

    /// @notice Check whether an address is permanently blacklisted.
    /// @param keeper Address to query
    /// @return       True if blacklisted; false otherwise
    function isBlacklisted(address keeper) external view returns (bool) {
        return _blacklisted[keeper];
    }
}
