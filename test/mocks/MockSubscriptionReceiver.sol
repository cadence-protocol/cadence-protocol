// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISubscriptionReceiver} from "../../src/interfaces/ISubscription.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/// @dev Merchant contract that implements ISubscriptionReceiver so the
///      callback paths in SubscriptionManager can be exercised.
contract MockSubscriptionReceiver is ISubscriptionReceiver, ERC165 {
    bytes32 public lastPaymentSubId;
    uint256 public lastPaymentAmount;
    address public lastPaymentToken;
    bytes32 public lastCancelledSubId;

    uint256 public paymentCallCount;
    uint256 public cancelCallCount;

    bool public shouldRevert;

    function setShouldRevert(bool v) external {
        shouldRevert = v;
    }

    function onPaymentCollected(bytes32 subId, uint256 amount, address token) external returns (bytes4) {
        if (shouldRevert) revert("MockReceiver: payment reverted");
        lastPaymentSubId = subId;
        lastPaymentAmount = amount;
        lastPaymentToken = token;
        paymentCallCount++;
        return ISubscriptionReceiver.onPaymentCollected.selector;
    }

    function onSubscriptionCancelled(bytes32 subId) external returns (bytes4) {
        if (shouldRevert) revert("MockReceiver: cancel reverted");
        lastCancelledSubId = subId;
        cancelCallCount++;
        return ISubscriptionReceiver.onSubscriptionCancelled.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ISubscriptionReceiver).interfaceId || super.supportsInterface(interfaceId);
    }
}

/// @dev A contract that is present at an address but does NOT implement ERC-165.
///      Without a fallback, any unmatched call (including supportsInterface) reverts,
///      which exercises the catch branch inside _supportsReceiverInterface.
contract NonERC165Contract {
    // No fallback — unknown selectors will revert, caught by try/catch
}
