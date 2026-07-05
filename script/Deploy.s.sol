// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {BovineTracking} from "../src/BovineTracking.sol";
import {BovineNFT} from "../src/BovineNFT.sol";
import {RanchToken} from "../src/RanchToken.sol";

/// @notice Deploys the full ranch ledger stack to a local anvil chain.
///         Writes the deployed addresses to deployments/local.json so the
///         off-chain service (services/bovineService.js) can pick them up.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80) // anvil[0]
        );
        address admin = vm.envOr("ADMIN", address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266)); // anvil[0]

        vm.startBroadcast(deployerKey);

        RanchToken token = new RanchToken(admin, 6);
        BovineNFT nft = new BovineNFT(admin, "ipfs://bovine/");
        BovineTracking tracking = new BovineTracking(admin);

        // Grant minter roles to the admin (matches anvil[0]) so the bulk
        // mint script can drive 100 agents from the deployer account.
        nft.grantRole(nft.MINTER_ROLE(), address(tracking));
        tracking.setNFTReceiver(address(nft));

        // Top up the deployer with 1M RANCH for simulation.
        token.mint(admin, 1_000_000e6);

        vm.stopBroadcast();

        // Persist addresses for the off-chain service.
        string memory json = string.concat(
            "{\n",
            '  "chainId": ', vm.toString(block.chainid), ",\n",
            '  "deployer": "', vm.toString(admin), '",\n',
            '  "BovineTracking": "', vm.toString(address(tracking)), '",\n',
            '  "BovineNFT":      "', vm.toString(address(nft)), '",\n',
            '  "RanchToken":     "', vm.toString(address(token)), '"\n',
            "}\n"
        );
        vm.writeFile("deployments/local.json", json);

        console2.log("== Ranch Ledger deployed ==");
        console2.log("BovineTracking:", address(tracking));
        console2.log("BovineNFT:     ", address(nft));
        console2.log("RanchToken:    ", address(token));
        console2.log("Admin:         ", admin);
    }
}
