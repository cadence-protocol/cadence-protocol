// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// No imports required: ISubscriptionTiered does not reference types from ISubscription.sol

/// @title ISubscriptionTiered
/// @author Cadence Protocol
/// @notice Optional extension interface for merchant-defined subscription tiers.
/// @dev Allows merchants to declare multiple pricing plans (e.g. Basic, Pro, Enterprise)
///      on-chain. Tier definitions are merchant-scoped: `tierId` values are unique per
///      merchant address. Subscribers are associated with a tier at subscription creation
///      and may upgrade or downgrade between tiers.
///
///      Tier amount and interval are immutable after creation to protect existing
///      subscribers from unexpected price changes. To change pricing, a merchant must
///      create a new tier and migrate subscribers voluntarily.
///
///      This interface is independent of `ISubscription` — neither requires the other.
///      ERC-165 detection via `SUBSCRIPTION_TIERED_INTERFACE_ID` is the canonical way
///      to check support.
/// @custom:security-contact security@cadenceprotocol.build

// ─────────────────────────────────────────────
// Structs
// ─────────────────────────────────────────────

/// @notice Defines a merchant's subscription plan with its pricing and capacity rules
struct Tier {
    /// @dev Unique identifier for this tier, typically keccak256(merchant, tierName)
    ///      or another merchant-assigned deterministic value
    bytes32 tierId;
    /// @dev Human-readable label for the tier, e.g. "Basic", "Pro", "Enterprise"
    string name;
    /// @dev Payment amount per interval, in the payment token's smallest unit
    uint256 amount;
    /// @dev Payment interval in seconds (e.g. 2592000 = 30 days)
    uint48 interval;
    /// @dev Maximum number of concurrent subscribers on this tier; 0 = unlimited
    uint256 maxSubscribers;
    /// @dev When false, no new subscribers may join this tier; existing subscribers
    ///      retain their association until they upgrade, downgrade, or cancel
    bool active;
    /// @dev IPFS CID or HTTPS URL pointing to off-chain metadata describing this tier's
    ///      features, benefits, and any terms specific to the plan
    string metadataURI;
}

// ─────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────

/// @notice Emitted when a merchant creates a new subscription tier
/// @param merchant  Address of the merchant who owns the tier
/// @param tierId    Unique identifier of the newly created tier
/// @param name      Human-readable name of the tier
/// @param amount    Payment amount per interval for this tier
event TierCreated(address indexed merchant, bytes32 indexed tierId, string name, uint256 amount);

/// @notice Emitted when a merchant updates the metadata URI of an existing tier
/// @param merchant  Address of the merchant who owns the tier
/// @param tierId    Unique identifier of the updated tier
event TierUpdated(address indexed merchant, bytes32 indexed tierId);

/// @notice Emitted when a merchant deactivates a tier, preventing new subscribers
/// @param merchant  Address of the merchant who owns the tier
/// @param tierId    Unique identifier of the deactivated tier
event TierDeactivated(address indexed merchant, bytes32 indexed tierId);

/// @notice Emitted when a subscriber moves to a higher-value tier
/// @param subId      Subscription identifier
/// @param fromTierId Tier the subscriber is leaving
/// @param toTierId   Tier the subscriber is joining
event SubscriberUpgraded(bytes32 indexed subId, bytes32 fromTierId, bytes32 toTierId);

/// @notice Emitted when a subscriber moves to a lower-value tier
/// @param subId      Subscription identifier
/// @param fromTierId Tier the subscriber is leaving
/// @param toTierId   Tier the subscriber is joining
event SubscriberDowngraded(bytes32 indexed subId, bytes32 fromTierId, bytes32 toTierId);

// ─────────────────────────────────────────────
// Custom Errors
// ─────────────────────────────────────────────

/// @notice Thrown when an operation references a tier that does not exist
/// @param tierId The unknown tier identifier
error TierNotFound(bytes32 tierId);

/// @notice Thrown when a new subscriber attempts to join a deactivated tier
/// @param tierId The deactivated tier identifier
error TierNotActive(bytes32 tierId);

/// @notice Thrown when joining a tier that has reached its maximum subscriber limit
/// @param tierId         The tier at capacity
/// @param maxSubscribers The configured maximum number of subscribers
error TierAtCapacity(bytes32 tierId, uint256 maxSubscribers);

/// @notice Thrown when attempting to change a subscriber's tier to the one they are
///         already on
/// @param subId   Subscription identifier
/// @param tierId  The tier the subscriber already holds
error AlreadyOnThisTier(bytes32 subId, bytes32 tierId);

/// @notice Thrown when an address other than the merchant attempts to manage tier
///         definitions
/// @param caller The address that attempted the call
error OnlyMerchantCanManageTiers(address caller);

/// @notice Thrown when a merchant attempts to deactivate a tier that still has active
///         subscribers assigned to it
/// @param tierId      The tier with active subscribers
/// @param activeCount Number of currently active subscribers on this tier
error CannotDeactivateTierWithActiveSubscribers(bytes32 tierId, uint256 activeCount);

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

interface ISubscriptionTiered {
    /// @notice Register a new subscription tier for the calling merchant
    /// @dev `msg.sender` is recorded as the owner of the tier. The implementation
    ///      should derive `tierId` deterministically (e.g. `keccak256(abi.encodePacked(
    ///      msg.sender, name, block.timestamp))`) or accept a caller-supplied value.
    ///      Emits {TierCreated}.
    /// @param name           Human-readable label for the tier
    /// @param amount         Payment amount per interval in the token's smallest unit
    /// @param interval       Payment interval in seconds
    /// @param maxSubscribers Maximum concurrent subscribers; 0 = unlimited
    /// @param metadataURI    IPFS CID or URL to off-chain tier metadata
    /// @return tierId        Unique identifier assigned to the new tier
    function createTier(
        string calldata name,
        uint256 amount,
        uint48 interval,
        uint256 maxSubscribers,
        string calldata metadataURI
    ) external returns (bytes32 tierId);

    /// @notice Update the metadata URI for an existing tier
    /// @dev Only the merchant who owns the tier may call this. Amount and interval
    ///      cannot be changed via this function to protect existing subscribers;
    ///      create a new tier instead if pricing changes are required.
    ///      Emits {TierUpdated}.
    /// @param tierId       Identifier of the tier to update
    /// @param metadataURI  New IPFS CID or URL to off-chain tier metadata
    function updateTierMetadata(bytes32 tierId, string calldata metadataURI) external;

    /// @notice Deactivate a tier so that no new subscribers can join it
    /// @dev Existing subscribers retain their tier association; deactivation only
    ///      prevents new subscriptions from being linked to this tier. Reverts if
    ///      any active subscriber is currently assigned to this tier.
    ///      Emits {TierDeactivated}.
    /// @param tierId  Identifier of the tier to deactivate
    function deactivateTier(bytes32 tierId) external;

    /// @notice Return the full `Tier` struct for a given tier identifier
    /// @dev Reverts with {TierNotFound} if no tier exists for the given identifier.
    /// @param tierId  Identifier of the tier to query
    /// @return        The `Tier` struct containing all plan parameters
    function getTier(bytes32 tierId) external view returns (Tier memory);

    /// @notice Return all tier identifiers registered by a given merchant
    /// @dev Returns both active and inactive tiers. The returned array is a snapshot
    ///      and may change between blocks as tiers are created or deactivated.
    /// @param merchant  Address of the merchant to query
    /// @return          Array of tier identifiers owned by `merchant`
    function getMerchantTiers(address merchant) external view returns (bytes32[] memory);

    /// @notice Return the tier identifier currently associated with a subscription
    /// @dev Returns `bytes32(0)` if the subscription was created without a tier
    ///      association (i.e. the implementing contract predates this extension or the
    ///      subscriber did not select a tier at creation time).
    /// @param subId  Subscription identifier
    /// @return       Tier identifier associated with the subscription
    function getSubscriberTier(bytes32 subId) external view returns (bytes32);

    /// @notice Move a subscriber to a higher-value tier
    /// @dev The subscription's amount and interval are updated to match the new tier
    ///      from the next payment cycle. The current period is not prorated.
    ///      Reverts if `newTierId` is inactive, at capacity, or equal to the current tier.
    ///      Emits {SubscriberUpgraded}.
    /// @param subId      Subscription identifier
    /// @param newTierId  Identifier of the tier to upgrade to
    function upgradeTier(bytes32 subId, bytes32 newTierId) external;

    /// @notice Move a subscriber to a lower-value tier
    /// @dev The subscription's amount and interval are updated to match the new tier
    ///      from the next payment cycle. The current period is not prorated.
    ///      Reverts if `newTierId` is inactive, at capacity, or equal to the current tier.
    ///      Emits {SubscriberDowngraded}.
    /// @param subId      Subscription identifier
    /// @param newTierId  Identifier of the tier to downgrade to
    function downgradeTier(bytes32 subId, bytes32 newTierId) external;
}

// ─────────────────────────────────────────────
// ERC-165 Interface ID
// ─────────────────────────────────────────────

// ERC-165 interface ID for ISubscriptionTiered, computed as `type(ISubscriptionTiered).interfaceId`
bytes4 constant SUBSCRIPTION_TIERED_INTERFACE_ID = type(ISubscriptionTiered).interfaceId;
