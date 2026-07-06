// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BovineTracking} from "../src/BovineTracking.sol";
import {BovineNFT} from "../src/BovineNFT.sol";
import {FractionalizationManager} from "../src/FractionalizationManager.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract SpawnAndFractionalize is Script {
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

        // Read deployment addresses
        address trackingAddr = _readDeployment("BovineTracking");
        address nftAddr = _readDeployment("BovineNFT");
        address fracMgrAddr = _readDeployment("FractionalizationManager");
        
        BovineTracking tracking = BovineTracking(trackingAddr);
        BovineNFT nft = BovineNFT(nftAddr);
        FractionalizationManager fracMgr = FractionalizationManager(fracMgrAddr);

        // Pre-compute names
        string[] memory fullNames = new string[](AGENT_COUNT);
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            fullNames[i] = string.concat(names[i % names.length], "-", vm.toString(i));
        }

        uint256 beforeCount = tracking.totalBovines();

        // Phase 1: Grant roles + fund agents
        vm.startBroadcast(deployerKey);
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            uint256 agentKey = uint256(keccak256(abi.encodePacked("agent-", vm.toString(i))));
            address agent = vm.addr(agentKey);
            tracking.grantRole(tracking.REGISTRAR_ROLE(), agent);
            payable(agent).transfer(1 ether);
        }
        vm.stopBroadcast();

        // Phase 2: Each agent registers a bovine
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            uint256 agentKey = uint256(keccak256(abi.encodePacked("agent-", vm.toString(i))));
            vm.startBroadcast(agentKey);
            // Generate a 15-digit SISBOV-like ID
            string memory sisbovId = _padTo15(i);
            tracking.addBovine(
                fullNames[i],
                1 + (i % 15),
                breeds[i % breeds.length],
                locations[i % locations.length],
                vm.addr(agentKey)
            );
            vm.stopBroadcast();
        }

        // Phase 3: Batch mint NFTs
        uint256[] memory bovineIds = new uint256[](AGENT_COUNT);
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            bovineIds[i] = tracking.getBovineByName(fullNames[i]);
        }

        vm.startBroadcast(deployerKey);
        nft.mintBatchForBovines(deployer, bovineIds);
        vm.stopBroadcast();

        // Phase 4: Transfer NFTs to agents
        vm.startBroadcast(deployerKey);
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            uint256 tokenId = i + 1; // Token IDs start at 1
            address agent = vm.addr(uint256(keccak256(abi.encodePacked("agent-", vm.toString(i)))));
            nft.transferFrom(deployer, agent, tokenId);
        }
        vm.stopBroadcast();

        // Phase 5: Each agent fractionalizes their NFT
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            uint256 agentKey = uint256(keccak256(abi.encodePacked("agent-", vm.toString(i))));
            address agent = vm.addr(agentKey);
            uint256 tokenId = i + 1;
            
            vm.startBroadcast(agentKey);
            // Approve FractionalizationManager to transfer NFT
            nft.approve(address(fracMgr), tokenId);
            // Fractionalize: 1000 shares at 0.01 ETH each
            fracMgr.fractionalize(address(nft), tokenId, 1000, 0.01 ether);
            vm.stopBroadcast();
        }

        // Summary
        uint256 afterCount = tracking.totalBovines();
        console.log("== Spawn & Fractionalize summary ==");
        console.log("Agents spawned:        ", AGENT_COUNT);
        console.log("Bovines before:        ", beforeCount);
        console.log("Bovines after:         ", afterCount);
        console.log("Bovines added:         ", afterCount - beforeCount);
        console.log("NFTs batch-minted:     ", AGENT_COUNT);
        console.log("NFTs fractionalized:   ", AGENT_COUNT);
        console.log("Shares per cow:        ", uint256(1000));
        console.log("Price per share:       ", uint256(0.01 ether));
        console.log("BovineTracking:        ", trackingAddr);
        console.log("BovineNFT:             ", nftAddr);
        console.log("FractionalizationMgr:  ", fracMgrAddr);
    }

    function _padTo15(uint256 n) internal pure returns (string memory) {
        // Pad number to 15 digits for SISBOV format
        string memory s = vm.toString(n);
        uint256 len = bytes(s).length;
        if (len >= 15) return s;
        bytes memory padding = new bytes(15 - len);
        for (uint256 i = 0; i < padding.length; i++) {
            padding[i] = "0";
        }
        return string.concat(string(padding), s);
    }

    function _readDeployment(string memory key) internal view returns (address) {
        string memory path = "deployments/local.json";
        try vm.readFile(path) returns (string memory json) {
            bytes memory needle = abi.encodePacked('"', key, '": "');
            bytes memory hay = bytes(json);
            uint256 start;
            bool found;
            for (uint256 i = 0; i + needle.length <= hay.length; i++) {
                bool matches = true;
                for (uint256 j = 0; j < needle.length; j++) {
                    if (hay[i + j] != needle[j]) { matches = false; break; }
                }
                if (matches) { start = i + needle.length; found = true; break; }
            }
            require(found, "key not found in deployment file");
            
            bytes memory addrBytes = new bytes(42);
            for (uint256 i = 0; i < 42; i++) {
                addrBytes[i] = hay[start + i];
            }
            return vm.parseAddress(string(addrBytes));
        } catch {
            return address(0);
        }
    }
}