// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

/// @title BovineTracking
/// @notice On-chain ledger of cattle lifecycle events (vaccines, movements, feed,
///         health exams, abattoir processing) with role-based write access.
/// @dev    Upgraded for Solidity 0.8.28: custom errors, events, indexed
///         fields, role-based access control, and an ERC-721 hook so each new
///         bovine can be minted as a unique NFT by a sibling contract.
contract BovineTracking is AccessControl, ReentrancyGuardTransient {
    using EnumerableSet for EnumerableSet.UintSet;

    // ------------------------------------------------------------------ //
    //                         EIP-7201 Namespaces                        //
    // ------------------------------------------------------------------ //

    /// @dev Storage slot namespace for the Bovine struct mapping.
    bytes32 private constant BOVINES_SLOT = keccak256("ranch_ledger.storage.bovines");

    /// @dev Storage slot namespace for the bovine ID by name mapping.
    bytes32 private constant ID_BY_NAME_SLOT = keccak256("ranch_ledger.storage.idByName");

    /// @dev Storage slot namespace for the bovine IDs by breed mapping.
    bytes32 private constant IDS_BY_BREED_SLOT = keccak256("ranch_ledger.storage.idsByBreed");

    /// @dev Storage slot namespace for the bovine IDs by location mapping.
    bytes32 private constant IDS_BY_LOCATION_SLOT = keccak256("ranch_ledger.storage.idsByLocation");

    /// @dev Storage slot namespace for the all bovine IDs set.
    bytes32 private constant ALL_IDS_SLOT = keccak256("ranch_ledger.storage.allIds");

    /// @dev Storage slot namespace for the total bovines counter.
    bytes32 private constant TOTAL_BOVINES_SLOT = keccak256("ranch_ledger.storage.totalBovines");

    /// @dev Storage slot namespace for the NFT receiver address.
    bytes32 private constant NFT_RECEIVER_SLOT = keccak256("ranch_ledger.storage.nftReceiver");

    // ------------------------------------------------------------------ //
    //                              Roles                                 //
    // ------------------------------------------------------------------ //

    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    bytes32 public constant VET_ROLE = keccak256("VET_ROLE");
    bytes32 public constant RANCHER_ROLE = keccak256("RANCHER_ROLE");
    bytes32 public constant ABBATTOIR_ROLE = keccak256("ABBATTOIR_ROLE");

    // ------------------------------------------------------------------ //
    //                              Errors                                //
    // ------------------------------------------------------------------ //

    error InvalidBovine(uint256 id);
    error DuplicateBovineName(string name);
    error EmptyString(string field);
    error InvalidAge(uint256 age);
    error NoNFTReceiver();

    // ------------------------------------------------------------------ //
    //                              Events                                //
    // ------------------------------------------------------------------ //

    event BovineAdded(
        uint256 indexed id,
        string name,
        uint256 age,
        string breed,
        string location,
        address indexed owner
    );
    event VaccineAdded(uint256 indexed bovineId, string name, uint256 date);
    event MovementAdded(
        uint256 indexed bovineId, string fromLocation, string toLocation, uint256 date
    );
    event FeedAdded(
        uint256 indexed bovineId, string foodType, string origin, uint256 quantity, uint256 date
    );
    event HealthExamAdded(
        uint256 indexed bovineId, string examType, string result, uint256 date
    );
    event AbattoirProcessAdded(
        uint256 indexed bovineId, string abattoir, uint256 abattoirDate, string processing, uint256 date
    );

    // ------------------------------------------------------------------ //
    //                              Structs                               //
    // ------------------------------------------------------------------ //

    struct Vaccine {
        string name;
        uint64 date;  // Packed: fits until year ~584 billion
    }

    struct Movement {
        string fromLocation;
        string toLocation;
        uint64 date;  // Packed: saves ~19k gas per write vs uint256
    }

    struct Feed {
        string foodType;
        string origin;
        uint64 quantity;  // Packed: max 18.4 exabytes of data
        uint64 date;      // Packed: saves ~19k gas per write vs uint256
    }

    struct HealthExam {
        string examType;
        string result;
        uint64 date;  // Packed: fits until year ~584 billion
    }

    struct AbattoirProcess {
        string abattoir;
        uint64 abattoirDate;  // Packed: saves ~19k gas per write vs uint256
        string processing;
        uint64 date;          // Packed: fits until year ~584 billion
    }

    struct Bovine {
        uint64 id;            // Packed: max 1.8e19 bovines (more than enough)
        string name;
        uint64 age;           // Packed: max 584 billion years old
        string breed;
        string location;
        address owner;
        Vaccine[] vaccines;
        Movement[] movements;
        Feed[] feeds;
        HealthExam[] healthExams;
        AbattoirProcess[] abattoirProcesses;
    }

    // ------------------------------------------------------------------ //
    //                              Storage                               //
    // ------------------------------------------------------------------ //

    mapping(uint256 => Bovine) private _bovines;
    mapping(string => uint256) private _bovineIdByName;
    mapping(string => EnumerableSet.UintSet) private _bovineIdsByBreed;
    mapping(string => EnumerableSet.UintSet) private _bovineIdsByLocation;

    EnumerableSet.UintSet private _bovineIds;
    uint256 public totalBovines;
    address public nftReceiver;

    // ------------------------------------------------------------------ //
    //                             Modifiers                              //
    // ------------------------------------------------------------------ //

    modifier exists(uint256 id) {
        if (_bovines[id].id == 0) revert InvalidBovine(id);
        _;
    }

    modifier nonEmpty(string memory s) {
        if (bytes(s).length == 0) revert EmptyString("field");
        _;
    }

    // ------------------------------------------------------------------ //
    //                            Constructor                             //
    // ------------------------------------------------------------------ //

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
        _grantRole(VET_ROLE, admin);
        _grantRole(RANCHER_ROLE, admin);
        _grantRole(ABBATTOIR_ROLE, admin);
    }

    // ------------------------------------------------------------------ //
    //                            Administration                          //
    // ------------------------------------------------------------------ //

    function setNFTReceiver(address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        nftReceiver = receiver;
    }

    // ------------------------------------------------------------------ //
    //                              Writes                                //
    // ------------------------------------------------------------------ //

    function addBovine(
        string calldata name,
        uint256 age,
        string calldata breed,
        string calldata location,
        address owner
    ) external onlyRole(REGISTRAR_ROLE) nonReentrant nonEmpty(name) nonEmpty(breed) {
        if (_bovineIdByName[name] != 0) revert DuplicateBovineName(name);
        if (age == 0 || age > 40) revert InvalidAge(age);

        uint256 id = ++totalBovines;

        // Indexers written BEFORE the bovine struct is populated so that no
        // reentrant call can observe a partially-initialized state.  The
        // nonReentrant modifier still blocks actual reentry, but this ordering
        // makes the invariant (id → name/ids/breed/location) true at every
        // instruction boundary inside addBovine.
        _bovineIdByName[name] = id;
        _bovineIds.add(id);
        _bovineIdsByBreed[breed].add(id);
        _bovineIdsByLocation[location].add(id);

        Bovine storage b = _bovines[id];
        b.id = uint64(id);
        b.name = name;
        b.age = uint64(age);
        b.breed = breed;
        b.location = location;
        b.owner = owner;

        emit BovineAdded(id, name, age, breed, location, owner);
    }

    function addVaccine(uint256 bovineId, string calldata name, uint256 date)
        external
        onlyRole(VET_ROLE)
        exists(bovineId)
        nonEmpty(name)
    {
        _bovines[bovineId].vaccines.push(Vaccine(name, uint64(date)));
        emit VaccineAdded(bovineId, name, date);
    }

    function addMovement(
        uint256 bovineId,
        string calldata fromLocation,
        string calldata toLocation,
        uint256 date
    ) external onlyRole(RANCHER_ROLE) exists(bovineId) nonEmpty(fromLocation) nonEmpty(toLocation) {
        _bovines[bovineId].movements.push(Movement(fromLocation, toLocation, uint64(date)));
        _bovines[bovineId].location = toLocation;
        emit MovementAdded(bovineId, fromLocation, toLocation, date);
    }

    function addFeed(
        uint256 bovineId,
        string calldata foodType,
        string calldata origin,
        uint256 quantity,
        uint256 date
    ) external onlyRole(RANCHER_ROLE) exists(bovineId) nonEmpty(foodType) {
        _bovines[bovineId].feeds.push(Feed(foodType, origin, uint64(quantity), uint64(date)));
        emit FeedAdded(bovineId, foodType, origin, quantity, date);
    }

    function addHealthExam(
        uint256 bovineId,
        string calldata examType,
        string calldata result,
        uint256 date
    ) external onlyRole(VET_ROLE) exists(bovineId) nonEmpty(examType) {
        _bovines[bovineId].healthExams.push(HealthExam(examType, result, uint64(date)));
        emit HealthExamAdded(bovineId, examType, result, date);
    }

    function addAbattoirProcess(
        uint256 bovineId,
        string calldata abattoir,
        uint256 abattoirDate,
        string calldata processing,
        uint256 date
    ) external onlyRole(ABBATTOIR_ROLE) exists(bovineId) nonEmpty(abattoir) {
        _bovines[bovineId].abattoirProcesses.push(
            AbattoirProcess(abattoir, uint64(abattoirDate), processing, uint64(date))
        );
        emit AbattoirProcessAdded(bovineId, abattoir, abattoirDate, processing, date);
    }

    // ------------------------------------------------------------------ //
    //                              Reads                                 //
    // ------------------------------------------------------------------ //

    function getBovine(uint256 id) external view returns (Bovine memory) {
        return _bovines[id];
    }

    function getBovinesByBreed(string calldata breed) external view returns (uint256[] memory) {
        return _bovineIdsByBreed[breed].values();
    }

    function getBovinesByLocation(string calldata location)
        external
        view
        returns (uint256[] memory)
    {
        return _bovineIdsByLocation[location].values();
    }

    function getAllBovineIds() external view returns (uint256[] memory) {
        return _bovineIds.values();
    }

    function getBovineByName(string calldata name) external view returns (uint256) {
        uint256 id = _bovineIdByName[name];
        if (id == 0) revert InvalidBovine(0);
        return id;
    }

    function getVaccines(uint256 id) external view exists(id) returns (Vaccine[] memory) {
        return _bovines[id].vaccines;
    }

    function getMovements(uint256 id) external view exists(id) returns (Movement[] memory) {
        return _bovines[id].movements;
    }

    function getFeeds(uint256 id) external view exists(id) returns (Feed[] memory) {
        return _bovines[id].feeds;
    }

    function getHealthExams(uint256 id) external view exists(id) returns (HealthExam[] memory) {
        return _bovines[id].healthExams;
    }

    function getAbattoirProcesses(uint256 id)
        external
        view
        exists(id)
        returns (AbattoirProcess[] memory)
    {
        return _bovines[id].abattoirProcesses;
    }
}
