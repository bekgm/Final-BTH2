// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFeeVault
/// @notice Interface for the ERC-4626 fee vault that receives protocol fees
interface IFeeVault {
    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when fees are deposited into the vault by a market
    /// @param depositor Address calling depositFees (PredictionMarket)
    /// @param amount    USDC amount deposited
    event FeesDeposited(address indexed depositor, uint256 amount);

    // =========================================================================
    // Functions
    // =========================================================================

    /// @notice Accepts fee payment from an authorised market contract
    /// @dev Caller must hold DEPOSITOR_ROLE. Pulls USDC via transferFrom.
    /// @param amount USDC amount to deposit as fees
    function depositFees(uint256 amount) external;

    /// @notice Returns the total assets held in the vault
    /// @return Total USDC balance managed by the vault
    function totalAssets() external view returns (uint256);

    /// @notice Converts a share amount to its equivalent asset amount (rounded down)
    /// @param shares Number of vault shares
    /// @return assets Equivalent USDC amount
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /// @notice Converts an asset amount to its equivalent share amount (rounded down)
    /// @param assets USDC amount
    /// @return shares Equivalent vault shares
    function convertToShares(uint256 assets) external view returns (uint256 shares);
}
