# Contributing to Cadence Protocol

Cadence Protocol is an open ERC standard for onchain recurring payments. Contributions are welcome across the full stack — the core standard, reference implementation, companion specs, tests, and documentation.

## Areas of contribution

### 1. ERC Standard (`src/interfaces/ISubscription.sol`)

Changes to the core interface are high-impact and require careful consideration. Before opening a PR:

- Open a discussion on [Ethereum Magicians](https://ethereum-magicians.org/t/erc-standard-interface-for-onchain-recurring-payments/27946) first — breaking changes to the interface need community buy-in.
- Keep the core interface minimal. Optional extensions (e.g. `ISubscriptionGenericPayment`) should be proposed as additive interfaces, not modifications to `ISubscription`.
- Update `docs/rationale.md` to explain the reasoning behind any interface change.

### 2. Reference Implementation (`src/SubscriptionManager.sol`, `src/KeeperRegistry.sol`)

Improvements to the reference implementation must:

- Maintain 100% line coverage on production contracts (`forge coverage`).
- Pass all 94 existing tests plus any new tests covering the changed behaviour.
- Respect the Checks-Effects-Interactions pattern and `ReentrancyGuard` usage throughout.
- Not change the `ISubscription` interface unless accompanied by a standard proposal (see above).

### 3. Companion Specs (`docs/`)

Companion specifications extend the standard without modifying the core interface. Current drafts:

| Spec | File | Status |
|------|------|--------|
| `IKeeperHook` | `docs/IKeeperHook-draft.md` | Draft — feedback welcome |

To propose a new companion spec:

1. Add a Markdown draft to `docs/` following the structure of existing specs (interface, execution flow, hook patterns, open questions).
2. Reference the spec in a comment on the [Ethereum Magicians thread](https://ethereum-magicians.org/t/erc-standard-interface-for-onchain-recurring-payments/27946).
3. Open a PR with the draft — Solidity implementation can follow separately.

### 4. Tests (`test/`)

New tests are always welcome. Follow the existing conventions:

- Unit tests in `test/SubscriptionManager.t.sol` and `test/KeeperRegistry.t.sol`.
- Fuzz tests use `vm.assume` to bound inputs; keep them fast (no `--fuzz-runs` override needed for CI).
- Invariant tests in `test/invariants/` — new invariants must hold across 256 runs × 128k calls.
- Mock contracts in `test/mocks/` — one mock per interface, minimal implementation.

### 5. Documentation (`docs/`)

- `docs/rationale.md` — design decisions and tradeoffs.
- `docs/security-considerations.md` — threat model and known limitations.
- `docs/test-cases.md` — human-readable test case descriptions.

Keep documentation in sync with code changes. If you change behaviour in `SubscriptionManager.sol`, update the relevant doc.

## Code style

- Solidity `^0.8.20`.
- Named errors over `require` strings.
- NatSpec on all public and external functions.
- No magic numbers — use named constants.
- Follow the style of existing contracts (`ISubscription.sol` is the reference).

## Submitting a PR

1. One concern per PR — interface change, implementation fix, companion spec, or test addition. Mixed PRs will be asked to split.
2. Include a brief description of the problem being solved and any trust or security assumptions.
3. Run the full test suite before opening: `forge test -vv`.
4. For companion specs that introduce new Solidity interfaces, add the interface to `src/interfaces/`.

## Running tests

```bash
forge install
forge build
forge test -vv
forge coverage
```

## Discussion

- [Ethereum Magicians thread](https://ethereum-magicians.org/t/erc-standard-interface-for-onchain-recurring-payments/27946) — ERC-level design questions
- GitHub Issues — bugs, implementation questions, feature requests

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
