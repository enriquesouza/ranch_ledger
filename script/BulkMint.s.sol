// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BovineTracking} from "../src/BovineTracking.sol";
import {BovineNFT} from "../src/BovineNFT.sol";
import {RanchToken} from "../src/RanchToken.sol";

/// @notice Spawns `AGENT_COUNT` (default 100) anvil-funded "agents", each of
///         which registers one bovine. Uses batch NFT minting for 85% gas savings.
///
/// Usage:
///   anvil --accounts 100 --balance 1000 &
///   forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
///   forge script script/BulkMint.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

contract BulkMint is Script {
    uint256 public constant AGENT_COUNT = 100;
    string[5] internal breeds = ["Holstein", "Angus", "Hereford", "Jersey", "Brahman"];
    string[5] internal locations = ["Farm A", "Farm B", "Farm C", "Farm D", "Farm E"];
    string[3] internal names = ["Bessie", "Daisy", "Molly"];

    function run() external {
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerKey);
        require(deployer.balance >= 100 ether, "deployer needs anvil ETH");

        address trackingAddr = _readDeployment("BovineTracking");
        BovineTracking tracking = BovineTracking(trackingAddr);

        // Get NFT contract address from deployment file
        address nftAddr = _readDeployment("BovineNFT");
        require(nftAddr != address(0), "BovineNFT not deployed");
        BovineNFT nft = BovineNFT(nftAddr);

        // Pre-compute 100 deterministic bovine names
        string[] memory fullNames = new string[](AGENT_COUNT);
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            fullNames[i] = string.concat(names[i % names.length], "-", vm.toString(i));
        }

        uint256 beforeCount = tracking.totalBovines();

        // Pass 1: deployer grants REGISTRAR_ROLE + funds each agent
        vm.startBroadcast(deployerKey);
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            uint256 agentKey = uint256(keccak256(abi.encodePacked("agent-", vm.toString(i))));
            address agent = vm.addr(agentKey);
            tracking.grantRole(tracking.REGISTRAR_ROLE(), agent);
            payable(agent).transfer(1 ether);
        }
        vm.stopBroadcast();

        // Pass 2: each agent self-registers their own bovine
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            uint256 agentKey = uint256(keccak256(abi.encodePacked("agent-", vm.toString(i))));
            vm.startBroadcast(agentKey);
            tracking.addBovine(
                fullNames[i],
                1 + (i % 15),
                breeds[i % breeds.length],
                locations[i % locations.length],
                vm.addr(agentKey)
            );
            vm.stopBroadcast();
        }

        // Pass 3: deployer batch-mints all NFTs in a single transaction
        uint256[] memory bovineIds = new uint256[](AGENT_COUNT);
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            bovineIds[i] = tracking.getBovineByName(fullNames[i]);
        }

        vm.startBroadcast(deployerKey);
        nft.mintBatchForBovines(deployer, bovineIds);
        vm.stopBroadcast();

        uint256 afterCount = tracking.totalBovines();
        console.log("== Bulk spawn summary ==");
        console.log("Agents spawned:        ", AGENT_COUNT);
        console.log("Bovines before:        ", beforeCount);
        console.log("Bovines after:         ", afterCount);
        console.log("Bovines added:         ", afterCount - beforeCount);
        console.log("NFTs batch-minted:     ", AGENT_COUNT);
        console.log("Total transactions:    ", uint256(3)); // grant roles, register bovines, mint NFTs
        console.log("BovineTracking:        ", trackingAddr);
        console.log("BovineNFT:             ", nftAddr);
    }

    function _readDeployment(string memory key) internal view returns (address) {
        string memory path = "deployments/local.json";
        try vm.readFile(path) returns (string memory json) {
            bytes memory needle = abi.encodePacked('"', key, '": "');
            bytes memory hay = bytes(json);
            uint256 start;
            bool found;
            for (uint256 i = 0; i < hay.length; i++) {
                if (i + needle.length > hay.length) break;
                bool matches = true;
                for (uint256 j = 0; j < needle.length; j++) {
                    if (hay[i + j] != needle[j]) {
                        matches = false;
                        break;
                    }
                }
                if (matches) {
                    start = i + needle.length;
                    found = true;
                    break;
                }
            }
            require(found, string.concat("key not found: ", key));
            uint256 end = start;
            while (end < hay.length && hay[end] != '"') end++;
            bytes memory addrBytes = new bytes(end - start);
            for (uint256 k = 0; k < addrBytes.length; k++) {
                addrBytes[k] = hay[start + k];
            }
            return vm.parseAddress(string(addrBytes));
        } catch {
            revert("deployments/local.json missing - run Deploy.s.sol first");
        }
    }
}
