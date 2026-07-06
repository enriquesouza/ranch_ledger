// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @title GovernorRanch
/// @notice Lightweight DAO governance for the RanchLendingVault.
///         RanchToken holders create and vote on proposals to update vault
///         parameters (liquidation thresholds, interest rates, fee structures).
///         Uses simple token-weighted voting (1 token = 1 vote) with a
/// configurable voting delay and voting period.
contract GovernorRanch is AccessControl, ReentrancyGuardTransient {
    // ------------------------------------------------------------------ //
    //                              Roles                                 //
    // ------------------------------------------------------------------ //

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant VOTER_ROLE = keccak256("VOTER_ROLE");

    // ------------------------------------------------------------------ //
    //                              Errors                                //
    // ------------------------------------------------------------------ //

    error ProposalNotFound(uint256 proposalId);
    error AlreadyVoted(uint256 proposalId, address voter);
    error InsufficientVotingPower(address voter, uint256 has, uint256 needed);
    error ProposalNotActive(uint256 proposalId);
    error ProposalNotSucceeded(uint256 proposalId);
    error InvalidVoteType(uint8 support);
    error ArrayLengthMismatch();

    // ------------------------------------------------------------------ //
    //                              Events                                //
    // ------------------------------------------------------------------ //

    event ProposalCreated(
        uint256 indexed proposalId,
        string description,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 voteStart,
        uint256 voteEnd
    );
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 weight,
        string reason
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);

    // ------------------------------------------------------------------ //
    //                              Enums                                 //
    // ------------------------------------------------------------------ //

    enum ProposalState { Pending, Active, Succeeded, Defeated, Executed, Canceled }

    // ------------------------------------------------------------------ //
    //                              Structs                               //
    // ------------------------------------------------------------------ //

    struct Proposal {
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        uint256 voteStart;
        uint256 voteEnd;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
        bool executed;
        bool canceled;
        mapping(address => bool) hasVoted;
    }

    // ------------------------------------------------------------------ //
    //                              Storage                               //
    // ------------------------------------------------------------------ //

    ERC20 public immutable token;
    uint256 public immutable votingDelay;
    uint256 public immutable votingPeriod;
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 1e6; // 1 token (6 decimals)

    uint256 private _proposalCount;
    mapping(uint256 => Proposal) private _proposals;

    // ------------------------------------------------------------------ //
    //                            Constructor                             //
    // ------------------------------------------------------------------ //

    constructor(
        ERC20 _token,
        string memory /* name_ */,
        uint256 votingDelay_,
        uint256 votingPeriod_
    ) {
        token = _token;
        votingDelay = votingDelay_;
        votingPeriod = votingPeriod_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROPOSER_ROLE, msg.sender);
    }

    // ------------------------------------------------------------------ //
    //                          View Functions                            //
    // ------------------------------------------------------------------ //

    function name() public pure returns (string memory) {
        return "RanchDAO";
    }

    function version() public pure returns (string memory) {
        return "1.0";
    }

    function proposalCount() external view returns (uint256) {
        return _proposalCount;
    }

    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description,
            uint256 voteStart,
            uint256 voteEnd,
            uint256 yesVotes,
            uint256 noVotes,
            uint256 abstainVotes,
            bool executed,
            bool canceled
        )
    {
        if (proposalId == 0 || proposalId > _proposalCount) revert ProposalNotFound(proposalId);
        Proposal storage p = _proposals[proposalId];
        return (
            p.targets, p.values, p.calldatas, p.description,
            p.voteStart, p.voteEnd,
            p.yesVotes, p.noVotes, p.abstainVotes,
            p.executed, p.canceled
        );
    }

    function state(uint256 proposalId) public view returns (ProposalState) {
        if (proposalId == 0 || proposalId > _proposalCount) revert ProposalNotFound(proposalId);
        Proposal storage p = _proposals[proposalId];

        if (p.canceled) return ProposalState.Canceled;
        if (p.executed) return ProposalState.Executed;
        if (block.number < p.voteStart) return ProposalState.Pending;
        if (block.number <= p.voteEnd) return ProposalState.Active;
        if (_voteSucceeded(proposalId)) return ProposalState.Succeeded;
        return ProposalState.Defeated;
    }

    function hasVoted(uint256 proposalId, address account) external view returns (bool) {
        return _proposals[proposalId].hasVoted[account];
    }

    function quorum() public view returns (uint256) {
        return token.totalSupply() / 10; // 10% quorum
    }

    function proposalThreshold() public pure returns (uint256) {
        return MIN_PROPOSAL_THRESHOLD;
    }

    // ------------------------------------------------------------------ //
    //                         Proposal Creation                          //
    // ------------------------------------------------------------------ //

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        if (targets.length != values.length || targets.length != calldatas.length) {
            revert ArrayLengthMismatch();
        }
        if (!hasRole(PROPOSER_ROLE, msg.sender)) {
            revert InsufficientVotingPower(msg.sender, 0, MIN_PROPOSAL_THRESHOLD);
        }

        uint256 proposalId = ++_proposalCount;
        Proposal storage p = _proposals[proposalId];
        p.targets = targets;
        p.values = values;
        p.calldatas = calldatas;
        p.description = description;
        p.voteStart = block.number + votingDelay;
        p.voteEnd = block.number + votingDelay + votingPeriod;

        emit ProposalCreated(proposalId, description, targets, values, calldatas, p.voteStart, p.voteEnd);
        return proposalId;
    }

    function cancel(uint256 proposalId) external {
        if (proposalId == 0 || proposalId > _proposalCount) revert ProposalNotFound(proposalId);
        if (!hasRole(PROPOSER_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert InsufficientVotingPower(msg.sender, 0, MIN_PROPOSAL_THRESHOLD);
        }
        Proposal storage p = _proposals[proposalId];
        p.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    // ------------------------------------------------------------------ //
    //                             Voting                                 //
    // ------------------------------------------------------------------ //

    function castVote(uint256 proposalId, uint8 support) external returns (uint256) {
        return _castVote(proposalId, support, "");
    }

    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external returns (uint256) {
        return _castVote(proposalId, support, reason);
    }

    function _castVote(uint256 proposalId, uint8 support, string memory reason) internal returns (uint256) {
        if (proposalId == 0 || proposalId > _proposalCount) revert ProposalNotFound(proposalId);
        if (support > 2) revert InvalidVoteType(support);

        Proposal storage p = _proposals[proposalId];
        if (state(proposalId) != ProposalState.Active) revert ProposalNotActive(proposalId);
        if (p.hasVoted[msg.sender]) revert AlreadyVoted(proposalId, msg.sender);

        uint256 weight = token.balanceOf(msg.sender);
        if (weight == 0) revert InsufficientVotingPower(msg.sender, 0, 1);

        p.hasVoted[msg.sender] = true;

        if (support == 0) {
            p.noVotes += weight;
        } else if (support == 1) {
            p.yesVotes += weight;
        } else {
            p.abstainVotes += weight;
        }

        emit VoteCast(msg.sender, proposalId, support, weight, reason);
        return weight;
    }

    // ------------------------------------------------------------------ //
    //                           Execution                                //
    // ------------------------------------------------------------------ //

    function execute(uint256 proposalId) external nonReentrant {
        if (proposalId == 0 || proposalId > _proposalCount) revert ProposalNotFound(proposalId);
        Proposal storage p = _proposals[proposalId];

        if (state(proposalId) != ProposalState.Succeeded) revert ProposalNotSucceeded(proposalId);
        p.executed = true;

        for (uint256 i = 0; i < p.targets.length; i++) {
            (bool success, ) = p.targets[i].call{value: p.values[i]}(p.calldatas[i]);
            require(success, "Proposal execution failed");
        }

        emit ProposalExecuted(proposalId);
    }

    // ------------------------------------------------------------------ //
    //                         Internal Helpers                           //
    // ------------------------------------------------------------------ //

    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        Proposal storage p = _proposals[proposalId];
        return p.yesVotes > p.noVotes && (p.yesVotes + p.abstainVotes) >= quorum();
    }

    // ------------------------------------------------------------------ //
    //                         Role Management                           //
    // ------------------------------------------------------------------ //

    function grantVoterRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(VOTER_ROLE, account);
    }

    function revokeVoterRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(VOTER_ROLE, account);
    }

    function grantProposerRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PROPOSER_ROLE, account);
    }

    receive() external payable {}
}