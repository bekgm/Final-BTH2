// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IOracleAdapter
/// @notice Interface for the Chainlink oracle adapter used to resolve markets
interface IOracleAdapter {
    // Errors

    /// @notice Reverts when the Chainlink feed returns a non-positive price
    /// @param price The invalid price value returned
    error InvalidPrice(int256 price);

    /// @notice Reverts when the price data is older than the allowed staleness window
    /// @param updatedAt     Timestamp of the last price update
    /// @param blockTimestamp Current block timestamp
    error StalePrice(uint256 updatedAt, uint256 blockTimestamp);
    // Functions

    /// @notice Fetches the latest price from a Chainlink aggregator feed
    /// @dev Reverts with InvalidPrice if answer <= 0, or StalePrice if stale
    /// @param feed  Address of the AggregatorV3Interface feed
    /// @return price     Latest price answer from the feed
    /// @return updatedAt Timestamp of the last update round
    function getLatestPrice(address feed) external view returns (int256 price, uint256 updatedAt);

    /// @notice Checks whether a given feed's data is considered stale
    /// @param feed   Address of the AggregatorV3Interface feed
    /// @param maxAge Maximum acceptable age in seconds
    /// @return True if the last update is older than maxAge seconds
    function isStale(address feed, uint256 maxAge) external view returns (bool);
}
