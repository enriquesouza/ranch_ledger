// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {GPSValidator, GPSCoordinate} from "../src/GPSValidator.sol";

/// @dev Wraps internal validateCoordinate in an external function for expectRevert.
contract GPSValidatorWrapper is GPSValidator {
    function wrapValidateCoordinate(GPSCoordinate memory coord) external view returns (bool) {
        return validateCoordinate(coord);
    }
}

contract GPSValidatorTest is Test {
    GPSValidatorWrapper internal wrapper;

    function setUp() public {
        wrapper = new GPSValidatorWrapper();
    }

    function test_ValidateMovement_Valid() public {
        vm.warp(1000000);
        GPSCoordinate memory from = GPSCoordinate(-23123456, -46123456, block.timestamp - 100);
        GPSCoordinate memory to = GPSCoordinate(-23123400, -46123400, block.timestamp - 50);
        assertTrue(wrapper.validateMovement(from, to));
    }

    function test_ValidateMovement_InvalidLatitude() public {
        vm.warp(1000000);
        GPSCoordinate memory from = GPSCoordinate(91000000, 0, block.timestamp - 100);
        GPSCoordinate memory to = GPSCoordinate(0, 0, block.timestamp - 50);
        vm.expectRevert(abi.encodeWithSelector(GPSValidator.InvalidLatitude.selector, 91000000));
        wrapper.wrapValidateCoordinate(from);
    }

    function test_CalculateDistance_SamePoint() public {
        GPSCoordinate memory coord = GPSCoordinate(-23123456, -46123456, block.timestamp);
        assertEq(wrapper.calculateDistance(coord, coord), 0);
    }

    function test_CalculateDistance_NonZero() public {
        GPSCoordinate memory from = GPSCoordinate(0, 0, block.timestamp);
        GPSCoordinate memory to = GPSCoordinate(10000000, 10000000, block.timestamp);
        uint256 dist = wrapper.calculateDistance(from, to);
        assertTrue(dist > 0);
    }
}