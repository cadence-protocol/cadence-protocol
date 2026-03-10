# Cadence Protocol — Test Cases

These test cases define the normative behaviour that any conforming `ISubscription` implementation must satisfy, independent of programming language or smart-contract toolchain. Each entry is derived directly from a scenario encoded in the Foundry reference test suite contained in this repository (`test/SubscriptionManager.t.sol`, `test/KeeperRegistry.t.sol`, `test/invariants/SubscriptionInvariant.t.sol`).

## Summary Table

| TC-ID | Title | Category | Type |
|-------|-------|----------|------|
| TC-01 | ERC-20 subscribe succeeds and collects first payment immediately | Subscribe | Unit |
| TC-02 | ERC-20 subscribe with trial defers first payment | Subscribe | Unit |
| TC-03 | subscribe reverts when amount is zero | Subscribe | Unit |
| TC-04 | subscribe reverts when interval is zero | Subscribe | Unit |
| TC-05 | subscribe reverts when merchant is the zero address | Subscribe | Unit |
| TC-06 | subscribe reverts when ERC-20 allowance is insufficient | Subscribe | Unit |
| TC-07 | subscribe reverts when token address is not a contract | Subscribe | Unit |
| TC-08 | subscribe reverts when msg.value is non-zero for ERC-20 | Subscribe | Unit |
| TC-09 | ETH subscribe succeeds and credits first payment to merchant | Subscribe | Unit |
| TC-10 | ETH subscribe reverts when msg.value does not equal terms.amount | Subscribe | Unit |
| TC-11 | ETH subscribe with trial credits deposit to subscriber, not merchant | Subscribe | Unit |
| TC-12 | ETH subscribe with trial and zero msg.value succeeds | Subscribe | Unit |
| TC-13 | depositETH credits subscriber's deposit balance | ETH Escrow | Unit |
| TC-14 | depositETH reverts when msg.value is zero | ETH Escrow | Unit |
| TC-15 | withdrawETH decrements subscriber's deposit balance | ETH Escrow | Unit |
| TC-16 | withdrawETH reverts when requested amount exceeds deposit balance | ETH Escrow | Unit |
| TC-17 | claimMerchantETH transfers accrued ETH to merchant | ETH Escrow | Unit |
| TC-18 | claimMerchantETH reverts when merchant has no accrued balance | ETH Escrow | Unit |
| TC-19 | collectPayment transfers token and increments payment count | CollectPayment | Unit |
| TC-20 | collectPayment reverts before the next payment timestamp | CollectPayment | Unit |
| TC-21 | collectPayment reverts on a cancelled subscription | CollectPayment | Unit |
| TC-22 | collectPayment reverts on a paused subscription | CollectPayment | Unit |
| TC-23 | collectPayment reverts for an unauthorised caller | CollectPayment | Unit |
| TC-24 | collectPayment soft-fails and sets PastDue when allowance is zero | CollectPayment | Unit |
| TC-25 | collectPayment succeeds after recovering from PastDue status | CollectPayment | Unit |
| TC-26 | collectPayment reverts when maxPayments cap is reached | CollectPayment | Unit |
| TC-27 | collectPayment reverts for a non-existent subscription ID | CollectPayment | Unit |
| TC-28 | ETH collectPayment succeeds when subscriber has sufficient deposit | CollectPayment | Unit |
| TC-29 | ETH collectPayment soft-fails and sets PastDue on insufficient deposit | CollectPayment | Unit |
| TC-30 | subscriber can cancel their own subscription | Cancel | Unit |
| TC-31 | merchant can cancel a subscription | Cancel | Unit |
| TC-32 | cancelSubscription reverts for an unauthorised caller | Cancel | Unit |
| TC-33 | cancelSubscription reverts for a non-existent subscription | Cancel | Unit |
| TC-34 | subscriber can pause and resume a subscription | Pause/Resume | Unit |
| TC-35 | pauseSubscription reverts when caller is not the subscriber | Pause/Resume | Unit |
| TC-36 | pauseSubscription reverts when subscription is already paused | Pause/Resume | Unit |
| TC-37 | resumeSubscription reverts when subscription is not paused | Pause/Resume | Unit |
| TC-38 | resumeSubscription reverts when caller is not the subscriber | Pause/Resume | Unit |
| TC-39 | pauseSubscription reverts for a non-existent subscription | Pause/Resume | Unit |
| TC-40 | resumeSubscription reverts for a non-existent subscription | Pause/Resume | Unit |
| TC-41 | constructor sets the owner | KeeperRegistry | Unit |
| TC-42 | constructor registers the initial keeper | KeeperRegistry | Unit |
| TC-43 | constructor with zero initialKeeper produces an empty global set | KeeperRegistry | Unit |
| TC-44 | addKeeper adds a keeper to the global set | KeeperRegistry | Unit |
| TC-45 | addKeeper reverts when caller is not the owner | KeeperRegistry | Unit |
| TC-46 | addKeeper reverts when keeper address is zero | KeeperRegistry | Unit |
| TC-47 | addKeeper reverts when keeper is already registered | KeeperRegistry | Unit |
| TC-48 | addKeeper reverts when keeper is blacklisted | KeeperRegistry | Unit |
| TC-49 | removeKeeper removes a keeper from the global set | KeeperRegistry | Unit |
| TC-50 | removeKeeper reverts when caller is not the owner | KeeperRegistry | Unit |
| TC-51 | removeKeeper reverts when keeper is not registered | KeeperRegistry | Unit |
| TC-52 | blacklistKeeper blocks isAuthorised for that keeper | KeeperRegistry | Unit |
| TC-53 | blacklistKeeper removes the keeper from the global set | KeeperRegistry | Unit |
| TC-54 | blacklistKeeper succeeds for an address not in the global set | KeeperRegistry | Unit |
| TC-55 | blacklistKeeper reverts when keeper address is zero | KeeperRegistry | Unit |
| TC-56 | blacklistKeeper reverts when caller is not the owner | KeeperRegistry | Unit |
| TC-57 | blacklisted keeper cannot be re-added via addKeeper | KeeperRegistry | Unit |
| TC-58 | merchant can add a keeper scoped to their own subscriptions | KeeperRegistry | Unit |
| TC-59 | removeMerchantKeeper revokes authorisation for that merchant | KeeperRegistry | Unit |
| TC-60 | addMerchantKeeper reverts when keeper is already registered for that merchant | KeeperRegistry | Unit |
| TC-61 | addMerchantKeeper reverts when keeper address is zero | KeeperRegistry | Unit |
| TC-62 | addMerchantKeeper reverts when keeper is blacklisted | KeeperRegistry | Unit |
| TC-63 | removeMerchantKeeper reverts when keeper is not registered for that merchant | KeeperRegistry | Unit |
| TC-64 | global keeper is authorised for any merchant | KeeperRegistry | Unit |
| TC-65 | non-keeper address returns false from isAuthorised | KeeperRegistry | Unit |
| TC-66 | blacklisted global keeper returns false from isAuthorised | KeeperRegistry | Unit |
| TC-67 | blacklisted merchant keeper returns false from isAuthorised | KeeperRegistry | Unit |
| TC-68 | isBlacklisted returns false for addresses never blacklisted | KeeperRegistry | Unit |
| TC-69 | ownership transfer follows the two-step accept pattern | KeeperRegistry | Unit |
| TC-70 | only the pending owner can accept an ownership transfer | KeeperRegistry | Unit |
| TC-71 | subscribe accepts any non-zero amount within uint128 bounds | Subscribe | Fuzz |
| TC-72 | nextPaymentDue equals subscribe time plus interval for any valid interval | Subscribe | Fuzz |
| TC-73 | paymentCount reaches exactly maxPayments then collectPayment reverts | CollectPayment | Fuzz |
| TC-74 | collectPayment reverts for any warp time strictly before nextPaymentAt | CollectPayment | Fuzz |
| TC-75 | withdrawETH leaves correct residual balance for any deposit/withdraw pair | ETH Escrow | Fuzz |
| TC-76 | payment count never increases after a subscription enters Cancelled state | Invariant | Invariant |
| TC-77 | nextPaymentAt is strictly greater after every successful collectPayment | Invariant | Invariant |
| TC-78 | payment count never exceeds maxPayments when a cap is set | Invariant | Invariant |
| TC-79 | two consecutive collectPayment calls in the same block cannot both succeed | Invariant | Invariant |

---

## Group A — subscribe() [ERC-20]

### TC-01: ERC-20 subscribe succeeds and collects first payment immediately

**Category:** Subscribe
**Requirement:** `subscribe(address merchant, SubscriptionTerms calldata terms)`
**Type:** Unit

**Preconditions:**
- Subscriber holds sufficient ERC-20 token balance.
- Subscriber has approved the contract for at least `terms.amount`.
- `terms.trialPeriod` is zero.

**Action:**
- Subscriber calls `subscribe(merchant, terms)` with a valid ERC-20 token, non-zero amount, and non-zero interval.

**Expected outcome:**
- Returns a non-zero `bytes32` subscription ID.
- Subscription status is `Active`.
- `nextPaymentDue` equals `block.timestamp + terms.interval`.
- `getSubscriber` and `getMerchant` return the correct addresses.
- `getPaymentCount` returns `1` (first payment collected at subscription time).
- `terms.amount` tokens are transferred from subscriber to merchant immediately.
- `SubscriptionCreated` and `PaymentCollected` events are emitted.

---

### TC-02: ERC-20 subscribe with trial defers first payment

**Category:** Subscribe
**Requirement:** `subscribe(address merchant, SubscriptionTerms calldata terms)`
**Type:** Unit

**Preconditions:**
- `terms.trialPeriod > 0`.
- Subscriber holds sufficient allowance.

**Action:**
- Subscriber calls `subscribe(merchant, terms)` with a non-zero `trialPeriod`.

**Expected outcome:**
- Returns a non-zero subscription ID.
- Subscription status is `Active`.
- `nextPaymentDue` equals `block.timestamp + terms.trialPeriod` (not `+ interval`).
- `getPaymentCount` returns `0` (no payment collected during trial).
- Merchant token balance is unchanged.
- `SubscriptionCreated` event is emitted; `PaymentCollected` is not.

---

### TC-03: subscribe reverts when amount is zero

**Category:** Subscribe
**Requirement:** `subscribe` — validation of `terms.amount`
**Type:** Unit

**Preconditions:**
- `terms.amount` is `0`.

**Action:**
- Subscriber calls `subscribe(merchant, terms)`.

**Expected outcome:**
- Reverts with `ZeroAmount`.

---

### TC-04: subscribe reverts when interval is zero

**Category:** Subscribe
**Requirement:** `subscribe` — validation of `terms.interval`
**Type:** Unit

**Preconditions:**
- `terms.interval` is `0`.

**Action:**
- Subscriber calls `subscribe(merchant, terms)`.

**Expected outcome:**
- Reverts with `ZeroInterval`.

---

### TC-05: subscribe reverts when merchant is the zero address

**Category:** Subscribe
**Requirement:** `subscribe` — validation of `merchant`
**Type:** Unit

**Preconditions:**
- `merchant` argument is `address(0)`.

**Action:**
- Subscriber calls `subscribe(address(0), terms)`.

**Expected outcome:**
- Reverts with `InvalidTerms("merchant cannot be zero address")`.

---

### TC-06: subscribe reverts when ERC-20 allowance is insufficient

**Category:** Subscribe
**Requirement:** `subscribe` — allowance check at subscription time
**Type:** Unit

**Preconditions:**
- `terms.token` is a valid ERC-20 contract.
- Subscriber's allowance for the contract is `0`, less than `terms.amount`.
- `terms.trialPeriod` is zero (first payment is due immediately).

**Action:**
- Subscriber calls `subscribe(merchant, terms)`.

**Expected outcome:**
- Reverts with `InsufficientAllowance(subscriber, terms.amount, 0)`.

---

### TC-07: subscribe reverts when token address is not a contract

**Category:** Subscribe
**Requirement:** `subscribe` — validation of `terms.token`
**Type:** Unit

**Preconditions:**
- `terms.token` is set to an externally-owned account (EOA) address.

**Action:**
- Subscriber calls `subscribe(merchant, terms)`.

**Expected outcome:**
- Reverts with `InvalidTerms("token must be a contract")`.

---

### TC-08: subscribe reverts when msg.value is non-zero for ERC-20

**Category:** Subscribe
**Requirement:** `subscribe` — ERC-20 / ETH mutual exclusion
**Type:** Unit

**Preconditions:**
- `terms.token` is a valid ERC-20 contract address (not `address(0)`).
- Call is sent with `msg.value > 0`.

**Action:**
- Subscriber calls `subscribe{value: 1 ether}(merchant, terms)`.

**Expected outcome:**
- Reverts with `InvalidTerms("msg.value must be 0 for ERC-20 subscription")`.

---

## Group B — subscribe() [ETH]

### TC-09: ETH subscribe succeeds and credits first payment to merchant

**Category:** Subscribe
**Requirement:** `subscribe` — native ETH payment path
**Type:** Unit

**Preconditions:**
- `terms.token` is `address(0)` (native ETH).
- `terms.trialPeriod` is zero.
- `msg.value` equals `terms.amount`.

**Action:**
- Subscriber calls `subscribe{value: terms.amount}(merchant, terms)`.

**Expected outcome:**
- Returns a non-zero subscription ID.
- Subscription status is `Active`.
- `nextPaymentDue` equals `block.timestamp + terms.interval`.
- `getPaymentCount` returns `1`.
- `merchantEthBalance(merchant)` increases by `terms.amount`.
- `ethDepositBalance(subscriber)` is zero (credited then immediately debited).

---

### TC-10: ETH subscribe reverts when msg.value does not equal terms.amount

**Category:** Subscribe
**Requirement:** `subscribe` — ETH amount validation without trial
**Type:** Unit

**Preconditions:**
- `terms.token` is `address(0)`.
- `terms.trialPeriod` is zero.
- `msg.value != terms.amount`.

**Action:**
- Subscriber calls `subscribe{value: terms.amount * 2}(merchant, terms)`.

**Expected outcome:**
- Reverts with `InvalidTerms("msg.value must equal terms.amount for ETH subscription without trial")`.

---

### TC-11: ETH subscribe with trial credits deposit to subscriber, not merchant

**Category:** Subscribe
**Requirement:** `subscribe` — ETH trial period handling
**Type:** Unit

**Preconditions:**
- `terms.token` is `address(0)`.
- `terms.trialPeriod > 0`.
- Subscriber sends `msg.value = terms.amount`.

**Action:**
- Subscriber calls `subscribe{value: terms.amount}(merchant, terms)`.

**Expected outcome:**
- Returns a non-zero subscription ID.
- `getPaymentCount` returns `0`.
- `merchantEthBalance(merchant)` is unchanged (zero increase).
- `ethDepositBalance(subscriber)` equals `terms.amount`.

---

### TC-12: ETH subscribe with trial and zero msg.value succeeds

**Category:** Subscribe
**Requirement:** `subscribe` — ETH trial period, no upfront deposit required
**Type:** Unit

**Preconditions:**
- `terms.token` is `address(0)`.
- `terms.trialPeriod > 0`.
- Subscriber sends `msg.value = 0`.

**Action:**
- Subscriber calls `subscribe{value: 0}(merchant, terms)`.

**Expected outcome:**
- Returns a non-zero subscription ID.
- `getPaymentCount` returns `0`.
- `ethDepositBalance(subscriber)` is zero.
- No revert.

---

## Group C — ETH Escrow

### TC-13: depositETH credits subscriber's deposit balance

**Category:** ETH Escrow
**Requirement:** `depositETH()`
**Type:** Unit

**Preconditions:**
- Subscriber holds sufficient native ETH.

**Action:**
- Subscriber calls `depositETH{value: 2 ether}()`.

**Expected outcome:**
- `ethDepositBalance(subscriber)` equals `2 ether`.
- `ETHDeposited` event emitted.

---

### TC-14: depositETH reverts when msg.value is zero

**Category:** ETH Escrow
**Requirement:** `depositETH()` — zero-value guard
**Type:** Unit

**Preconditions:**
- None.

**Action:**
- Subscriber calls `depositETH{value: 0}()`.

**Expected outcome:**
- Reverts with `ZeroAmount`.

---

### TC-15: withdrawETH decrements subscriber's deposit balance

**Category:** ETH Escrow
**Requirement:** `withdrawETH(uint256 amount)`
**Type:** Unit

**Preconditions:**
- Subscriber has previously deposited `3 ether`.

**Action:**
- Subscriber calls `withdrawETH(1 ether)`.

**Expected outcome:**
- `ethDepositBalance(subscriber)` equals `2 ether`.
- `1 ether` is transferred back to the subscriber.
- `ETHWithdrawn` event emitted.

---

### TC-16: withdrawETH reverts when requested amount exceeds deposit balance

**Category:** ETH Escrow
**Requirement:** `withdrawETH(uint256 amount)` — balance guard
**Type:** Unit

**Preconditions:**
- Subscriber's deposit balance is `1 ether`.

**Action:**
- Subscriber calls `withdrawETH(2 ether)`.

**Expected outcome:**
- Reverts with `InsufficientBalance(subscriber, 2 ether, 1 ether)`.

---

### TC-17: claimMerchantETH transfers accrued ETH to merchant

**Category:** ETH Escrow
**Requirement:** `claimMerchantETH()`
**Type:** Unit

**Preconditions:**
- A native ETH subscription was created without a trial, so `merchantEthBalance(merchant)` is `terms.amount`.

**Action:**
- Merchant calls `claimMerchantETH()`.

**Expected outcome:**
- `merchantEthBalance(merchant)` becomes `0`.
- Merchant's native ETH balance increases by the previously accrued amount.

---

### TC-18: claimMerchantETH reverts when merchant has no accrued balance

**Category:** ETH Escrow
**Requirement:** `claimMerchantETH()` — zero-balance guard
**Type:** Unit

**Preconditions:**
- `merchantEthBalance(merchant)` is `0`.

**Action:**
- Merchant calls `claimMerchantETH()`.

**Expected outcome:**
- Reverts with `InsufficientBalance(merchant, 1, 0)`.

---

## Group D — collectPayment()

### TC-19: collectPayment transfers token and increments payment count

**Category:** CollectPayment
**Requirement:** `collectPayment(bytes32 subId)`
**Type:** Unit

**Preconditions:**
- An active ERC-20 subscription exists.
- `block.timestamp >= nextPaymentDue(subId)`.
- Caller is an authorised keeper.
- Subscriber has sufficient allowance.

**Action:**
- Keeper calls `collectPayment(subId)`.

**Expected outcome:**
- Returns `true`.
- `getPaymentCount(subId)` increments by `1`.
- `terms.amount` tokens transferred from subscriber to merchant.
- `nextPaymentDue(subId)` advances by `terms.interval`.
- `PaymentCollected` event emitted.

---

### TC-20: collectPayment reverts before the next payment timestamp

**Category:** CollectPayment
**Requirement:** `collectPayment` — time-lock guard
**Type:** Unit

**Preconditions:**
- An active subscription exists.
- `block.timestamp < nextPaymentDue(subId)`.

**Action:**
- Keeper calls `collectPayment(subId)`.

**Expected outcome:**
- Reverts with `PaymentIntervalNotElapsed(subId, nextPaymentDue(subId))`.

---

### TC-21: collectPayment reverts on a cancelled subscription

**Category:** CollectPayment
**Requirement:** `collectPayment` — terminal-state guard
**Type:** Unit

**Preconditions:**
- Subscription status is `Cancelled`.

**Action:**
- Keeper calls `collectPayment(subId)` after the payment interval has elapsed.

**Expected outcome:**
- Reverts with `SubscriptionNotActive(subId, Status.Cancelled)`.

---

### TC-22: collectPayment reverts on a paused subscription

**Category:** CollectPayment
**Requirement:** `collectPayment` — terminal-state guard
**Type:** Unit

**Preconditions:**
- Subscription status is `Paused`.

**Action:**
- Keeper calls `collectPayment(subId)` after the payment interval has elapsed.

**Expected outcome:**
- Reverts with `SubscriptionNotActive(subId, Status.Paused)`.

---

### TC-23: collectPayment reverts for an unauthorised caller

**Category:** CollectPayment
**Requirement:** `collectPayment` — keeper authorisation
**Type:** Unit

**Preconditions:**
- A keeper registry is configured (not `address(0)`).
- Caller is neither the registry contract nor a registered keeper.
- Payment interval has elapsed.

**Action:**
- Unauthorised address calls `collectPayment(subId)`.

**Expected outcome:**
- Reverts with `UnauthorizedCaller(caller)`.

---

### TC-24: collectPayment soft-fails and sets PastDue when allowance is zero

**Category:** CollectPayment
**Requirement:** `collectPayment` — soft failure on insufficient ERC-20 allowance
**Type:** Unit

**Preconditions:**
- An active ERC-20 subscription exists.
- Subscriber's allowance has been revoked (set to `0`).
- Payment interval has elapsed.

**Action:**
- Keeper calls `collectPayment(subId)`.

**Expected outcome:**
- Returns `false`.
- Subscription status becomes `PastDue`.
- `PaymentFailed` event emitted.
- No tokens transferred.

---

### TC-25: collectPayment succeeds after recovering from PastDue status

**Category:** CollectPayment
**Requirement:** `collectPayment` — recovery from PastDue
**Type:** Unit

**Preconditions:**
- Subscription status is `PastDue` (soft-fail was previously triggered).
- Subscriber has re-approved the contract for sufficient allowance.
- `nextPaymentAt` is still in the past (not advanced by the failed collect).

**Action:**
- Keeper calls `collectPayment(subId)` again without warping time.

**Expected outcome:**
- Returns `true`.
- Subscription status returns to `Active`.
- `getPaymentCount` increments by `1`.
- Tokens transferred to merchant.

---

### TC-26: collectPayment reverts when maxPayments cap is reached

**Category:** CollectPayment
**Requirement:** `collectPayment` — `maxPayments` enforcement
**Type:** Unit

**Preconditions:**
- `terms.maxPayments = N > 0`.
- `getPaymentCount(subId)` equals `N`.
- Payment interval has elapsed.

**Action:**
- Keeper calls `collectPayment(subId)`.

**Expected outcome:**
- Reverts with `SubscriptionNotActive(subId, Status.Expired)`.
- `getPaymentCount(subId)` remains `N` (the attempted status write is rolled back with the revert).

---

### TC-27: collectPayment reverts for a non-existent subscription ID

**Category:** CollectPayment
**Requirement:** `collectPayment` — existence guard
**Type:** Unit

**Preconditions:**
- No subscription exists for the given ID.

**Action:**
- Keeper calls `collectPayment(fakeId)`.

**Expected outcome:**
- Reverts with `SubscriptionNotFound(fakeId)`.

---

### TC-28: ETH collectPayment succeeds when subscriber has sufficient deposit

**Category:** CollectPayment
**Requirement:** `collectPayment` — native ETH payment path
**Type:** Unit

**Preconditions:**
- An active native ETH subscription exists.
- Subscriber has deposited at least `terms.amount` into the escrow.
- Payment interval has elapsed.

**Action:**
- Keeper calls `collectPayment(subId)`.

**Expected outcome:**
- Returns `true`.
- `merchantEthBalance(merchant)` increases by `terms.amount`.
- `ethDepositBalance(subscriber)` decreases by `terms.amount`.
- `getPaymentCount(subId)` increments by `1`.

---

### TC-29: ETH collectPayment soft-fails and sets PastDue on insufficient deposit

**Category:** CollectPayment
**Requirement:** `collectPayment` — soft failure on insufficient ETH deposit
**Type:** Unit

**Preconditions:**
- An active native ETH subscription exists.
- Subscriber's deposit balance is less than `terms.amount`.
- Payment interval has elapsed.

**Action:**
- Keeper calls `collectPayment(subId)`.

**Expected outcome:**
- Returns `false`.
- Subscription status becomes `PastDue`.
- `PaymentFailed` event emitted.
- `merchantEthBalance` unchanged.

---

## Group E — cancelSubscription() / pauseSubscription() / resumeSubscription()

### TC-30: subscriber can cancel their own subscription

**Category:** Cancel
**Requirement:** `cancelSubscription(bytes32 subId)`
**Type:** Unit

**Preconditions:**
- An active subscription exists.
- Caller is the subscriber.

**Action:**
- Subscriber calls `cancelSubscription(subId)`.

**Expected outcome:**
- `getStatus(subId)` returns `Cancelled`.
- Subsequent `collectPayment` calls revert with `SubscriptionNotActive(subId, Status.Cancelled)`.
- `SubscriptionCancelled` event emitted.

---

### TC-31: merchant can cancel a subscription

**Category:** Cancel
**Requirement:** `cancelSubscription(bytes32 subId)`
**Type:** Unit

**Preconditions:**
- An active subscription exists.
- Caller is the merchant.

**Action:**
- Merchant calls `cancelSubscription(subId)`.

**Expected outcome:**
- `getStatus(subId)` returns `Cancelled`.

---

### TC-32: cancelSubscription reverts for an unauthorised caller

**Category:** Cancel
**Requirement:** `cancelSubscription` — caller authorisation
**Type:** Unit

**Preconditions:**
- An active subscription exists.
- Caller is neither the subscriber nor the merchant.

**Action:**
- Third-party address calls `cancelSubscription(subId)`.

**Expected outcome:**
- Reverts with `UnauthorizedCaller(caller)`.

---

### TC-33: cancelSubscription reverts for a non-existent subscription

**Category:** Cancel
**Requirement:** `cancelSubscription` — existence guard
**Type:** Unit

**Preconditions:**
- No subscription exists for the given ID.

**Action:**
- Any caller calls `cancelSubscription(fakeId)`.

**Expected outcome:**
- Reverts with `SubscriptionNotFound(fakeId)`.

---

### TC-34: subscriber can pause and resume a subscription

**Category:** Pause/Resume
**Requirement:** `pauseSubscription` / `resumeSubscription`
**Type:** Unit

**Preconditions:**
- An active subscription exists.
- Caller is the subscriber.

**Action:**
1. Subscriber calls `pauseSubscription(subId)`.
2. Subscriber calls `resumeSubscription(subId)`.

**Expected outcome:**
- After step 1: status is `Paused`; `collectPayment` reverts with `SubscriptionNotActive(subId, Status.Paused)`.
- After step 2: status is `Active`; `nextPaymentDue` equals `block.timestamp + terms.interval` (reset from resume time).
- `collectPayment` succeeds once the new interval elapses.
- `SubscriptionPaused` and `SubscriptionResumed` events emitted respectively.

---

### TC-35: pauseSubscription reverts when caller is not the subscriber

**Category:** Pause/Resume
**Requirement:** `pauseSubscription` — subscriber-only guard
**Type:** Unit

**Preconditions:**
- An active subscription exists.
- Caller is the merchant (not the subscriber).

**Action:**
- Merchant calls `pauseSubscription(subId)`.

**Expected outcome:**
- Reverts with `UnauthorizedCaller(merchant)`.

---

### TC-36: pauseSubscription reverts when subscription is already paused

**Category:** Pause/Resume
**Requirement:** `pauseSubscription` — state guard
**Type:** Unit

**Preconditions:**
- Subscription status is `Paused`.

**Action:**
- Subscriber calls `pauseSubscription(subId)` again.

**Expected outcome:**
- Reverts with `SubscriptionNotActive(subId, Status.Paused)`.

---

### TC-37: resumeSubscription reverts when subscription is not paused

**Category:** Pause/Resume
**Requirement:** `resumeSubscription` — state guard
**Type:** Unit

**Preconditions:**
- Subscription status is `Active`.

**Action:**
- Subscriber calls `resumeSubscription(subId)`.

**Expected outcome:**
- Reverts with `SubscriptionNotActive(subId, Status.Active)`.

---

### TC-38: resumeSubscription reverts when caller is not the subscriber

**Category:** Pause/Resume
**Requirement:** `resumeSubscription` — subscriber-only guard
**Type:** Unit

**Preconditions:**
- Subscription status is `Paused`.
- Caller is the merchant.

**Action:**
- Merchant calls `resumeSubscription(subId)`.

**Expected outcome:**
- Reverts with `UnauthorizedCaller(merchant)`.

---

### TC-39: pauseSubscription reverts for a non-existent subscription

**Category:** Pause/Resume
**Requirement:** `pauseSubscription` — existence guard
**Type:** Unit

**Preconditions:**
- No subscription exists for the given ID.

**Action:**
- Any caller calls `pauseSubscription(fakeId)`.

**Expected outcome:**
- Reverts with `SubscriptionNotFound(fakeId)`.

---

### TC-40: resumeSubscription reverts for a non-existent subscription

**Category:** Pause/Resume
**Requirement:** `resumeSubscription` — existence guard
**Type:** Unit

**Preconditions:**
- No subscription exists for the given ID.

**Action:**
- Any caller calls `resumeSubscription(fakeId)`.

**Expected outcome:**
- Reverts with `SubscriptionNotFound(fakeId)`.

---

## Group F — KeeperRegistry

### TC-41: constructor sets the owner

**Category:** KeeperRegistry
**Requirement:** `KeeperRegistry` constructor
**Type:** Unit

**Preconditions:**
- Contract is being deployed.

**Action:**
- Deploy `KeeperRegistry(owner, initialKeeper)`.

**Expected outcome:**
- `owner()` returns the supplied `owner` address.

---

### TC-42: constructor registers the initial keeper

**Category:** KeeperRegistry
**Requirement:** `KeeperRegistry` constructor — initial keeper registration
**Type:** Unit

**Preconditions:**
- `initialKeeper != address(0)`.

**Action:**
- Deploy `KeeperRegistry(owner, initialKeeper)`.

**Expected outcome:**
- `getGlobalKeepers()` returns an array of length `1` containing `initialKeeper`.

---

### TC-43: constructor with zero initialKeeper produces an empty global set

**Category:** KeeperRegistry
**Requirement:** `KeeperRegistry` constructor — optional initial keeper
**Type:** Unit

**Preconditions:**
- `initialKeeper == address(0)`.

**Action:**
- Deploy `KeeperRegistry(owner, address(0))`.

**Expected outcome:**
- `getGlobalKeepers().length` equals `0`.

---

### TC-44: addKeeper adds a keeper to the global set

**Category:** KeeperRegistry
**Requirement:** `addKeeper(address keeper)`
**Type:** Unit

**Preconditions:**
- Caller is the owner.
- Keeper is not already registered and not blacklisted.

**Action:**
- Owner calls `addKeeper(newKeeper)`.

**Expected outcome:**
- `getGlobalKeepers()` includes `newKeeper`.
- `isAuthorised(newKeeper, anyMerchant)` returns `true`.

---

### TC-45: addKeeper reverts when caller is not the owner

**Category:** KeeperRegistry
**Requirement:** `addKeeper` — owner-only guard
**Type:** Unit

**Preconditions:**
- Caller is not the owner.

**Action:**
- Non-owner calls `addKeeper(keeper)`.

**Expected outcome:**
- Reverts (OwnableUnauthorizedAccount or equivalent).

---

### TC-46: addKeeper reverts when keeper address is zero

**Category:** KeeperRegistry
**Requirement:** `addKeeper` — zero-address guard
**Type:** Unit

**Preconditions:**
- Caller is the owner.

**Action:**
- Owner calls `addKeeper(address(0))`.

**Expected outcome:**
- Reverts with `ZeroAddress`.

---

### TC-47: addKeeper reverts when keeper is already registered

**Category:** KeeperRegistry
**Requirement:** `addKeeper` — duplicate guard
**Type:** Unit

**Preconditions:**
- `keeper` is already in the global keeper set.

**Action:**
- Owner calls `addKeeper(keeper)`.

**Expected outcome:**
- Reverts with `AlreadyRegistered(keeper)`.

---

### TC-48: addKeeper reverts when keeper is blacklisted

**Category:** KeeperRegistry
**Requirement:** `addKeeper` — blacklist guard
**Type:** Unit

**Preconditions:**
- `keeper` has been blacklisted by the owner.

**Action:**
- Owner calls `addKeeper(keeper)`.

**Expected outcome:**
- Reverts with `KeeperIsBlacklisted(keeper)`.

---

### TC-49: removeKeeper removes a keeper from the global set

**Category:** KeeperRegistry
**Requirement:** `removeKeeper(address keeper)`
**Type:** Unit

**Preconditions:**
- Caller is the owner.
- `keeper` is in the global keeper set.

**Action:**
- Owner calls `removeKeeper(keeper)`.

**Expected outcome:**
- `isAuthorised(keeper, anyMerchant)` returns `false`.
- `getGlobalKeepers()` no longer contains `keeper`.

---

### TC-50: removeKeeper reverts when caller is not the owner

**Category:** KeeperRegistry
**Requirement:** `removeKeeper` — owner-only guard
**Type:** Unit

**Preconditions:**
- Caller is not the owner.

**Action:**
- Non-owner calls `removeKeeper(keeper)`.

**Expected outcome:**
- Reverts (OwnableUnauthorizedAccount or equivalent).

---

### TC-51: removeKeeper reverts when keeper is not registered

**Category:** KeeperRegistry
**Requirement:** `removeKeeper` — existence guard
**Type:** Unit

**Preconditions:**
- `keeper` is not in the global keeper set.

**Action:**
- Owner calls `removeKeeper(keeper)`.

**Expected outcome:**
- Reverts with `NotRegistered(keeper)`.

---

### TC-52: blacklistKeeper blocks isAuthorised for that keeper

**Category:** KeeperRegistry
**Requirement:** `blacklistKeeper(address keeper)`
**Type:** Unit

**Preconditions:**
- `keeper` is an authorised global keeper (`isAuthorised` returns `true`).

**Action:**
- Owner calls `blacklistKeeper(keeper)`.

**Expected outcome:**
- `isAuthorised(keeper, anyMerchant)` returns `false`.
- `isBlacklisted(keeper)` returns `true`.
- `KeeperBlacklisted` event emitted.

---

### TC-53: blacklistKeeper removes the keeper from the global set

**Category:** KeeperRegistry
**Requirement:** `blacklistKeeper` — global set cleanup
**Type:** Unit

**Preconditions:**
- `keeper` is in the global keeper set.

**Action:**
- Owner calls `blacklistKeeper(keeper)`.

**Expected outcome:**
- `getGlobalKeepers()` no longer contains `keeper`.

---

### TC-54: blacklistKeeper succeeds for an address not in the global set

**Category:** KeeperRegistry
**Requirement:** `blacklistKeeper` — pre-emptive blacklisting
**Type:** Unit

**Preconditions:**
- `keeper` has never been added to the global set.

**Action:**
- Owner calls `blacklistKeeper(keeper)`.

**Expected outcome:**
- No revert.
- `isBlacklisted(keeper)` returns `true`.

---

### TC-55: blacklistKeeper reverts when keeper address is zero

**Category:** KeeperRegistry
**Requirement:** `blacklistKeeper` — zero-address guard
**Type:** Unit

**Preconditions:**
- Caller is the owner.

**Action:**
- Owner calls `blacklistKeeper(address(0))`.

**Expected outcome:**
- Reverts with `ZeroAddress`.

---

### TC-56: blacklistKeeper reverts when caller is not the owner

**Category:** KeeperRegistry
**Requirement:** `blacklistKeeper` — owner-only guard
**Type:** Unit

**Preconditions:**
- Caller is not the owner.

**Action:**
- Non-owner calls `blacklistKeeper(keeper)`.

**Expected outcome:**
- Reverts (OwnableUnauthorizedAccount or equivalent).

---

### TC-57: blacklisted keeper cannot be re-added via addKeeper

**Category:** KeeperRegistry
**Requirement:** `addKeeper` + `blacklistKeeper` interaction
**Type:** Unit

**Preconditions:**
- `keeper` has been blacklisted.

**Action:**
- Owner calls `addKeeper(keeper)`.

**Expected outcome:**
- Reverts with `KeeperIsBlacklisted(keeper)`.

---

### TC-58: merchant can add a keeper scoped to their own subscriptions

**Category:** KeeperRegistry
**Requirement:** `addMerchantKeeper(address keeper)`
**Type:** Unit

**Preconditions:**
- `keeper` is not blacklisted.
- `keeper` is not already in the merchant's keeper set.

**Action:**
- Merchant calls `addMerchantKeeper(keeper)`.

**Expected outcome:**
- `isAuthorised(keeper, merchant)` returns `true`.
- `isAuthorised(keeper, otherMerchant)` returns `false` (scoped to merchant only).
- `getMerchantKeepers(merchant)` contains `keeper`.

---

### TC-59: removeMerchantKeeper revokes authorisation for that merchant

**Category:** KeeperRegistry
**Requirement:** `removeMerchantKeeper(address keeper)`
**Type:** Unit

**Preconditions:**
- `keeper` is in the merchant's keeper set.

**Action:**
- Merchant calls `removeMerchantKeeper(keeper)`.

**Expected outcome:**
- `isAuthorised(keeper, merchant)` returns `false`.

---

### TC-60: addMerchantKeeper reverts when keeper is already registered for that merchant

**Category:** KeeperRegistry
**Requirement:** `addMerchantKeeper` — duplicate guard
**Type:** Unit

**Preconditions:**
- `keeper` is already in the merchant's keeper set.

**Action:**
- Merchant calls `addMerchantKeeper(keeper)` again.

**Expected outcome:**
- Reverts with `AlreadyRegistered(keeper)`.

---

### TC-61: addMerchantKeeper reverts when keeper address is zero

**Category:** KeeperRegistry
**Requirement:** `addMerchantKeeper` — zero-address guard
**Type:** Unit

**Preconditions:**
- None.

**Action:**
- Merchant calls `addMerchantKeeper(address(0))`.

**Expected outcome:**
- Reverts with `ZeroAddress`.

---

### TC-62: addMerchantKeeper reverts when keeper is blacklisted

**Category:** KeeperRegistry
**Requirement:** `addMerchantKeeper` — blacklist guard
**Type:** Unit

**Preconditions:**
- `keeper` has been blacklisted by the owner.

**Action:**
- Merchant calls `addMerchantKeeper(keeper)`.

**Expected outcome:**
- Reverts with `KeeperIsBlacklisted(keeper)`.

---

### TC-63: removeMerchantKeeper reverts when keeper is not registered for that merchant

**Category:** KeeperRegistry
**Requirement:** `removeMerchantKeeper` — existence guard
**Type:** Unit

**Preconditions:**
- `keeper` is not in the calling merchant's keeper set.

**Action:**
- Merchant calls `removeMerchantKeeper(keeper)`.

**Expected outcome:**
- Reverts with `NotRegistered(keeper)`.

---

### TC-64: global keeper is authorised for any merchant

**Category:** KeeperRegistry
**Requirement:** `isAuthorised(address keeper, address merchant)` — global tier
**Type:** Unit

**Preconditions:**
- `keeper` is in the global keeper set.
- `keeper` is not blacklisted.

**Action:**
- Call `isAuthorised(keeper, merchantA)` and `isAuthorised(keeper, merchantB)` for two distinct merchant addresses.

**Expected outcome:**
- Both return `true`.

---

### TC-65: non-keeper address returns false from isAuthorised

**Category:** KeeperRegistry
**Requirement:** `isAuthorised` — unknown address
**Type:** Unit

**Preconditions:**
- Address is neither a global keeper nor a merchant keeper for the queried merchant.

**Action:**
- Call `isAuthorised(stranger, merchant)`.

**Expected outcome:**
- Returns `false`.

---

### TC-66: blacklisted global keeper returns false from isAuthorised

**Category:** KeeperRegistry
**Requirement:** `isAuthorised` — blacklist overrides global registration
**Type:** Unit

**Preconditions:**
- `keeper` is (or was) in the global keeper set.
- `keeper` has been blacklisted.

**Action:**
- Call `isAuthorised(keeper, anyMerchant)`.

**Expected outcome:**
- Returns `false`.

---

### TC-67: blacklisted merchant keeper returns false from isAuthorised

**Category:** KeeperRegistry
**Requirement:** `isAuthorised` — blacklist overrides merchant registration
**Type:** Unit

**Preconditions:**
- `keeper` is in the merchant's keeper set.
- `keeper` has subsequently been blacklisted.

**Action:**
- Call `isAuthorised(keeper, merchant)`.

**Expected outcome:**
- Returns `false` (blacklist overrides merchant-level authorisation).

---

### TC-68: isBlacklisted returns false for addresses never blacklisted

**Category:** KeeperRegistry
**Requirement:** `isBlacklisted(address keeper)`
**Type:** Unit

**Preconditions:**
- Neither `keeper` nor `stranger` has ever been blacklisted.

**Action:**
- Call `isBlacklisted(keeper)` and `isBlacklisted(stranger)`.

**Expected outcome:**
- Both return `false`.

---

### TC-69: ownership transfer follows the two-step accept pattern

**Category:** KeeperRegistry
**Requirement:** `transferOwnership` / `acceptOwnership` (Ownable2Step)
**Type:** Unit

**Preconditions:**
- Current owner initiates a transfer to `newOwner`.

**Action:**
1. Owner calls `transferOwnership(newOwner)`.
2. `newOwner` calls `acceptOwnership()`.

**Expected outcome:**
- After step 1: `owner()` still equals the old owner; `pendingOwner()` equals `newOwner`.
- After step 2: `owner()` equals `newOwner`; `pendingOwner()` equals `address(0)`.

---

### TC-70: only the pending owner can accept an ownership transfer

**Category:** KeeperRegistry
**Requirement:** `acceptOwnership` — pending-owner guard
**Type:** Unit

**Preconditions:**
- A transfer to `newOwner` has been initiated.
- Caller is a third party (not `newOwner`).

**Action:**
- Third party calls `acceptOwnership()`.

**Expected outcome:**
- Reverts (OwnableUnauthorizedAccount or equivalent).

---

## Group G — Fuzz Properties

### TC-71: subscribe accepts any non-zero amount within uint128 bounds

**Category:** Subscribe
**Requirement:** `subscribe` — amount domain
**Type:** Fuzz

**Preconditions:**
- Subscriber holds sufficient token balance and allowance for the randomised amount.

**Action:**
- For any `amount` in `[1, type(uint128).max]`, subscriber calls `subscribe(merchant, terms)` where `terms.amount = amount`.

**Expected outcome:**
- Returns a non-zero subscription ID for every sampled value.
- Status is `Active` and `getPaymentCount` equals `1` for every sample.

---

### TC-72: nextPaymentDue equals subscribe time plus interval for any valid interval

**Category:** Subscribe
**Requirement:** `nextPaymentDue` — timing calculation
**Type:** Fuzz

**Preconditions:**
- No trial period.

**Action:**
- For any `interval` in `[1 hour, 365 days]`, subscriber calls `subscribe` at timestamp `t0`.

**Expected outcome:**
- `nextPaymentDue(subId)` equals `t0 + interval` for every sampled value.

---

### TC-73: paymentCount reaches exactly maxPayments then collectPayment reverts

**Category:** CollectPayment
**Requirement:** `collectPayment` — `maxPayments` boundary
**Type:** Fuzz

**Preconditions:**
- `terms.maxPayments = N` where `N` is sampled from `[1, 20]`.
- Subscription is created (first payment counts as payment 1).

**Action:**
- Collect `N - 1` more times by warping past each interval.
- Attempt one further collect after the final interval elapses.

**Expected outcome:**
- After `N` total payments, `getPaymentCount` equals `N`.
- The `(N+1)`th collect attempt reverts with `SubscriptionNotActive(subId, Status.Expired)`.

---

### TC-74: collectPayment reverts for any warp time strictly before nextPaymentAt

**Category:** CollectPayment
**Requirement:** `collectPayment` — time-lock boundary
**Type:** Fuzz

**Preconditions:**
- An active subscription exists with `nextPaymentDue = D`.
- Time is warped to `block.timestamp + warpTime` where `warpTime` is sampled from `[0, interval - 1]`.

**Action:**
- Keeper calls `collectPayment(subId)`.

**Expected outcome:**
- Reverts with `PaymentIntervalNotElapsed(subId, D)` for every sampled `warpTime`.

---

### TC-75: withdrawETH leaves correct residual balance for any deposit/withdraw pair

**Category:** ETH Escrow
**Requirement:** `depositETH` / `withdrawETH` — balance accounting
**Type:** Fuzz

**Preconditions:**
- `depositAmt` sampled from `[1, 50 ether]`.
- `withdrawAmt` sampled from `[1, depositAmt]`.

**Action:**
1. Subscriber calls `depositETH{value: depositAmt}()`.
2. Subscriber calls `withdrawETH(withdrawAmt)`.

**Expected outcome:**
- `ethDepositBalance(subscriber)` equals `depositAmt - withdrawAmt` for every sampled pair.

---

## Group H — Invariants

### TC-76: payment count never increases after a subscription enters Cancelled state

**Category:** Invariant
**Requirement:** `cancelSubscription` / `collectPayment` — terminal-state integrity
**Type:** Invariant

**Description:**
Once a subscription transitions to `Cancelled` status, no subsequent call to `collectPayment` may increase `getPaymentCount`. Any implementation in which a cancelled subscription accumulates further payments violates this invariant.

**Ghost variable:** `ghost_paymentCountIncreasedAfterTerminal` — set to `true` if `paymentCount` increments after cancellation is observed.

**Expected outcome:**
- `ghost_paymentCountIncreasedAfterTerminal` is `false` after any sequence of `createSubscription`, `collectPayment`, and `cancelSubscription` calls.

---

### TC-77: nextPaymentAt is strictly greater after every successful collectPayment

**Category:** Invariant
**Requirement:** `collectPayment` — monotonic time progression
**Type:** Invariant

**Description:**
Every successful `collectPayment` call must advance `nextPaymentDue` strictly forward in time. A conforming implementation must never leave `nextPaymentDue` unchanged or move it backwards after a successful collection.

**Ghost variable:** `ghost_nextPaymentDecreased` — set to `true` if `nextPaymentDue` after a successful collect is not strictly greater than the value before.

**Expected outcome:**
- `ghost_nextPaymentDecreased` is `false` after any sequence of calls.

---

### TC-78: payment count never exceeds maxPayments when a cap is set

**Category:** Invariant
**Requirement:** `collectPayment` — `maxPayments` upper bound
**Type:** Invariant

**Description:**
For any subscription where `terms.maxPayments > 0`, `getPaymentCount` must never exceed `terms.maxPayments`. A conforming implementation must enforce this bound strictly.

**Ghost variable:** `ghost_paymentCountExceededMax` — set to `true` if `getPaymentCount > terms.maxPayments` is observed after a successful collect.

**Expected outcome:**
- `ghost_paymentCountExceededMax` is `false` after any sequence of calls.

---

### TC-79: two consecutive collectPayment calls in the same block cannot both succeed

**Category:** Invariant
**Requirement:** `collectPayment` — double-collection prevention
**Type:** Invariant

**Description:**
Within a single block timestamp, at most one `collectPayment` call for a given subscription may return `true`. A second call at the same timestamp must either revert (`PaymentIntervalNotElapsed`) or return `false`. Any implementation that allows two successful collections within the same timestamp violates this invariant.

**Ghost variable:** `ghost_doubleCollectSucceeded` — set to `true` if two consecutive calls in the same block both return `true`.

**Expected outcome:**
- `ghost_doubleCollectSucceeded` is `false` after any sequence of calls.

---

## Running the Reference Test Suite

```bash
# Run all unit, fuzz, and integration tests
forge test -vv

# Generate a line-coverage summary across all source contracts
forge coverage --report summary

# Run the invariant suite in isolation
forge test --match-contract SubscriptionInvariantTest
```
