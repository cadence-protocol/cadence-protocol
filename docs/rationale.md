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
6. [Extension Interfaces](#extension-interfaces)
   - [Why Extension Interfaces Instead of a Monolithic ISubscription](#1-why-extension-interfaces-instead-of-a-monolithic-isubscription)
   - [ISubscriptionTrial — Why Not Rely Solely on SubscriptionTerms.trialPeriod](#2-isubscriptiontrial--why-not-rely-solely-on-subscriptiontermstrialperiod)
   - [ISubscriptionTiered — tierId as bytes32 and Price/Interval Immutability](#3-isubscriptiontiered--tierid-as-bytes32-and-priceinterval-immutability)
   - [ISubscriptionDiscovery — Minimal On-Chain Data, Rich Off-Chain Metadata](#4-isubscriptiondiscovery--minimal-on-chain-data-rich-off-chain-metadata)
   - [ISubscriptionHook vs ISubscriptionReceiver — Separation of Concerns](#5-isubscriptionhook-vs-isubscriptionreceiver--separation-of-concerns)

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

---

## Extension Interfaces

The Cadence Protocol standard is deliberately layered. `ISubscription` defines the
minimum interface that all conforming implementations must satisfy: subscribe, collect,
cancel, pause, resume, and the associated view functions. Beyond this core, the protocol
defines four standalone extension interfaces — `ISubscriptionTrial`, `ISubscriptionTiered`,
`ISubscriptionDiscovery`, and `ISubscriptionHook` — each of which a contract may implement
independently. No extension requires inheriting from `ISubscription` or from any other
extension. A contract declares support for an extension exclusively via ERC-165
`supportsInterface()`, returning `true` for the corresponding interface ID constant.
This approach is preferable to a monolithic interface for the same reason the SOLID
principle of interface segregation exists in software engineering: a single large interface
forces every implementor to provide every feature, raising the minimum viable
implementation cost for simple use cases. A minimal recurring-revenue SaaS contract
needs nothing beyond `ISubscription`. A creator platform that offers free trials adds
`ISubscriptionTrial`. A DAO treasury that sells tiered governance seats adds
`ISubscriptionTiered`. Each protocol chooses exactly the surface area it needs, and
external contracts — access-control layers, frontends, cross-chain bridges, indexers —
can detect the supported feature set at runtime without any hard coupling to a particular
implementation class.

### 1. Why Extension Interfaces Instead of a Monolithic ISubscription

A monolithic interface that includes trial management, tier management, discovery
registration, and dunning hooks in a single type definition would impose a non-trivial
implementation burden on every conforming contract. A developer deploying a simple
on-chain subscription gate for a DAO proposal would be required to implement tier
management functions they have no use for, or to provide stub reverts that satisfy the
type-checker while adding no real behaviour. This creates two failure modes: either the
standard is adopted at a lower rate because the implementation cost is too high, or it is
adopted with hollow stubs that satisfy the interface mechanically but provide no semantic
guarantee.

The opt-in extension model solves both problems. Each extension interface is a coherent
unit of functionality — a collection of functions, events, and errors that address a
single capability — and a contract that does not implement an extension simply returns
`false` from `supportsInterface()` for that extension's ID. Any external contract or
off-chain indexer that wants to interact with a capability it cannot find degrades
gracefully rather than failing with a missing-function revert.

This pattern has a direct precedent in the Ethereum standard library. ERC-721 defines the
base NFT interface (`IERC721`), but enumeration of all tokens (`IERC721Enumerable`) and
metadata retrieval (`IERC721Metadata`) are separate optional extensions. OpenZeppelin's
ERC-721 implementation exposes them independently and declares each via ERC-165.
Wallets, marketplaces, and explorers probe `supportsInterface()` before attempting
enumeration or metadata reads — the same runtime detection mechanism used by the
Cadence Protocol. The key difference is that while ERC-721 extensions are defined in
the same EIP, the Cadence extensions are defined in separate interface files to keep
the core EIP specification minimal and to allow future extensions to be proposed as
independent EIPs without modifying the base standard.

### 2. ISubscriptionTrial — Why Not Rely Solely on SubscriptionTerms.trialPeriod

`SubscriptionTerms.trialPeriod` encodes the initial trial duration as part of the
subscription agreement between subscriber and merchant at creation time. Like every other
field in `SubscriptionTerms`, it is logically immutable once the subscription exists: it
is part of the recorded terms of the bilateral agreement. A subscriber accepted those
terms; changing them retroactively would alter a record that both parties have implicitly
signed by virtue of the on-chain transaction.

`ISubscriptionTrial` adds capabilities that are operational rather than contractual.
`isInTrial(subId)` is a derived read that any frontend, keeper, or access-control
contract needs to gate behaviour (e.g. do not collect payment, show "Trial" badge in
UI). The core `ISubscription` interface does not expose a dedicated trial-query function
because `getStatus()` and `nextPaymentDue()` together convey sufficient information
for core payment logic. But an interface that explicitly names trial concepts makes UIs
and integrations clearer and eliminates the need for each consumer to re-implement the
`trialPeriod > 0 && block.timestamp < createdAt + trialPeriod` derivation. Similarly,
`trialEndsAt(subId)` returns the timestamp directly, rather than requiring callers to
call `getTerms()` and `nextPaymentDue()` and reconstruct it.

`extendTrial()` is the key addition that `SubscriptionTerms` cannot model. A merchant
may wish to extend a trial for a high-value prospect — a sales concession that is common
in commercial SaaS. This is an operational decision made unilaterally by the merchant;
it does not require the subscriber's consent because it only benefits the subscriber by
delaying their payment obligation. Restricting `extendTrial()` to the merchant prevents
subscribers from extending their own trials indefinitely — a free-ride vector that would
undermine the commercial viability of any subscription product using this extension.
Critically, extending a trial does not modify `SubscriptionTerms`. The terms of the
agreement — interval, amount, maxPayments — remain unchanged. The extension only defers
`nextPaymentAt`, which is runtime state, not agreed contractual terms.

### 3. ISubscriptionTiered — tierId as bytes32 and Price/Interval Immutability

**`tierId` as `bytes32`.** The choice of `bytes32` for tier identifiers is consistent
with the `bytes32` type used for `subId` throughout the core interface, and for the same
underlying reason: cross-chain determinism. A merchant who defines their pricing tiers
once may want those tier definitions to be referenceable from any chain where their
product operates. A `tierId` derived as `keccak256(abi.encodePacked(merchant, name))`
produces the same value on every EVM chain, allowing cross-chain messaging systems to
reference tiers by a stable identifier without a chain-specific lookup. A sequential
`uint256` counter would differ between a deployment on Ethereum mainnet and one on
Arbitrum, making cross-chain tier references impossible without an explicit mapping layer.

**Price and interval immutability after tier creation.** The `updateTierMetadata()`
function deliberately allows only the `metadataURI` to change — not `amount` or
`interval`. This design choice protects existing subscribers from silent price changes.
If a merchant could call `updateTier(tierId, newAmount)` and have the new amount take
effect immediately for all subscribers on that tier, it would effectively be a unilateral
contract modification without subscriber consent. Merchants who need to reprice must
create a new tier and migrate subscribers explicitly — a deliberate friction that ensures
any subscriber moving to a new price does so via an observable on-chain action. This
mirrors how cloud providers handle pricing changes: existing customers retain their
grandfathered rates until they actively upgrade or agree to new terms.

**`deactivateTier()` reverts if active subscribers remain.** Allowing a merchant to
deactivate a tier while subscribers are still on it would strand those subscribers: the
tier's `active` flag becomes `false`, but the subscription still references the tier ID.
Future interactions — upgrades, downgrades, feature-gating based on tier — would hit
unexpected states. Requiring all subscribers to migrate off a tier before deactivation
forces an explicit, auditable transition rather than a silent stranding. Merchants who
want to sunset a tier cleanly must first offer subscribers an alternative and wait for
them to migrate; this is the correct commercial behaviour.

**`metadataURI` for feature descriptions.** Subscription tiers are differentiated by
features, limits, and SLAs as much as by price — "Basic" may mean 10 API calls per day
where "Pro" means unlimited. Encoding feature sets on-chain would make every
`createTier()` transaction expensive and inflexible: adding a new feature attribute
would require a contract upgrade. Storing only a URI on-chain and placing rich feature
descriptions in a JSON document at the URI keeps the on-chain footprint minimal and
allows features to be updated without gas costs.

### 4. ISubscriptionDiscovery — Minimal On-Chain Data, Rich Off-Chain Metadata

The discovery registry stores only the four fields needed for on-chain discoverability
and trust signalling: merchant address, display name, metadata URI, and registration
timestamp. The `verified` flag adds a lightweight operator-set trust signal. Everything
else — feature descriptions, pricing plans, logos, social links, subscriber testimonials —
lives at the `metadataURI`.

**Why active subscriber counts are not stored on-chain.** Maintaining an accurate active
subscriber count in the discovery registry would require every `subscribe()` and
`cancelSubscription()` call on every `SubscriptionManager` to write to the discovery
contract. This creates a hard cross-contract dependency in the core payment flow: a
subscribe that fails because the discovery registry's gas is exhausted, or because the
registry has been upgraded incompatibly, would break the base `ISubscription` interface.
More fundamentally, it would permanently couple the discovery mechanism to the payment
mechanism — a violation of the same single-responsibility principle that motivates the
extension interface design. The correct home for aggregated metrics is an off-chain
indexer (The Graph subgraph), which reconstructs counts from the `SubscriptionCreated`
and `SubscriptionCancelled` event stream at no on-chain cost.

**Pagination via `getMerchants(offset, limit)`.** An implementation backed by an
`EnumerableSet` or dynamic array would allow unbounded iteration over the merchant list
in a single call. As the registry grows, such a call becomes a denial-of-service vector:
a caller can trigger an out-of-gas revert that is proportional to the registry size,
and no mitigation is possible without a contract upgrade. Explicit pagination shifts
the responsibility for bounding gas consumption to the caller, where it belongs. A limit
cap of 100 per call provides a practical maximum while keeping individual transactions
within gas limits on any current EVM.

**The `verified` flag.** On-chain verification is analogous to a verified checkmark on
a social platform: it signals that the registry operator has performed some off-chain
due diligence (e.g. confirmed legal identity, checked for scam indicators) but it is
not a cryptographic security guarantee. The mechanism is intentionally simple. More
sophisticated on-chain reputation systems — staking, attestation networks, challenge
mechanisms — can be built on top of the `MerchantRegistered` event stream and the
`verified` flag without modifying this interface.

### 5. ISubscriptionHook vs ISubscriptionReceiver — Separation of Concerns

**`ISubscriptionReceiver`** is called synchronously by `SubscriptionManager` during the
execution of `collectPayment()` and `cancelSubscription()`. It handles success events:
the payment was collected, the subscription was cancelled. Its design is tightly
constrained by the requirement that it must never block the core operation — hence the
`try/catch` wrapper in the reference implementation and the explicit note in the NatSpec
that a reverting callback does not prevent payment collection. The receiver is the
merchant's last-mile notification mechanism for on-chain applications that need to update
their state in the same transaction as the payment.

**`ISubscriptionHook`** is a fundamentally different category of integration. It handles
failure events, and failure handling in subscription billing is inherently a multi-step,
time-delayed process: detect failure, wait for a grace period, attempt retries at
scheduled intervals, finally cancel if the grace period expires without recovery. None of
these steps can be encoded in a single synchronous transaction. A hook that blocks
`collectPayment()` while it waits for a retry window is not just a liveness risk — it is
architecturally impossible. Consequently, `ISubscriptionHook` is designed to be called
by the off-chain Dunning Manager component of the Cadence Automation Service, which
reads `getDunningConfig()` to obtain the merchant's preferred policy and then executes
the dunning sequence asynchronously.

This separation yields three concrete benefits. First, it removes all merchant-defined
dunning logic from the critical path of payment collection. A bug in a merchant's hook
implementation cannot cause `collectPayment()` to revert or exceed its gas limit. Second,
it allows the dunning schedule to span multiple blocks and even multiple days — a retry
seven days after the initial failure is straightforwardly expressed in a keeper's job
scheduler, whereas it would require complex on-chain state machines to handle in a
synchronous contract call. Third, it makes the dunning policy a view-queryable
configuration rather than an opaque code path: any party can read `getDunningConfig(subId)`
to understand what will happen when a payment fails, enabling transparent off-chain
auditing of dunning behaviour.

**The `bytes4` return value pattern.** All callback functions in `ISubscriptionHook`
return their own four-byte selector, following the pattern established by
`IERC721Receiver.onERC721Received()` and `IERC1155Receiver.onERC1155Received()`. This
convention serves as a proof of intent: only a contract that has explicitly read the
interface specification and implemented the function correctly will return the exact
selector value. An EOA address returns nothing; a contract that accidentally accepts
the call returns a default value; a contract that has not implemented the function
reverts. All three non-compliant cases produce a result that differs from the expected
selector, allowing the Dunning Manager to detect opt-outs and fall back to protocol
defaults without having to distinguish between different revert reasons or empty return
data. If the Cadence Automation Service falls back to protocol defaults (7-day grace
period, 2 retries at 48-hour intervals), merchants that do not implement `ISubscriptionHook`
receive reasonable behaviour without any configuration overhead.
