// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EUDRCompliance, NationalLivestockId} from "../src/EUDRCompliance.sol";

/// @dev Wraps internal validators in external functions so vm.expectRevert works.
contract EUDRComplianceWrapper is EUDRCompliance {
    function wrapValidateSisbovId(string memory s) external pure returns (bool) {
        return validateSisbovId(s);
    }
    function wrapValidateEUId(string memory s) external pure returns (bool) {
        return validateEUId(s);
    }
    function wrapValidateUSDAAnid(string memory s) external pure returns (bool) {
        return validateUSDAAnid(s);
    }
    function wrapValidateUSDEid(string memory s) external pure returns (bool) {
        return validateUSDEid(s);
    }
    function wrapValidateNLIS(string memory s) external pure returns (bool) {
        return validateNLIS(s);
    }
    function wrapValidateChinaId(string memory s) external pure returns (bool) {
        return validateChinaId(s);
    }
    function wrapValidateGCCId(string memory s) external pure returns (bool) {
        return validateGCCId(s);
    }
    function wrapValidateNationalId(NationalLivestockId memory id) external pure returns (bool) {
        return validateNationalId(id);
    }
}

contract EUDRComplianceTest is Test {
    EUDRComplianceWrapper internal wrapper;

    function setUp() public {
        wrapper = new EUDRComplianceWrapper();
    }

    function test_ValidateSisbovId_Valid() public {
        assertTrue(wrapper.wrapValidateSisbovId("123456789012345"));
    }
    function test_ValidateSisbovId_InvalidLength() public {
        vm.expectRevert(abi.encodeWithSelector(EUDRCompliance.InvalidSisbovId.selector, "12345"));
        wrapper.wrapValidateSisbovId("12345");
    }
    function test_ValidateSisbovId_InvalidChars() public {
        vm.expectRevert(abi.encodeWithSelector(EUDRCompliance.InvalidSisbovId.selector, "12345678901234A"));
        wrapper.wrapValidateSisbovId("12345678901234A");
    }
    function test_ValidateEUId_Valid() public {
        assertTrue(wrapper.wrapValidateEUId("DE12ABCD004"));
    }
    function test_ValidateUSDAAnid_Valid() public {
        assertTrue(wrapper.wrapValidateUSDAAnid("840123456789012"));
    }
    function test_ValidateUSDAAnid_InvalidLength() public {
        vm.expectRevert();
        wrapper.wrapValidateUSDAAnid("84012345678901");
    }
    function test_ValidateUSDEid_Valid() public {
        assertTrue(wrapper.wrapValidateUSDEid("123456789"));
    }
    function test_ValidateNLIS_Valid() public {
        assertTrue(wrapper.wrapValidateNLIS("123456789012"));
    }
    function test_ValidateChinaId_Valid() public {
        assertTrue(wrapper.wrapValidateChinaId("123456789012345"));
    }
    function test_ValidateGCCId_Valid() public {
        assertTrue(wrapper.wrapValidateGCCId("SA-001234-5678"));
    }
    function test_ValidateGCCId_InvalidSeparator() public {
        vm.expectRevert();
        wrapper.wrapValidateGCCId("SA0012345678");
    }
    function test_ValidateNationalId_Brazil() public {
        NationalLivestockId memory id = NationalLivestockId({
            countryCode: "BR",
            nationalId: "123456789012345",
            earTag: "BR-EAR-001",
            timestamp: block.timestamp
        });
        assertTrue(wrapper.wrapValidateNationalId(id));
    }
    function test_ValidateNationalId_InvalidCountryCode() public {
        NationalLivestockId memory id = NationalLivestockId({
            countryCode: "BRA",
            nationalId: "123",
            earTag: "",
            timestamp: block.timestamp
        });
        vm.expectRevert(abi.encodeWithSelector(EUDRCompliance.InvalidCountryCode.selector, "BRA"));
        wrapper.wrapValidateNationalId(id);
    }
}