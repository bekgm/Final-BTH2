// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from
    "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title MockAggregator
/// @notice Test-only implementation of AggregatorV3Interface.
/// @dev    Allows test suites to set arbitrary price answers and updatedAt
///         timestamps to exercise staleness and resolution logic without a
///         live Chainlink feed. NOT for production use.
/// @custom:security-contact security@predictionprotocol.xyz
contract MockAggregator is AggregatorV3Interface {
    // Storage

    /// @dev Current answer returned by latestRoundData
    int256 private _answer;

    /// @dev Timestamp at which the current answer was set
    uint256 private _updatedAt;

    /// @dev Decimal precision of the feed (immutable after deploy)
    uint8 private _decimals;

    /// @dev Monotonically increasing round counter
    uint80 private _roundId;
    // Constructor

    /// @notice Initialises the mock aggregator with an answer and decimal count
    /// @param initialAnswer The first price answer to return
    /// @param decimals_     Number of decimals (e.g. 8 for USD feeds)
    constructor(int256 initialAnswer, uint8 decimals_) {
        _answer = initialAnswer;
        _updatedAt = block.timestamp;
        _decimals = decimals_;
        _roundId = 1;
    }
    // Setter helpers (test use only)

    /// @notice Updates the mock price and stamps updatedAt to block.timestamp
    /// @param answer New price answer to return
    function setAnswer(int256 answer) external {
        _answer = answer;
        _updatedAt = block.timestamp;
        ++_roundId;
    }

    /// @notice Overrides the updatedAt timestamp for staleness testing
    /// @dev Call after setAnswer to simulate stale data.
    /// @param timestamp Unix timestamp to set as updatedAt
    function setUpdatedAt(uint256 timestamp) external {
        _updatedAt = timestamp;
    }
    // AggregatorV3Interface implementation

    /// @notice Returns the feed's decimal precision
    /// @return Number of decimals
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /// @notice Returns a human-readable feed description
    /// @return Constant description string
    function description() external pure override returns (string memory) {
        return "MockAggregator";
    }

    /// @notice Returns the AggregatorV3Interface version
    /// @return Constant version number
    function version() external pure override returns (uint256) {
        return 1;
    }

    /// @notice Returns data for a specific historical round (dummy values)
    /// @dev    Only the latest round is tracked; historical rounds return zeros.
    /// @param  roundId_ Round ID to query
    /// @return roundId       Echo of the requested round ID
    /// @return answer        0 (historical data not stored)
    /// @return startedAt     0
    /// @return updatedAt     0
    /// @return answeredInRound 0
    function getRoundData(
        uint80 roundId_
    )
        external
        pure
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (roundId_, 0, 0, 0, 0);
    }

    /// @notice Returns the latest round data
    /// @return roundId         Current round ID
    /// @return answer          Current mock price answer
    /// @return startedAt       Same as updatedAt (mock simplification)
    /// @return updatedAt       Timestamp when the answer was last set
    /// @return answeredInRound Same as roundId
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }
}
