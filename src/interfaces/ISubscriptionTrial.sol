// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// No imports required: ISubscriptionTrial does not reference types from ISubscription.sol

/// @title ISubscriptionTrial
/// @author Cadence Protocol
/// @notice Optional extension interface for runtime trial-period management.
/// @dev Extends the base trial semantics defined by `SubscriptionTerms.trialPeriod`.
///      A conforming implementation stores the trial end timestamp per subscription
///      and exposes it for querying and extension. Implementers must emit the
///      corresponding events on every state transition.
///
///      This interface is independent of `ISubscription` — a contract may implement
///      both, but neither requires the other. ERC-165 detection via
///      `SUBSCRIPTION_TRIAL_INTERFACE_ID` is the canonical way to check support.
/// @custom:security-contact security@cadenceprotocol.build

// ─────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────

/// @notice Emitted when a subscription's trial period begins
/// @param subId        Subscription identifier
/// @param trialEndsAt  Unix timestamp at which the trial period expires
event TrialStarted(bytes32 indexed subId, uint256 trialEndsAt);

/// @notice Emitted when a subscription's trial period ends and regular billing begins
/// @param subId     Subscription identifier
/// @param timestamp Unix timestamp at which the trial ended
event TrialEnded(bytes32 indexed subId, uint256 timestamp);

/// @notice Emitted when a merchant extends an active trial period
/// @param subId           Subscription identifier
/// @param extension       Number of seconds added to the current trial end
/// @param newTrialEndsAt  New Unix timestamp at which the extended trial expires
event TrialExtended(bytes32 indexed subId, uint48 extension, uint256 newTrialEndsAt);

// ─────────────────────────────────────────────
// Custom Errors
// ─────────────────────────────────────────────

/// @notice Thrown when a trial-specific operation is attempted on a subscription
///         that is not currently within its trial period
/// @param subId Subscription identifier
error NotInTrial(bytes32 subId);

/// @notice Thrown when an attempt is made to extend a trial that has already ended
/// @param subId Subscription identifier
error TrialAlreadyEnded(bytes32 subId);

/// @notice Thrown when the requested extension would push the trial end beyond
///         the maximum allowed trial duration
/// @param extension   The requested extension in seconds
/// @param maxAllowed  The maximum permitted extension in seconds
error ExtensionExceedsMaxTrial(uint48 extension, uint48 maxAllowed);

/// @notice Thrown when an address other than the merchant attempts to extend a trial
/// @param caller The address that attempted the call
error OnlyMerchantCanExtendTrial(address caller);

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

interface ISubscriptionTrial {
    /// @notice Return whether the given subscription is currently within its trial period
    /// @dev Implementations should compare the current `block.timestamp` against the
    ///      stored trial end timestamp. Returns `false` if no trial was configured or
    ///      if the trial has already elapsed.
    /// @param subId Subscription identifier
    /// @return      `true` if the subscription is in an active trial; `false` otherwise
    function isInTrial(bytes32 subId) external view returns (bool);

    /// @notice Return the Unix timestamp at which the trial period ends
    /// @dev Returns `0` if the subscription was created without a trial period.
    ///      The trial end timestamp is fixed at subscription creation based on
    ///      `SubscriptionTerms.trialPeriod` and may be extended via `extendTrial`.
    /// @param subId Subscription identifier
    /// @return      Unix timestamp of trial expiry, or `0` if no trial exists
    function trialEndsAt(bytes32 subId) external view returns (uint256);

    /// @notice Extend the trial period of an active subscription by `extension` seconds
    /// @dev Only callable by the merchant associated with `subId`. Reverts if the
    ///      trial has already ended. Implementers should add `extension` to the current
    ///      `trialEndsAt` value and update `nextPaymentAt` accordingly so that payment
    ///      collection is deferred to match the new trial end.
    ///      Emits {TrialExtended}.
    /// @param subId      Subscription identifier whose trial is to be extended
    /// @param extension  Additional seconds to add to the current trial end timestamp
    function extendTrial(bytes32 subId, uint48 extension) external;
}

// ─────────────────────────────────────────────
// ERC-165 Interface ID
// ─────────────────────────────────────────────

// ERC-165 interface ID for ISubscriptionTrial, computed as `type(ISubscriptionTrial).interfaceId`
bytes4 constant SUBSCRIPTION_TRIAL_INTERFACE_ID = type(ISubscriptionTrial).interfaceId;
