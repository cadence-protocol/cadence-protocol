// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CadenceUSD} from "../src/CadenceUSD.sol";

/// @notice Deploys CadenceUSD (cUSD) to the target network.
/// @dev Run with:
///      forge script script/DeployCUSD.s.sol --rpc-url sepolia --broadcast --verify -vvvv
contract DeployCUSD is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        vm.startBroadcast();

        CadenceUSD token = new CadenceUSD(deployer);

        vm.stopBroadcast();

        console.log("---");
        console.log("CadenceUSD deployed at: ", address(token));
        console.log("Name:                   ", token.name());
        console.log("Symbol:                 ", token.symbol());
        console.log("Decimals:               ", token.decimals());
        console.log("Total supply (raw):     ", token.totalSupply());
        console.log("Deployer balance (raw): ", token.balanceOf(deployer));
        console.log("Network:                ", block.chainid);
        console.log("Deployer:               ", deployer);
    }
}
