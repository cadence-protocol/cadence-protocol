// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// No imports required: ISubscriptionHook does not reference types from ISubscription.sol

/// @title ISubscriptionHook
/// @author Cadence Protocol
/// @notice Optional extension interface for merchant-defined dunning and payment-failure
///         handling logic.
/// @dev `ISubscriptionReceiver` (defined in `ISubscription.sol`) handles success events:
///      payment collected and subscription cancelled. `ISubscriptionHook` handles the
///      failure path: payment failed, grace period started, and grace period expired.
///
///      **Architectural separation from SubscriptionManager:**
///      Unlike `ISubscriptionReceiver`, which `SubscriptionManager` calls directly via
///      ERC-165 detection and `try/catch`, `ISubscriptionHook` is intended to be called
///      by the Cadence Automation Service's off-chain Dunning Manager — not by
///      `SubscriptionManager` itself. This separation is intentional and mandatory:
///      `SubscriptionManager` must never block a payment attempt on merchant-defined
///      dunning logic. The Dunning Manager reads `getDunningConfig` off-chain and calls
///      the hook functions on the merchant's contract as part of its retry and
///      cancellation workflow, independently of the core payment flow.
///
///      Merchants implement this interface on their own contracts to define custom
///      dunning policies (retry schedules, grace windows, subscriber notification hints,
///      and cleanup logic) without modifying or subclassing `SubscriptionManager`.
///
///      All callback functions follow the ERC-721/ERC-1155 safe-transfer callback
///      pattern: the return value must equal the function's own selector. The Dunning
///      Manager must verify the return value and treat any other value or revert as
///      an opt-out signal, falling back to protocol-default dunning behaviour.
///
///      This interface does not depend on `ISubscription`. ERC-165 detection via
///      `SUBSCRIPTION_HOOK_INTERFACE_ID` is the canonical way to check support.
/// @custom:security-contact security@cadenceprotocol.build

// ─────────────────────────────────────────────
// Structs
// ─────────────────────────────────────────────

/// @notice Configuration parameters that govern the Dunning Manager's retry and
///         cancellation behaviour for a given subscription
struct DunningConfig {
    /// @dev Seconds after the first payment failure before the Dunning Manager will
    ///      call `cancelSubscription`. A value of 0 means cancellation is immediate
    ///      on first failure (no grace period).
    uint48 gracePeriod;
    /// @dev Maximum number of payment retry attempts the Dunning Manager should make
    ///      during the grace period before invoking `onGracePeriodExpired` and
    ///      cancelling. A value of 0 means no retries — the subscription is cancelled
    ///      after the grace period elapses regardless of subscriber action.
    uint8 maxRetries;
    /// @dev Seconds between successive retry attempts during the grace period.
    ///      Ignored when `maxRetries` is 0.
    uint48 retryInterval;
    /// @dev Hint to the Dunning Manager indicating whether it should attempt to notify
    ///      the subscriber (e.g. via webhook, email, or push notification) when a
    ///      payment fails. Notification delivery is the Dunning Manager's responsibility;
    ///      this field is advisory only.
    bool notifySubscriber;
}

// ─────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────

/// @notice Emitted by the implementing contract when `onPaymentFailed` is successfully
///         processed
/// @param subId       Subscription identifier
/// @param failedAt    Unix timestamp of the failed payment attempt
/// @param retryCount  Number of retries already attempted before this call (0 = first failure)
event PaymentFailedHookCalled(bytes32 indexed subId, uint256 failedAt, uint256 retryCount);

/// @notice Emitted by the implementing contract when `onGracePeriodStarted` is
///         successfully processed
/// @param subId               Subscription identifier
/// @param gracePeriodEndsAt   Unix timestamp at which the grace period expires
event GracePeriodStarted(bytes32 indexed subId, uint256 gracePeriodEndsAt);

/// @notice Emitted by the implementing contract when `onGracePeriodExpired` is
///         successfully processed, immediately before cancellation is triggered
/// @param subId  Subscription identifier
event GracePeriodExpired(bytes32 indexed subId);

/// @notice Emitted by the implementing contract when a merchant updates their dunning
///         configuration
/// @param merchant  Address of the merchant whose configuration was updated
event DunningConfigUpdated(address indexed merchant);

// ─────────────────────────────────────────────
// Interface
// ─────────────────────────────────────────────

interface ISubscriptionHook {
    /// @notice Called by the Dunning Manager when a `collectPayment()` attempt returns
    ///         `false` (soft failure) for the given subscription
    /// @dev The Dunning Manager calls this function after detecting a `PaymentFailed`
    ///      event. Implementations may use this hook to log the failure, update an
    ///      internal ledger, or trigger a subscriber notification.
    ///
    ///      The return value MUST equal `ISubscriptionHook.onPaymentFailed.selector`
    ///      (i.e. `bytes4(keccak256("onPaymentFailed(bytes32,uint256,uint256)"))` =
    ///      `0x____` — the exact value is determined at compile time by the selector).
    ///      Any other return value or a revert is treated by the Dunning Manager as an
    ///      opt-out, and protocol-default failure handling is applied instead.
    ///
    ///      Emits {PaymentFailedHookCalled}.
    /// @param subId       Subscription identifier for the failed payment
    /// @param failedAt    Unix timestamp of the failed collection attempt
    /// @param retryCount  Number of collection retries already attempted (0 = first failure)
    /// @return            Must return `ISubscriptionHook.onPaymentFailed.selector`
    function onPaymentFailed(bytes32 subId, uint256 failedAt, uint256 retryCount) external returns (bytes4);

    /// @notice Called by the Dunning Manager when it begins a grace period for a
    ///         subscription following an initial payment failure
    /// @dev The Dunning Manager calls this once, at the moment the grace period clock
    ///      starts (typically on the first failed collection attempt). Implementations
    ///      may use this hook to suspend service access, send a subscriber notification,
    ///      or update internal billing state.
    ///
    ///      The return value MUST equal `ISubscriptionHook.onGracePeriodStarted.selector`
    ///      (i.e. `bytes4(keccak256("onGracePeriodStarted(bytes32,uint256)"))` —
    ///      the exact value is determined at compile time by the selector).
    ///      Any other return value or a revert is treated by the Dunning Manager as an
    ///      opt-out, and default grace-period behaviour is applied instead.
    ///
    ///      Emits {GracePeriodStarted}.
    /// @param subId               Subscription identifier entering the grace period
    /// @param gracePeriodEndsAt   Unix timestamp at which the grace period expires
    /// @return                    Must return `ISubscriptionHook.onGracePeriodStarted.selector`
    function onGracePeriodStarted(bytes32 subId, uint256 gracePeriodEndsAt) external returns (bytes4);

    /// @notice Called by the Dunning Manager immediately before it calls
    ///         `cancelSubscription()` after a grace period has expired without payment
    /// @dev This is the merchant's last opportunity to perform cleanup, revoke service
    ///      access, or log the cancellation reason before the subscription is permanently
    ///      terminated. The Dunning Manager will call `cancelSubscription()` on the
    ///      `SubscriptionManager` contract regardless of whether this hook reverts.
    ///
    ///      The return value MUST equal `ISubscriptionHook.onGracePeriodExpired.selector`
    ///      (i.e. `bytes4(keccak256("onGracePeriodExpired(bytes32)"))` — the exact value
    ///      is determined at compile time by the selector). Any other return value or a
    ///      revert does not prevent the subsequent `cancelSubscription()` call.
    ///
    ///      Emits {GracePeriodExpired}.
    /// @param subId  Subscription identifier whose grace period has expired
    /// @return       Must return `ISubscriptionHook.onGracePeriodExpired.selector`
    function onGracePeriodExpired(bytes32 subId) external returns (bytes4);

    /// @notice Return the merchant's dunning configuration for a given subscription
    /// @dev The Dunning Manager reads this view function off-chain before processing a
    ///      failed payment to determine the appropriate grace period and retry schedule.
    ///      If the merchant does not implement this interface or if this call reverts,
    ///      the Dunning Manager falls back to protocol-default dunning parameters.
    ///
    ///      Implementations may return different configurations per subscription (e.g.
    ///      longer grace periods for higher-tier subscribers) or a uniform configuration
    ///      for all subscriptions belonging to a given merchant.
    /// @param subId  Subscription identifier to query dunning configuration for
    /// @return       `DunningConfig` struct defining the grace period and retry policy
    function getDunningConfig(bytes32 subId) external view returns (DunningConfig memory);
}

// ─────────────────────────────────────────────
// ERC-165 Interface ID
// ─────────────────────────────────────────────

// ERC-165 interface ID for ISubscriptionHook, computed as `type(ISubscriptionHook).interfaceId`
bytes4 constant SUBSCRIPTION_HOOK_INTERFACE_ID = type(ISubscriptionHook).interfaceId;
