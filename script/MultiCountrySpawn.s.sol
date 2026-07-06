// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BovineTracking} from "../src/BovineTracking.sol";
import {BovineNFT} from "../src/BovineNFT.sol";
import {QRCodeRegistry} from "../src/QRCodeRegistry.sol";
import {FractionalizationManager} from "../src/FractionalizationManager.sol";
import {RanchToken} from "../src/RanchToken.sol";

/// @title MultiCountrySpawn
/// @notice Spawns 100 farmers from 8 countries, each registering bovines with
///         their own national ID system (SISBOV, USDA ANID, EU ISO, NLIS, MARA,
///         GCC GSO 2057). Mints NFTs, generates QR codes, and fractionalizes.
///
/// Usage:
///   anvil --accounts 100 --balance 1000 &
///   forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
///   forge script script/MultiCountrySpawn.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract MultiCountrySpawn is Script {
    uint256 public constant AGENT_COUNT = 100;

    struct FarmerInfo {
        string countryCode;
        string nationalId;
        string earTag;
        string breed;
        string location;
    }

    string[5] internal breeds = ["Holstein", "Angus", "Hereford", "Jersey", "Brahman"];
    string[8] internal countries = ["BR", "US", "DE", "AU", "CN", "SA", "AE", "QA"];
    uint256[8] internal distribution = [40, 20, 10, 10, 8, 5, 4, 3]; // 100 total

    function run() external {
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerKey);
        require(deployer.balance >= 100 ether, "deployer needs anvil ETH");

        // Read deployment addresses (Deploy.s.sol writes 3 contracts;
        // QRCodeRegistry and FractionalizationManager are deployed here if
        // they are not already in the deployment file).
        address trackingAddr = _readDeployment("BovineTracking");
        address nftAddr = _readDeployment("BovineNFT");
        address tokenAddr = _readDeployment("RanchToken");
        address qrAddr = _readDeployment("QRCodeRegistry");
        address fracAddr = _readDeployment("FractionalizationManager");

        BovineTracking tracking = BovineTracking(trackingAddr);
        BovineNFT nft = BovineNFT(nftAddr);
        RanchToken token = RanchToken(tokenAddr);

        // Deploy QRCodeRegistry + FractionalizationManager if not yet deployed
        QRCodeRegistry qrRegistry;
        FractionalizationManager fracMgr;
        if (qrAddr == address(0)) {
            vm.startBroadcast(deployerKey);
            qrRegistry = new QRCodeRegistry(deployer);
            vm.stopBroadcast();
            qrAddr = address(qrRegistry);
            console.log("Deployed QRCodeRegistry at:", qrAddr);
        } else {
            qrRegistry = QRCodeRegistry(qrAddr);
        }
        if (fracAddr == address(0)) {
            vm.startBroadcast(deployerKey);
            fracMgr = new FractionalizationManager();
            vm.stopBroadcast();
            fracAddr = address(fracMgr);
            console.log("Deployed FractionalizationManager at:", fracAddr);
        } else {
            fracMgr = FractionalizationManager(fracAddr);
        }

        // Generate farmer info for all 100 agents
        FarmerInfo[] memory farmers = new FarmerInfo[](AGENT_COUNT);
        uint256 idx = 0;
        for (uint8 c = 0; c < countries.length; c++) {
            for (uint256 j = 0; j < distribution[c]; j++) {
                farmers[idx] = FarmerInfo({
                    countryCode: countries[c],
                    nationalId: _generateNationalId(countries[c], idx),
                    earTag: string.concat(countries[c], "-EAR-", vm.toString(idx)),
                    breed: breeds[idx % breeds.length],
                    location: string.concat(countries[c], "-Farm-", vm.toString(j % 5))
                });
                idx++;
            }
        }
        require(idx == AGENT_COUNT, "distribution mismatch");

        // Pre-compute names
        string[] memory fullNames = new string[](AGENT_COUNT);
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            fullNames[i] = string.concat("Cow-", vm.toString(i));
        }

        uint256 beforeCount = tracking.totalBovines();

        // Phase 1: Grant roles + fund agents
        vm.startBroadcast(deployerKey);
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            uint256 agentKey = _agentKey(i);
            address agent = vm.addr(agentKey);
            tracking.grantRole(tracking.REGISTRAR_ROLE(), agent);
            payable(agent).transfer(1 ether);
        }
        vm.stopBroadcast();

        // Phase 2: Each agent registers a bovine with their national ID
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            uint256 agentKey = _agentKey(i);
            vm.startBroadcast(agentKey);
            tracking.addBovineWithId(
                fullNames[i],
                1 + (i % 15),
                farmers[i].breed,
                farmers[i].location,
                vm.addr(agentKey),
                farmers[i].countryCode,
                farmers[i].nationalId,
                farmers[i].earTag
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

        // Phase 4: Generate QR codes for all bovines
        vm.startBroadcast(deployerKey);
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            uint256 bovineId = bovineIds[i];
            string memory metadataURI = string.concat("ipfs://bovine/", vm.toString(bovineId), "/metadata.json");
            string memory qrHash = string.concat("Qm", vm.toString(bovineId));
            qrRegistry.generateQRCode(bovineId, metadataURI, qrHash);
        }
        vm.stopBroadcast();

        // Phase 5: Transfer NFTs to agents + fractionalize
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            uint256 agentKey = _agentKey(i);
            address agent = vm.addr(agentKey);
            uint256 tokenId = i + 1;

            // Transfer NFT to agent
            vm.startBroadcast(deployerKey);
            nft.transferFrom(deployer, agent, tokenId);
            vm.stopBroadcast();

            // Agent fractionalizes
            vm.startBroadcast(agentKey);
            nft.approve(address(fracMgr), tokenId);
            fracMgr.fractionalize(address(nft), tokenId, 1000, 0.01 ether);
            vm.stopBroadcast();
        }

        // Summary
        uint256 afterCount = tracking.totalBovines();
        console.log("=== Multi-Country Spawn Summary ===");
        console.log("Total farmers spawned:  ", AGENT_COUNT);
        console.log("Bovines before:         ", beforeCount);
        console.log("Bovines after:          ", afterCount);
        console.log("Bovines added:         ", afterCount - beforeCount);
        console.log("NFTs batch-minted:     ", AGENT_COUNT);
        console.log("QR codes generated:   ", AGENT_COUNT);
        console.log("NFTs fractionalized:  ", AGENT_COUNT);
        console.log("Countries represented: 8 (BR, US, EU, AU, CN, SA, AE, QA)");
        console.log("BovineTracking:        ", trackingAddr);
        console.log("BovineNFT:             ", nftAddr);
        console.log("QRCodeRegistry:        ", qrAddr);
        console.log("FractionalizationMgr:  ", fracAddr);
    }

    function _agentKey(uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked("farmer-", vm.toString(i))));
    }

    function _generateNationalId(string memory country, uint256 idx) internal pure returns (string memory) {
        bytes32 c = keccak256(bytes(country));

        // BR: SISBOV 15-digit numeric
        if (c == keccak256("BR")) return _padDigits(idx, 15);
        // US: USDA ANID 840 + 12 digits
        if (c == keccak256("US")) return string.concat("840", _padDigits(idx, 12));
        // DE: EU ISO format
        if (c == keccak256("DE")) return string.concat("DE00HERD", _padDigits(idx, 3));
        // AU: NLIS 12-digit
        if (c == keccak256("AU")) return _padDigits(idx, 12);
        // CN: MARA 15-digit
        if (c == keccak256("CN")) return _padDigits(idx, 15);
        // SA: GSO 2057 SA-XXXXXX-XXXX
        if (c == keccak256("SA")) return string.concat("SA-", _padDigits(idx, 6), "-", _padDigits(idx, 4));
        // AE: GSO 2057 AE-XXXXXX-XXXX
        if (c == keccak256("AE")) return string.concat("AE-", _padDigits(idx, 6), "-", _padDigits(idx, 4));
        // QA: GSO 2057 QA-XXXXXX-XXXX
        if (c == keccak256("QA")) return string.concat("QA-", _padDigits(idx, 6), "-", _padDigits(idx, 4));

        return _padDigits(idx, 15);
    }

    function _padDigits(uint256 n, uint256 targetLen) internal pure returns (string memory) {
        string memory s = vm.toString(n);
        uint256 len = bytes(s).length;
        if (len >= targetLen) return s;
        bytes memory padding = new bytes(targetLen - len);
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
                bool matches;
                {
                    matches = true;
                    for (uint256 j = 0; j < needle.length; j++) {
                        if (hay[i + j] != needle[j]) {
                            matches = false;
                            break;
                        }
                    }
                }
                if (matches) {
                    start = i + needle.length;
                    found = true;
                    break;
                }
            }
            if (!found) return address(0);

            // Find the closing quote to robustly extract the address
            uint256 end = start;
            while (end < hay.length && hay[end] != '"') end++;
            bytes memory addrBytes = new bytes(end - start);
            for (uint256 i = 0; i < addrBytes.length; i++) {
                addrBytes[i] = hay[start + i];
            }
            return vm.parseAddress(string(addrBytes));
        } catch {
            return address(0);
        }
    }
}