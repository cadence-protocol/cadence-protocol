# IKeeperHook — Companion Spec Draft

> **Status:** Draft for discussion
> **Authors:** Cadence Protocol, ThoughtProof (to be confirmed)
> **Related:** ERC-8191 (Onchain Recurring Payments), ERC-8183 (Agentic Commerce)

---

## Motivation

ERC-8191 defines a minimal interface for pull-based recurring payments. The `KeeperRegistry` allows any permissioned keeper to call `collectPayment` when a payment interval has elapsed. The base standard is intentionally silent on what logic a keeper runs before collecting.

In practice, recurring agentic services surface a class of decisions that one-shot jobs do not: **continuation verification**. Before collecting each cycle's payment, a keeper may need to check whether the service relationship is still valid, whether the subscriber has consented, or whether the provider meets a minimum trust threshold.

`IKeeperHook` standardizes this pre-collection verification surface, keeping it separate from core ERC-8191 so that the base standard remains minimal.

The pattern is directly analogous to:
- `beforeSettle` in ThoughtProof's `pot-x402` (decision verification before x402 payment settlement)
- `beforeAction` in ERC-8183's `IACPHook` (pre/post lifecycle hooks for agentic jobs)

---

## Interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IKeeperHook
/// @notice Optional hook interface for keepers implementing ERC-8191.
///         Called by the keeper before and after each collectPayment.
interface IKeeperHook {
    /// @notice Called before collectPayment is executed.
    /// @param subscriptionId The subscription being collected.
    /// @param cycle The current payment cycle number (0-indexed).
    /// @return allow Whether the keeper should proceed with collection.
    /// @return reason Human-readable reason if allow is false.
    function beforeKeep(
        bytes32 subscriptionId,
        uint256 cycle
    ) external returns (bool allow, string memory reason);

    /// @notice Called after collectPayment completes (or is skipped).
    /// @param subscriptionId The subscription that was processed.
    /// @param cycle The payment cycle number.
    /// @param success Whether collectPayment succeeded on-chain.
    function afterKeep(
        bytes32 subscriptionId,
        uint256 cycle,
        bool success
    ) external;
}
```

---

## Execution Flow

```
KeeperRegistry.collectPayment(subscriptionId)
    │
    ├─ if (hook != address(0))
    │       (allow, reason) = hook.beforeKeep(subscriptionId, cycle)
    │       if (!allow) → emit KeeperHookAborted(subscriptionId, cycle, reason)
    │                   → return (skip collection)
    │
    ├─ SubscriptionManager.collectPayment(subscriptionId)
    │       → transfer token from subscriber to provider
    │       → emit PaymentCollected(subscriptionId, cycle, amount)
    │
    └─ if (hook != address(0))
            hook.afterKeep(subscriptionId, cycle, success)
```

Hooks are registered per-keeper at keeper registration time, not per-subscription. A keeper without a hook registered proceeds with default behavior.

---

## Hook Patterns

### Pattern A — Recurring Verification

Before each collection, verify whether continuation is still justified given usage, quality, and alternatives. Designed for AI-agent service relationships where value delivery may degrade over time.

```typescript
// Off-chain keeper logic (TypeScript/viem)
async function beforeKeep(subscriptionId: string, cycle: number) {
  const result = await verify(await getRenewalContext(subscriptionId), {
    claim: 'Is this renewal still justified given current usage, alternatives, and quality?',
    stakeLevel: 'medium',
    classifyMateriality: true,
  });

  if (result.materiality.hasMaterialDefect) {
    return { allow: false, reason: result.synthesis };
  }
  return { allow: true, reason: '' };
}
```

*Reference: ThoughtProof `pot-x402` `beforeSettle` middleware.*

---

### Pattern B — Trust Gating

Before each collection, verify that the provider maintains a minimum reputation score. Prevents payment to providers that have been flagged or whose score has fallen below a threshold.

```solidity
contract TrustGatedKeeperHook is IKeeperHook {
    IReputationRegistry public immutable reputation;
    uint256 public immutable minScore;

    constructor(address _reputation, uint256 _minScore) {
        reputation = IReputationRegistry(_reputation);
        minScore = _minScore;
    }

    function beforeKeep(bytes32 subscriptionId, uint256 cycle)
        external view override
        returns (bool allow, string memory reason)
    {
        address provider = subscriptionManager.getProvider(subscriptionId);
        uint256 score = reputation.getScore(provider);
        if (score < minScore) {
            return (false, "Provider reputation below threshold");
        }
        return (true, "");
    }

    function afterKeep(bytes32, uint256, bool) external override {}
}
```

*Composable with ERC-8004 (Agent Identity & Reputation).*

---

### Pattern C — Consent / Approval Gate

Before each collection, check whether the subscriber has explicitly re-confirmed intent for the current cycle. Useful for high-value subscriptions or after periods of inactivity.

```solidity
contract ConsentKeeperHook is IKeeperHook {
    // subscriptionId => cycle => approved
    mapping(bytes32 => mapping(uint256 => bool)) public approvals;

    function approveKeep(bytes32 subscriptionId, uint256 cycle) external {
        // Caller must be the subscriber
        require(
            subscriptionManager.getSubscriber(subscriptionId) == msg.sender,
            "Not subscriber"
        );
        approvals[subscriptionId][cycle] = true;
    }

    function beforeKeep(bytes32 subscriptionId, uint256 cycle)
        external view override
        returns (bool allow, string memory reason)
    {
        if (!approvals[subscriptionId][cycle]) {
            return (false, "Subscriber approval not granted for this cycle");
        }
        return (true, "");
    }

    function afterKeep(bytes32, uint256, bool) external override {}
}
```

---

## Open Questions

1. **Hook registration scope**: Per-keeper (proposed above) vs. per-subscription. Per-subscription gives subscribers more control but increases gas cost at creation time.

2. **`afterKeep` use cases**: Currently included for symmetry with ERC-8183's `afterAction`. Are there concrete use cases (e.g., writing reputation attestations after successful collection)?

3. **Gas limits**: Should the spec impose a gas limit on `beforeKeep` to prevent keepers from being griefed by expensive hooks?

4. **Hook failure handling**: If `beforeKeep` reverts (rather than returning `allow: false`), should the keeper skip collection silently or propagate the revert?

---

## Relationship to Other Standards

| Standard | Hook Interface | Trigger |
|---|---|---|
| ERC-8183 | `IACPHook.beforeAction` / `afterAction` | Per job lifecycle event |
| x402 | `beforeSettle` | Per HTTP payment settlement |
| **ERC-8191** | `IKeeperHook.beforeKeep` / `afterKeep` | Per recurring payment cycle |

---

*This is an early draft for collaborative discussion. Interface and patterns subject to change.*
