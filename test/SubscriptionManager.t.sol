// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";
import "../src/interfaces/ISubscription.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockKeeperRegistry} from "./mocks/MockKeeperRegistry.sol";
import {MockSubscriptionReceiver, NonERC165Contract} from "./mocks/MockSubscriptionReceiver.sol";

contract SubscriptionManagerTest is Test {
    // ─── Contracts ────────────────────────────────────────────────────────────

    SubscriptionManager public manager;
    MockERC20 public token;
    MockKeeperRegistry public registry;

    // ─── Actors ───────────────────────────────────────────────────────────────

    address public subscriber = makeAddr("subscriber");
    address public merchant   = makeAddr("merchant");
    address public keeper     = makeAddr("keeper");
    address public stranger   = makeAddr("stranger");

    // ─── Constants ────────────────────────────────────────────────────────────

    uint256 constant AMOUNT   = 100e18;
    uint48  constant INTERVAL = 30 days;
    uint48  constant TRIAL    = 7 days;

    // ─── Setup ────────────────────────────────────────────────────────────────

    function setUp() public {
        token    = new MockERC20();
        registry = new MockKeeperRegistry();
        manager  = new SubscriptionManager(address(registry));

        registry.setAuthorized(keeper, true);

        token.mint(subscriber, type(uint128).max);
        vm.prank(subscriber);
        token.approve(address(manager), type(uint256).max);

        vm.deal(subscriber, 100 ether);
        vm.deal(merchant,   10 ether);

        vm.label(address(manager),  "SubscriptionManager");
        vm.label(address(token),    "MockERC20");
        vm.label(address(registry), "MockKeeperRegistry");
        vm.label(subscriber,        "Subscriber");
        vm.label(merchant,          "Merchant");
        vm.label(keeper,            "Keeper");
        vm.label(stranger,          "Stranger");
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function makeTerms(address token_, uint256 amount_, uint48 interval_)
        internal
        view
        returns (SubscriptionTerms memory)
    {
        return SubscriptionTerms({
            token:         token_,
            amount:        amount_,
            interval:      interval_,
            trialPeriod:   0,
            maxPayments:   0,
            originChainId: block.chainid,
            paymentChainId: block.chainid
        });
    }

    function makeEthTerms(uint256 amount_, uint48 interval_)
        internal
        view
        returns (SubscriptionTerms memory)
    {
        return makeTerms(address(0), amount_, interval_);
    }

    function subscribeERC20() internal returns (bytes32) {
        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, INTERVAL);
        vm.prank(subscriber);
        return manager.subscribe(merchant, terms);
    }

    function subscribeERC20WithMax(uint256 maxPayments) internal returns (bytes32) {
        SubscriptionTerms memory terms = SubscriptionTerms({
            token:         address(token),
            amount:        AMOUNT,
            interval:      INTERVAL,
            trialPeriod:   0,
            maxPayments:   maxPayments,
            originChainId: block.chainid,
            paymentChainId: block.chainid
        });
        vm.prank(subscriber);
        return manager.subscribe(merchant, terms);
    }

    function collectAsKeeper(bytes32 subId) internal returns (bool) {
        vm.prank(keeper);
        return manager.collectPayment(subId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ERC-20 Subscribe Tests
    // ─────────────────────────────────────────────────────────────────────────

    function test_Subscribe_ERC20_Success() public {
        uint256 merchantBefore    = token.balanceOf(merchant);
        uint256 subscriberBefore  = token.balanceOf(subscriber);
        uint256 t0                = block.timestamp;

        bytes32 subId = subscribeERC20();

        assertNotEq(subId, bytes32(0));
        assertEq(uint8(manager.getStatus(subId)),  uint8(Status.Active));
        assertEq(manager.nextPaymentDue(subId),    t0 + INTERVAL);
        assertEq(manager.getSubscriber(subId),     subscriber);
        assertEq(manager.getMerchant(subId),       merchant);
        assertEq(manager.getPaymentCount(subId),   1);

        // First payment collected immediately on subscribe
        assertEq(token.balanceOf(merchant),    merchantBefore   + AMOUNT);
        assertEq(token.balanceOf(subscriber),  subscriberBefore - AMOUNT);
    }

    function test_Subscribe_ERC20_WithTrial() public {
        uint256 merchantBefore = token.balanceOf(merchant);
        uint256 t0             = block.timestamp;

        SubscriptionTerms memory terms = SubscriptionTerms({
            token:         address(token),
            amount:        AMOUNT,
            interval:      INTERVAL,
            trialPeriod:   TRIAL,
            maxPayments:   0,
            originChainId: block.chainid,
            paymentChainId: block.chainid
        });

        vm.prank(subscriber);
        bytes32 subId = manager.subscribe(merchant, terms);

        // No payment collected during trial period
        assertEq(token.balanceOf(merchant),  merchantBefore, "no payment during trial");
        assertEq(manager.getPaymentCount(subId), 0);
        assertEq(manager.nextPaymentDue(subId),  t0 + TRIAL);
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Active));
    }

    function test_Subscribe_Reverts_ZeroAmount() public {
        SubscriptionTerms memory terms = makeTerms(address(token), 0, INTERVAL);
        vm.prank(subscriber);
        vm.expectRevert(ZeroAmount.selector);
        manager.subscribe(merchant, terms);
    }

    function test_Subscribe_Reverts_ZeroInterval() public {
        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, 0);
        vm.prank(subscriber);
        vm.expectRevert(ZeroInterval.selector);
        manager.subscribe(merchant, terms);
    }

    function test_Subscribe_Reverts_ZeroMerchant() public {
        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, INTERVAL);
        vm.prank(subscriber);
        vm.expectRevert(abi.encodeWithSelector(InvalidTerms.selector, "merchant cannot be zero address"));
        manager.subscribe(address(0), terms);
    }

    function test_Subscribe_Reverts_InsufficientAllowance() public {
        vm.prank(subscriber);
        token.approve(address(manager), 0);

        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, INTERVAL);
        vm.prank(subscriber);
        vm.expectRevert(
            abi.encodeWithSelector(InsufficientAllowance.selector, subscriber, AMOUNT, uint256(0))
        );
        manager.subscribe(merchant, terms);
    }

    function test_Subscribe_Reverts_TokenNotContract() public {
        // Use an EOA as token address
        SubscriptionTerms memory terms = makeTerms(address(0xdead), AMOUNT, INTERVAL);
        vm.prank(subscriber);
        vm.expectRevert(abi.encodeWithSelector(InvalidTerms.selector, "token must be a contract"));
        manager.subscribe(merchant, terms);
    }

    function test_Subscribe_Reverts_MsgValueWithERC20() public {
        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, INTERVAL);
        vm.prank(subscriber);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidTerms.selector, "msg.value must be 0 for ERC-20 subscription")
        );
        manager.subscribe{value: 1 ether}(merchant, terms);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ETH Subscribe Tests
    // ─────────────────────────────────────────────────────────────────────────

    function test_Subscribe_ETH_Success() public {
        uint256 t0 = block.timestamp;
        SubscriptionTerms memory terms = makeEthTerms(1 ether, INTERVAL);

        vm.prank(subscriber);
        bytes32 subId = manager.subscribe{value: 1 ether}(merchant, terms);

        assertNotEq(subId, bytes32(0));
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Active));
        assertEq(manager.nextPaymentDue(subId),   t0 + INTERVAL);
        assertEq(manager.getPaymentCount(subId),  1);
        // First payment credited to merchant's claimable balance
        assertEq(manager.merchantEthBalance(merchant), 1 ether);
        // Subscriber's deposit is net zero (credited then immediately debited)
        assertEq(manager.ethDepositBalance(subscriber), 0);
    }

    function test_Subscribe_ETH_WrongValue() public {
        SubscriptionTerms memory terms = makeEthTerms(1 ether, INTERVAL);
        vm.prank(subscriber);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidTerms.selector,
                "msg.value must equal terms.amount for ETH subscription without trial"
            )
        );
        manager.subscribe{value: 2 ether}(merchant, terms);
    }

    function test_Subscribe_ETH_WithTrial_CreditsDeposit() public {
        SubscriptionTerms memory terms = SubscriptionTerms({
            token:         address(0),
            amount:        1 ether,
            interval:      INTERVAL,
            trialPeriod:   TRIAL,
            maxPayments:   0,
            originChainId: block.chainid,
            paymentChainId: block.chainid
        });

        // Send ETH during trial — should be credited to deposit, not to merchant
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe{value: 1 ether}(merchant, terms);

        assertEq(manager.getPaymentCount(subId),        0);
        assertEq(manager.merchantEthBalance(merchant),  0);
        assertEq(manager.ethDepositBalance(subscriber), 1 ether);
    }

    function test_Subscribe_ETH_WithTrial_NoValue() public {
        SubscriptionTerms memory terms = SubscriptionTerms({
            token:         address(0),
            amount:        1 ether,
            interval:      INTERVAL,
            trialPeriod:   TRIAL,
            maxPayments:   0,
            originChainId: block.chainid,
            paymentChainId: block.chainid
        });

        // No ETH sent with trial — should succeed with zero deposit
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe{value: 0}(merchant, terms);

        assertEq(manager.getPaymentCount(subId),        0);
        assertEq(manager.ethDepositBalance(subscriber), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ETH Escrow Tests
    // ─────────────────────────────────────────────────────────────────────────

    function test_DepositETH_Success() public {
        vm.prank(subscriber);
        manager.depositETH{value: 2 ether}();
        assertEq(manager.ethDepositBalance(subscriber), 2 ether);
    }

    function test_DepositETH_Reverts_ZeroAmount() public {
        vm.prank(subscriber);
        vm.expectRevert(ZeroAmount.selector);
        manager.depositETH{value: 0}();
    }

    function test_WithdrawETH_Success() public {
        vm.startPrank(subscriber);
        manager.depositETH{value: 3 ether}();
        manager.withdrawETH(1 ether);
        vm.stopPrank();

        assertEq(manager.ethDepositBalance(subscriber), 2 ether);
    }

    function test_WithdrawETH_Reverts_InsufficientBalance() public {
        vm.prank(subscriber);
        manager.depositETH{value: 1 ether}();

        vm.prank(subscriber);
        vm.expectRevert(
            abi.encodeWithSelector(
                SubscriptionManager.InsufficientBalance.selector,
                subscriber, 2 ether, 1 ether
            )
        );
        manager.withdrawETH(2 ether);
    }

    function test_ClaimMerchantETH_Success() public {
        SubscriptionTerms memory terms = makeEthTerms(1 ether, INTERVAL);
        vm.prank(subscriber);
        manager.subscribe{value: 1 ether}(merchant, terms);

        uint256 balanceBefore = merchant.balance;

        vm.prank(merchant);
        manager.claimMerchantETH();

        assertEq(manager.merchantEthBalance(merchant), 0);
        assertEq(merchant.balance, balanceBefore + 1 ether);
    }

    function test_ClaimMerchantETH_Reverts_NoBalance() public {
        vm.prank(merchant);
        vm.expectRevert(
            abi.encodeWithSelector(
                SubscriptionManager.InsufficientBalance.selector,
                merchant, uint256(1), uint256(0)
            )
        );
        manager.claimMerchantETH();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // collectPayment — ERC-20
    // ─────────────────────────────────────────────────────────────────────────

    function test_CollectPayment_Success() public {
        bytes32 subId = subscribeERC20();
        uint256 merchantBefore   = token.balanceOf(merchant);
        uint256 subscriberBefore = token.balanceOf(subscriber);

        vm.warp(block.timestamp + INTERVAL + 1);
        bool success = collectAsKeeper(subId);

        assertTrue(success);
        assertEq(manager.getPaymentCount(subId),    2);
        assertEq(token.balanceOf(merchant),    merchantBefore   + AMOUNT);
        assertEq(token.balanceOf(subscriber),  subscriberBefore - AMOUNT);
    }

    function test_CollectPayment_Reverts_TooEarly() public {
        bytes32 subId  = subscribeERC20();
        uint256 nextPay = manager.nextPaymentDue(subId);

        vm.warp(nextPay - 1);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentIntervalNotElapsed.selector, subId, nextPay)
        );
        manager.collectPayment(subId);
    }

    function test_CollectPayment_Reverts_Cancelled() public {
        bytes32 subId = subscribeERC20();
        vm.prank(subscriber);
        manager.cancelSubscription(subId);

        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(SubscriptionNotActive.selector, subId, Status.Cancelled)
        );
        manager.collectPayment(subId);
    }

    function test_CollectPayment_Reverts_Paused() public {
        bytes32 subId = subscribeERC20();
        vm.prank(subscriber);
        manager.pauseSubscription(subId);

        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(SubscriptionNotActive.selector, subId, Status.Paused)
        );
        manager.collectPayment(subId);
    }

    function test_CollectPayment_Reverts_UnauthorisedCaller() public {
        bytes32 subId = subscribeERC20();
        vm.warp(block.timestamp + INTERVAL + 1);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, stranger));
        manager.collectPayment(subId);
    }

    function test_CollectPayment_SetsStatusPastDue() public {
        bytes32 subId = subscribeERC20();

        // Revoke allowance to force soft-fail
        vm.prank(subscriber);
        token.approve(address(manager), 0);

        vm.warp(block.timestamp + INTERVAL + 1);
        bool success = collectAsKeeper(subId);

        assertFalse(success);
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.PastDue));
    }

    function test_CollectPayment_RecoverFromPastDue() public {
        bytes32 subId = subscribeERC20();

        // Trigger PastDue by revoking allowance
        vm.prank(subscriber);
        token.approve(address(manager), 0);
        vm.warp(block.timestamp + INTERVAL + 1);
        collectAsKeeper(subId);

        assertEq(uint8(manager.getStatus(subId)), uint8(Status.PastDue));

        // Re-approve and collect — nextPaymentAt hasn't advanced, still in the past
        vm.prank(subscriber);
        token.approve(address(manager), type(uint256).max);

        bool success = collectAsKeeper(subId);
        assertTrue(success);
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Active));
        assertEq(manager.getPaymentCount(subId), 2);
    }

    function test_CollectPayment_RespectsMaxPayments() public {
        bytes32 subId = subscribeERC20WithMax(3);
        // paymentCount == 1 after subscribe

        // Collect 2 more times (total 3)
        for (uint256 i = 0; i < 2; i++) {
            vm.warp(block.timestamp + INTERVAL + 1);
            collectAsKeeper(subId);
        }
        assertEq(manager.getPaymentCount(subId), 3);

        // Next attempt hits maxPayments guard — hard revert
        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(SubscriptionNotActive.selector, subId, Status.Expired)
        );
        manager.collectPayment(subId);

        // The status write inside the guard was rolled back with the revert
        // paymentCount is unchanged
        assertEq(manager.getPaymentCount(subId), 3);
    }

    function test_CollectPayment_Reverts_NonExistent() public {
        bytes32 fakeId = bytes32(uint256(0xdead));
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(SubscriptionNotFound.selector, fakeId));
        manager.collectPayment(fakeId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // collectPayment — ETH
    // ─────────────────────────────────────────────────────────────────────────

    function test_CollectPayment_ETH_Success() public {
        SubscriptionTerms memory terms = makeEthTerms(1 ether, INTERVAL);
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe{value: 1 ether}(merchant, terms);

        // Pre-fund for the next payment
        vm.prank(subscriber);
        manager.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + INTERVAL + 1);
        bool success = collectAsKeeper(subId);

        assertTrue(success);
        assertEq(manager.getPaymentCount(subId),       2);
        assertEq(manager.merchantEthBalance(merchant), 2 ether);
        assertEq(manager.ethDepositBalance(subscriber), 0);
    }

    function test_CollectPayment_ETH_SoftFail_InsufficientDeposit() public {
        SubscriptionTerms memory terms = makeEthTerms(1 ether, INTERVAL);
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe{value: 1 ether}(merchant, terms);

        // No additional deposit
        vm.warp(block.timestamp + INTERVAL + 1);
        bool success = collectAsKeeper(subId);

        assertFalse(success);
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.PastDue));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle — cancel / pause / resume
    // ─────────────────────────────────────────────────────────────────────────

    function test_Cancel_BySubscriber() public {
        bytes32 subId = subscribeERC20();

        vm.prank(subscriber);
        manager.cancelSubscription(subId);

        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Cancelled));

        // Further collect attempts must revert
        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(SubscriptionNotActive.selector, subId, Status.Cancelled)
        );
        manager.collectPayment(subId);
    }

    function test_Cancel_ByMerchant() public {
        bytes32 subId = subscribeERC20();

        vm.prank(merchant);
        manager.cancelSubscription(subId);

        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Cancelled));
    }

    function test_Cancel_Reverts_Unauthorised() public {
        bytes32 subId = subscribeERC20();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, stranger));
        manager.cancelSubscription(subId);
    }

    function test_Cancel_Reverts_NonExistent() public {
        bytes32 fakeId = bytes32(uint256(0xbeef));
        vm.expectRevert(abi.encodeWithSelector(SubscriptionNotFound.selector, fakeId));
        manager.cancelSubscription(fakeId);
    }

    function test_Pause_And_Resume() public {
        bytes32 subId = subscribeERC20();

        // Pause
        vm.prank(subscriber);
        manager.pauseSubscription(subId);
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Paused));

        // collectPayment must revert while paused
        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(SubscriptionNotActive.selector, subId, Status.Paused)
        );
        manager.collectPayment(subId);

        // Resume
        vm.prank(subscriber);
        manager.resumeSubscription(subId);
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Active));

        // nextPaymentAt is reset to now + interval from the resume timestamp
        assertEq(manager.nextPaymentDue(subId), block.timestamp + INTERVAL);

        // Collect succeeds after new interval elapses
        vm.warp(block.timestamp + INTERVAL + 1);
        assertTrue(collectAsKeeper(subId));
    }

    function test_Pause_Reverts_NotSubscriber() public {
        bytes32 subId = subscribeERC20();

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, merchant));
        manager.pauseSubscription(subId);
    }

    function test_Pause_Reverts_AlreadyPaused() public {
        bytes32 subId = subscribeERC20();

        vm.prank(subscriber);
        manager.pauseSubscription(subId);

        vm.prank(subscriber);
        vm.expectRevert(
            abi.encodeWithSelector(SubscriptionNotActive.selector, subId, Status.Paused)
        );
        manager.pauseSubscription(subId);
    }

    function test_Resume_Reverts_NotPaused() public {
        bytes32 subId = subscribeERC20();

        vm.prank(subscriber);
        vm.expectRevert(
            abi.encodeWithSelector(SubscriptionNotActive.selector, subId, Status.Active)
        );
        manager.resumeSubscription(subId);
    }

    function test_Resume_Reverts_NotSubscriber() public {
        bytes32 subId = subscribeERC20();

        vm.prank(subscriber);
        manager.pauseSubscription(subId);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, merchant));
        manager.resumeSubscription(subId);
    }

    function test_Pause_Reverts_NonExistent() public {
        bytes32 fakeId = bytes32(uint256(0x1));
        vm.expectRevert(abi.encodeWithSelector(SubscriptionNotFound.selector, fakeId));
        manager.pauseSubscription(fakeId);
    }

    function test_Resume_Reverts_NonExistent() public {
        bytes32 fakeId = bytes32(uint256(0x2));
        vm.expectRevert(abi.encodeWithSelector(SubscriptionNotFound.selector, fakeId));
        manager.resumeSubscription(fakeId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    function test_GetStatus_PastDue_Dynamic() public {
        bytes32 subId = subscribeERC20();

        // Warp past due without collecting
        vm.warp(manager.nextPaymentDue(subId) + 1);

        // getStatus returns PastDue without persisting it
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.PastDue));
    }

    function test_GetTerms() public {
        SubscriptionTerms memory terms = SubscriptionTerms({
            token:          address(token),
            amount:         AMOUNT,
            interval:       INTERVAL,
            trialPeriod:    TRIAL,
            maxPayments:    5,
            originChainId:  block.chainid,
            paymentChainId: block.chainid
        });
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe(merchant, terms);

        SubscriptionTerms memory stored = manager.getTerms(subId);
        assertEq(stored.token,          address(token));
        assertEq(stored.amount,         AMOUNT);
        assertEq(stored.interval,       INTERVAL);
        assertEq(stored.trialPeriod,    TRIAL);
        assertEq(stored.maxPayments,    5);
        assertEq(stored.originChainId,  block.chainid);
        assertEq(stored.paymentChainId, block.chainid);
    }

    function test_ViewFunctions_Revert_NonExistent() public {
        bytes32 fakeId = bytes32(uint256(0xfeed));
        vm.expectRevert(abi.encodeWithSelector(SubscriptionNotFound.selector, fakeId));
        manager.getStatus(fakeId);

        vm.expectRevert(abi.encodeWithSelector(SubscriptionNotFound.selector, fakeId));
        manager.nextPaymentDue(fakeId);

        vm.expectRevert(abi.encodeWithSelector(SubscriptionNotFound.selector, fakeId));
        manager.getTerms(fakeId);

        vm.expectRevert(abi.encodeWithSelector(SubscriptionNotFound.selector, fakeId));
        manager.getSubscriber(fakeId);

        vm.expectRevert(abi.encodeWithSelector(SubscriptionNotFound.selector, fakeId));
        manager.getMerchant(fakeId);

        vm.expectRevert(abi.encodeWithSelector(SubscriptionNotFound.selector, fakeId));
        manager.getPaymentCount(fakeId);
    }

    function test_SubscriberSubscriptions_Index() public {
        bytes32 subId1 = subscribeERC20();
        bytes32 subId2 = subscribeERC20();

        bytes32[] memory subs = manager.subscriberSubscriptions(subscriber);
        assertEq(subs.length, 2);
        assertEq(subs[0], subId1);
        assertEq(subs[1], subId2);
    }

    function test_MerchantSubscriptions_Index() public {
        bytes32 subId1 = subscribeERC20();
        bytes32 subId2 = subscribeERC20();

        bytes32[] memory subs = manager.merchantSubscriptions(merchant);
        assertEq(subs.length, 2);
        assertEq(subs[0], subId1);
        assertEq(subs[1], subId2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ERC-165
    // ─────────────────────────────────────────────────────────────────────────

    function test_SupportsInterface_ISubscription() public view {
        assertTrue(manager.supportsInterface(CADENCE_INTERFACE_ID));
    }

    function test_SupportsInterface_IERC165() public view {
        assertTrue(manager.supportsInterface(0x01ffc9a7));
    }

    function test_SupportsInterface_Random() public view {
        assertFalse(manager.supportsInterface(0xdeadbeef));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Merchant Callback Tests
    // ─────────────────────────────────────────────────────────────────────────

    function test_MerchantCallback_PaymentCollected() public {
        MockSubscriptionReceiver receiver = new MockSubscriptionReceiver();

        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, INTERVAL);
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe(address(receiver), terms);

        // First payment callback fired on subscribe
        assertEq(receiver.paymentCallCount(), 1);
        assertEq(receiver.lastPaymentSubId(), subId);
        assertEq(receiver.lastPaymentAmount(), AMOUNT);
        assertEq(receiver.lastPaymentToken(), address(token));

        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(keeper);
        manager.collectPayment(subId);

        assertEq(receiver.paymentCallCount(), 2);
    }

    function test_MerchantCallback_CancelFired() public {
        MockSubscriptionReceiver receiver = new MockSubscriptionReceiver();

        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, INTERVAL);
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe(address(receiver), terms);

        vm.prank(subscriber);
        manager.cancelSubscription(subId);

        assertEq(receiver.cancelCallCount(),    1);
        assertEq(receiver.lastCancelledSubId(), subId);
    }

    function test_MerchantCallback_RevertDoesNotBlockPayment() public {
        MockSubscriptionReceiver receiver = new MockSubscriptionReceiver();
        receiver.setShouldRevert(true);

        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, INTERVAL);
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe(address(receiver), terms);

        // Despite callback reverting, subscribe should have succeeded
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Active));

        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(keeper);
        bool success = manager.collectPayment(subId);
        // Payment collected even though callback reverted
        assertTrue(success);
    }

    function test_MerchantCallback_RevertDoesNotBlockCancel() public {
        MockSubscriptionReceiver receiver = new MockSubscriptionReceiver();
        receiver.setShouldRevert(true);

        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, INTERVAL);
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe(address(receiver), terms);

        // Cancel must succeed even if merchant callback reverts
        vm.prank(subscriber);
        manager.cancelSubscription(subId);
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Cancelled));
    }

    function test_MerchantCallback_NonERC165Contract_IsSkipped() public {
        // A contract that doesn't implement ERC-165 should not block anything
        NonERC165Contract nc = new NonERC165Contract();

        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, INTERVAL);
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe(address(nc), terms);

        // Should succeed without callback attempt
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Active));

        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(keeper);
        assertTrue(manager.collectPayment(subId));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Keeper Registry Edge Cases
    // ─────────────────────────────────────────────────────────────────────────

    function test_KeeperRegistry_Itself_CanCollect() public {
        // The keeperRegistry contract address itself is always authorised
        bytes32 subId = subscribeERC20();
        vm.warp(block.timestamp + INTERVAL + 1);

        vm.prank(address(registry));
        assertTrue(manager.collectPayment(subId));
    }

    function test_NoRegistryMode_AnyoneCanCollect() public {
        // keeperRegistry == address(0) means permissionless collection
        SubscriptionManager openManager = new SubscriptionManager(address(0));

        token.mint(subscriber, AMOUNT);
        vm.startPrank(subscriber);
        token.approve(address(openManager), type(uint256).max);
        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, INTERVAL);
        bytes32 subId = openManager.subscribe(merchant, terms);
        vm.stopPrank();

        vm.warp(block.timestamp + INTERVAL + 1);

        vm.prank(stranger);
        assertTrue(openManager.collectPayment(subId));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fuzz Tests
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_Subscribe_AnyValidAmount(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        SubscriptionTerms memory terms = makeTerms(address(token), amount, INTERVAL);
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe(merchant, terms);

        assertNotEq(subId, bytes32(0));
        assertEq(uint8(manager.getStatus(subId)), uint8(Status.Active));
        assertEq(manager.getPaymentCount(subId), 1);
    }

    function testFuzz_Subscribe_AnyValidInterval(uint48 interval_) public {
        interval_ = uint48(bound(interval_, 1 hours, 365 days));
        uint256 t0 = block.timestamp;

        SubscriptionTerms memory terms = makeTerms(address(token), AMOUNT, interval_);
        vm.prank(subscriber);
        bytes32 subId = manager.subscribe(merchant, terms);

        assertEq(manager.nextPaymentDue(subId), t0 + interval_);
    }

    function testFuzz_CollectPayment_MultipleRounds(uint8 rounds) public {
        rounds = uint8(bound(rounds, 1, 20));

        bytes32 subId = subscribeERC20WithMax(uint256(rounds));
        // paymentCount == 1 after subscribe

        // Collect rounds-1 more times successfully
        for (uint256 i = 1; i < rounds; i++) {
            vm.warp(block.timestamp + INTERVAL + 1);
            collectAsKeeper(subId);
        }
        assertEq(manager.getPaymentCount(subId), rounds);

        // The next collect attempt must hit the maxPayments guard and revert
        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(SubscriptionNotActive.selector, subId, Status.Expired)
        );
        manager.collectPayment(subId);
    }

    function testFuzz_CannotCollectTwiceInSamePeriod(uint256 warpTime) public {
        bytes32 subId  = subscribeERC20();
        uint256 nextPay = manager.nextPaymentDue(subId);

        // Warp to strictly before the next payment timestamp
        warpTime = bound(warpTime, 0, INTERVAL - 1);
        vm.warp(block.timestamp + warpTime);

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentIntervalNotElapsed.selector, subId, nextPay)
        );
        manager.collectPayment(subId);
    }

    function testFuzz_ETH_AnyDepositAndWithdraw(uint256 depositAmt, uint256 withdrawAmt) public {
        depositAmt  = bound(depositAmt,  1, 50 ether);
        withdrawAmt = bound(withdrawAmt, 1, depositAmt);

        vm.deal(subscriber, depositAmt);

        vm.prank(subscriber);
        manager.depositETH{value: depositAmt}();

        vm.prank(subscriber);
        manager.withdrawETH(withdrawAmt);

        assertEq(manager.ethDepositBalance(subscriber), depositAmt - withdrawAmt);
    }
}
