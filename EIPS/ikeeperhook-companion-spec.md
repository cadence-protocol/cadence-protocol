# IKeeperHook — Companion Spec Draft
## Pre-Payment Verification Hooks for ERC-8191 Recurring Payments

**Co-authors:** ThoughtProof, Cadence Protocol
**Status:** Draft v0.2 — PENDING ERC-8191 SPEC REVIEW
**Companion to:** ERC-8191 (Onchain Recurring Payments)
**Pattern source:** IACPHook (ERC-8183), beforeSettle (x402)

**⚠️ UPDATED after reading full ERC-8191 spec (PR #1595):**
- Core payment function is `collectPayment(bytes32 subId)`, not `collect()`
- ERC-8191 already defines `ISubscriptionHook` for post-failure dunning
- Our hook addresses a DIFFERENT gap: pre-payment verification (before collectPayment executes)
- ERC-8191 uses `bytes32` subscription IDs, not `uint256` — updated interface accordingly

---

## 1. Motivation

ERC-8191 defines a KeeperRegistry that executes recurring pull payments on behalf of subscribers. Each payment cycle, a keeper calls `collectPayment()` to transfer funds from subscriber to service provider.

Currently, `collectPayment()` executes unconditionally — if the subscription is active, funds are available, and the interval has elapsed, payment proceeds. ERC-8191 defines `ISubscriptionHook` for **post-failure** dunning (onPaymentFailed, onDunningCancelled), but there is no hook point for external logic to run **before** each collection.

This companion spec defines **IKeeperHook** — an optional interface that runs before and after `collectPayment()` executes. Unlike `ISubscriptionHook` (which handles failure aftermath), IKeeperHook handles **pre-payment verification**:

- **Verification:** Is this renewal still justified? (ThoughtProof)
- **Trust gating:** Is the service provider still trusted? (Maiat, RNWY)
- **Consent:** Has the subscriber approved this cycle? (multi-sig, DAO vote)
- **Rate limiting:** Has the payment frequency changed beyond policy?
- **Compliance:** Does this payment meet regulatory requirements?

---

## 2. Interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IKeeperHook
 * @notice Optional hook interface for ERC-8191 recurring payment cycles.
 *         Hooks execute before and after each keeper collection.
 *         beforeKeep can revert to block a collection cycle.
 *         afterKeep is for bookkeeping and cannot block.
 */
interface IKeeperHook {
    /**
     * @notice Called before a keeper executes a collection cycle.
     * @dev Revert to block the collection. Return silently to allow.
     * @param subId The subscription being collected (bytes32 per ERC-8191)
     * @param cycle The current cycle number (0-indexed)
     * @param amount The amount to be collected this cycle
     * @param merchant The service provider receiving payment
     * @param data Optional hook-specific data
     */
    function beforeKeep(
        bytes32 subId,
        uint256 cycle,
        uint256 amount,
        address merchant,
        bytes calldata data
    ) external;

    /**
     * @notice Called after a successful collection.
     * @dev Cannot revert to undo the collection. For bookkeeping only.
     *      Note: ERC-8191's ISubscriptionHook handles post-FAILURE hooks (dunning).
     *      This afterKeep handles post-SUCCESS bookkeeping (reputation, logging).
     * @param subId The subscription collected (bytes32 per ERC-8191)
     * @param cycle The cycle that was collected
     * @param amount The amount that was collected
     * @param merchant The merchant that received payment
     * @param data Optional hook-specific data
     */
    function afterKeep(
        bytes32 subId,
        uint256 cycle,
        uint256 amount,
        address merchant,
        bytes calldata data
    ) external;
}
```

---

## 3. Execution Flow

```
Keeper triggers collect()
        │
        ▼
┌─────────────────────┐
│  beforeKeep()       │ ← Hook can revert to block
│  - verification     │
│  - trust check      │
│  - consent check    │
└─────────┬───────────┘
          │ (no revert)
          ▼
┌─────────────────────┐
│  collect()          │ ← ERC-8191 core: transfer funds
│  - pull payment     │
│  - update state     │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  afterKeep()        │ ← Bookkeeping only, cannot block
│  - reputation update│
│  - logging          │
│  - feedback loop    │
└─────────────────────┘
```

---

## 4. Hook Patterns

### 4.1 Recurring Verification (ThoughtProof)

Before each renewal, verify whether continuation is still justified.

```solidity
function beforeKeep(
    bytes32 subId,
    uint256 cycle,
    uint256 amount,
    address merchant,
    bytes calldata data
) external {
    // Call off-chain verification service
    // Revert if reasoning is insufficient
    // "Is this renewal still justified given current usage, alternatives, and quality?"
    
    IVerificationOracle oracle = IVerificationOracle(verificationOracle);
    (bool passed, uint256 confidence) = oracle.getVerification(subId, cycle);
    
    require(passed, "KeeperHook: renewal verification failed");
}
```

### 4.2 Trust Gating (Maiat / RNWY)

Before each payment, check that the provider is still trusted.

```solidity
function beforeKeep(
    bytes32 subId,
    uint256 cycle,
    uint256 amount,
    address merchant,
    bytes calldata data
) external {
    uint256 trustScore = ITrustOracle(trustOracle).getScore(merchant);
    require(trustScore >= minimumTrust, "KeeperHook: provider trust below threshold");
}
```

### 4.3 Consent / Approval Gate

Require explicit approval for high-value cycles or policy changes.

```solidity
function beforeKeep(
    bytes32 subId,
    uint256 cycle,
    uint256 amount,
    address merchant,
    bytes calldata data
) external {
    if (amount > autoApproveThreshold) {
        require(approvals[subId][cycle] >= requiredApprovals, "KeeperHook: approval required");
    }
}
```

### 4.4 Feedback Loop (afterKeep)

After successful collection, report outcome to trust systems.

```solidity
function afterKeep(
    bytes32 subId,
    uint256 cycle,
    uint256 amount,
    address merchant,
    bytes calldata data
) external {
    // Report successful payment to reputation system
    ITrustOracle(trustOracle).reportOutcome(merchant, "success", cycle);
}
```

---

## 5. Design Decisions

### 5.1 Why companion spec, not in-core?

ERC-8191 should stay minimal — subscription + keeper + collect. Hooks add complexity that not every implementation needs. A companion spec lets implementations opt in.

### 5.2 Why beforeKeep can revert but afterKeep cannot?

Same pattern as ERC-8183's IACPHook:
- `beforeKeep` is a gate — it can block the action
- `afterKeep` is bookkeeping — undoing a completed payment creates worse problems than letting it through

### 5.3 Why include `data` parameter?

Different hooks need different context. The `data` field lets hook contracts receive arbitrary context (verification results, approval signatures, policy parameters) without changing the interface.

### 5.4 Relationship to existing hook interfaces

| Standard | Hook Interface | Trigger |
|----------|---------------|---------|
| ERC-8183 | IACPHook.beforeAction/afterAction | Job state transitions |
| x402 | beforeSettle/afterSettle | Payment settlement |
| **ERC-8191** | **IKeeperHook.beforeKeep/afterKeep** | **Recurring collection cycles** |

Same pattern, different trigger points. Composable across standards.

---

## 6. Open Questions

1. ~~**Should hooks be per-subscription or global?**~~ **RESOLVED: Per-subscription.** Different subscriptions may require different verification conditions. The subscriber's funds are at risk — they need per-subscription control. (Consensus: ThoughtProof, InsumerAPI, Cadence)

2. **Gas limits for beforeKeep?** Hooks that call external oracles may use significant gas. Should there be a gas cap?

3. ~~**Hook registration:** Who sets the hook?~~ **RESOLVED: The subscriber sets the hook.** Analogous to ERC-8183 where the job creator sets the hook. Prevents a provider from registering a hook that always approves their own payments. The subscriber is the party whose funds are at risk — they control the gate. (Consensus: ThoughtProof, InsumerAPI, Cadence)

4. **Multiple hooks per subscription?** ERC-8183 supports one hook per job. Should ERC-8191 support chaining?

5. **Upgrade path:** Can hooks be changed after subscription creation? Security implications if yes.

---

## 7. Next Steps

- [ ] Review by Cadence Protocol team
- [ ] Align with ERC-8191 core spec (subscription lifecycle, keeper interface)
- [ ] Reference implementations for patterns 4.1-4.4
- [ ] Discuss open questions
- [ ] Formal EIP submission as companion to ERC-8191
