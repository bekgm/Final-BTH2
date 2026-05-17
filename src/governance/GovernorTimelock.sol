// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from
    "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title GovernorTimelock
/// @notice TimelockController that enforces a minimum delay between governance
///         proposal queueing and execution. Wraps OZ TimelockController with
///         no additional logic - the protocol uses the standard OZ roles:
///           PROPOSER_ROLE  -> granted to PredictionGovernor
///           EXECUTOR_ROLE  -> granted to address(0) (anyone can execute)
///           CANCELLER_ROLE -> granted to admin at deploy time
///           DEFAULT_ADMIN_ROLE -> granted to admin (can manage roles)
/// @dev    Deploy this first, then deploy PredictionGovernor and grant it
///         PROPOSER_ROLE via grantRole(PROPOSER_ROLE, governorAddress).
/// @custom:security-contact security@predictionprotocol.xyz
contract GovernorTimelock is TimelockController {
    /// @notice Deploys the timelock with a minimum delay
    /// @param minDelay   Minimum seconds between queue and execute (e.g. 2 days)
    /// @param proposers  Addresses that can queue operations (usually [governor])
    /// @param executors  Addresses that can execute (pass [address(0)] for open)
    /// @param admin      Address receiving DEFAULT_ADMIN_ROLE (renounce after setup)
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
