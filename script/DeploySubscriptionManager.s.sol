// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SubscriptionManager} from "../src/SubscriptionManager.sol";

/// @title DeploySubscriptionManager
/// @notice Deploys a fresh SubscriptionManager wired to an existing KeeperRegistry.
/// @dev Run with:
///      forge script script/DeploySubscriptionManager.s.sol --rpc-url sepolia --broadcast --verify -vvvv
///
///      Required env vars:
///        PRIVATE_KEY       — deployer private key (hex, no 0x prefix)
///        KEEPER_REGISTRY   — address of the already-deployed KeeperRegistry
contract DeploySubscriptionManager is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address keeperRegistry = vm.envAddress("KEEPER_REGISTRY");

        vm.startBroadcast(pk);
        SubscriptionManager manager = new SubscriptionManager(keeperRegistry, deployer);
        vm.stopBroadcast();

        console.log("---");
        console.log("SubscriptionManager deployed at:", address(manager));
        console.log("KeeperRegistry (existing):      ", keeperRegistry);
        console.log("Network:                        ", block.chainid);
    }
}
