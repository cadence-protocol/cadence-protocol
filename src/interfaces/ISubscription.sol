// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISubscription
/// @author Cadence Protocol
/// @notice Core interface for the Cadence Protocol onchain recurring payments standard
/// @dev Implement this interface to be compatible with the Cadence ERC standard for subscriptions.
///      Supports both ERC-20 token payments and native ETH, with optional cross-chain metadata.
/// @custom:security-contact info@cadenceprotocol.build

// ─────────────────────────────────────────────
// Structs
// ─────────────────────────────────────────────

/// @notice Defines the immutable terms of a subscription agreement
struct SubscriptionTerms {
    /// @dev ERC-20 token used for payment, or address(0) for native ETH
    address token;
    /// @dev Amount charged per payment interval, in the token's smallest unit
    uint256 amount;
    /// @dev Seconds between successive payments (e.g. 2592000 = 30 days)
    uint48 interval;
    /// @dev Free trial duration in seconds before the first payment; 0 = no trial
    uint48 trialPeriod;
    /// @dev Maximum number of payments to collect; 0 = unlimited
    uint256 maxPayments;
    /// @dev Chain ID on which the subscription was originally created
    uint256 originChainId;
    /// @dev Chain ID on which payments are collected
    uint256 paymentChainId;
}

// ─────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────

/// @notice Lifecycle status of a subscription
enum Status {
    Active,
    Paused,
    Cancelled,
    Expired,
    PastDue
}

// ─────────────────────────────────────────────
// Custom Errors
// ─────────────────────────────────────────────

/// @notice Thrown when a subscription ID does not exist
/// @param subId The unknown subscription ID
error SubscriptionNotFound(bytes32 subId);

/// @notice Thrown when an operation requires an active subscription but the current status differs
/// @param subId The subscription ID
/// @param currentStatus The actual status of the subscription
error SubscriptionNotActive(bytes32 subId, Status currentStatus);

/// @notice Thrown when attempting to collect payment before the next payment date
/// @param subId The subscription ID
/// @param nextPaymentAt Unix timestamp of the next valid payment
error PaymentIntervalNotElapsed(bytes32 subId, uint256 nextPaymentAt);

/// @notice Thrown when the caller is not authorised to perform the operation
/// @param caller The address that attempted the call
error UnauthorizedCaller(address caller);

/// @notice Thrown when the subscriber has not approved enough tokens
/// @param subscriber The subscriber address
/// @param required The amount required for the payment
/// @param available The allowance currently granted
error InsufficientAllowance(address subscriber, uint256 required, uint256 available);

/// @notice Thrown when subscription terms contain invalid values
/// @param reason Human-readable description of the validation failure
error InvalidTerms(string reason);

/// @notice Thrown when a payment amount of zero is provided
error ZeroAmount();

/// @notice Thrown when a payment interval of zero is provided
error ZeroInterval();

// ─────────────────────────────────────────────
// Interfaces
// ─────────────────────────────────────────────

/// @title ISubscription
/// @notice Core interface every Cadence Protocol subscription contract must implement
interface ISubscription {
    // ─── Events ────────────────────────────────

    /// @notice Emitted when a new subscription is created
    /// @param subId    Unique identifier for the subscription
    /// @param subscriber Address of the subscriber
    /// @param merchant   Address of the merchant receiving payments
    /// @param terms      The agreed-upon subscription terms
    event SubscriptionCreated(
        bytes32 indexed subId, address indexed subscriber, address indexed merchant, SubscriptionTerms terms
    );

    /// @notice Emitted when a payment is successfully collected
    /// @param subId     Subscription identifier
    /// @param amount    Amount collected in token's smallest unit
    /// @param token     Token address used for payment (address(0) = native ETH)
    /// @param timestamp Unix timestamp of the payment
    event PaymentCollected(bytes32 indexed subId, uint256 amount, address token, uint256 timestamp);

    /// @notice Emitted when a subscription is cancelled
    /// @param subId       Subscription identifier
    /// @param cancelledBy Address that triggered the cancellation
    /// @param timestamp   Unix timestamp of the cancellation
    event SubscriptionCancelled(bytes32 indexed subId, address cancelledBy, uint256 timestamp);

    /// @notice Emitted when a payment attempt fails
    /// @param subId     Subscription identifier
    /// @param timestamp Unix timestamp of the failed attempt
    /// @param reason    Human-readable failure reason
    event PaymentFailed(bytes32 indexed subId, uint256 timestamp, string reason);

    /// @notice Emitted when a subscription is paused
    /// @param subId     Subscription identifier
    /// @param pausedBy  Address that triggered the pause
    /// @param timestamp Unix timestamp of the pause
    event SubscriptionPaused(bytes32 indexed subId, address pausedBy, uint256 timestamp);

    /// @notice Emitted when a paused subscription is resumed
    /// @param subId     Subscription identifier
    /// @param timestamp Unix timestamp of the resumption
    event SubscriptionResumed(bytes32 indexed subId, uint256 timestamp);

    // ─── Core Lifecycle ────────────────────────

    /// @notice Create a new subscription between the caller (subscriber) and a merchant
    /// @dev Emits {SubscriptionCreated}. For native ETH subscriptions the first payment
    ///      (or deposit) may be collected immediately via msg.value.
    /// @param merchant Address of the merchant to subscribe to
    /// @param terms    Agreed subscription terms
    /// @return subId   Unique identifier for the created subscription
    function subscribe(address merchant, SubscriptionTerms calldata terms) external payable returns (bytes32 subId);

    /// @notice Collect the next due payment for a subscription
    /// @dev Reverts with {PaymentIntervalNotElapsed} if called too early.
    ///      Emits {PaymentCollected} on success or {PaymentFailed} on failure.
    /// @param subId   Subscription identifier
    /// @return success True if the payment was collected successfully
    function collectPayment(bytes32 subId) external returns (bool success);

    /// @notice Cancel a subscription, preventing future payments
    /// @dev Callable by the subscriber or the merchant. Emits {SubscriptionCancelled}.
    /// @param subId Subscription identifier
    function cancelSubscription(bytes32 subId) external;

    /// @notice Pause a subscription, temporarily halting payment collection
    /// @dev Emits {SubscriptionPaused}. The interval clock should freeze while paused.
    /// @param subId Subscription identifier
    function pauseSubscription(bytes32 subId) external;

    /// @notice Resume a previously paused subscription
    /// @dev Emits {SubscriptionResumed}. Implementations should reset the next-payment
    ///      timestamp from the time of resumption.
    /// @param subId Subscription identifier
    function resumeSubscription(bytes32 subId) external;

    // ─── View Functions ────────────────────────

    /// @notice Return the current lifecycle status of a subscription
    /// @param subId Subscription identifier
    /// @return      Current {Status} value
    function getStatus(bytes32 subId) external view returns (Status);

    /// @notice Return the Unix timestamp at which the next payment is due
    /// @param subId     Subscription identifier
    /// @return timestamp Unix timestamp of the next payment
    function nextPaymentDue(bytes32 subId) external view returns (uint256 timestamp);

    /// @notice Return the full terms of a subscription
    /// @param subId Subscription identifier
    /// @return      The {SubscriptionTerms} struct for this subscription
    function getTerms(bytes32 subId) external view returns (SubscriptionTerms memory);

    /// @notice Return the subscriber address for a subscription
    /// @param subId Subscription identifier
    /// @return      Address of the subscriber
    function getSubscriber(bytes32 subId) external view returns (address);

    /// @notice Return the merchant address for a subscription
    /// @param subId Subscription identifier
    /// @return      Address of the merchant
    function getMerchant(bytes32 subId) external view returns (address);

    /// @notice Return the total number of payments collected for a subscription
    /// @param subId Subscription identifier
    /// @return      Number of successful payments collected so far
    function getPaymentCount(bytes32 subId) external view returns (uint256);
}

// ─────────────────────────────────────────────
// ERC-165 Interface ID
// ─────────────────────────────────────────────

// ERC-165 interface ID for ISubscription, computed as `type(ISubscription).interfaceId`
bytes4 constant CADENCE_INTERFACE_ID = type(ISubscription).interfaceId;

// ─────────────────────────────────────────────
// Receiver Interface
// ─────────────────────────────────────────────

/// @title ISubscriptionReceiver
/// @author Cadence Protocol
/// @notice Optional interface for merchants that wish to receive callbacks on payment events
/// @dev Implement this interface and register via ERC-165 supportsInterface to opt in to callbacks.
///      Return values must match the function selector to acknowledge the callback.
interface ISubscriptionReceiver {
    /// @notice Called by the subscription contract after a payment is successfully collected
    /// @param subId  Subscription identifier
    /// @param amount Amount collected in token's smallest unit
    /// @param token  Token address (address(0) = native ETH)
    /// @return       Must return `ISubscriptionReceiver.onPaymentCollected.selector`
    function onPaymentCollected(bytes32 subId, uint256 amount, address token) external returns (bytes4);

    /// @notice Called by the subscription contract after a subscription is cancelled
    /// @param subId Subscription identifier
    /// @return      Must return `ISubscriptionReceiver.onSubscriptionCancelled.selector`
    function onSubscriptionCancelled(bytes32 subId) external returns (bytes4);
}
