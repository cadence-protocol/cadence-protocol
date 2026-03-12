// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/ISubscription.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @dev Minimal interface for the KeeperRegistry authorisation check.
///      Any contract that gates keeper access must implement this.
interface IKeeperRegistry {
    /// @notice Returns true if `keeper` is authorised to collect payments
    function isAuthorized(address keeper) external view returns (bool);
}

/// @title SubscriptionManager
/// @author Cadence Protocol
/// @notice Reference implementation of the ISubscription interface for the Cadence Protocol
///         onchain recurring payments standard.
/// @dev Supports both ERC-20 and native ETH subscriptions. ETH subscriptions use a deposit/
///      escrow model: subscribers pre-fund via depositETH() and merchant proceeds accumulate
///      in a claimable balance to avoid re-entrancy risks in collectPayment().
///      Payment collection is gated behind a KeeperRegistry to prevent griefing.
/// @custom:security-contact security@cadenceprotocol.build
contract SubscriptionManager is ISubscription, ERC165, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────
    // Internal Types
    // ─────────────────────────────────────────────

    /// @dev Full runtime state for a single subscription.
    ///      `status` records the last _persisted_ state; PastDue is computed
    ///      dynamically in getStatus() to avoid requiring a keeper status-update tx.
    struct SubscriptionData {
        address subscriber;
        address merchant;
        SubscriptionTerms terms;
        Status status;
        uint256 createdAt;
        uint256 lastPaymentAt;
        uint256 nextPaymentAt;
        uint256 paymentCount;
        bool exists;
    }

    // ─────────────────────────────────────────────
    // Additional Errors
    // ─────────────────────────────────────────────

    /// @notice Thrown when a withdrawal is requested for more than the available balance
    /// @param account   The address that attempted the withdrawal
    /// @param required  Amount requested
    /// @param available Amount actually held
    error InsufficientBalance(address account, uint256 required, uint256 available);

    // ─────────────────────────────────────────────
    // Additional Events
    // ─────────────────────────────────────────────

    /// @notice Emitted when a subscriber deposits ETH for future payments
    /// @param depositor Address that deposited
    /// @param amount    Amount deposited in wei
    event ETHDeposited(address indexed depositor, uint256 amount);

    /// @notice Emitted when ETH is withdrawn from the contract (subscriber or merchant)
    /// @param recipient Address that received ETH
    /// @param amount    Amount withdrawn in wei
    event ETHWithdrawn(address indexed recipient, uint256 amount);

    // ─────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────

    /// @dev Core subscription records, keyed by subId
    mapping(bytes32 => SubscriptionData) private _subscriptions;

    /// @dev Index of all subscription IDs per subscriber address
    mapping(address => bytes32[]) private _subscriberSubscriptions;

    /// @dev Index of all subscription IDs per merchant address
    mapping(address => bytes32[]) private _merchantSubscriptions;

    /// @dev Pre-funded ETH balances keyed by subscriber address.
    ///      Debited on every ETH collectPayment.
    mapping(address => uint256) private _ethDeposits;

    /// @dev Accumulated ETH payment proceeds per merchant.
    ///      Claimed via claimMerchantETH() — pull model avoids re-entrancy.
    mapping(address => uint256) private _merchantEthBalances;

    /// @notice Address of the KeeperRegistry contract that authorises payment collectors.
    ///         If address(0), collectPayment is permissionless (test/development only).
    address public keeperRegistry;

    /// @dev Monotonic nonce used in subId derivation to guarantee uniqueness
    uint256 private _nonce;

    // ─────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────

    /// @notice Deploy a new SubscriptionManager
    /// @param keeperRegistry_ Address of the KeeperRegistry. Pass address(0) to
    ///                        disable keeper gating (not recommended for production).
    constructor(address keeperRegistry_) {
        keeperRegistry = keeperRegistry_;
    }

    // ─────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────

    /// @dev Reverts unless msg.sender is the keeperRegistry itself or is whitelisted by it.
    ///      When keeperRegistry is address(0) the check is skipped.
    modifier onlyAuthorizedKeeper() {
        _checkKeeperAuth();
        _;
    }

    /// @dev Reverts with SubscriptionNotFound if subId does not exist
    modifier onlyExistingSubscription(bytes32 subId) {
        if (!_subscriptions[subId].exists) revert SubscriptionNotFound(subId);
        _;
    }

    // ─────────────────────────────────────────────
    // ETH Escrow — Subscriber Side
    // ─────────────────────────────────────────────

    /// @notice Deposit ETH to pre-fund one or more native ETH subscriptions.
    /// @dev The deposited balance is shared across all ETH subscriptions held by
    ///      msg.sender. Call this before the next payment date to avoid PastDue status.
    ///      Emits {ETHDeposited}.
    function depositETH() external payable {
        if (msg.value == 0) revert ZeroAmount();
        _ethDeposits[msg.sender] += msg.value;
        emit ETHDeposited(msg.sender, msg.value);
    }

    /// @notice Withdraw unused ETH deposits back to the caller.
    /// @dev Follows checks-effects-interactions. Emits {ETHWithdrawn}.
    /// @param amount Amount to withdraw in wei
    function withdrawETH(uint256 amount) external nonReentrant {
        uint256 available = _ethDeposits[msg.sender];
        if (available < amount) revert InsufficientBalance(msg.sender, amount, available);

        // Effect
        _ethDeposits[msg.sender] -= amount;

        // Interaction
        emit ETHWithdrawn(msg.sender, amount);
        (bool sent,) = msg.sender.call{value: amount}("");
        require(sent, "ETH withdrawal failed");
    }

    // ─────────────────────────────────────────────
    // ETH Escrow — Merchant Side
    // ─────────────────────────────────────────────

    /// @notice Claim all accumulated ETH payment proceeds for the calling merchant.
    /// @dev Pull model: merchant proceeds are credited to an internal balance by
    ///      collectPayment() rather than pushed directly, eliminating re-entrancy risk.
    ///      Emits {ETHWithdrawn}.
    function claimMerchantETH() external nonReentrant {
        uint256 amount = _merchantEthBalances[msg.sender];
        if (amount == 0) revert InsufficientBalance(msg.sender, 1, 0);

        // Effect
        _merchantEthBalances[msg.sender] = 0;

        // Interaction
        emit ETHWithdrawn(msg.sender, amount);
        (bool sent,) = msg.sender.call{value: amount}("");
        require(sent, "ETH claim failed");
    }

    // ─────────────────────────────────────────────
    // Core Lifecycle — ISubscription
    // ─────────────────────────────────────────────

    /// @notice Create a new recurring subscription between the caller and a merchant.
    /// @dev For ERC-20 subscriptions, the caller must have approved this contract for at
    ///      least `terms.amount`. For ETH subscriptions without a trial, `msg.value` must
    ///      equal `terms.amount` — the first payment is collected immediately. For ETH
    ///      subscriptions with a trial, any `msg.value` is credited to the subscriber's
    ///      deposit balance for use when the first payment becomes due.
    ///      Emits {SubscriptionCreated} and, if no trial, {PaymentCollected}.
    /// @param merchant Address of the merchant to subscribe to
    /// @param terms    Subscription terms agreed by both parties
    /// @return subId   Unique deterministic subscription identifier
    function subscribe(address merchant, SubscriptionTerms calldata terms)
        external
        payable
        nonReentrant
        returns (bytes32 subId)
    {
        _validateTerms(terms, merchant);

        address subscriber = msg.sender;

        // ── ERC-20 pre-flight ──────────────────────────────────────────────────
        if (terms.token != address(0)) {
            if (msg.value != 0) revert InvalidTerms("msg.value must be 0 for ERC-20 subscription");
            uint256 allowance = IERC20(terms.token).allowance(subscriber, address(this));
            if (allowance < terms.amount) {
                revert InsufficientAllowance(subscriber, terms.amount, allowance);
            }
        }

        // ── ETH pre-flight (no trial only) ────────────────────────────────────
        if (terms.token == address(0) && terms.trialPeriod == 0) {
            if (msg.value != terms.amount) {
                revert InvalidTerms("msg.value must equal terms.amount for ETH subscription without trial");
            }
        }

        // ── Derive subscription ID ─────────────────────────────────────────────
        subId = keccak256(abi.encodePacked(subscriber, merchant, block.timestamp, block.chainid, _nonce++));

        // ── Compute timing ────────────────────────────────────────────────────
        uint256 now_ = block.timestamp;
        bool hasTrial = terms.trialPeriod > 0;

        // nextPaymentAt: after trial if trial exists, otherwise one full interval from now
        uint256 nextPaymentAt_ = hasTrial ? now_ + terms.trialPeriod : now_ + terms.interval;

        // ── Effects: store subscription ───────────────────────────────────────
        _subscriptions[subId] = SubscriptionData({
            subscriber: subscriber,
            merchant: merchant,
            terms: terms,
            status: Status.Active,
            createdAt: now_,
            lastPaymentAt: hasTrial ? 0 : now_,
            nextPaymentAt: nextPaymentAt_,
            paymentCount: hasTrial ? 0 : 1,
            exists: true
        });

        _subscriberSubscriptions[subscriber].push(subId);
        _merchantSubscriptions[merchant].push(subId);

        emit SubscriptionCreated(subId, subscriber, merchant, terms);

        // ── Interactions: collect first payment if no trial ───────────────────
        if (!hasTrial) {
            if (terms.token == address(0)) {
                // ETH: msg.value == terms.amount (validated above).
                // Credit then immediately debit — keeps ETH accounting consistent.
                _ethDeposits[subscriber] += msg.value;
                _ethDeposits[subscriber] -= terms.amount;
                _merchantEthBalances[merchant] += terms.amount;
                emit PaymentCollected(subId, terms.amount, address(0), now_);
                _notifyPaymentCollected(merchant, subId, terms.amount, address(0));
            } else {
                // ERC-20: transfer directly from subscriber to merchant
                IERC20(terms.token).safeTransferFrom(subscriber, merchant, terms.amount);
                emit PaymentCollected(subId, terms.amount, terms.token, now_);
                _notifyPaymentCollected(merchant, subId, terms.amount, terms.token);
            }
        } else {
            // Trial: no payment now. Credit any ETH sent to subscriber deposit.
            if (terms.token == address(0) && msg.value > 0) {
                _ethDeposits[subscriber] += msg.value;
                emit ETHDeposited(subscriber, msg.value);
            }
        }
    }

    /// @notice Collect the next due payment for a subscription.
    /// @dev Caller must be authorised by the KeeperRegistry. Reverts if the payment
    ///      interval has not yet elapsed. For ERC-20 subscriptions, an insufficient
    ///      allowance results in a soft failure (status → PastDue, returns false) rather
    ///      than a hard revert, allowing a dunning manager to handle retries. For ETH
    ///      subscriptions the same soft-fail applies when the deposit balance is too low.
    ///      Emits {PaymentCollected} on success or {PaymentFailed} on soft failure.
    /// @param subId Subscription identifier
    /// @return success True if the payment was collected; false on soft failure
    function collectPayment(bytes32 subId)
        external
        nonReentrant
        onlyExistingSubscription(subId)
        onlyAuthorizedKeeper
        returns (bool success)
    {
        SubscriptionData storage sub = _subscriptions[subId];

        // Terminal-state guard
        Status stored = sub.status;
        if (stored == Status.Paused || stored == Status.Cancelled || stored == Status.Expired) {
            revert SubscriptionNotActive(subId, stored);
        }

        // Time-lock guard
        if (block.timestamp < sub.nextPaymentAt) {
            revert PaymentIntervalNotElapsed(subId, sub.nextPaymentAt);
        }

        // Max-payments guard: soft-fail so the status change persists on-chain.
        // Hard-reverting here would roll back the Expired status write, leaving the
        // subscription stuck in Active/PastDue and causing keepers to retry forever.
        if (sub.terms.maxPayments > 0 && sub.paymentCount >= sub.terms.maxPayments) {
            sub.status = Status.Expired;
            emit SubscriptionExpired(subId, block.timestamp);
            return false;
        }

        if (sub.terms.token == address(0)) {
            return _collectETHPayment(subId, sub);
        } else {
            return _collectERC20Payment(subId, sub);
        }
    }

    /// @notice Cancel a subscription, permanently preventing future payment collection.
    /// @dev Callable by either the subscriber or the merchant. If the merchant implements
    ///      {ISubscriptionReceiver}, onSubscriptionCancelled is called in a try/catch so
    ///      a reverting callback cannot prevent cancellation.
    ///      Emits {SubscriptionCancelled}.
    /// @param subId Subscription identifier
    function cancelSubscription(bytes32 subId) external nonReentrant onlyExistingSubscription(subId) {
        SubscriptionData storage sub = _subscriptions[subId];

        if (msg.sender != sub.subscriber && msg.sender != sub.merchant) {
            revert UnauthorizedCaller(msg.sender);
        }

        // Effect
        sub.status = Status.Cancelled;
        address merchant = sub.merchant;

        emit SubscriptionCancelled(subId, msg.sender, block.timestamp);

        // Interaction: optional merchant callback
        _notifyCancelled(merchant, subId);
    }

    /// @notice Pause a subscription, freezing the payment interval clock.
    /// @dev Only the subscriber may pause. Reverts if the subscription is not Active.
    ///      Emits {SubscriptionPaused}.
    /// @param subId Subscription identifier
    function pauseSubscription(bytes32 subId) external onlyExistingSubscription(subId) {
        SubscriptionData storage sub = _subscriptions[subId];

        if (msg.sender != sub.subscriber) revert UnauthorizedCaller(msg.sender);
        if (sub.status != Status.Active) revert SubscriptionNotActive(subId, sub.status);

        sub.status = Status.Paused;
        emit SubscriptionPaused(subId, msg.sender, block.timestamp);
    }

    /// @notice Resume a paused subscription.
    /// @dev Only the subscriber may resume. Resets nextPaymentAt to
    ///      block.timestamp + interval from the moment of resumption.
    ///      Emits {SubscriptionResumed}.
    /// @param subId Subscription identifier
    function resumeSubscription(bytes32 subId) external onlyExistingSubscription(subId) {
        SubscriptionData storage sub = _subscriptions[subId];

        if (msg.sender != sub.subscriber) revert UnauthorizedCaller(msg.sender);
        if (sub.status != Status.Paused) revert SubscriptionNotActive(subId, sub.status);

        sub.status = Status.Active;
        sub.nextPaymentAt = block.timestamp + sub.terms.interval;

        emit SubscriptionResumed(subId, block.timestamp);
    }

    // ─────────────────────────────────────────────
    // View Functions — ISubscription
    // ─────────────────────────────────────────────

    /// @notice Return the current lifecycle status of a subscription.
    /// @dev PastDue is derived dynamically: if the stored status is Active but
    ///      block.timestamp > nextPaymentAt, PastDue is returned without writing state.
    /// @param subId Subscription identifier
    /// @return      Current {Status}
    function getStatus(bytes32 subId) external view onlyExistingSubscription(subId) returns (Status) {
        SubscriptionData storage sub = _subscriptions[subId];
        if (sub.status == Status.Active && block.timestamp > sub.nextPaymentAt) {
            return Status.PastDue;
        }
        return sub.status;
    }

    /// @notice Return the Unix timestamp at which the next payment is due.
    /// @param subId     Subscription identifier
    /// @return timestamp Unix timestamp of the next payment
    function nextPaymentDue(bytes32 subId) external view onlyExistingSubscription(subId) returns (uint256 timestamp) {
        return _subscriptions[subId].nextPaymentAt;
    }

    /// @notice Return the full terms of a subscription.
    /// @param subId Subscription identifier
    /// @return      The {SubscriptionTerms} struct
    function getTerms(bytes32 subId) external view onlyExistingSubscription(subId) returns (SubscriptionTerms memory) {
        return _subscriptions[subId].terms;
    }

    /// @notice Return the subscriber address for a subscription.
    /// @param subId Subscription identifier
    /// @return      Address of the subscriber
    function getSubscriber(bytes32 subId) external view onlyExistingSubscription(subId) returns (address) {
        return _subscriptions[subId].subscriber;
    }

    /// @notice Return the merchant address for a subscription.
    /// @param subId Subscription identifier
    /// @return      Address of the merchant
    function getMerchant(bytes32 subId) external view onlyExistingSubscription(subId) returns (address) {
        return _subscriptions[subId].merchant;
    }

    /// @notice Return the total number of successful payments collected.
    /// @param subId Subscription identifier
    /// @return      Payment count
    function getPaymentCount(bytes32 subId) external view onlyExistingSubscription(subId) returns (uint256) {
        return _subscriptions[subId].paymentCount;
    }

    // ─────────────────────────────────────────────
    // Additional View Functions
    // ─────────────────────────────────────────────

    /// @notice Return the pre-funded ETH deposit balance for an address.
    /// @param depositor Address to query
    /// @return          ETH balance in wei
    function ethDepositBalance(address depositor) external view returns (uint256) {
        return _ethDeposits[depositor];
    }

    /// @notice Return the claimable ETH proceeds balance for a merchant.
    /// @param merchant Merchant address to query
    /// @return         ETH balance in wei
    function merchantEthBalance(address merchant) external view returns (uint256) {
        return _merchantEthBalances[merchant];
    }

    /// @notice Return all subscription IDs associated with a subscriber.
    /// @param subscriber Address to query
    /// @return           Array of subIds
    function subscriberSubscriptions(address subscriber) external view returns (bytes32[] memory) {
        return _subscriberSubscriptions[subscriber];
    }

    /// @notice Return all subscription IDs associated with a merchant.
    /// @param merchant Address to query
    /// @return         Array of subIds
    function merchantSubscriptions(address merchant) external view returns (bytes32[] memory) {
        return _merchantSubscriptions[merchant];
    }

    // ─────────────────────────────────────────────
    // ERC-165
    // ─────────────────────────────────────────────

    /// @inheritdoc ERC165
    /// @dev Returns true for ISubscription.interfaceId and IERC165.interfaceId.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ISubscription).interfaceId || super.supportsInterface(interfaceId);
    }

    // ─────────────────────────────────────────────
    // Internal — Payment Execution
    // ─────────────────────────────────────────────

    /// @dev Collect a single ETH payment. Soft-fails (PastDue + PaymentFailed event,
    ///      returns false) if the subscriber's deposit balance is insufficient.
    function _collectETHPayment(bytes32 subId, SubscriptionData storage sub) internal returns (bool) {
        uint256 available = _ethDeposits[sub.subscriber];
        if (available < sub.terms.amount) {
            sub.status = Status.PastDue;
            emit PaymentFailed(subId, block.timestamp, "insufficient ETH deposit");
            return false;
        }

        // ── Effects ────────────────────────────────────────────────────────────
        _ethDeposits[sub.subscriber] -= sub.terms.amount;
        _merchantEthBalances[sub.merchant] += sub.terms.amount;
        sub.paymentCount += 1;
        sub.lastPaymentAt = block.timestamp;
        sub.nextPaymentAt = block.timestamp + sub.terms.interval;
        sub.status = Status.Active;

        address merchant = sub.merchant;
        uint256 amount = sub.terms.amount;

        // ── Interactions ───────────────────────────────────────────────────────
        emit PaymentCollected(subId, amount, address(0), block.timestamp);
        _notifyPaymentCollected(merchant, subId, amount, address(0));

        return true;
    }

    /// @dev Collect a single ERC-20 payment. Soft-fails (PastDue + PaymentFailed event,
    ///      returns false) if the subscriber's allowance is insufficient.
    function _collectERC20Payment(bytes32 subId, SubscriptionData storage sub) internal returns (bool) {
        uint256 allowance = IERC20(sub.terms.token).allowance(sub.subscriber, address(this));
        if (allowance < sub.terms.amount) {
            sub.status = Status.PastDue;
            emit PaymentFailed(subId, block.timestamp, "insufficient allowance");
            return false;
        }

        // Cache before writes to avoid re-reading storage after state changes
        address subscriber = sub.subscriber;
        address merchant = sub.merchant;
        address token = sub.terms.token;
        uint256 amount = sub.terms.amount;

        // ── Effects ────────────────────────────────────────────────────────────
        sub.paymentCount += 1;
        sub.lastPaymentAt = block.timestamp;
        sub.nextPaymentAt = block.timestamp + sub.terms.interval;
        sub.status = Status.Active;

        // ── Interactions ───────────────────────────────────────────────────────
        IERC20(token).safeTransferFrom(subscriber, merchant, amount);
        emit PaymentCollected(subId, amount, token, block.timestamp);
        _notifyPaymentCollected(merchant, subId, amount, token);

        return true;
    }

    // ─────────────────────────────────────────────
    // Internal — Merchant Callbacks
    // ─────────────────────────────────────────────

    /// @dev Attempt to call ISubscriptionReceiver.onPaymentCollected on `merchant`.
    ///      If the merchant does not support ISubscriptionReceiver or the call reverts,
    ///      the failure is silently swallowed — the callback must never block payment.
    function _notifyPaymentCollected(address merchant, bytes32 subId, uint256 amount, address token) internal {
        if (!_supportsReceiverInterface(merchant)) return;
        try ISubscriptionReceiver(merchant).onPaymentCollected(subId, amount, token) {} catch {}
    }

    /// @dev Attempt to call ISubscriptionReceiver.onSubscriptionCancelled on `merchant`.
    ///      Failures are silently swallowed — the callback must never block cancellation.
    function _notifyCancelled(address merchant, bytes32 subId) internal {
        if (!_supportsReceiverInterface(merchant)) return;
        try ISubscriptionReceiver(merchant).onSubscriptionCancelled(subId) {} catch {}
    }

    /// @dev Returns true if `target` is a contract that declares support for
    ///      ISubscriptionReceiver via ERC-165. EOAs and non-compliant contracts return false.
    function _supportsReceiverInterface(address target) internal view returns (bool) {
        if (target.code.length == 0) return false;
        try IERC165(target).supportsInterface(type(ISubscriptionReceiver).interfaceId) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }

    // ─────────────────────────────────────────────
    // Internal — Validation & Auth
    // ─────────────────────────────────────────────

    /// @dev Validates subscription terms, reverting with a specific error on each failure.
    function _validateTerms(SubscriptionTerms calldata terms, address merchant) internal view {
        if (terms.amount == 0) revert ZeroAmount();
        if (terms.interval == 0) revert ZeroInterval();
        if (merchant == address(0)) revert InvalidTerms("merchant cannot be zero address");
        if (terms.token != address(0) && terms.token.code.length == 0) {
            revert InvalidTerms("token must be a contract");
        }
    }

    /// @dev Reverts with UnauthorizedCaller unless msg.sender is authorised.
    ///      Authorisation is skipped entirely when keeperRegistry == address(0).
    function _checkKeeperAuth() internal view {
        if (keeperRegistry == address(0)) return;
        bool authorized = msg.sender == keeperRegistry || IKeeperRegistry(keeperRegistry).isAuthorized(msg.sender);
        if (!authorized) revert UnauthorizedCaller(msg.sender);
    }
}
