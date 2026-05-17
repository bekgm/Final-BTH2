// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from
    "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from
    "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from
    "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from
    "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title PredictionGovernor
/// @notice On-chain governance contract for the PredictionMarket protocol.
///         Proposals are voted on by PGOV token holders and executed via the
///         GovernorTimelock after a mandatory delay.
/// @dev    Inherits the full OpenZeppelin v5 Governor stack:
///           - GovernorSettings            - voting delay, period, threshold
///           - GovernorCountingSimple      - For/Against/Abstain counting
///           - GovernorVotes               - ERC20Votes snapshot integration
///           - GovernorVotesQuorumFraction - quorum as % of total supply
///           - GovernorTimelockControl     - routes execution through Timelock
///         Clock mode: uses block.timestamp (matching GovernanceToken's clock).
///         Override list rules (OZ v5):
///           - Functions defined in BOTH Governor and one extension -> override(Governor, Extension)
///           - Functions defined ONLY in GovernorTimelockControl    -> override alone
///           - supportsInterface: NOT overridden by GovernorTimelockControl -> no override needed
/// @custom:security-contact security@predictionprotocol.xyz
contract PredictionGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    // Constructor

    /// @notice Deploys the governor with all parameters configured
    /// @param token_             GovernanceToken (PGOV) address implementing IVotes
    /// @param timelock_          GovernorTimelock address
    /// @param votingDelay_       Delay (in seconds) from proposal creation to voting start
    /// @param votingPeriod_      Duration (in seconds) of the voting window
    /// @param proposalThreshold_ Minimum PGOV tokens required to submit a proposal
    /// @param quorumNumerator_   Quorum as percentage of total supply (e.g. 4 = 4%)
    constructor(
        IVotes token_,
        TimelockController timelock_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumNumerator_
    )
        Governor("PredictionGovernor")
        GovernorSettings(votingDelay_, votingPeriod_, proposalThreshold_)
        GovernorVotes(token_)
        GovernorVotesQuorumFraction(quorumNumerator_)
        GovernorTimelockControl(timelock_)
    {}
    // Overrides required to resolve multiple-inheritance conflicts (OZ v5)

    /// @notice Returns the delay between proposal creation and voting start
    /// @dev GovernorSettings and Governor (IGovernor) both define this.
    /// @return Voting delay in clock units (seconds with timestamp clock)
    function votingDelay()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    /// @notice Returns the duration of the voting window
    /// @dev GovernorSettings and Governor (IGovernor) both define this.
    /// @return Voting period in clock units
    function votingPeriod()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    /// @notice Returns the minimum PGOV balance required to create a proposal
    /// @dev GovernorSettings and Governor both define proposalThreshold.
    /// @return Token amount threshold (in 1e18 units)
    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    /// @notice Returns the quorum required for a proposal to succeed
    /// @dev GovernorVotesQuorumFraction and IGovernor both define this.
    /// @param timepoint Snapshot timestamp at which quorum is computed
    /// @return Minimum vote weight needed for quorum
    function quorum(
        uint256 timepoint
    )
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(timepoint);
    }

    /// @notice Returns the current state of a proposal
    /// @dev GovernorTimelockControl overrides Governor.state - both in the chain.
    /// @param proposalId Target proposal identifier
    /// @return Current ProposalState
    function state(
        uint256 proposalId
    )
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /// @notice Returns whether this proposal must be queued before execution
    /// @dev GovernorTimelockControl overrides Governor (IGovernor) definition.
    /// @param proposalId Target proposal identifier
    /// @return True - all proposals go through the timelock queue
    function proposalNeedsQueuing(
        uint256 proposalId
    )
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /// @notice Queues a successful proposal's operations into the timelock
    /// @dev Only GovernorTimelockControl defines _queueOperations; single override.
    /// @param proposalId      Proposal identifier
    /// @param targets         Call targets
    /// @param values          ETH values
    /// @param calldatas       Encoded calls
    /// @param descriptionHash keccak256 of the proposal description
    /// @return eta            Earliest execution timestamp (uint48)
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(
            proposalId, targets, values, calldatas, descriptionHash
        );
    }

    /// @notice Executes queued proposal operations via the timelock
    /// @dev Only GovernorTimelockControl defines _executeOperations; single override.
    /// @param proposalId      Proposal identifier
    /// @param targets         Call targets
    /// @param values          ETH values
    /// @param calldatas       Encoded calls
    /// @param descriptionHash keccak256 of the proposal description
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(
            proposalId, targets, values, calldatas, descriptionHash
        );
    }

    /// @notice Cancels a proposal, also cancelling its timelock operation if queued
    /// @dev Only GovernorTimelockControl defines _cancel; single override.
    /// @param targets         Call targets
    /// @param values          ETH values
    /// @param calldatas       Encoded calls
    /// @param descriptionHash keccak256 of the proposal description
    /// @return proposalId     The cancelled proposal's ID
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @notice Returns the executor address (the timelock controller)
    /// @dev Only GovernorTimelockControl defines _executor; single override.
    /// @return The timelock controller address
    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }
}
