// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AggregatorV3Interface} from
    "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";

/// @title OracleAdapter
/// @notice Wraps Chainlink AggregatorV3Interface feeds with staleness and
///         validity checks, providing a uniform interface for the protocol.
/// @dev    Reverts with InvalidPrice for non-positive answers and StalePrice
///         when updatedAt is older than MAX_STALENESS seconds.
///         AccessControl is included so future admin roles (e.g. whitelisting
///         feeds) can be added without a re-deploy.
/// @custom:security-contact security@predictionprotocol.xyz
contract OracleAdapter is AccessControl, IOracleAdapter {
    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Maximum acceptable age for a price update (1 hour)
    uint256 public constant MAX_STALENESS = 3600;

    // =========================================================================
    // Constructor
    // =========================================================================

    /// @notice Grants DEFAULT_ADMIN_ROLE to the deployer
    /// @param admin Address receiving DEFAULT_ADMIN_ROLE
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // =========================================================================
    // IOracleAdapter implementation
    // =========================================================================

    /// @notice Fetches the latest price and timestamp from a Chainlink feed
    /// @dev Calls latestRoundData() on the AggregatorV3Interface feed.
    ///      Reverts with InvalidPrice if answer <= 0.
    ///      Reverts with StalePrice if updatedAt is older than MAX_STALENESS.
    /// @param feed Chainlink AggregatorV3Interface feed address
    /// @return price     Raw answer from the feed (positive int256)
    /// @return updatedAt Timestamp of the last successful oracle update
    function getLatestPrice(
        address feed
    ) external view override returns (int256 price, uint256 updatedAt) {
        (
            /* uint80 roundId */,
            int256 answer,
            /* uint256 startedAt */,
            uint256 _updatedAt,
            /* uint80 answeredInRound */
        ) = AggregatorV3Interface(feed).latestRoundData();

        if (answer <= 0) revert InvalidPrice(answer);
        if (_updatedAt < block.timestamp - MAX_STALENESS) {
            revert StalePrice(_updatedAt, block.timestamp);
        }

        price = answer;
        updatedAt = _updatedAt;
    }

    /// @notice Returns whether the feed's latest data is considered stale
    /// @dev Does NOT revert — callers can use this for soft checks.
    ///      A feed is stale if updatedAt < block.timestamp - maxAge.
    /// @param feed   Chainlink AggregatorV3Interface feed address
    /// @param maxAge Maximum acceptable age in seconds
    /// @return True if the last update is older than maxAge seconds ago
    function isStale(
        address feed,
        uint256 maxAge
    ) external view override returns (bool) {
        (
            /* uint80 roundId */,
            /* int256 answer */,
            /* uint256 startedAt */,
            uint256 _updatedAt,
            /* uint80 answeredInRound */
        ) = AggregatorV3Interface(feed).latestRoundData();

        return _updatedAt < block.timestamp - maxAge;
    }
}
