// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISubscriptionDiscovery
/// @author Cadence Protocol
/// @notice Optional extension interface for an on-chain merchant discovery registry.
/// @dev Allows merchants to register a minimal on-chain presence — name, metadata URI,
///      and registration timestamp — so that subscribers and frontends can discover them
///      without relying solely on off-chain databases.
///
///      Rich metadata (features list, pricing, logo, social links) is intentionally kept
///      off-chain at the `metadataURI` to minimise gas costs. Active subscriber counts
///      and per-merchant subscription lists are not stored on-chain; they are derived
///      from indexed events by off-chain infrastructure such as The Graph.
///
///      A registry owner may mark merchants as `verified` as an optional trust signal.
///      Verification semantics are defined by the registry deployment and are not
///      standardised by this interface.
///
///      This interface is self-contained and does not depend on `ISubscription`.
///      ERC-165 detection via `SUBSCRIPTION_DISCOVERY_INTERFACE_ID` is the canonical
///      way to check support.
/// @custom:security-contact security@cadenceprotocol.build

// ─────────────────────────────────────────────
// Structs
// ─────────────────────────────────────────────

/// @notice Minimal on-chain record for a registered merchant
struct MerchantInfo {
    /// @dev Ethereum address of the registered merchant
    address merchant;
    /// @dev Human-readable display name for the merchant or their service
    string name;
    /// @dev IPFS CID or HTTPS URL pointing to a JSON document containing rich
    ///      merchant metadata (features, pricing plans, logo, contact details)
    string metadataURI;
    /// @dev Unix timestamp at which the merchant first registered
    uint256 registeredAt;
    /// @dev Optional trust signal set by the registry operator; not self-reported
    bool verified;
}

// ─────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────

/// @notice Emitted when a merchant registers for the first time
/// @param merchant     Address of the registering merchant
/// @param name         Display name provided at registration
/// @param metadataURI  URI to off-chain merchant metadata
/// @param timestamp    Unix timestamp of registration
event MerchantRegistered(address indexed merchant, string name, string metadataURI, uint256 timestamp);

/// @notice Emitted when a merchant updates their metadata URI
/// @param merchant       Address of the merchant
/// @param newMetadataURI The updated URI
event MerchantMetadataUpdated(address indexed merchant, string newMetadataURI);

/// @notice Emitted when the registry operator marks a merchant as verified
/// @param merchant  Address of the verified merchant
event MerchantVerified(address indexed merchant);

/// @notice Emitted when a merchant removes their registration from the registry
/// @param merchant  Address of the unregistering merchant
event MerchantUnregistered(address indexed merchant);

// ─────────────────────────────────────────────
// Custom Errors
// ─────────────────────────────────────────────

/// @notice Thrown when an address that is already registered attempts to register again
/// @param merchant The duplicate merchant address
error AlreadyRegistered(address merchant);

/// @notice Thrown when an operation references an address that is not registered
/// @param merchant The unregistered merchant address
error MerchantNotFound(address merchant);

/// @notice Thrown when an empty string is provided where a merchant name is required
error EmptyName();

/// @notice Thrown when an empty string is provided where a metadata URI is required
error EmptyMetadataURI();

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

interface ISubscriptionDiscovery {
    /// @notice Register `msg.sender` as a discoverable merchant in the registry
    /// @dev Reverts if `msg.sender` is already registered, if `name` is empty, or if
    ///      `metadataURI` is empty. The `registeredAt` timestamp is set to
    ///      `block.timestamp` and `verified` defaults to `false`.
    ///      Emits {MerchantRegistered}.
    /// @param name         Human-readable display name for the merchant
    /// @param metadataURI  IPFS CID or URL to off-chain merchant metadata
    function registerMerchant(string calldata name, string calldata metadataURI) external;

    /// @notice Update the metadata URI for `msg.sender`'s registration
    /// @dev Reverts if `msg.sender` is not registered or if `metadataURI` is empty.
    ///      Only the registered merchant address may update their own record.
    ///      Emits {MerchantMetadataUpdated}.
    /// @param metadataURI  New IPFS CID or URL to off-chain merchant metadata
    function updateMetadata(string calldata metadataURI) external;

    /// @notice Remove `msg.sender`'s registration from the registry
    /// @dev Reverts if `msg.sender` is not registered. After unregistration,
    ///      `isRegistered(msg.sender)` returns `false` and `getMerchantInfo` reverts.
    ///      The address may re-register in the future.
    ///      Emits {MerchantUnregistered}.
    function unregisterMerchant() external;

    /// @notice Return the full `MerchantInfo` record for a given merchant address
    /// @dev Reverts with {MerchantNotFound} if the address is not registered.
    /// @param merchant  Address of the merchant to query
    /// @return          The `MerchantInfo` struct for the registered merchant
    function getMerchantInfo(address merchant) external view returns (MerchantInfo memory);

    /// @notice Return whether a given address is currently registered
    /// @param merchant  Address to query
    /// @return          `true` if the address has an active registration; `false` otherwise
    function isRegistered(address merchant) external view returns (bool);

    /// @notice Return a paginated list of registered merchant addresses
    /// @dev Implementations should cap `limit` at 100 to bound gas consumption.
    ///      If `offset + limit` exceeds the total number of merchants, a shorter array
    ///      is returned. Reverts or returns an empty array if `offset >= totalMerchants()`.
    /// @param offset  Zero-based start index into the list of all registered merchants
    /// @param limit   Maximum number of addresses to return (implementations may cap this)
    /// @return        Array of registered merchant addresses for the requested page
    function getMerchants(uint256 offset, uint256 limit) external view returns (address[] memory);

    /// @notice Return the total number of currently registered merchants
    /// @dev Unregistered merchants are excluded from the count.
    /// @return  Total number of active merchant registrations
    function totalMerchants() external view returns (uint256);
}

// ─────────────────────────────────────────────
// ERC-165 Interface ID
// ─────────────────────────────────────────────

// ERC-165 interface ID for ISubscriptionDiscovery, computed as `type(ISubscriptionDiscovery).interfaceId`
bytes4 constant SUBSCRIPTION_DISCOVERY_INTERFACE_ID = type(ISubscriptionDiscovery).interfaceId;
