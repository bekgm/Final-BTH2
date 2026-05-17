// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ReentrancyFixed
/// @notice AUDIT CASE STUDY - Fixed version of ReentrancyVulnerable.sol.
///         Demonstrates correct Checks-Effects-Interactions pattern combined
///         with OpenZeppelin's ReentrancyGuard as defence-in-depth.
/// @dev    Two mitigations are applied:
///           1. Checks-Effects-Interactions (CEI): all state is updated BEFORE
///              any external call. Even if a re-entrant call is made, the user's
///              balance is already zero so the check at step (A) reverts.
///           2. nonReentrant modifier: adds a mutex that causes any re-entrant
///              call to this function to revert immediately, regardless of state.
///         Either fix alone is sufficient; combining them is best practice.
contract ReentrancyFixed is ReentrancyGuard {
    // State

    /// @dev Winning token balances (marketId -> user -> amount)
    mapping(uint256 => mapping(address => uint256)) public winningBalances;

    /// @dev Total ETH collateral backing each market
    mapping(uint256 => uint256) public totalCollateral;

    /// @dev Total winning tokens outstanding per market
    mapping(uint256 => uint256) public totalWinningSupply;
    // Events

    /// @notice Emitted when a winning redemption succeeds
    event WinningsRedeemed(uint256 indexed marketId, address indexed redeemer, uint256 amount);
    // Setup helpers

    /// @notice Seeds a user's winning balance (stand-in for actual token minting)
    /// @param marketId Target market
    /// @param user     User to credit
    /// @param amount   Winning token balance to assign
    function seedBalance(uint256 marketId, address user, uint256 amount) external payable {
        winningBalances[marketId][user] += amount;
        totalWinningSupply[marketId]    += amount;
        totalCollateral[marketId]       += msg.value;
    }
    // FIXED function - CEI + nonReentrant

    /// @notice FIXED: follows Checks-Effects-Interactions; protected by nonReentrant
    /// @dev    Fix 1 - CEI: balance is cleared at step (B, Effects) BEFORE the
    ///         ETH transfer at step (C, Interactions). A re-entrant call now hits
    ///         a zero balance at step (A) and reverts harmlessly.
    ///         Fix 2 - nonReentrant: the OZ mutex immediately reverts any re-entry
    ///         regardless of state, providing defence-in-depth.
    /// @param marketId Target market
    function redeemWinningTokens(uint256 marketId) external nonReentrant {
        // (A) CHECKS - validate user has a balance
        uint256 userBalance = winningBalances[marketId][msg.sender];
        require(userBalance > 0, "no balance");

        uint256 payout = (userBalance * totalCollateral[marketId])
            / totalWinningSupply[marketId];

        // OK: (B) EFFECTS - zero balance and update totals BEFORE external call
        winningBalances[marketId][msg.sender] = 0;
        totalCollateral[marketId]       -= payout;
        totalWinningSupply[marketId]    -= userBalance;

        emit WinningsRedeemed(marketId, msg.sender, payout);

        // OK: (C) INTERACTIONS - ETH transfer happens LAST
        (bool success, ) = msg.sender.call{value: payout}("");
        require(success, "transfer failed");
    }

    /// @dev Allow contract to receive ETH for testing
    receive() external payable {}
}
