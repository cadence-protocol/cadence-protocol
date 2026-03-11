// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {KeeperRegistry} from "../src/KeeperRegistry.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";

/// @title Deploy
/// @notice Deploys KeeperRegistry and SubscriptionManager to the target network.
/// @dev Run with:
///      forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify -vvvv
contract Deploy is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        vm.startBroadcast();

        // 1. Deploy KeeperRegistry
        //    - deployer is both owner and initial global keeper
        KeeperRegistry registry = new KeeperRegistry(deployer, deployer);
        console.log("KeeperRegistry deployed at:", address(registry));

        // 2. Deploy SubscriptionManager
        //    - wired to the KeeperRegistry just deployed
        SubscriptionManager manager = new SubscriptionManager(address(registry));
        console.log("SubscriptionManager deployed at:", address(manager));

        vm.stopBroadcast();

        // Summary
        console.log("---");
        console.log("Network:             ", block.chainid);
        console.log("Deployer:            ", deployer);
        console.log("KeeperRegistry:      ", address(registry));
        console.log("SubscriptionManager: ", address(manager));
    }
}
