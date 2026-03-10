# Cadence Protocol — Security Considerations

This document constitutes the Security Considerations section for the Cadence Protocol EIP submission, as required by EIP-1. It analyses the threat model of the `ISubscription` interface and the `SubscriptionManager` reference implementation in detail, covering reentrancy, keeper trust, allowance risks, ETH escrow, identifier integrity, access control, arithmetic safety, and recommendations for third-party implementers.

---

## Reentrancy

`SubscriptionManager` makes external calls in five functions. Each is analysed below with respect to call ordering and reentrancy protection.

### External call inventory

| Function               | External call                                                              | Order relative to state changes            |
| ---------------------- | -------------------------------------------------------------------------- | ------------------------------------------ |
| `subscribe()`          | `IERC20.allowance` (view)                                                  | Before state writes                        |
| `subscribe()`          | `IERC20.safeTransferFrom`                                                  | After all state writes                     |
| `subscribe()`          | `ISubscriptionReceiver.onPaymentCollected` (via `_notifyPaymentCollected`) | After all state writes                     |
| `collectPayment()`     | `IKeeperRegistry.isAuthorized` (view, in modifier)                         | Before state writes; under reentrancy lock |
| `collectPayment()`     | `IERC20.allowance` (view)                                                  | Before state writes                        |
| `collectPayment()`     | `IERC20.safeTransferFrom`                                                  | After all state writes                     |
| `collectPayment()`     | `ISubscriptionReceiver.onPaymentCollected`                                 | After all state writes                     |
| `cancelSubscription()` | `ISubscriptionReceiver.onSubscriptionCancelled`                            | After all state writes                     |
| `withdrawETH()`        | `address.call{value}` (ETH transfer)                                       | After decrementing `_ethDeposits`          |
| `claimMerchantETH()`   | `address.call{value}` (ETH transfer)                                       | After zeroing `_merchantEthBalances`       |

### Reentrancy lock coverage

`subscribe`, `collectPayment`, `cancelSubscription`, `withdrawETH`, and `claimMerchantETH` are all guarded by the `nonReentrant` modifier from OpenZeppelin's `ReentrancyGuard`. This means that any reentrant call to any of these five functions — including a cross-function reentrant call from a callback into `withdrawETH` — is blocked by the shared lock. `pauseSubscription` and `resumeSubscription` carry no external calls and therefore require no reentrancy guard.

### IKeeperRegistry as an external call site

The `_checkKeeperAuth()` function issues an external view call to `IKeeperRegistry(keeperRegistry).isAuthorized(msg.sender)`. This call executes inside the `onlyAuthorizedKeeper` modifier, which is evaluated after `nonReentrant` has already acquired the lock. A malicious or upgradeable `keeperRegistry` cannot therefore use this call site to re-enter any guarded function. The call is also purely a view: it neither transfers value nor modifies state.

### ISubscriptionReceiver callbacks

Merchant callbacks (`onPaymentCollected`, `onSubscriptionCancelled`) are the highest-risk external call sites because the target address is user-supplied. The implementation defends against malicious merchants in three ways:

1. **All state changes are complete before the callback is issued.** The subscription data — including `paymentCount`, `nextPaymentAt`, and `status` — is updated in storage before `_notifyPaymentCollected` or `_notifyCancelled` is called.
2. **All callbacks are wrapped in `try/catch`.** A reverting or out-of-gas callback is silently swallowed. The callback return value is not inspected beyond confirming that the call does not revert; no downstream logic branches on the returned `bytes4` selector in the current implementation.
3. **The reentrancy lock is active during the callback.** Even if a merchant's `onPaymentCollected` implementation attempts to call back into `collectPayment`, `cancelSubscription`, `withdrawETH`, or `claimMerchantETH`, the lock will cause all such calls to revert.

**Residual risk.** A merchant callback can still consume gas up to the available gas limit of the outer transaction. A sufficiently gas-hungry callback could cause the outer `collectPayment` call to run out of gas, reverting the entire transaction. Keepers should monitor gas consumption when collecting payments for subscriptions whose merchant implements `ISubscriptionReceiver`, and should increase the gas limit accordingly or detect the pattern off-chain.

### ERC-20 token reentrancy

`SafeERC20.safeTransferFrom` is used for all ERC-20 transfers. SafeERC20 handles tokens that do not return a boolean from `transferFrom` and reverts on failure. A token with a callback mechanism in `transferFrom` (such as ERC-777) could attempt a reentrant call, but the reentrancy lock blocks any reentry into guarded functions. However, a token that calls back into `subscribe()` mid-transfer would find the reentrancy lock engaged and the call would revert. This is the correct and safe outcome.

---

## Keeper Trust Model and Griefing

### Compromised global keeper

A global keeper registered in `KeeperRegistry` is authorised to call `collectPayment` for any subscription on any `SubscriptionManager` that references that registry. If a global keeper's private key is compromised, an attacker gains the ability to trigger payment collection for any due subscription. The mitigation is the `blacklistKeeper` function, callable only by the `KeeperRegistry` owner, which permanently and immediately removes the compromised keeper from the global set and prevents re-registration. Keepers should be monitored with on-chain event indexing so that `KeeperBlacklisted` can be emitted and acted upon within minutes of detection.

**Residual risk.** Between the moment of compromise and the blacklist transaction, an attacker may call `collectPayment` for any due subscription. The damage is bounded by the time-lock: only subscriptions for which `block.timestamp >= nextPaymentAt` can be collected, and each can be collected at most once per interval. An attacker cannot collect early and cannot collect twice within an interval. The financial exposure is therefore limited to legitimate due payments, not arbitrary theft.

### KeeperRegistry with a malicious owner

The `KeeperRegistry` owner can add global keepers, blacklist them, and transfer ownership via a two-step (`Ownable2Step`) process. A malicious or compromised owner could register a keeper they control and use it to call `collectPayment` on any due subscription. This is not materially different from a compromised keeper key and carries the same bounded risk described above. `SubscriptionManager` deployments that reference a shared, community-governed `KeeperRegistry` should ensure the registry's ownership is protected by a multisig or DAO governance contract with an appropriate timelock.

### Griefing via repeated collectPayment calls

A whitelisted keeper cannot grief subscribers by calling `collectPayment` more than once per interval. The time-lock guard (`if (block.timestamp < sub.nextPaymentAt) revert PaymentIntervalNotElapsed`) is evaluated before any state changes or token transfers. Repeated calls within the same payment window revert immediately and inexpensively. The worst-case gas cost to a subscriber from this class of griefing is zero: the subscriber pays no tokens and no gas, since they are not the transaction sender.

### Front-running a subscriber's cancelSubscription

A race condition exists between a subscriber's pending `cancelSubscription` transaction and a keeper's `collectPayment` transaction when both are submitted to the mempool near the same time. If the keeper's transaction is included first, the payment for that period is collected; the subscriber's cancel is then included and the subscription is terminated. This means the subscriber pays one additional period they may have intended to avoid.

The practical impact is bounded: only one payment is at risk, it corresponds to a legitimately due billing period (the time-lock ensures this), and the subscriber receives the service for that period if the merchant provides one. A subscriber wishing to avoid this race should cancel during the early portion of a payment interval, maximising the gap between cancellation and the next payment date. Alternatively, a subscriber can cancel and immediately revoke the ERC-20 allowance in a single bundle using a multicall contract, ensuring the payment cannot be collected even if the keeper call is included first.

### Permissionless collection (`keeperRegistry == address(0)`)

When `keeperRegistry` is set to `address(0)`, the keeper authorisation check is skipped entirely and any address may call `collectPayment`. This mode is appropriate for testing and development but substantially changes the trust model in production:

- Any party, including the merchant or an adversarial third party, can trigger payment collection the moment an interval elapses.
- There is no mechanism to prevent spam calls (though the time-lock and state guards still apply).
- The griefing surface for the front-running race condition described above expands from registered keepers to the entire network.

Implementers deploying `SubscriptionManager` with `keeperRegistry == address(0)` in a production environment accept full responsibility for these trade-offs. The constructor NatSpec explicitly marks this configuration as "not recommended for production."

---

## ERC-20 Allowance Risks

### Infinite approvals

The `subscribe` flow requires the subscriber to have approved the `SubscriptionManager` for at least `terms.amount` before calling. Many wallet UIs and SDK libraries encourage approving `type(uint256).max` for convenience. An infinite approval exposes the subscriber's entire token balance to the contract: if the `SubscriptionManager` itself were exploited (e.g. through an upgrade mechanism or a critical bug discovered post-deployment), an attacker could drain all approved tokens for all subscribers. Implementers should recommend that subscribers approve only the exact amount required for the current period and refresh the approval before each collection. Where the payment token supports EIP-2612 (`permit`), using a signed permit with a per-payment deadline is strongly preferable: it removes the standing on-chain approval entirely, limits the window of exposure to the duration of a single transaction, and eliminates the need for a separate approval transaction.

### Allowance reduction between check and transfer (TOCTOU)

`_collectERC20Payment` reads `allowance` at the start of the function and then calls `safeTransferFrom`. Between these two operations — specifically, within the execution of the `safeTransferFrom` call itself if the token has a callback — a subscriber could in theory reduce their allowance. In practice, Solidity function execution is atomic: no state change from another transaction can intervene between the allowance read and the transfer within the same EVM call. The TOCTOU risk is therefore not present within a single transaction. However, in a cross-block scenario, a subscriber can submit a transaction to set allowance to zero that is included in the same block as a keeper's `collectPayment` and is ordered first. This results in the `safeTransferFrom` reverting. The implementation handles this correctly by checking allowance before the transfer and soft-failing (setting status to `PastDue` and emitting `PaymentFailed`) rather than reverting the entire `collectPayment` call. Soft failure is the correct design here because: (a) it preserves the subscription record rather than forcing the keeper to handle a revert; (b) it allows dunning logic to retry after the subscriber restores their allowance; and (c) it accurately represents the subscription state to all parties via the `PastDue` status and `PaymentFailed` event.

### Fee-on-transfer tokens

If `terms.token` is a token that deducts a fee during `transferFrom`, the merchant will receive less than `terms.amount`. The contract does not check the recipient's balance before and after the transfer; it trusts the return value of `safeTransferFrom` (which succeeds as long as the transfer does not revert). Implementers should explicitly document in their subscription UIs and terms of service whether fee-on-transfer tokens are supported, and if so, how the billing amount is defined (gross sent vs. net received). The reference implementation makes no accommodation for fee-on-transfer tokens: merchants receive whatever the token delivers, which may be less than `terms.amount`. If net receipt equality is required, the implementation would need to measure the merchant's balance delta after the transfer, which introduces additional complexity and a second storage read.

### Rebasing tokens

Tokens such as stETH, whose balances change autonomously through rebase mechanisms without explicit transfer events, are unsuitable as payment tokens in this standard unless the subscription manager actively tracks balance changes. The `amount` field is fixed at subscription creation time and does not adjust with rebases. A subscriber whose stETH balance grows between payments would pay a fixed nominal amount per period; a subscriber whose balance contracts due to a negative rebase may find their `safeTransferFrom` failing if their balance falls below `terms.amount`, triggering a `PastDue` soft-fail with no fault attributable to the subscriber. Implementers and integrators should warn against using rebasing tokens as the payment denomination for any subscription where predictable billing amounts are a requirement.

---

## ETH Escrow and Native ETH Risks

### Why direct ETH pull was not used

An alternative design for ETH subscriptions would have `collectPayment` send ETH directly from the subscriber's wallet to the merchant via a signed authorisation, or pull ETH from a subscriber-controlled account. Any design that issues an outbound ETH transfer to the merchant during `collectPayment` creates a re-entrancy vector: the merchant's `receive` or `fallback` function executes mid-payment, while the subscription's `paymentCount` and `nextPaymentAt` fields may not yet have been updated. Even with a reentrancy lock, designing around push-ETH patterns in a function that also modifies subscriber state is brittle. The chosen escrow model resolves this by separating payment execution into two phases: subscribers pre-fund via `depositETH`, and merchant proceeds accumulate in `_merchantEthBalances`. No ETH leaves the contract during `collectPayment` — it merely moves between two internal accounting mappings. ETH transfers to external addresses occur only in `withdrawETH` and `claimMerchantETH`, both of which are straightforward CEI-compliant single-purpose functions.

### Subscriber underfunding

If `_ethDeposits[subscriber] < terms.amount` when `collectPayment` is called, the function soft-fails: status is set to `PastDue`, `PaymentFailed` is emitted, and the function returns `false`. No ETH is transferred. Keepers operating the Cadence Automation Service should check `ethDepositBalance(subscriber)` off-chain before submitting a collect transaction for an ETH subscription, to avoid paying gas for a predictable soft-fail. Keepers may also choose to notify subscribers proactively when their deposit balance is low relative to the next payment amount.

### Merchant claiming: CEI verification

`claimMerchantETH` follows checks-effects-interactions strictly:

1. **Check:** the merchant's accumulated balance is read and verified to be non-zero.
2. **Effect:** `_merchantEthBalances[msg.sender]` is set to zero before any ETH transfer.
3. **Interaction:** ETH is transferred via `call{value}` with no gas stipend restriction (the full remaining gas is forwarded).

The `nonReentrant` guard is active. Even if the merchant's `receive` function re-enters `claimMerchantETH`, the reentrancy lock reverts the inner call. The outer call proceeds with `_merchantEthBalances[msg.sender]` already zeroed, so no double-withdrawal is possible. No code path exists that credits `_merchantEthBalances` after it has been zeroed within the same transaction.

### ETH locked after cancellation

If a subscriber cancels a subscription without first withdrawing their ETH deposit, any balance in `_ethDeposits[subscriber]` remains in the contract. The `cancelSubscription` function does not automatically refund the deposit because the deposit is shared across all ETH subscriptions held by that subscriber. Cancelling one subscription does not necessarily mean the subscriber wishes to withdraw funds that may be needed for other active ETH subscriptions. Subscribers must call `withdrawETH(amount)` explicitly to recover unused deposits. Implementers building subscription management UIs should surface the subscriber's current deposit balance prominently and prompt withdrawal upon cancellation when it is the subscriber's last active ETH subscription.

---

## Subscription ID Collision

### Input analysis

The subscription ID is derived as:

```solidity
keccak256(abi.encodePacked(subscriber, merchant, block.timestamp, block.chainid, _nonce++))
```

The inputs are: the subscriber's address (160 bits of entropy), the merchant's address (160 bits), the current block timestamp (a Unix second), the chain ID, and a monotonically incrementing global nonce (`uint256`). The nonce is the collision-prevention mechanism for same-block subscriptions: if two subscriptions are created in the same block (same `block.timestamp` and `block.chainid`) by the same subscriber and merchant pair, the nonce differs between the two calls, guaranteeing distinct IDs. The nonce is private to the contract and cannot be manipulated by external callers, and it increments post-derivation (via `_nonce++`), so it is consistent with the number of subscriptions created since deployment.

### Probability of collision

A keccak256 hash is 256 bits. The birthday paradox gives an approximate collision probability of `n² / 2²⁵⁶` for `n` independently derived IDs. Given that `_nonce` is strictly monotonic and is included in every derivation, no two calls to `subscribe` will ever produce the same pre-image, and therefore no two calls will ever produce the same hash unless keccak256 itself suffers a collision. keccak256 has no known practical collision attacks as of the date of this writing.

### Front-running and ID pre-computation

An attacker who observes a pending `subscribe` transaction in the mempool can predict the resulting `subId` (because `block.timestamp` is predictable to within one block and `_nonce` can be read from the contract's storage). However, knowing a future `subId` in advance yields no advantage: there is no mechanism to register state against a not-yet-existing ID, and creating a subscription with the predicted ID requires the attacker to execute their own `subscribe` call first, which increments the nonce and causes the victim's subscription to receive a different ID. This is not harmful — the victim's subscription is still created, with a different (but equally valid) ID returned to their transaction.

### Cross-chain replay prevention

`block.chainid` is an input to the derivation. A subscription created on chain A with `chainid = 1` and a subscription created on chain B with `chainid = 137` by the same subscriber/merchant pair at the same timestamp will produce different IDs, even with the same nonce value. Cross-chain replay of a subscription ID is therefore not possible. Implementers building cross-chain subscription bridges should note that `originChainId` and `paymentChainId` fields in `SubscriptionTerms` serve as metadata for routing and auditing purposes, while the `block.chainid` embedded in the ID derivation serves the collision-prevention purpose.

---

## Access Control on Lifecycle Functions

### Merchant-initiated cancellation

`cancelSubscription` is callable by either the subscriber or the merchant. A merchant can therefore cancel a subscriber's active subscription at any time without the subscriber's consent. This is intentional: merchants may need to offboard subscribers due to geographic restrictions, terms-of-service violations, account closure, or service discontinuation. The `SubscriptionCancelled` event includes the `cancelledBy` address, enabling off-chain indexers and UIs to distinguish subscriber-initiated and merchant-initiated cancellations. Implementers who wish to restrict merchant cancellation rights — for example, requiring advance notice — must encode this constraint in a higher-level contract or governance layer that wraps `cancelSubscription`.

### Indefinite pause by subscriber

`pauseSubscription` is callable only by the subscriber and can be called at any time while the subscription is `Active`. There is no maximum pause duration enforced in the reference implementation. A subscriber can pause indefinitely, effectively receiving a permanent suspension of payment obligations without cancelling the subscription. Merchants who cannot tolerate unbounded pauses — such as those providing continuously consumable services — should implement a maximum pause duration through a mechanism outside this standard, for example by monitoring the `SubscriptionPaused` event and calling `cancelSubscription` after a specified grace period.

### Resume extends the free period by the pause duration

When `resumeSubscription` is called, `nextPaymentAt` is reset to `block.timestamp + terms.interval`. This means a subscriber who pauses for duration `d` and then resumes has effectively obtained `d` additional seconds before the next payment is due, beyond what the original schedule would have provided. This is intended behaviour: freezing the payment clock is the semantic definition of a pause, and it follows that resuming restarts the clock from the current moment rather than from the original scheduled payment date. Implementers and merchants should be aware of this when evaluating the subscription pause feature for their use case.

### Status inconsistency at maxPayments boundary

When `getPaymentCount(subId) >= terms.maxPayments` and a keeper attempts to collect, the implementation writes `sub.status = Status.Expired` and then reverts. The revert rolls back the storage write, so `sub.status` remains `Active` in persistent storage. Consequently, `getStatus(subId)` returns `PastDue` (because `block.timestamp > sub.nextPaymentAt` and the stored status is still `Active`) rather than `Expired`. Meanwhile, `collectPayment` reverts with `SubscriptionNotActive(subId, Status.Expired)`. Off-chain tooling that relies on `getStatus()` to determine whether collection will succeed will observe `PastDue` but receive an `Expired` revert on the collect call. Indexers should treat a `SubscriptionNotActive` revert with `Status.Expired` as a terminal signal and update their local state accordingly, rather than relying on the on-chain `getStatus()` return value as the sole source of truth for this edge case.

---

## Integer Overflow and Timestamp Handling

### Solidity ^0.8.24 overflow protection

All arithmetic in `SubscriptionManager` and `KeeperRegistry` is compiled under Solidity 0.8.24, which performs checked arithmetic by default. Addition, subtraction, and multiplication operations revert on overflow or underflow unless explicitly performed in an `unchecked` block. No `unchecked` arithmetic blocks are present in either contract.

### uint48 interval and uint256 timestamp addition

`nextPaymentAt` is computed as `block.timestamp + terms.interval`, where `block.timestamp` is `uint256` and `terms.interval` is `uint48`. The `uint48` value is implicitly widened to `uint256` before the addition, and the result is stored as `uint256`. The maximum value of `uint48` is `2⁴⁸ - 1` seconds, approximately 8.9 million years. Adding this to any plausible `block.timestamp` (which currently represents a Unix timestamp in the billions of seconds) produces a result well within `uint256` range. No overflow is possible on this computation.

### maxPayments == 0 sentinel

The `maxPayments` field uses `0` as the sentinel value for "unlimited payments." The expiry guard is written as:

```solidity
if (sub.terms.maxPayments > 0 && sub.paymentCount >= sub.terms.maxPayments) {
    sub.status = Status.Expired;
    revert SubscriptionNotActive(subId, Status.Expired);
}
```

The `maxPayments > 0` short-circuit ensures that the `paymentCount >= maxPayments` comparison is never evaluated when `maxPayments` is zero, and therefore `paymentCount` reaching zero (which cannot happen since it increments from one at creation) cannot be misinterpreted as expiry. Implementers must not interpret `paymentCount == maxPayments` as expiry when `maxPayments == 0`; the check is defined as `maxPayments > 0 && paymentCount >= maxPayments`.

---

## Recommendations for Implementers

Developers implementing `ISubscription` in conforming contracts should observe the following minimum requirements:

- **Use SafeERC20** (or an equivalent safe transfer library) for all ERC-20 token operations. Direct calls to `transferFrom` do not uniformly handle tokens that return no boolean or revert with non-standard encoding.
- **Apply `nonReentrant`** (or an equivalent reentrancy guard) to every state-changing function that issues an external call, including `subscribe`, `collectPayment`, `cancelSubscription`, and all ETH transfer functions.
- **Follow checks-effects-interactions strictly.** Emit events and update all internal state before making any external call, including token transfers and merchant callbacks.
- **Wrap all merchant callbacks in try/catch.** A reverting `ISubscriptionReceiver` callback must never prevent `collectPayment` or `cancelSubscription` from completing. The liveness guarantee of the protocol — that a due payment can always be collected — must not depend on third-party contract correctness.
- **Validate token addresses.** `terms.token` must be a contract (`code.length > 0`) when non-zero. Accepting EOA addresses as token fields allows subscribers to subscribe with non-functional tokens and can produce unexpected behaviour at collection time.
- **Gate `collectPayment` behind an authorisation registry** in production deployments. The `keeperRegistry == address(0)` mode disables access control entirely and should not be used in environments where subscriptions carry significant value.
- **Implement a maximum pause duration policy** if your use case cannot tolerate indefinite subscriber pauses. The `ISubscription` interface is silent on maximum pause duration by design; this constraint belongs at the application layer.
- **Recommend exact allowances or EIP-2612 Permit** to subscribers rather than infinite approvals. Document clearly in your integration that standing infinite approvals expose the full token balance to the contract.
- **Test explicitly with fee-on-transfer tokens** if you intend to support them, and document whether `terms.amount` represents the gross amount debited from the subscriber or the net amount credited to the merchant.
- **Emit events for all state transitions.** The `ISubscription` interface specifies a mandatory event set (`SubscriptionCreated`, `PaymentCollected`, `PaymentFailed`, `SubscriptionCancelled`, `SubscriptionPaused`, `SubscriptionResumed`). Off-chain indexers, keeper networks, and subscriber dashboards rely on complete event logs to maintain accurate state.

---

## Summary

The `SubscriptionManager` reference implementation has been designed with the security considerations outlined above in mind. Reentrancy is mitigated through comprehensive `nonReentrant` guards and strict adherence to the checks-effects-interactions pattern across all external call sites. The ETH escrow model eliminates re-entrancy vectors inherent in direct ETH push patterns. The keeper registry provides access control for `collectPayment` with an emergency blacklist mechanism, and all merchant callbacks are isolated in `try/catch` blocks to preserve protocol liveness. Notwithstanding these precautions, the reference implementation has not yet undergone a formal third-party security audit. A formal audit — including automated static analysis, followed by a competitive audit engagement — is planned before the reference implementation is recommended for production deployment with significant value at risk.
