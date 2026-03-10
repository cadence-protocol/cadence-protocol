# Cadence Protocol

> The open ERC standard for onchain recurring payments.

Cadence defines a standard interface for onchain subscriptions — native pull payments, full lifecycle state management, and cross-chain support via ERC-7683. No off-chain relays. No meta-transactions. No bespoke per-protocol implementations.

## Overview

| Layer | Description |
|-------|-------------|
| **ERC Standard** | `ISubscription` interface — subscribe, collectPayment, cancel, pause, resume, getStatus |
| **Automation Service** | Keeper network, scheduler, dunning manager, Stripe-compatible webhooks |
| **SDK & Tooling** | TypeScript SDK, The Graph subgraph, React hooks, CLI |

## Status

✅ **Phase 1 — Core Implementation** (complete)

The `ISubscription` interface, `SubscriptionManager` reference implementation, and `KeeperRegistry` are complete with a full Foundry test suite achieving ≥95% line coverage across all source contracts.

## Repository Structure

```
src/
  interfaces/
    ISubscription.sol       # Core interface: structs, enums, events, errors, ERC-165
  SubscriptionManager.sol   # Reference implementation (ISubscription + ETH escrow)
  KeeperRegistry.sol        # Keeper authorisation registry (global + per-merchant)
test/
  SubscriptionManager.t.sol # Unit + fuzz tests (60 tests)
  KeeperRegistry.t.sol      # Unit tests (30 tests)
  invariants/
    SubscriptionInvariant.t.sol  # Foundry invariant suite (4 invariants)
  mocks/
    MockERC20.sol
    MockKeeperRegistry.sol
    MockSubscriptionReceiver.sol
docs/
  rationale.md              # EIP design rationale
```

## Contracts

### ISubscription (`src/interfaces/ISubscription.sol`)

Defines the standard interface all conforming subscription managers must implement.

- **`SubscriptionTerms`** — token, amount, interval, trialPeriod, maxPayments, originChainId, paymentChainId
- **`Status`** — `Active | PastDue | Paused | Cancelled | Expired`
- **`ISubscriptionReceiver`** — optional merchant callback interface (`onPaymentCollected`, `onSubscriptionCancelled`)
- **ERC-165** — `CADENCE_INTERFACE_ID` constant for interface detection

### SubscriptionManager (`src/SubscriptionManager.sol`)

Reference implementation of `ISubscription`.

- ERC-20 and native ETH payment support
- Pull-payment ETH escrow (subscriber deposits, merchant claims)
- Trial period support (first payment deferred)
- Optional `maxPayments` cap with automatic expiry
- Keeper-gated `collectPayment` via `IKeeperRegistry` (pass `address(0)` for permissionless)
- Optional merchant callbacks via `ISubscriptionReceiver` with `try/catch` isolation
- Reentrancy-guarded via OpenZeppelin `ReentrancyGuard`
- Checks-Effects-Interactions throughout

### KeeperRegistry (`src/KeeperRegistry.sol`)

Two-tier keeper authorisation registry.

- **Global keepers** — authorised by owner for all merchants (via `addKeeper`)
- **Merchant keepers** — authorised by each merchant for their own subscriptions (via `addMerchantKeeper`)
- **Blacklist** — owner can permanently block a keeper address from both tiers
- `isAuthorised(address keeper, address merchant)` — single read combining both tiers and blacklist
- `Ownable2Step` for safe ownership transfers

## Development

```bash
# Install dependencies
forge install

# Build
forge build

# Test
forge test -vv

# Coverage report
forge coverage

# Run invariant suite only
forge test --match-contract SubscriptionInvariantTest -vv
```

## Design Rationale

See [docs/rationale.md](docs/rationale.md) for the reasoning behind key design decisions: bytes32 subscription IDs, pull-payment ETH model, soft-fail collection, PastDue as a computed status, and trial period handling.

## Links

- Website: [cadenceprotocol.build](https://cadenceprotocol.build)
- Discussion: Ethereum Magicians *(coming soon)*
- X: [@cadencefinance](https://x.com/cadencefinance)

## License

MIT
