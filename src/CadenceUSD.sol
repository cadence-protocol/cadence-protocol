// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CadenceUSD
/// @author Cadence Protocol
/// @notice Test stablecoin for the Cadence Protocol testnet.
///         Mimics a USD-pegged ERC-20 with 6 decimals (like USDC).
///         The deployer receives the entire initial supply and retains
///         the ability to mint additional tokens for testing purposes.
contract CadenceUSD is ERC20, Ownable {
    // ── Constants ──────────────────────────────────────────────────────────────

    /// @notice Initial supply: 1,000,000 cUSD
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 6;

    // ── Constructor ────────────────────────────────────────────────────────────

    /// @param initialOwner Address that receives the initial supply and owner rights.
    constructor(address initialOwner) ERC20("Cadence USD", "cUSD") Ownable(initialOwner) {
        _mint(initialOwner, INITIAL_SUPPLY);
    }

    // ── Owner functions ────────────────────────────────────────────────────────

    /// @notice Mint additional cUSD tokens. Restricted to owner.
    /// @dev    Useful for distributing testnet tokens to subscribers.
    /// @param  to     Recipient address
    /// @param  amount Amount in the token's smallest unit (6 decimals)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // ── ERC-20 overrides ───────────────────────────────────────────────────────

    /// @notice Returns 6 decimals, matching USDC conventions.
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
