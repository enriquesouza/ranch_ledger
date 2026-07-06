// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {QRCodeRegistry} from "../src/QRCodeRegistry.sol";

contract QRCodeRegistryTest is Test {
    QRCodeRegistry internal registry;
    address internal admin = address(this);
    address internal registrar;
    address internal consumer;

    function setUp() public {
        registry = new QRCodeRegistry(admin);
        registrar = makeAddr("registrar");
        consumer = makeAddr("consumer");
        registry.grantRole(registry.REGISTRAR_ROLE(), registrar);
    }

    function test_GenerateQRCode() public {
        vm.prank(registrar);
        registry.generateQRCode(1, "ipfs://bovine/1/metadata", "QmHash123");
        assertTrue(registry.hasQRCode(1));
        assertEq(registry.totalQRCodes(), 1);
    }

    function test_GetQRCode() public {
        vm.prank(registrar);
        registry.generateQRCode(1, "ipfs://bovine/1/metadata", "QmHash123");

        QRCodeRegistry.QRCodeData memory qr = registry.getQRCode(1);
        assertEq(qr.metadataURI, "ipfs://bovine/1/metadata");
        assertEq(qr.qrCodeHash, "QmHash123");
        assertTrue(qr.exists);
    }

    function test_GetMetadataURI() public {
        vm.prank(registrar);
        registry.generateQRCode(1, "ipfs://bovine/1/metadata", "QmHash123");
        assertEq(registry.getMetadataURI(1), "ipfs://bovine/1/metadata");
    }

    function test_HasQRCode_False() public view {
        assertFalse(registry.hasQRCode(999));
    }

    function test_UpdateQRCode() public {
        vm.startPrank(registrar);
        registry.generateQRCode(1, "ipfs://bovine/1/metadata", "QmHash123");
        registry.updateQRCode(1, "ipfs://bovine/1/metadata-v2", "QmHash456");
        vm.stopPrank();

        QRCodeRegistry.QRCodeData memory qr = registry.getQRCode(1);
        assertEq(qr.metadataURI, "ipfs://bovine/1/metadata-v2");
        assertEq(qr.qrCodeHash, "QmHash456");
        assertEq(registry.totalQRCodes(), 1);
    }

    function test_RevertGenerateInvalidBovineId() public {
        vm.prank(registrar);
        vm.expectRevert(abi.encodeWithSelector(QRCodeRegistry.InvalidBovineId.selector, 0));
        registry.generateQRCode(0, "ipfs://bovine/0", "QmHash");
    }

    function test_RevertGenerateEmptyURI() public {
        vm.prank(registrar);
        vm.expectRevert(abi.encodeWithSelector(QRCodeRegistry.EmptyURI.selector));
        registry.generateQRCode(1, "", "QmHash");
    }

    function test_RevertGenerateNonRegistrar() public {
        vm.prank(consumer);
        vm.expectRevert();
        registry.generateQRCode(1, "ipfs://bovine/1", "QmHash");
    }

    function test_RevertGetNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(QRCodeRegistry.QRCodeNotFound.selector, 999));
        registry.getQRCode(999);
    }

    function test_ConsumerCanRead() public {
        vm.prank(registrar);
        registry.generateQRCode(1, "ipfs://bovine/1/metadata", "QmHash123");

        vm.prank(consumer);
        QRCodeRegistry.QRCodeData memory qr = registry.getQRCode(1);
        assertEq(qr.metadataURI, "ipfs://bovine/1/metadata");
    }
}