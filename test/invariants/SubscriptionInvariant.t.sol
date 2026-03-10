// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {SubscriptionManager} from "../../src/SubscriptionManager.sol";
import "../../src/interfaces/ISubscription.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Handler
// ─────────────────────────────────────────────────────────────────────────────

/// @dev Exposes bounded, randomisable actions on SubscriptionManager and
///      accumulates ghost variables that the invariant test contract checks.
contract SubscriptionManagerHandler is Test {
    SubscriptionManager public manager;
    MockERC20 public token;

    address public subscriber;
    address public merchant;

    // Tracked subscription IDs
    uint256 public subIdCount;
    mapping(uint256 => bytes32) public subIdAt;

    // ── Ghost variables (violation flags) ─────────────────────────────────────

    /// @dev Set true if paymentCount increases after a subscription entered a
    ///      terminal state (Cancelled).
    bool public ghost_paymentCountIncreasedAfterTerminal;

    /// @dev Set true if nextPaymentAt ever decreased after a successful collect.
    bool public ghost_nextPaymentDecreased;

    /// @dev Set true if paymentCount ever exceeded maxPayments.
    bool public ghost_paymentCountExceededMax;

    /// @dev Set true if two consecutive collectPayment calls in the same block
    ///      both returned true.
    bool public ghost_doubleCollectSucceeded;

    // ── Per-subscription snapshots ────────────────────────────────────────────

    mapping(bytes32 => bool) public ghost_wasTerminal;
    mapping(bytes32 => uint256) public ghost_lastPaymentCount;
    mapping(bytes32 => uint256) public ghost_lastNextPaymentAt;

    // ── Constants ─────────────────────────────────────────────────────────────

    uint256 constant AMOUNT = 100e18;
    uint48 constant INTERVAL = 1 days;

    constructor(SubscriptionManager _manager, MockERC20 _token) {
        manager = _manager;
        token = _token;
        subscriber = makeAddr("inv_subscriber");
        merchant = makeAddr("inv_merchant");

        token.mint(subscriber, type(uint128).max);
        vm.prank(subscriber);
        token.approve(address(manager), type(uint256).max);
    }

    // ── Exposed handler functions ─────────────────────────────────────────────

    /// @dev Create a new subscription, optionally with a maxPayments cap.
    function createSubscription(uint256 maxPayments) external {
        maxPayments = bound(maxPayments, 0, 10);

        SubscriptionTerms memory terms = SubscriptionTerms({
            token: address(token),
            amount: AMOUNT,
            interval: INTERVAL,
            trialPeriod: 0,
            maxPayments: maxPayments,
            originChainId: block.chainid,
            paymentChainId: block.chainid
        });

        vm.prank(subscriber);
        try manager.subscribe(merchant, terms) returns (bytes32 subId) {
            subIdAt[subIdCount] = subId;
            subIdCount++;
            ghost_lastPaymentCount[subId] = manager.getPaymentCount(subId);
            ghost_lastNextPaymentAt[subId] = manager.nextPaymentDue(subId);
        } catch {}
    }

    /// @dev Warp to the next payment time and attempt to collect.
    function collectPayment(uint256 seed) external {
        if (subIdCount == 0) return;
        bytes32 subId = subIdAt[seed % subIdCount];

        // Skip if subscription is in a terminal persisted state
        Status currentStatus;
        try manager.getStatus(subId) returns (Status s) {
            currentStatus = s;
        } catch {
            return;
        }

        if (currentStatus == Status.Cancelled) {
            ghost_wasTerminal[subId] = true;
        }

        uint256 nextBefore = manager.nextPaymentDue(subId);

        // Warp to payment due if needed
        if (block.timestamp < nextBefore) {
            vm.warp(nextBefore + 1);
        }

        try manager.collectPayment(subId) returns (bool success) {
            if (success) {
                uint256 countAfter = manager.getPaymentCount(subId);
                uint256 nextAfter = manager.nextPaymentDue(subId);

                // nextPaymentAt must be monotonically increasing
                if (nextAfter <= nextBefore) {
                    ghost_nextPaymentDecreased = true;
                }

                // paymentCount must not exceed maxPayments
                SubscriptionTerms memory terms = manager.getTerms(subId);
                if (terms.maxPayments > 0 && countAfter > terms.maxPayments) {
                    ghost_paymentCountExceededMax = true;
                }

                // paymentCount must not increase once the subscription was terminal
                if (ghost_wasTerminal[subId] && countAfter > ghost_lastPaymentCount[subId]) {
                    ghost_paymentCountIncreasedAfterTerminal = true;
                }

                ghost_lastPaymentCount[subId] = countAfter;
                ghost_lastNextPaymentAt[subId] = nextAfter;
            }
        } catch {
            // Revert is expected for expired / cancelled / paused states
        }
    }

    /// @dev Try to collect twice in the same block and flag if the second succeeds.
    function tryDoubleCollect(uint256 seed) external {
        if (subIdCount == 0) return;
        bytes32 subId = subIdAt[seed % subIdCount];

        uint256 nextPay = manager.nextPaymentDue(subId);
        if (block.timestamp < nextPay) vm.warp(nextPay + 1);

        // First collect
        try manager.collectPayment(subId) returns (bool first) {
            if (!first) return;

            // Second collect at the same timestamp — must always fail
            try manager.collectPayment(subId) returns (bool second) {
                if (second) {
                    ghost_doubleCollectSucceeded = true;
                }
            } catch {
                // Expected: PaymentIntervalNotElapsed or SubscriptionNotActive
            }
        } catch {}
    }

    /// @dev Cancel a subscription, marking it terminal in ghost state.
    function cancelSubscription(uint256 seed) external {
        if (subIdCount == 0) return;
        bytes32 subId = subIdAt[seed % subIdCount];

        vm.prank(subscriber);
        try manager.cancelSubscription(subId) {
            ghost_wasTerminal[subId] = true;
            ghost_lastPaymentCount[subId] = manager.getPaymentCount(subId);
        } catch {}
    }

    /// @dev Pause then immediately resume a subscription (exercises both paths).
    function pauseAndResume(uint256 seed) external {
        if (subIdCount == 0) return;
        bytes32 subId = subIdAt[seed % subIdCount];

        vm.prank(subscriber);
        try manager.pauseSubscription(subId) {} catch {}

        vm.prank(subscriber);
        try manager.resumeSubscription(subId) {} catch {}
    }

    /// @dev Deposit ETH for future ETH subscription payments (no-op for ERC-20 tests).
    function depositETH(uint256 amount) external {
        amount = bound(amount, 1, 10 ether);
        vm.deal(subscriber, amount);
        vm.prank(subscriber);
        try manager.depositETH{value: amount}() {} catch {}
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant Test Contract
// ─────────────────────────────────────────────────────────────────────────────

contract SubscriptionInvariantTest is Test {
    SubscriptionManagerHandler public handler;
    SubscriptionManager public manager;
    MockERC20 public token;

    function setUp() public {
        token = new MockERC20();
        // keeperRegistry == address(0): permissionless collection for invariant testing
        manager = new SubscriptionManager(address(0));
        handler = new SubscriptionManagerHandler(manager, token);

        targetContract(address(handler));
    }

    // ─── Invariants ───────────────────────────────────────────────────────────

    /// @dev For any subscription that entered Cancelled state, the payment count
    ///      must never increase afterwards.
    function invariant_StatusConsistency() public view {
        assertFalse(
            handler.ghost_paymentCountIncreasedAfterTerminal(),
            "paymentCount increased after subscription was cancelled"
        );
    }

    /// @dev nextPaymentAt must be strictly greater after each successful
    ///      collectPayment (the clock always moves forward).
    function invariant_NextPaymentMonotonic() public view {
        assertFalse(handler.ghost_nextPaymentDecreased(), "nextPaymentAt decreased after a successful collectPayment");
    }

    /// @dev When maxPayments > 0, paymentCount must never exceed it.
    function invariant_PaymentCountBounded() public view {
        assertFalse(handler.ghost_paymentCountExceededMax(), "paymentCount exceeded maxPayments");
    }

    /// @dev Two consecutive collectPayment calls in the same block must not both
    ///      return true — the time-lock guards against double collection.
    function invariant_NoDoubleCollect() public view {
        assertFalse(
            handler.ghost_doubleCollectSucceeded(),
            "two consecutive collectPayment calls in the same block both succeeded"
        );
    }
}
