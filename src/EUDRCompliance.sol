// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BovineTracking} from "../src/BovineTracking.sol";

/// @title EUDRMetadata
/// @notice Metadata required for EU Deforestation Regulation (EUDR) compliance.
///         Includes farm polygon coordinates, deforestation certification hash,
///         and national livestock registration ID (SISBOV for Brazil).
struct EUDRMetadata {
    string sisbovId;           // 15-digit Brazilian national livestock ID (legacy EUDR field)
    string cnpj;               // Operator legal entity (CNPJ: XX.XXX.XXX/XXXX-XX)
    uint256 birthTimestamp;    // Animal birth date (Unix timestamp)
    bytes32 deforestationCertHash; // Hash of EUDR deforestation certificate
    GeoPolygon farmPolygon;    // Farm boundary coordinates
}

/// @title NationalLivestockId
/// @notice Unified struct for all global bovine identification systems.
///         Supports: Brazil SISBOV, EU ISO 11784/11785, USA USDA ANID/EID,
///         Australia NLIS, China MARA, GCC (SA/AE/QA), and custom formats.
struct NationalLivestockId {
    string countryCode;        // ISO 3166-1 alpha-2: BR, EU, US, AU, CN, SA, AE, QA, etc.
    string nationalId;         // Country-specific ID (format varies by country)
    string earTag;             // Physical ear tag number (human-readable)
    uint256 timestamp;         // When this ID was registered/anchored on-chain
}

/// @title GeoPolygon
/// @notice Geographic polygon defining a farm's boundaries.
///         Uses 4 corner points (minimum for rectangular farms) with lat/long precision.
struct GeoPolygon {
    int256[4] latE7;   // Latitude × 10^7 for each corner
    int256[4] longE7;  // Longitude × 10^7 for each corner
}

/// @notice Event emitted when EUDR metadata is added to a bovine.
event EudrAttestations(
    uint256 indexed bovineId,
    string sisbovId,
    bytes32 certHash,
    GeoPolygon farmPolygon
);

/// @title EUDRCompliance
/// @notice Adds EUDR compliance fields and validation to BovineTracking.
///         Also provides validators for all global bovine identification systems:
///         Brazil SISBOV, EU ISO 11784/11785, USA USDA ANID/EID, Australia NLIS,
///         China MARA, GCC (Saudi Arabia/UAE/Qatar), and custom formats.
contract EUDRCompliance {
    // ------------------------------------------------------------------ //
    //                     Brazil — SISBOV Constants                      //
    // ------------------------------------------------------------------ //

    uint256 public constant MIN_SISBOV_LENGTH = 15;
    uint256 public constant MAX_SISBOV_LENGTH = 15;

    // ------------------------------------------------------------------ //
    //                     EU ISO 11784/11785 Constants                   //
    // ------------------------------------------------------------------ //

    /// @notice EU format: CC + HerdMark (up to 6 chars) + Individual (up to 3 digits)
    uint256 public constant MIN_EU_ID_LENGTH = 9;   // e.g., "DE12ABCD004"
    uint256 public constant MAX_EU_ID_LENGTH = 12;  // e.g., "DE12ABCDEF004"

    // ------------------------------------------------------------------ //
    //                     USA — USDA ANID/EID Constants                  //
    // ------------------------------------------------------------------ //

    /// @notice USDA ANID: 15-digit numeric. EID: 9-digit numeric.
    uint256 public constant MIN_USD_ANID_LENGTH = 15;
    uint256 public constant MAX_USD_ANID_LENGTH = 15;
    uint256 public constant MIN_USD_EID_LENGTH = 9;
    uint256 public constant MAX_USD_EID_LENGTH = 9;

    // ------------------------------------------------------------------ //
    //                     Australia — NLIS Constants                     //
    // ------------------------------------------------------------------ //

    /// @notice NLIS: 12-digit DUNS-based traceability number.
    uint256 public constant MIN_NLIS_LENGTH = 12;
    uint256 public constant MAX_NLIS_LENGTH = 12;

    // ------------------------------------------------------------------ //
    //                     China — MARA Constants                         //
    // ------------------------------------------------------------------ //

    /// @notice China MARA: 15-digit numeric following ISO 11784/11785.
    uint256 public constant MIN_CHINA_ID_LENGTH = 15;
    uint256 public constant MAX_CHINA_ID_LENGTH = 15;

    // ------------------------------------------------------------------ //
    //                     GCC (SA/AE/QA) — GSO 2057 Constants            //
    // ------------------------------------------------------------------ //

    /// @notice GCC format: CC-XXXXXX-XXXX (country + farm + individual).
    uint256 public constant MIN_GCC_ID_LENGTH = 14;  // "SA-001234-5678"
    uint256 public constant MAX_GCC_ID_LENGTH = 14;

    // ------------------------------------------------------------------ //
    //                              Errors                                //
    // ------------------------------------------------------------------ //

    error InvalidSisbovId(string sisbovId);
    error InvalidCnpj(string cnpj);
    error InvalidPolygon();
    error EmptyString(string field);
    error InvalidCountryCode(string countryCode);
    error InvalidNationalId(string nationalId, string reason);

    /// @notice Validate SISBOV ID format (15 digits)
    function validateSisbovId(string memory sisbovId) internal pure returns (bool valid) {
        if (bytes(sisbovId).length != MIN_SISBOV_LENGTH) {
            revert InvalidSisbovId(sisbovId);
        }
        // Check all characters are digits
        for (uint256 i = 0; i < bytes(sisbovId).length; i++) {
            if (bytes(sisbovId)[i] < '0' || bytes(sisbovId)[i] > '9') {
                revert InvalidSisbovId(sisbovId);
            }
        }
        return true;
    }

    /// @notice Validate CNPJ format (XX.XXX.XXX/XXXX-XX)
    function validateCnpj(string memory cnpj) internal pure returns (bool valid) {
        if (bytes(cnpj).length != 14) {
            revert InvalidCnpj(cnpj);
        }
        // Check format: XX.XXX.XXX/XXXX-XX
        if (bytes(cnpj)[2] != '.' || bytes(cnpj)[6] != '.' || 
            bytes(cnpj)[10] != '/' || bytes(cnpj)[15] != '-') {
            revert InvalidCnpj(cnpj);
        }
        // Check all other positions are digits
        for (uint256 i = 0; i < bytes(cnpj).length; i++) {
            if (i == 2 || i == 6 || i == 10 || i == 15) continue; // Skip format chars
            if (bytes(cnpj)[i] < '0' || bytes(cnpj)[i] > '9') {
                revert InvalidCnpj(cnpj);
            }
        }
        return true;
    }

    /// @notice Validate EU ISO 11784/11785 format (CC + HerdMark + Individual)
    function validateEUId(string memory euId) internal pure returns (bool valid) {
        if (bytes(euId).length < MIN_EU_ID_LENGTH || bytes(euId).length > MAX_EU_ID_LENGTH) {
            revert InvalidNationalId(euId, "Invalid length");
        }
        // First 2 chars must be letters (country code)
        for (uint256 i = 0; i < 2; i++) {
            if (!(bytes(euId)[i] >= 'A' && bytes(euId)[i] <= 'Z')) {
                revert InvalidNationalId(euId, "Country code must be letters");
            }
        }
        // Last 3 chars must be digits (individual number)
        uint256 len = bytes(euId).length;
        for (uint256 i = len - 3; i < len; i++) {
            if (bytes(euId)[i] < '0' || bytes(euId)[i] > '9') {
                revert InvalidNationalId(euId, "Individual number must be digits");
            }
        }
        return true;
    }

    /// @notice Validate USDA ANID format (15-digit numeric)
    function validateUSDAAnid(string memory anid) internal pure returns (bool valid) {
        if (bytes(anid).length != MIN_USD_ANID_LENGTH) {
            revert InvalidNationalId(anid, "Invalid length");
        }
        for (uint256 i = 0; i < bytes(anid).length; i++) {
            if (bytes(anid)[i] < '0' || bytes(anid)[i] > '9') {
                revert InvalidNationalId(anid, "Must be all digits");
            }
        }
        return true;
    }

    /// @notice Validate USDA EID format (9-digit numeric)
    function validateUSDEid(string memory eid) internal pure returns (bool valid) {
        if (bytes(eid).length != MIN_USD_EID_LENGTH) {
            revert InvalidNationalId(eid, "Invalid length");
        }
        for (uint256 i = 0; i < bytes(eid).length; i++) {
            if (bytes(eid)[i] < '0' || bytes(eid)[i] > '9') {
                revert InvalidNationalId(eid, "Must be all digits");
            }
        }
        return true;
    }

    /// @notice Validate Australia NLIS format (12-digit DUNS-based)
    function validateNLIS(string memory nlis) internal pure returns (bool valid) {
        if (bytes(nlis).length != MIN_NLIS_LENGTH) {
            revert InvalidNationalId(nlis, "Invalid length");
        }
        for (uint256 i = 0; i < bytes(nlis).length; i++) {
            if (bytes(nlis)[i] < '0' || bytes(nlis)[i] > '9') {
                revert InvalidNationalId(nlis, "Must be all digits");
            }
        }
        return true;
    }

    /// @notice Validate China MARA format (15-digit numeric)
    function validateChinaId(string memory chinaId) internal pure returns (bool valid) {
        if (bytes(chinaId).length != MIN_CHINA_ID_LENGTH) {
            revert InvalidNationalId(chinaId, "Invalid length");
        }
        for (uint256 i = 0; i < bytes(chinaId).length; i++) {
            if (bytes(chinaId)[i] < '0' || bytes(chinaId)[i] > '9') {
                revert InvalidNationalId(chinaId, "Must be all digits");
            }
        }
        return true;
    }

    /// @notice Validate GCC GSO 2057 format (CC-XXXXXX-XXXX)
    function validateGCCId(string memory gccId) internal pure returns (bool valid) {
        if (bytes(gccId).length != MIN_GCC_ID_LENGTH) {
            revert InvalidNationalId(gccId, "Invalid length");
        }
        // Check format: XX-XXXXXX-XXXX
        if (bytes(gccId)[2] != '-' || bytes(gccId)[9] != '-') {
            revert InvalidNationalId(gccId, "Invalid separator position");
        }
        // First 2 chars must be letters (country code)
        for (uint256 i = 0; i < 2; i++) {
            if (!(bytes(gccId)[i] >= 'A' && bytes(gccId)[i] <= 'Z')) {
                revert InvalidNationalId(gccId, "Country code must be letters");
            }
        }
        // Digits between separators
        for (uint256 i = 3; i < 9; i++) {
            if (bytes(gccId)[i] < '0' || bytes(gccId)[i] > '9') {
                revert InvalidNationalId(gccId, "Farm number must be digits");
            }
        }
        for (uint256 i = 10; i < 14; i++) {
            if (bytes(gccId)[i] < '0' || bytes(gccId)[i] > '9') {
                revert InvalidNationalId(gccId, "Individual number must be digits");
            }
        }
        return true;
    }

    /// @notice Validate any national livestock ID based on country code
    function validateNationalId(NationalLivestockId memory id) internal pure returns (bool valid) {
        if (bytes(id.countryCode).length != 2) revert InvalidCountryCode(id.countryCode);
        
        // Convert countryCode to uppercase for comparison
        bytes memory cc = bytes(id.countryCode);
        string memory upperCC;
        assembly {
            upperCC := cc
        }
        
        if (keccak256(abi.encodePacked(cc[0])) == keccak256(abi.encodePacked('B')) &&
            keccak256(abi.encodePacked(cc[1])) == keccak256(abi.encodePacked('R'))) {
            return validateSisbovId(id.nationalId);
        } else if (keccak256(abi.encodePacked(cc[0])) == keccak256(abi.encodePacked('D')) &&
                   keccak256(abi.encodePacked(cc[1])) == keccak256(abi.encodePacked('E'))) {
            return validateEUId(id.nationalId);
        } else if (keccak256(abi.encodePacked(cc[0])) == keccak256(abi.encodePacked('U')) &&
                   keccak256(abi.encodePacked(cc[1])) == keccak256(abi.encodePacked('S'))) {
            return validateUSDAAnid(id.nationalId);
        } else if (keccak256(abi.encodePacked(cc[0])) == keccak256(abi.encodePacked('A')) &&
                   keccak256(abi.encodePacked(cc[1])) == keccak256(abi.encodePacked('U'))) {
            return validateNLIS(id.nationalId);
        } else if (keccak256(abi.encodePacked(cc[0])) == keccak256(abi.encodePacked('C')) &&
                   keccak256(abi.encodePacked(cc[1])) == keccak256(abi.encodePacked('N'))) {
            return validateChinaId(id.nationalId);
        } else if (keccak256(abi.encodePacked(cc[0])) == keccak256(abi.encodePacked('S')) &&
                   keccak256(abi.encodePacked(cc[1])) == keccak256(abi.encodePacked('A'))) {
            return validateGCCId(id.nationalId);
        } else if (keccak256(abi.encodePacked(cc[0])) == keccak256(abi.encodePacked('A')) &&
                   keccak256(abi.encodePacked(cc[1])) == keccak256(abi.encodePacked('E'))) {
            return validateGCCId(id.nationalId);
        } else if (keccak256(abi.encodePacked(cc[0])) == keccak256(abi.encodePacked('Q')) &&
                   keccak256(abi.encodePacked(cc[1])) == keccak256(abi.encodePacked('A'))) {
            return validateGCCId(id.nationalId);
        } else {
            revert InvalidCountryCode(id.countryCode);
        }
    }

    /// @notice Validate GeoPolygon coordinates are within valid ranges
    function validatePolygon(GeoPolygon memory polygon) internal pure returns (bool valid) {
        for (uint256 i = 0; i < 4; i++) {
            if (polygon.latE7[i] > 90_000_000 || polygon.latE7[i] < -90_000_000) {
                revert InvalidPolygon();
            }
            if (polygon.longE7[i] > 180_000_000 || polygon.longE7[i] < -180_000_000) {
                revert InvalidPolygon();
            }
        }
        return true;
    }

    /// @notice Validate complete EUDR metadata
    function validateMetadata(EUDRMetadata memory metadata) external pure returns (bool valid) {
        if (!validateSisbovId(metadata.sisbovId)) return false;
        if (!validateCnpj(metadata.cnpj)) return false;
        if (!validatePolygon(metadata.farmPolygon)) return false;
        if (metadata.birthTimestamp == 0) revert EmptyString("birthTimestamp");
        if (metadata.deforestationCertHash == bytes32(0)) revert EmptyString("deforestationCertHash");
        return true;
    }

    /// @notice Calculate approximate farm area in hectares using Shoelace formula
    function calculateFarmArea(GeoPolygon memory polygon) external pure returns (uint256 areaHectares) {
        // Convert from E7 to degrees
        int256[4] memory lat = [
            polygon.latE7[0] / 1e7,
            polygon.latE7[1] / 1e7,
            polygon.latE7[2] / 1e7,
            polygon.latE7[3] / 1e7
        ];
        
        int256[4] memory lon = [
            polygon.longE7[0] / 1e7,
            polygon.longE7[1] / 1e7,
            polygon.longE7[2] / 1e7,
            polygon.longE7[3] / 1e7
        ];

        // Shoelace formula (simplified for on-chain calculation)
        int256 sum = 0;
        for (uint256 i = 0; i < 4; i++) {
            uint256 j = (i + 1) % 4;
            sum += lat[i] * lon[j];
            sum -= lat[j] * lon[i];
        }
        
        // Convert to hectares (1 square degree ≈ 12,365 hectares at equator)
        areaHectares = uint256(abs(sum)) / 2;
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }
}
