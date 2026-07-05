// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BovineTracking} from "../src/BovineTracking.sol";

/// @title GPSCoordinate
/// @notice GPS coordinate struct for movement tracking with EUDR compliance.
///         Coordinates are stored as int256 * 10^7 to preserve precision
///         (e.g., -14.2350° becomes -142350000).
struct GPSCoordinate {
    int256 latE7;   // Latitude × 10^7 (-900000000 to 900000000)
    int256 longE7;  // Longitude × 10^7 (-1800000000 to 1800000000)
    uint256 timestamp; // Unix timestamp of GPS reading
}

/// @notice Event emitted when a movement includes GPS coordinates.
event MovementGPS(
    uint256 indexed bovineId,
    GPSCoordinate fromCoords,
    GPSCoordinate toCoords,
    uint256 date
);

/// @title GPSValidator
/// @notice Validates GPS coordinates for BovineTracking movements.
///         Ensures coordinates are within valid ranges and timestamps are reasonable.
contract GPSValidator {
    // Valid coordinate bounds (with 7 decimal places)
    int256 public constant MAX_LAT_E7 = 90_000_000;   // 90°
    int256 public constant MIN_LAT_E7 = -90_000_000;  // -90°
    int256 public constant MAX_LONG_E7 = 180_000_000; // 180°
    int256 public constant MIN_LONG_E7 = -180_000_000; // -180°

    // Maximum allowed time difference between GPS reading and movement date (24 hours)
    uint256 public constant MAX_GPS_AGE = 24 hours;

    error InvalidLatitude(int256 lat);
    error InvalidLongitude(int256 long);
    error GPSTooOld(uint256 age);
    error GPSNotProvided();

    /// @notice Validate a single GPS coordinate
    function validateCoordinate(GPSCoordinate memory coord) internal view returns (bool valid) {
        if (coord.latE7 > MAX_LAT_E7 || coord.latE7 < MIN_LAT_E7) {
            revert InvalidLatitude(coord.latE7);
        }
        if (coord.longE7 > MAX_LONG_E7 || coord.longE7 < MIN_LONG_E7) {
            revert InvalidLongitude(coord.longE7);
        }
        // Timestamp must be in the past (within reasonable bounds)
        uint256 age = block.timestamp - coord.timestamp;
        if (age > MAX_GPS_AGE) {
            revert GPSTooOld(age);
        }
        return true;
    }

    /// @notice Validate a pair of GPS coordinates for a movement
    function validateMovement(
        GPSCoordinate memory fromCoords,
        GPSCoordinate memory toCoords
    ) external view returns (bool valid) {
        // Validate both coordinates
        if (!validateCoordinate(fromCoords)) return false;
        if (!validateCoordinate(toCoords)) return false;

        // Optional: Check that the movement distance is reasonable
        // (e.g., not teleporting across the planet in 1 second)
        uint256 timeDiff = toCoords.timestamp - fromCoords.timestamp;
        if (timeDiff > 0 && timeDiff < 60) {
            // Less than 1 minute: check distance is small (< 1km)
            int256 latDiff = abs(toCoords.latE7 - fromCoords.latE7);
            int256 longDiff = abs(toCoords.longE7 - fromCoords.longE7);
            if (latDiff > 900 || longDiff > 900) {
                // More than ~1km in less than 1 minute is suspicious
                return false;
            }
        }

        return true;
    }

    /// @notice Calculate approximate distance between two GPS coordinates (Haversine formula)
    function calculateDistance(
        GPSCoordinate memory fromCoords,
        GPSCoordinate memory toCoords
    ) external pure returns (uint256 distanceMeters) {
        // Convert to radians and calculate differences
        int256 dLat = ((toCoords.latE7 - fromCoords.latE7) * 1e7) / 100;
        int256 dLong = ((toCoords.longE7 - fromCoords.longE7) * 1e7) / 100;

        // Haversine formula (simplified for on-chain calculation)
        // This is a rough approximation - for production, use Chainlink Functions or off-chain computation
        uint256 a = uint256((dLat * dLat + dLong * dLong) / 4);
        uint256 c = sqrt(a);
        
        // Earth radius in meters
        uint256 R = 6_371_000;
        
        distanceMeters = (c * R) / 1e7;
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = (y + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
