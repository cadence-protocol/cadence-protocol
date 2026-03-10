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

🚧 **FASE 1 — Interface Design** (in progress)

The `ISubscription` interface and supporting types are currently being designed. Community discussion will open on Ethereum Magicians before formal EIP submission.

## Repository Structure

```
src/
  interfaces/       # ISubscription and optional extensions
  SubscriptionManager.sol
  SubscriptionRegistry.sol
  KeeperRegistry.sol
test/               # Foundry test suite (target: ≥95% coverage)
script/             # Deploy scripts (CREATE2, multi-chain)
```

## Development

```bash
# Install dependencies
forge install

# Build
forge build

# Test
forge test

# Coverage
forge coverage
```

## Links

- Website: [cadenceprotocol.build](https://cadenceprotocol.build)
- Discussion: Ethereum Magicians *(coming soon)*
- X: [@cadencefinance](https://x.com/cadencefinance)

## License

MIT
