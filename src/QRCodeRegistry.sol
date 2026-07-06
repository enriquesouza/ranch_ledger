// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title QRCodeRegistry
/// @notice Consumer-facing QR code registry for bovine traceability.
///         Consumers scan a QR code on beef packaging to trace the animal's
///         full lifecycle: birth, vaccinations, movements, feed, health exams,
///         and abattoir processing.
contract QRCodeRegistry is AccessControl {
    // ------------------------------------------------------------------ //
    //                              Roles                                 //
    // ------------------------------------------------------------------ //

    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    // ------------------------------------------------------------------ //
    //                              Errors                                //
    // ------------------------------------------------------------------ //

    error QRCodeNotFound(uint256 bovineId);
    error InvalidBovineId(uint256 bovineId);
    error EmptyURI();

    // ------------------------------------------------------------------ //
    //                              Events                                //
    // ------------------------------------------------------------------ //

    event QRCodeGenerated(
        uint256 indexed bovineId,
        string metadataURI,
        string qrCodeHash,
        uint256 timestamp
    );
    event QRCodeUpdated(
        uint256 indexed bovineId,
        string newMetadataURI,
        string newQrCodeHash,
        uint256 timestamp
    );

    // ------------------------------------------------------------------ //
    //                              Structs                               //
    // ------------------------------------------------------------------ //

    struct QRCodeData {
        string metadataURI;     // IPFS URI or HTTPS URL to bovine metadata
        string qrCodeHash;      // IPFS hash of the QR code image
        uint64 createdAt;       // When the QR code was first generated
        uint64 updatedAt;       // When the QR code was last updated
        bool exists;            // Whether a QR code exists for this bovine
    }

    // ------------------------------------------------------------------ //
    //                              Storage                               //
    // ------------------------------------------------------------------ //

    /// @notice Mapping: bovineId => QR code data
    mapping(uint256 => QRCodeData) private _qrCodes;

    /// @notice Total number of QR codes generated
    uint256 public totalQRCodes;

    // ------------------------------------------------------------------ //
    //                            Constructor                             //
    // ------------------------------------------------------------------ //

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    // ------------------------------------------------------------------ //
    //                              Writes                                //
    // ------------------------------------------------------------------ //

    /// @notice Generate a QR code for a bovine (first time only)
    /// @param bovineId The bovine's on-chain ID
    /// @param metadataURI IPFS URI or HTTPS URL to the bovine's full metadata
    /// @param qrCodeHash IPFS hash of the generated QR code image
    function generateQRCode(
        uint256 bovineId,
        string calldata metadataURI,
        string calldata qrCodeHash
    ) external onlyRole(REGISTRAR_ROLE) {
        if (bovineId == 0) revert InvalidBovineId(bovineId);
        if (bytes(metadataURI).length == 0 || bytes(qrCodeHash).length == 0) revert EmptyURI();
        if (_qrCodes[bovineId].exists) {
            // Update instead of generate if already exists
            _updateQRCode(bovineId, metadataURI, qrCodeHash);
            return;
        }

        _qrCodes[bovineId] = QRCodeData({
            metadataURI: metadataURI,
            qrCodeHash: qrCodeHash,
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp),
            exists: true
        });

        totalQRCodes++;

        emit QRCodeGenerated(bovineId, metadataURI, qrCodeHash, block.timestamp);
    }

    /// @notice Update an existing QR code (e.g., when new lifecycle data is added)
    /// @param bovineId The bovine's on-chain ID
    /// @param metadataURI New IPFS URI or HTTPS URL with updated metadata
    /// @param qrCodeHash New IPFS hash of the regenerated QR code image
    function updateQRCode(
        uint256 bovineId,
        string calldata metadataURI,
        string calldata qrCodeHash
    ) external onlyRole(REGISTRAR_ROLE) {
        if (bovineId == 0) revert InvalidBovineId(bovineId);
        if (bytes(metadataURI).length == 0 || bytes(qrCodeHash).length == 0) revert EmptyURI();
        if (!_qrCodes[bovineId].exists) revert QRCodeNotFound(bovineId);

        _updateQRCode(bovineId, metadataURI, qrCodeHash);
    }

    function _updateQRCode(
        uint256 bovineId,
        string calldata metadataURI,
        string calldata qrCodeHash
    ) internal {
        QRCodeData storage qr = _qrCodes[bovineId];
        qr.metadataURI = metadataURI;
        qr.qrCodeHash = qrCodeHash;
        qr.updatedAt = uint64(block.timestamp);

        emit QRCodeUpdated(bovineId, metadataURI, qrCodeHash, block.timestamp);
    }

    // ------------------------------------------------------------------ //
    //                              Reads                                 //
    // ------------------------------------------------------------------ //

    /// @notice Get QR code data for a bovine (consumer-facing)
    /// @param bovineId The bovine's on-chain ID
    /// @return QRCodeData struct with metadata URI and QR code hash
    function getQRCode(uint256 bovineId) external view returns (QRCodeData memory) {
        if (!_qrCodes[bovineId].exists) revert QRCodeNotFound(bovineId);
        return _qrCodes[bovineId];
    }

    /// @notice Check if a QR code exists for a bovine
    function hasQRCode(uint256 bovineId) external view returns (bool) {
        return _qrCodes[bovineId].exists;
    }

    /// @notice Get the metadata URI for a bovine (consumer-facing convenience)
    function getMetadataURI(uint256 bovineId) external view returns (string memory) {
        if (!_qrCodes[bovineId].exists) revert QRCodeNotFound(bovineId);
        return _qrCodes[bovineId].metadataURI;
    }

    /// @notice Get the QR code image hash for a bovine
    function getQRCodeHash(uint256 bovineId) external view returns (string memory) {
        if (!_qrCodes[bovineId].exists) revert QRCodeNotFound(bovineId);
        return _qrCodes[bovineId].qrCodeHash;
    }
}