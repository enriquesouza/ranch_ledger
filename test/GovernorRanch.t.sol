// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {GovernorRanch} from "../src/GovernorRanch.sol";
import {RanchToken} from "../src/RanchToken.sol";

contract GovernorRanchTest is Test {
    GovernorRanch internal governor;
    RanchToken internal token;
    address internal admin = address(this);
    address internal proposer;
    address internal voter1;
    address internal voter2;

    function setUp() public {
        token = new RanchToken(admin, 6);
        governor = new GovernorRanch(token, "RanchDAO", 1, 10);

        proposer = makeAddr("proposer");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");

        // Mint tokens to voters (need enough to meet quorum = totalSupply/10)
        token.mint(voter1, 100_000e6);
        token.mint(voter2, 50_000e6);
        token.mint(proposer, 10e6);

        // Grant roles
        governor.grantProposerRole(proposer);
    }

    function test_Name() public view {
        assertEq(governor.name(), "RanchDAO");
    }

    function test_Version() public view {
        assertEq(governor.version(), "1.0");
    }

    function test_Quorum() public {
        assertEq(governor.quorum(), token.totalSupply() / 10);
    }

    function test_ProposalThreshold() public view {
        assertEq(governor.proposalThreshold(), 1e6);
    }

    function test_Propose() public {
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, proposer, 100e6);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Mint 100 tokens to proposer");
        assertEq(proposalId, 1);
    }

    function test_RevertProposeNonProposer() public {
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(voter1);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "test");
    }

    function test_VoteAndExecute() public {
        // Grant MINTER_ROLE to governor so it can execute mint proposals
        token.grantRole(token.MINTER_ROLE(), address(governor));

        // Create a proposal to mint tokens to voter1
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, voter1, 100e6);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Mint 100 to voter1");

        // Advance past voting delay (1 block)
        vm.roll(block.number + 1);

        // Check state is Active
        assertEq(uint8(governor.state(proposalId)), uint8(GovernorRanch.ProposalState.Active));

        // voter1 votes FOR
        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        // voter2 votes FOR
        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        // Advance past voting period (voteEnd = block.number_at_propose + 1 + 10)
        // We rolled +1 for delay, now roll +11 to go past voteEnd
        vm.roll(block.number + 11);

        // Check state is Succeeded
        assertEq(uint8(governor.state(proposalId)), uint8(GovernorRanch.ProposalState.Succeeded));

        // Execute
        governor.execute(proposalId);
        assertEq(token.balanceOf(voter1), 100_100e6); // 100k + 100
    }

    function test_RevertDoubleVote() public {
        _createAndActivateProposal();

        vm.startPrank(voter1);
        governor.castVote(1, 1);
        vm.expectRevert(abi.encodeWithSelector(GovernorRanch.AlreadyVoted.selector, 1, voter1));
        governor.castVote(1, 1);
        vm.stopPrank();
    }

    function test_Cancel() public {
        _createProposal();
        vm.prank(proposer);
        governor.cancel(1);
        assertEq(uint8(governor.state(1)), uint8(GovernorRanch.ProposalState.Canceled));
    }

    function test_GrantProposerRole() public {
        address newProposer = makeAddr("newProposer");
        governor.grantProposerRole(newProposer);
        assertTrue(governor.hasRole(governor.PROPOSER_ROLE(), newProposer));
    }

    function _createProposal() internal {
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, voter1, 100e6);

        vm.prank(proposer);
        governor.propose(targets, values, calldatas, "test proposal");
    }

    function _createAndActivateProposal() internal {
        _createProposal();
        vm.roll(block.number + 1);
    }
}