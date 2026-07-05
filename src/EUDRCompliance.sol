// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BovineTracking} from "../src/BovineTracking.sol";

/// @title EUDRMetadata
/// @notice Metadata required for EU Deforestation Regulation (EUDR) compliance.
///         Includes farm polygon coordinates, deforestation certification hash,
///         and Brazilian SISBOV registration ID.
struct EUDRMetadata {
    string sisbovId;           // 15-digit Brazilian national livestock ID
    string cnpj;               // Operator legal entity (CNPJ: XX.XXX.XXX/XXXX-XX)
    uint256 birthTimestamp;    // Animal birth date (Unix timestamp)
    bytes32 deforestationCertHash; // Hash of EUDR deforestation certificate
    GeoPolygon farmPolygon;    // Farm boundary coordinates
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
contract EUDRCompliance {
    // Required SISBOV ID format: 15 digits
    uint256 public constant MIN_SISBOV_LENGTH = 15;
    uint256 public constant MAX_SISBOV_LENGTH = 15;

    // Required CNPJ format: XX.XXX.XXX/XXXX-XX (14 characters)
    uint256 public constant MIN_CNPJ_LENGTH = 14;
    uint256 public constant MAX_CNPJ_LENGTH = 14;

    error InvalidSisbovId(string sisbovId);
    error InvalidCnpj(string cnpj);
    error InvalidPolygon();
    error EmptyString(string field);

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
        if (bytes(cnpj).length != MIN_CNPJ_LENGTH) {
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
