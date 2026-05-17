// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ReentrancyVulnerable
/// @notice AUDIT CASE STUDY — Demonstrates a reentrancy vulnerability in a
///         simplified redeemWinningTokens function that sends ETH before
///         updating state. DO NOT USE IN PRODUCTION.
/// @dev    The bug: ETH is sent via call{value:}() BEFORE the user's balance
///         is zeroed. A malicious contract can re-enter redeemWinningTokens()
///         in the fallback, draining the contract repeatedly until gas or funds
///         are exhausted.
///
///         Attack flow:
///           1. Attacker deploys MaliciousRedeemer with a fallback that calls
///              back into redeemWinningTokens().
///           2. Attacker calls redeemWinningTokens() with a valid balance.
///           3. Contract sends ETH at step (B) — before zeroing balance at (C).
///           4. Attacker's fallback re-enters: balance is still non-zero →
///              another ETH send → re-enters again → ... until funds drained.
///
///         Fix: see ReentrancyFixed.sol (uses Checks-Effects-Interactions).
contract ReentrancyVulnerable {
    // State

    /// @dev Winning token balances for demonstration (marketId → user → amount)
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
    // VULNERABLE function — DO NOT USE

    /// @notice VULNERABLE: sends ETH before zeroing balance (reentrancy risk)
    /// @dev    BUG: The ETH transfer at step (B) occurs BEFORE the balance is
    ///         cleared at step (C). This violates Checks-Effects-Interactions.
    ///         A re-entrant fallback can call this function again with a still-
    ///         non-zero balance, repeatedly draining collateral.
    /// @param marketId Target market
    function redeemWinningTokens(uint256 marketId) external {
        // (A) CHECK — valid balance
        uint256 userBalance = winningBalances[marketId][msg.sender];
        require(userBalance > 0, "no balance");

        uint256 payout = (userBalance * totalCollateral[marketId])
            / totalWinningSupply[marketId];

        // ❌ (B) INTERACTION — ETH sent BEFORE state update (VULNERABLE)
        (bool success, ) = msg.sender.call{value: payout}("");
        require(success, "transfer failed");

        // ❌ (C) EFFECT — balance zeroed AFTER the external call (TOO LATE)
        winningBalances[marketId][msg.sender] = 0;
        totalCollateral[marketId]       -= payout;
        totalWinningSupply[marketId]    -= userBalance;

        emit WinningsRedeemed(marketId, msg.sender, payout);
    }

    /// @dev Allow contract to receive ETH for testing
    receive() external payable {}
}
