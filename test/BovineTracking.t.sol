// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {BovineTracking} from "../src/BovineTracking.sol";

/// @dev  Mirrors the legacy `test/bovine_tracking.js` behaviour in Solidity.
contract BovineTrackingTest is Test {
    BovineTracking internal bt;
    address internal admin = address(this);
    address internal vet;
    address internal rancher;
    address internal abattoir;

    uint256 internal latestId;

    event BovineAdded(uint256 indexed id, string name, uint256 age, string breed, string location, address indexed owner);
    event VaccineAdded(uint256 indexed bovineId, string name, uint256 date);
    event FeedAdded(uint256 indexed bovineId, string foodType, string origin, uint256 quantity, uint256 date);
    event MovementAdded(uint256 indexed bovineId, string fromLocation, string toLocation, uint256 date);
    event AbattoirProcessAdded(
        uint256 indexed bovineId, string abattoir, uint256 abattoirDate, string processing, uint256 date
    );
    event HealthExamAdded(uint256 indexed bovineId, string examType, string result, uint256 date);

    function setUp() public {
        bt = new BovineTracking(admin);
        vet = makeAddr("vet");
        rancher = makeAddr("rancher");
        abattoir = makeAddr("abattoir");
        bt.grantRole(bt.VET_ROLE(), vet);
        bt.grantRole(bt.RANCHER_ROLE(), rancher);
        bt.grantRole(bt.ABBATTOIR_ROLE(), abattoir);
    }

    function test_AddBovine() public {
        uint256 before = bt.totalBovines();
        vm.expectEmit(true, true, false, true);
        emit BovineAdded(1, "Bessie", 5, "Holstein", "Farm A", address(this));
        bt.addBovine("Bessie", 5, "Holstein", "Farm A", address(this));
        latestId = bt.totalBovines();
        assertEq(bt.totalBovines(), before + 1);
    }

    function test_AddVaccine() public {
        test_AddBovine();
        vm.expectEmit(true, false, false, true);
        emit VaccineAdded(latestId, "COVID-19", 1632893482);
        vm.prank(vet);
        bt.addVaccine(latestId, "COVID-19", 1632893482);

        BovineTracking.Vaccine[] memory v = bt.getVaccines(latestId);
        assertEq(v[0].name, "COVID-19");
        assertEq(v[0].date, 1632893482);
    }

    function test_AddFeed() public {
        test_AddBovine();
        vm.prank(rancher);
        bt.addFeed(latestId, "Corn", "farm", 1, 1632893482);

        BovineTracking.Feed[] memory f = bt.getFeeds(latestId);
        assertEq(f[0].foodType, "Corn");
        assertEq(f[0].origin, "farm");
        assertEq(f[0].quantity, 1);
        assertEq(f[0].date, 1632893482);
    }

    function test_AddMovements() public {
        test_AddBovine();
        BovineTracking.Movement[] memory m = new BovineTracking.Movement[](3);
        m[0] = BovineTracking.Movement("Farm A", "Farm B", 1632893482);
        m[1] = BovineTracking.Movement("Farm B", "Farm C", 1632893490);
        m[2] = BovineTracking.Movement("Farm C", "Farm D", 1632893498);

        vm.startPrank(rancher);
        for (uint256 i = 0; i < m.length; i++) {
            bt.addMovement(latestId, m[i].fromLocation, m[i].toLocation, m[i].date);
        }
        vm.stopPrank();

        BovineTracking.Movement[] memory got = bt.getMovements(latestId);
        for (uint256 i = 0; i < m.length; i++) {
            assertEq(got[i].fromLocation, m[i].fromLocation);
            assertEq(got[i].toLocation, m[i].toLocation);
            assertEq(got[i].date, m[i].date);
        }
    }

    function test_AddAbattoirProcesses() public {
        test_AddBovine();
        BovineTracking.AbattoirProcess[3] memory procs = [
            BovineTracking.AbattoirProcess("Abattoir A", 1632893482, "Slaughter", 1632893482),
            BovineTracking.AbattoirProcess("Abattoir B", 1632893490, "Tanning", 1632893490),
            BovineTracking.AbattoirProcess("Abattoir C", 1632893498, "Cutting", 1632893498)
        ];

        vm.startPrank(abattoir);
        for (uint256 i = 0; i < procs.length; i++) {
            bt.addAbattoirProcess(
                latestId, procs[i].abattoir, procs[i].abattoirDate, procs[i].processing, procs[i].date
            );
        }
        vm.stopPrank();

        BovineTracking.AbattoirProcess[] memory got = bt.getAbattoirProcesses(latestId);
        for (uint256 i = 0; i < procs.length; i++) {
            assertEq(got[i].abattoir, procs[i].abattoir);
            assertEq(got[i].abattoirDate, procs[i].abattoirDate);
            assertEq(got[i].processing, procs[i].processing);
            assertEq(got[i].date, procs[i].date);
        }
    }

    function test_AddHealthExams() public {
        test_AddBovine();
        BovineTracking.HealthExam[3] memory exams = [
            BovineTracking.HealthExam("Check-up", "Healthy", 1632893482),
            BovineTracking.HealthExam("X-ray", "Normal", 1632893490),
            BovineTracking.HealthExam("Blood Test", "Negative", 1632893498)
        ];

        vm.startPrank(vet);
        for (uint256 i = 0; i < exams.length; i++) {
            bt.addHealthExam(latestId, exams[i].examType, exams[i].result, exams[i].date);
        }
        vm.stopPrank();

        BovineTracking.HealthExam[] memory got = bt.getHealthExams(latestId);
        for (uint256 i = 0; i < exams.length; i++) {
            assertEq(got[i].examType, exams[i].examType);
            assertEq(got[i].result, exams[i].result);
            assertEq(got[i].date, exams[i].date);
        }
    }

    function test_GetBovineAggregates() public {
        bt.addBovine("Bessie", 5, "Holstein", "Farm A", address(this));
        latestId = bt.totalBovines();

        vm.startPrank(vet);
        bt.addVaccine(latestId, "COVID-19", 1632893482);
        bt.addHealthExam(latestId, "Check-up", "Healthy", 1632893482);
        vm.stopPrank();

        vm.startPrank(rancher);
        bt.addFeed(latestId, "Corn", "farm", 1, 1632893482);
        bt.addMovement(latestId, "Farm A", "Farm B", 1632893482);
        bt.addMovement(latestId, "Farm B", "Farm C", 1632893490);
        bt.addMovement(latestId, "Farm C", "Farm D", 1632893498);
        vm.stopPrank();

        vm.startPrank(abattoir);
        bt.addAbattoirProcess(latestId, "Abattoir A", 1632893482, "Slaughter", 1632893482);
        bt.addAbattoirProcess(latestId, "Abattoir B", 1632893490, "Tanning", 1632893490);
        bt.addAbattoirProcess(latestId, "Abattoir C", 1632893498, "Cutting", 1632893498);
        vm.stopPrank();

        BovineTracking.Bovine memory b = bt.getBovine(latestId);
        assertEq(b.id, latestId);
        assertEq(b.name, "Bessie");
        assertEq(b.age, 5);
        assertEq(b.breed, "Holstein");
        assertEq(b.location, "Farm D");
        assertGt(b.vaccines.length, 0);
        assertGt(b.feeds.length, 0);
        assertGt(b.healthExams.length, 0);
        assertGt(b.movements.length, 0);
        assertGt(b.abattoirProcesses.length, 0);
    }

    function test_RevertInvalidBovine() public {
        vm.expectRevert(abi.encodeWithSelector(BovineTracking.InvalidBovine.selector, 99));
        vm.prank(vet);
        bt.addVaccine(99, "X", 1);
    }

    function test_RevertDuplicateName() public {
        bt.addBovine("Bessie", 5, "Holstein", "Farm A", address(this));
        vm.expectRevert(abi.encodeWithSignature("DuplicateBovineName(string)", "Bessie"));
        bt.addBovine("Bessie", 6, "Angus", "Farm B", address(this));
    }

    function test_RevertInvalidAge() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidAge(uint256)", 0));
        bt.addBovine("NoName", 0, "Holstein", "Farm A", address(this));
        vm.expectRevert(abi.encodeWithSignature("InvalidAge(uint256)", 50));
        bt.addBovine("Old", 50, "Holstein", "Farm A", address(this));
    }

    function test_AccessControl_OnlyVetCanVaccinate() public {
        bt.addBovine("Bessie", 5, "Holstein", "Farm A", address(this));
        latestId = bt.totalBovines();
        vm.prank(rancher);
        vm.expectRevert();
        bt.addVaccine(latestId, "COVID-19", 1);
    }

    function test_FuzzAddBovine(uint256 age) public {
        vm.assume(age > 0 && age <= 40);
        uint256 before = bt.totalBovines();
        bt.addBovine(string.concat("Fuzz-", vm.toString(block.timestamp)), age, "Angus", "Fuzz", address(this));
        assertEq(bt.totalBovines(), before + 1);
    }
}
