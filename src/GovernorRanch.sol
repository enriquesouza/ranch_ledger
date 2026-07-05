    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title GovernorRanch
/// @notice DAO governance for the RanchLendingVault. RanchToken holders vote on:
///         - Liquidation threshold changes
///         - New supported collateral types  
///         - Fee structure adjustments
contract GovernorRanch is Governor, Votes, AccessControl {
    // ------------------------------------------------------------------ //
    //                              Roles                                 //
    // ------------------------------------------------------------------ //

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant VOTER_ROLE = keccak256("VOTER_ROLE");

    // ------------------------------------------------------------------ //
    //                              Errors                                //
    // ------------------------------------------------------------------ //

    error ProposalNotFound(uint256 proposalId);
    error VotingPeriodExpired();

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
    //                              Storage                               //
    // ------------------------------------------------------------------ //

    ERC20 public immutable token;
    uint256 private immutable _votingDelay;
    uint256 private immutable _votingPeriod;
    
    uint256 private constant MIN_PROPOSAL_THRESHOLD = 1e18; // 1 token (6 decimals)

    mapping(uint256 => mapping(address => bool)) private _votesCast;

    constructor(
        ERC20 _token,
        string memory name_,
        uint256 votingDelay_,
        uint256 votingPeriod_
    ) Governor(name_) Votes(_token.name()) {
        token = _token;
        
        _votingDelay = votingDelay_;
        _votingPeriod = votingPeriod_;
        
        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, address(this));
        _grantRole(PROPOSER_ROLE, msg.sender);
    }

    function name() public view override returns (string memory) {
        return "RanchDAO";
    }

    function version() public pure override returns (string memory) {
        return "1.0";
    }

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure override returns (bytes32) {
        return keccak256(abi.encode(targets, values, calldatas, descriptionHash));
    }

    function votingDelay() public view override returns (uint256) {
        return _votingDelay;
    }

    function votingPeriod() public view override returns (uint256) {
        return _votingPeriod;
    }

    function quorum(uint256 blockNumber) public view override returns (uint256) {
        return token.totalSupply() / 10; // 10% quorum based on total supply
    }

    function proposalThreshold() public view override returns (uint256) {
        return MIN_PROPOSAL_THRESHOLD;
    }

    function getVotes(address account, uint256 blockNumber) public view override returns (uint256) {
        return token.balanceOf(account); // Simplified: use current balance instead of historical
    }

    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return _votesCast[proposalId][account];
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(Governor, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function COUNTING_MODE() external pure override returns (string memory) {
        return "support=bravo&quorum=yes";
    }

    function CLOCK_MODE() external pure override returns (string memory) {
        return "mode=blocknumber";
    }

    function clock() public view override returns (uint48) {
        return uint48(block.number);
    }

    function _getVotingUnits(address account) internal view override returns (uint256) {
        return token.getVotes(account);
    }

    function _quorumReached(uint256 proposalId) internal view virtual override returns (bool) {
        ProposalDetails memory details = _proposals[proposalId];
        uint256 quorumVotes = quorum(details.proposalSnapshot);
        return details.yesVotes + details.abstainVotes >= quorumVotes;
    }

    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool) {
        ProposalDetails memory details = _proposals[proposalId];
        return details.yesVotes > details.noVotes && _quorumReached(proposalId);
    }

    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal virtual override {
        ProposalDetails storage details = _proposals[proposalId];
        
        if (support == 0) {
            details.noVotes += weight;
        } else if (support == 1) {
            details.yesVotes += weight;
        } else if (support == 2) {
            details.abstainVotes += weight;
        }
        
        _votesCast[proposalId][account] = true;
    }

    function state(uint256 proposalId) public view override returns (ProposalState) {
        ProposalDetails memory details = _proposals[proposalId];
        
        if (details.proposalDeadline < block.number) {
            return ProposalState.Succeeded;
        } else if (_voteSucceeded(proposalId)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Active;
        }
    }

    function proposalDeadline(uint256 proposalId) public view override returns (uint256) {
        return _proposals[proposalId].proposalDeadline;
    }

    struct ProposalDetails {
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
        uint256 proposalSnapshot;
        uint256 proposalDeadline;
    }

    mapping(uint256 => ProposalDetails) private _proposals;

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        require(targets.length == values.length && targets.length == calldatas.length, "Invalid proposal");
        
        uint256 votes = token.getVotes(msg.sender);
        require(votes >= MIN_PROPOSAL_THRESHOLD, "Insufficient voting power");
        
        return super.propose(targets, values, calldatas, description);
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
        emit ProposalExecuted(proposalId);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override returns (uint256) {
        uint256 proposalId = super._cancel(targets, values, calldatas, descriptionHash);
        emit ProposalCanceled(proposalId);
        return proposalId;
    }

    function castVote(uint256 proposalId, uint8 support) public override returns (uint256) {
        require(support <= 2, "Invalid vote type");
        
        address voter = msg.sender;
        _requireVoter(voter);
        
        uint256 weight = getVotes(voter, block.number - 1);
        require(weight > 0, "Insufficient voting power");
        
        _votesCast[proposalId][voter] = true;
        
        return super.castVote(proposalId, support);
    }

    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public override returns (uint256) {
        require(support <= 2, "Invalid vote type");
        
        address voter = msg.sender;
        _requireVoter(voter);
        
        uint256 weight = getVotes(voter, block.number - 1);
        require(weight > 0, "Insufficient voting power");
        
        _votesCast[proposalId][voter] = true;
        
        return super.castVoteWithReason(proposalId, support, reason);
    }

    function _requireVoter(address account) internal view {
        if (!hasRole(VOTER_ROLE, account)) {
            revert("Not a voter");
        }
    }

    function grantVoterRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(VOTER_ROLE, account);
    }

    function revokeVoterRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(VOTER_ROLE, account);
    }

    function state(uint256 proposalId) public view override returns (ProposalState) {
        return super.state(proposalId);
    }

    function proposalDeadline(uint256 proposalId) public view override returns (uint256) {
        return super.proposalDeadline(proposalId);
    }
}
