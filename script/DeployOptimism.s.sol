// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BovineTracking} from "../src/BovineTracking.sol";
import {BovineNFT} from "../src/BovineNFT.sol";
import {RanchToken} from "../src/RanchToken.sol";

/// @notice Deploys all three contracts to Optimism Sepolia testnet.
///         Reads RPC URL and private key from environment variables.
///
/// Usage:
///   export OPTIMISM_SEPOLIA_RPC_URL=https://sepolia.optimism.io
///   export PRIVATE_KEY_OPTIMISM=0x...
///   forge script script/DeployOptimism.s.sol --broadcast -vvvv

contract DeployOptimism is Script {
    function run() external returns (BovineTracking tracking, BovineNFT nft, RanchToken token) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY_OPTIMISM");
        address deployer = vm.addr(deployerKey);

        console.log("Deploying to Optimism Sepolia from:", deployer);
        console.log("RPC URL:", vm.envString("OPTIMISM_SEPOLIA_RPC_URL"));

        vm.startBroadcast(deployerKey);

        // Deploy BovineTracking with admin role
        tracking = new BovineTracking(deployer);
        console.log("BovineTracking deployed to:", address(tracking));

        // Deploy BovineNFT with base URI for metadata
        nft = new BovineNFT(deployer, "https://api.ranchledger.io/metadata/");
        console.log("BovineNFT deployed to:", address(nft));

        // Deploy RanchToken with 6 decimals (micro-units)
        token = new RanchToken(deployer, 6);
        console.log("RanchToken deployed to:", address(token));

        vm.stopBroadcast();

        // Set NFT receiver on BovineTracking
        vm.startBroadcast(deployerKey);
        tracking.setNFTReceiver(address(nft));
        vm.stopBroadcast();

        console.log("\n=== Optimism Sepolia Deployment Summary ===");
        console.log("BovineTracking:", address(tracking));
        console.log("BovineNFT:     ", address(nft));
        console.log("RanchToken:    ", address(token));
        console.log("Network:       Optimism Sepolia Testnet (Chain ID 11155420)");

        // Write deployment info to file for CI/CD
        string memory json = vm.serializeAddress("deploy", "BovineTracking", address(tracking));
        json = vm.serializeAddress(json, "BovineNFT", address(nft));
        json = vm.serializeAddress(json, "RanchToken", address(token));
        vm.writeJson(json, "deployments/optimism-sepolia.json");

        console.log("\nDeployment info written to deployments/optimism-sepolia.json");
    }
}
