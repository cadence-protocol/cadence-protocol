// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {KeeperRegistry} from "../src/KeeperRegistry.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";
import {CadenceUSD} from "../src/CadenceUSD.sol";

/// @title Deploy
/// @notice Deploys KeeperRegistry, SubscriptionManager, and CadenceUSD to the target network.
/// @dev Run with:
///      forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify -vvvv
contract Deploy is Script {
    function run() external {
        uint256 pk      = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // 1. Deploy KeeperRegistry
        //    - deployer is both owner and initial global keeper
        KeeperRegistry registry = new KeeperRegistry(deployer, deployer);
        console.log("KeeperRegistry deployed at:   ", address(registry));

        // 2. Deploy SubscriptionManager
        //    - wired to the KeeperRegistry just deployed
        SubscriptionManager manager = new SubscriptionManager(address(registry));
        console.log("SubscriptionManager deployed at:", address(manager));

        // 3. Deploy CadenceUSD test token
        //    - all 1,000,000 cUSD minted to deployer
        CadenceUSD cusd = new CadenceUSD(deployer);
        console.log("CadenceUSD deployed at:       ", address(cusd));

        vm.stopBroadcast();

        // Summary
        console.log("---");
        console.log("Network:             ", block.chainid);
        console.log("Deployer:            ", deployer);
        console.log("KeeperRegistry:      ", address(registry));
        console.log("SubscriptionManager: ", address(manager));
        console.log("CadenceUSD (cUSD):   ", address(cusd));
        console.log("cUSD supply (raw):   ", cusd.totalSupply());
    }
}
