// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title InsumerKeeperHook
 * @notice Reference IKeeperHook for ERC-8191 recurring payments.
 *         Verifies InsumerAPI ECDSA P-256 attestations before each collection cycle.
 *
 * @dev Integration flow:
 *   1. Off-chain: keeper calls POST /v1/attest with the merchant's wallet and
 *      subscription-specific conditions (e.g., "holds governance token X").
 *   2. Keeper ABI-encodes the attestation fields + P-256 signature into `data`.
 *   3. beforeKeep() verifies the signature via RIP-7212, checks pass/wallet/freshness.
 *   4. If any check fails, beforeKeep reverts and the collection is blocked.
 *
 * Signed payload (from index.js):
 *   JSON.stringify({ id: attestId, pass: allPassed, results: results, attestedAt: ISO })
 *   -> SHA-256 -> ECDSA P-256 sign -> base64 P1363 (64 bytes = r || s)
 *
 * Response shape:
 *   { attestation: { id, pass, results[], passCount, failCount, attestedAt, expiresAt },
 *     sig: "<base64 P1363>", kid: "insumer-attest-v1" }
 *
 * Trust model:
 *   The P-256 signature proves InsumerAPI produced the attestation. The extracted
 *   fields (pass, conditionHash) are relayed by the keeper alongside the signature.
 *   The signature itself covers the full JSON payload — not just these fields — so
 *   the binding between extracted fields and signature relies on honest relay.
 *   For tighter binding in production, have the keeper submit the raw signed payload
 *   bytes and SHA-256 hash them on-chain before verifying the signature (~2000 gas
 *   per payload byte).
 *
 * RIP-7212 P256VERIFY precompile availability:
 *   Base, Optimism, Arbitrum, Polygon, Scroll, ZKsync, Celo, and other L2s.
 *
 * InsumerAPI public key:  https://insumermodel.com/.well-known/jwks.json
 * Verification library:   npm install insumer-verify
 * API docs:               https://insumermodel.com/developers/api-reference/
 *
 * Companion to: cadence-protocol/cadence-protocol EIPS/ikeeperhook-companion-spec.md
 * Pattern:      4.2 (Trust Gating) from the IKeeperHook companion spec
 */

/// @notice IKeeperHook interface -- beforeKeep/afterKeep naming per
///         chasseurmic + ThoughtProof consensus (cadence-protocol PR #1).
interface IKeeperHook {
    function beforeKeep(
        bytes32 subId,
        uint256 cycle,
        uint256 amount,
        address merchant,
        bytes calldata data
    ) external;

    function afterKeep(
        bytes32 subId,
        uint256 cycle,
        uint256 amount,
        address merchant,
        bytes calldata data
    ) external;
}

contract InsumerKeeperHook is IKeeperHook {

    // ─────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────

    error AttestationFailed();           // pass != true
    error InvalidSignature();            // P-256 sig verification failed
    error ConditionMismatch();           // conditionHash doesn't match expected
    error AttestationTooOld();           // block delta exceeds freshness window
    error WalletMismatch();              // attested wallet != merchant
    error NotSubscriber();               // caller not authorized

    // ─────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────

    /// @dev RIP-7212 P256VERIFY precompile address
    address constant P256_VERIFIER = address(0x0100);

    /// @dev Max block age for a fresh attestation (~30 min on L2 at 2s blocks)
    uint256 public constant MAX_BLOCK_AGE = 900;

    // ─────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────

    /// @dev InsumerAPI P-256 public key coordinates.
    ///      Source: https://insumermodel.com/.well-known/jwks.json
    ///      kid: "insumer-attest-v1", crv: P-256, alg: ES256
    ///      Decode JWK "x" and "y" (base64url) to uint256.
    uint256 public immutable pubKeyX;
    uint256 public immutable pubKeyY;

    /// @dev Subscriber who deployed this hook -- controls condition configuration.
    ///      Per companion spec Q3: subscriber sets the hook, not the merchant.
    address public immutable subscriber;

    /// @dev Expected conditionHash per subscription.
    ///      Value: keccak256(abi.encodePacked(conditionHashHexString))
    ///      where conditionHashHexString is results[0].conditionHash from the API
    ///      (SHA-256 hex, "0x"-prefixed, e.g. "0x3a7f1b2c...").
    ///
    ///      For multi-condition attestations, use results[0].conditionHash or
    ///      extend to store multiple hashes.
    mapping(bytes32 => bytes32) public expectedConditionHash;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    event AttestationVerified(bytes32 indexed subId, uint256 cycle, address merchant);
    event ConditionHashSet(bytes32 indexed subId, bytes32 conditionHash);

    // ─────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────

    /// @param _pubKeyX X coordinate of InsumerAPI P-256 public key (uint256)
    /// @param _pubKeyY Y coordinate of InsumerAPI P-256 public key (uint256)
    constructor(uint256 _pubKeyX, uint256 _pubKeyY) {
        pubKeyX = _pubKeyX;
        pubKeyY = _pubKeyY;
        subscriber = msg.sender;
    }

    // ─────────────────────────────────────────────
    // Configuration (subscriber only)
    // ─────────────────────────────────────────────

    /// @notice Set the expected conditionHash for a subscription.
    /// @param subId            ERC-8191 subscription ID (bytes32)
    /// @param _conditionHash   keccak256(abi.encodePacked(insumerConditionHashHex))
    function setConditionHash(bytes32 subId, bytes32 _conditionHash) external {
        if (msg.sender != subscriber) revert NotSubscriber();
        expectedConditionHash[subId] = _conditionHash;
        emit ConditionHashSet(subId, _conditionHash);
    }

    // ─────────────────────────────────────────────
    // IKeeperHook: beforeKeep
    // ─────────────────────────────────────────────

    /// @notice Verify an InsumerAPI attestation before allowing collection.
    /// @dev The keeper ABI-encodes the attestation into `data`:
    ///
    ///      (bool pass, address wallet, bytes32 conditionHash,
    ///       uint256 blockNumber, bytes32 r, bytes32 s, bytes32 messageHash)
    ///
    ///      Mapping from API response:
    ///        pass            <- attestation.pass
    ///        wallet          <- the wallet that was attested (must equal merchant)
    ///        conditionHash   <- keccak256(abi.encodePacked(attestation.results[0].conditionHash))
    ///        blockNumber     <- uint256(attestation.results[0].blockNumber)  (hex to uint)
    ///        r, s            <- decode sig from base64 P1363 (bytes 0-31 = r, bytes 32-63 = s)
    ///        messageHash     <- SHA-256 of the signed payload:
    ///                           JSON.stringify({id, pass, results, attestedAt})
    function beforeKeep(
        bytes32 subId,
        uint256 /* cycle */,
        uint256 /* amount */,
        address merchant,
        bytes calldata data
    ) external override {
        (
            bool pass,
            address wallet,
            bytes32 conditionHash,
            uint256 blockNumber,
            bytes32 r,
            bytes32 s,
            bytes32 messageHash
        ) = abi.decode(data, (bool, address, bytes32, uint256, bytes32, bytes32, bytes32));

        // 1. Attestation must pass
        if (!pass) revert AttestationFailed();

        // 2. Attested wallet must be the merchant receiving payment
        if (wallet != merchant) revert WalletMismatch();

        // 3. Condition hash must match subscriber's configuration
        if (conditionHash != expectedConditionHash[subId]) revert ConditionMismatch();

        // 4. Attestation must be fresh
        if (block.number - blockNumber > MAX_BLOCK_AGE) revert AttestationTooOld();

        // 5. Verify ECDSA P-256 signature via RIP-7212
        if (!_verifyP256(messageHash, r, s)) revert InvalidSignature();

        emit AttestationVerified(subId, block.number, merchant);
    }

    // ─────────────────────────────────────────────
    // IKeeperHook: afterKeep
    // ─────────────────────────────────────────────

    /// @notice Post-collection hook. No-op in this reference implementation.
    /// @dev Extend for pattern 4.4 (feedback loop) -- report successful payment
    ///      to a reputation system.
    function afterKeep(
        bytes32 /* subId */,
        uint256 /* cycle */,
        uint256 /* amount */,
        address /* merchant */,
        bytes calldata /* data */
    ) external override {}

    // ─────────────────────────────────────────────
    // Internal: P-256 signature verification
    // ─────────────────────────────────────────────

    /// @dev Verify P-256 signature using RIP-7212 precompile.
    ///      Input layout: messageHash || r || s || x || y (5 x 32 bytes)
    ///      Returns 1 if valid, 0 otherwise.
    function _verifyP256(bytes32 messageHash, bytes32 r, bytes32 s) internal view returns (bool) {
        (bool success, bytes memory result) = P256_VERIFIER.staticcall(
            abi.encodePacked(messageHash, r, s, pubKeyX, pubKeyY)
        );
        return success && result.length == 32 && abi.decode(result, (uint256)) == 1;
    }
}
