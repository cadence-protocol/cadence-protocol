# ISubscription Interface — Design Rationale

This document records the design decisions made in the `ISubscription` interface
(`src/interfaces/ISubscription.sol`) for the Cadence Protocol onchain recurring payments
standard. Each section identifies what was chosen,
what alternatives were considered, and the reasoning behind the final decision.

---

## Table of Contents

1. [`bytes32` as Subscription ID Instead of `uint256`](#1-bytes32-as-subscription-id-instead-of-uint256)
2. [`address(0)` for Native ETH Instead of Requiring WETH](#2-address0-for-native-eth-instead-of-requiring-weth)
3. [`uint48` for `interval` and `trialPeriod` Instead of `uint256`](#3-uint48-for-interval-and-trialperiod-instead-of-uint256)
4. [Security Model for `collectPayment()` — Keeper-Gated Access](#4-security-model-for-collectpayment--keeper-gated-access)
5. [Additional Design Decisions](#5-additional-design-decisions)
   - [Custom Errors vs. `require` Strings](#custom-errors-vs-require-strings)
   - [`getStatus()` Returning `PastDue` Dynamically](#getstatus-returning-pastdue-dynamically)
   - [`maxPayments == 0` Meaning Unlimited](#maxpayments--0-meaning-unlimited)
   - [`ISubscriptionReceiver` as an Optional Pull Interface](#isubscriptionreceiver-as-an-optional-pull-interface)

---

## 1. `bytes32` as Subscription ID Instead of `uint256`

### What was chosen

Subscription IDs (`subId`) are `bytes32` values derived as:

```solidity
bytes32 subId = keccak256(
    abi.encodePacked(subscriber, merchant, block.timestamp, block.chainid, nonce)
);
```

### Alternatives considered

**Auto-incrementing `uint256` counter.** The simplest possible approach — a storage
variable that increments by one for each new subscription. This is the model used by
ERC-721 for token IDs.

### Why `bytes32` was chosen

**Cross-chain determinism.** A hash-derived ID can be reproduced on any chain given the
same inputs. When a subscription is created on chain A and mirrored or settled on chain
B, both sides can independently derive and verify the same `subId` without any
cross-chain message carrying an ID. An auto-incrementing counter on chain A will be
at a completely different value on chain B, making correlation impossible without an
explicit mapping layer.

**Collision resistance across deployments.** If multiple `SubscriptionManager` contracts
are deployed — across chains, across versions, or across organisations — a counter-based
ID has a high probability of collision (`subId = 1` will exist in every deployment).
A keccak256-derived ID incorporating `block.chainid` and the contract's implicit context
is effectively collision-free across the entire EVM ecosystem.

**Contrast with ERC-721.** ERC-721 token IDs are `uint256` sequential counters because
tokens are single-chain assets: token `#42` exists on exactly one chain and is
unambiguous within its contract. A subscription, by contrast, may be created on an L2
for gas efficiency, tracked on a settlement chain, and referenced by a cross-chain
messaging layer — three contexts where the same logical object must carry the same
identifier. The sequential model breaks down entirely in this scenario.

**Trade-off: gas cost.** Storing and comparing `bytes32` costs marginally more gas than
`uint256` (an extra `MSTORE`/`MLOAD` word is not involved since both are 32 bytes, but
keccak256 derivation at creation time costs ~30 gas + 6 gas/word). This is a one-time
cost at subscription creation and is negligible relative to the benefits of cross-chain
portability and collision resistance.

---

## 2. `address(0)` for Native ETH Instead of Requiring WETH

### What was chosen

`SubscriptionTerms.token == address(0)` is the sentinel value indicating that payments
are denominated in native ETH rather than an ERC-20 token.

### Alternatives considered

**Require WETH.** Treat native ETH like any other ERC-20 by requiring subscribers to
wrap it into WETH (or the chain-specific equivalent) before creating a subscription. This
collapses all payment paths into a single ERC-20 code path.

### Why `address(0)` was chosen

**User experience.** Requiring WETH wrapping introduces a mandatory preliminary
transaction for subscribers who hold ETH. For consumer-facing subscription products —
the primary use case of this standard — adding friction before the first payment is a
material conversion barrier. The native ETH path eliminates it.

**Established convention.** Using `address(0)` as a sentinel for the native asset is
already idiomatic across the EVM ecosystem: Uniswap V3 uses it in its router, Aave V3
uses it in its `WETHGateway` abstraction, and numerous token lists use it for the native
asset entry. Adopting the same convention reduces cognitive load for integrators.

**Trade-off: two code paths.** Supporting native ETH requires a conditional branch in
`collectPayment()` — one path for ERC-20 `transferFrom`, another for ETH escrow
withdrawal. This adds a small amount of contract complexity and bytecode size.

**Security consideration.** The implementation uses a deposit/escrow pattern
(`depositETH()` records an internal balance; `collectPayment()` withdraws from it)
rather than direct ETH transfers at collection time. This eliminates the re-entrancy
vector that would arise from push-ETH patterns, where an attacker could craft a
fallback to re-enter `collectPayment()` mid-execution. The escrow model follows the
checks-effects-interactions pattern rigorously.

---

## 3. `uint48` for `interval` and `trialPeriod` Instead of `uint256`

### What was chosen

Both time-based fields in `SubscriptionTerms` are typed as `uint48`:

```solidity
struct SubscriptionTerms {
    address token;        // 20 bytes  ─┐
    uint256 amount;       // 32 bytes   │ slot 0: token (20) + 12 bytes padding
    uint48  interval;     //  6 bytes  ─┐ slot 2: interval (6) + trialPeriod (6) = 12 bytes
    uint48  trialPeriod;  //  6 bytes  ─┘       + maxPayments starts packing
    uint256 maxPayments;  // 32 bytes
    uint256 originChainId;// 32 bytes
    uint256 paymentChainId;// 32 bytes
}
```

Exact slot layout (Solidity packs fields in declaration order, right-to-left within a slot):

| Slot | Contents                                                                              |
| ---- | ------------------------------------------------------------------------------------- |
| 0    | `token` (20 bytes) + 12 bytes padding                                                 |
| 1    | `amount` (32 bytes)                                                                   |
| 2    | `interval` (6 bytes) + `trialPeriod` (6 bytes) + 20 bytes available for future fields |
| 3    | `maxPayments` (32 bytes)                                                              |
| 4    | `originChainId` (32 bytes)                                                            |
| 5    | `paymentChainId` (32 bytes)                                                           |

`interval` and `trialPeriod` share slot 2, saving one `SSTORE` compared to using
`uint256` for each, where each would occupy its own slot.

### Alternatives considered

**`uint32`.** Maximum representable value: 2³² − 1 seconds ≈ **136 years**. Sufficient
for most practical scenarios, but precludes very long-horizon contracts (e.g. century
bonds, perpetual licences) and introduces a cliff that implementors must document.

**`uint256`.** No packing benefit. Each field occupies a full 32-byte slot, adding one
`SSTORE` (20,000 gas cold / 2,900 gas warm) per field. Over the lifetime of a protocol
with millions of subscriptions, this is a material cost imposed on every subscriber.

### Why `uint48` was chosen

**Range.** `uint48` maxes out at 2⁴⁸ − 1 seconds ≈ **8,925,511 years** — effectively
unbounded for any real-world use case, removing the need for a range caveat in the EIP.

**Packing.** Two `uint48` fields (6 bytes each, 12 bytes total) pack comfortably into a
single 32-byte storage slot alongside additional smaller fields, yielding a net saving of
one storage slot versus two `uint256` fields.

**Overflow safety.** `nextPaymentAt` is computed as `block.timestamp + interval`, where
`block.timestamp` is `uint256`. The addition is performed in `uint256` arithmetic, so
there is no overflow risk even at the maximum `uint48` interval. The result is stored as
`uint256`, keeping comparisons type-consistent.

---

## 4. Security Model for `collectPayment()` — Keeper-Gated Access

### What was chosen

`collectPayment()` may only be called by addresses registered in a `KeeperRegistry`
contract. The registry supports two tiers: **global keepers** (operated by the Cadence
Automation Service) and **per-merchant custom keepers** (operated by individual
protocols). A blacklist mechanism allows the registry owner to permanently block a
compromised keeper without a contract upgrade.

### Alternatives considered

**Permissionless (callable by anyone).** Any EOA or contract could trigger payment
collection.

> **Rejected.** A permissionless `collectPayment()` is vulnerable to griefing: a
> malicious actor can spam calls to exhaust gas, manipulate payment timing at the
> block level, or front-run legitimate collection to trigger failure events. It also
> makes it impossible to implement rate-limiting or fee-compensation logic for keepers.

**Merchant-only restriction.** Only the merchant receives payments, so only the
merchant can trigger collection.

> **Rejected.** This reintroduces a manual, trust-dependent pull model. The core value
> proposition of the standard is that payment collection is **automatic and
> infrastructure-light** for merchants. If merchants must run a cron job or call a
> transaction, the standard degrades to a signed-invoice system with extra steps.

**Subscriber-only restriction.** Only the subscriber can trigger collection of their
own payment.

> **Rejected.** This entirely defeats the purpose of pull payments. A subscriber who
> must actively trigger their own payment can simply choose not to, making the mechanism
> unsuitable for any commercially reliable subscription product.

### Why the KeeperRegistry model was chosen

**Trustlessness with liveness.** The registry allows any sufficiently trusted party to
run a keeper without requiring permission from Cadence, while the blacklist ensures that
a single compromised keeper cannot permanently disrupt the network. The system degrades
gracefully: if the Cadence Automation Service goes offline, per-merchant keepers continue
to operate, and vice versa.

**No mandatory infrastructure dependency.** A protocol integrating this standard can
deploy its own keeper and register it without ever interacting with Cadence's
infrastructure. The standard is therefore self-sufficient — Cadence's automation service
is a convenience, not a dependency.

**Comparison to ERC-1337.** The ERC-1337 draft used off-chain signed messages relayed
via meta-transactions to authorise payment collection. While this avoids on-chain
registry overhead, it introduces an off-chain coordination layer that is harder to audit,
harder to blacklist on-chain, and dependent on relayer liveness. A fully on-chain
registry is more transparent, more composable, and better suited to an environment where
on-chain computation costs have fallen significantly since ERC-1337 was drafted.

---

## 5. Additional Design Decisions

### Custom Errors vs. `require` Strings

Custom errors (introduced in Solidity 0.8.4) are used throughout the interface instead
of `require(condition, "string")` reverts. A custom error encodes only its 4-byte
selector plus ABI-encoded parameters into the revert data, whereas a string revert
encodes the full UTF-8 string on every execution. For a frequently-called path like
`collectPayment()`, the gas saving per reverted call is typically 50–200 gas depending on
string length. Additionally, custom errors carry structured data — the failing `subId`,
the current `Status`, or the insufficient allowance amounts — which off-chain tooling and
frontends can decode without string parsing, improving debuggability.

---

### `getStatus()` Returning `PastDue` Dynamically

The persisted `status` field stored for each subscription only transitions on explicit
state-changing calls (`cancelSubscription`, `pauseSubscription`, etc.). The `PastDue`
state is never written to storage; instead, `getStatus()` computes it on-the-fly:

```solidity
if (stored.status == Status.Active && block.timestamp > nextPaymentAt[subId]) {
    return Status.PastDue;
}
return stored.status;
```

This design avoids requiring a keeper to submit a dedicated `markPastDue(subId)`
transaction. Such a transaction would cost gas, introduce latency, and add keeper
complexity for what is ultimately a derived, read-only fact. Any caller — a frontend,
another contract, or a keeper evaluating whether to attempt collection — can determine
`PastDue` status for free via a view call. Keepers only need to submit transactions that
actually collect payments, not transactions that update status flags.

---

### `maxPayments == 0` Meaning Unlimited

Zero is used as the sentinel value for "no payment limit" rather than
`type(uint256).max`. This convention is already idiomatic in the EVM ecosystem: ERC-20
infinite approvals use `type(uint256).max` but many protocols treat zero as "no limit"
in their own configuration parameters. More importantly, `0` costs zero calldata bytes
(it encodes as a zero word, which is cheaper in calldata than a non-zero word), whereas
`type(uint256).max` encodes as 32 non-zero bytes. For a parameter passed in every
`subscribe()` call, this is a meaningful calldata gas saving for the common case of
unlimited subscriptions. The implementation checks `maxPayments == 0 || paymentCount < maxPayments`
to express the invariant clearly.

---

### `ISubscriptionReceiver` as an Optional Pull Interface

Merchants can implement `ISubscriptionReceiver` to execute custom logic (e.g. provision
access, update an internal ledger) immediately when a payment is collected or a
subscription is cancelled — without relying on off-chain webhooks, which are
unreliable and incompatible with fully onchain applications. The interface is **optional**:
the subscription contract checks `IERC165.supportsInterface(type(ISubscriptionReceiver).interfaceId)`
before attempting a callback, adding overhead only when the merchant has opted in.
Critically, all callbacks are wrapped in `try/catch`: a reverting merchant hook never
blocks payment collection. The standard's liveness guarantee — that a due payment can
always be collected — must not be contingent on the correctness of third-party merchant
code.
