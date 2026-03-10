// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Implements the single-argument isAuthorized(address) interface that
///      SubscriptionManager's internal IKeeperRegistry uses.  The real
///      KeeperRegistry exposes isAuthorised(address,address) — this shim
///      bridges the gap for unit tests.
contract MockKeeperRegistry {
    mapping(address => bool) private _authorized;

    function setAuthorized(address keeper, bool status) external {
        _authorized[keeper] = status;
    }

    function isAuthorized(address keeper) external view returns (bool) {
        return _authorized[keeper];
    }
}
