// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AccessControlVulnerable
/// @notice AUDIT CASE STUDY — Demonstrates a missing access control vulnerability
///         in a simplified resolveMarket function that has NO role check.
///         DO NOT USE IN PRODUCTION.
/// @dev    The bug: resolveMarket() can be called by ANY address (including
///         bots, MEV searchers, or attackers) with no authorization check.
///         In a real market this enables:
///           - Premature resolution before resolutionTime
///           - Manipulation of the winning outcome if the oracle data is
///             ambiguous or the attacker can influence the oracle
///           - Griefing by triggering resolution with stale/incorrect data
///
///         Note: in this simplified demo, the oracle is a simple admin-set value.
///         In production the attacker who controls a feed could set a price and
///         then call this function to resolve in their favour.
///
///         Fix: see AccessControlFixed.sol (uses OpenZeppelin AccessControl).
contract AccessControlVulnerable {
    // State

    struct Market {
        uint256 resolutionTime;
        bool resolved;
        uint8 winningOutcome;
        int256 mockOraclePrice; // simplified: set by admin in tests
    }

    /// @dev marketId → Market
    mapping(uint256 => Market) public markets;
    // Events

    /// @notice Emitted when a market is resolved
    event MarketResolved(uint256 indexed marketId, uint8 winningOutcome);
    // Setup helpers

    /// @notice Creates a demo market (no access control for simplicity)
    /// @param marketId       Market identifier
    /// @param resolutionTime Earliest resolution timestamp
    /// @param mockPrice      Initial mock oracle price
    function createMarket(
        uint256 marketId,
        uint256 resolutionTime,
        int256 mockPrice
    ) external {
        markets[marketId] = Market({
            resolutionTime:  resolutionTime,
            resolved:        false,
            winningOutcome:  0,
            mockOraclePrice: mockPrice
        });
    }
    // VULNERABLE function — DO NOT USE

    /// @notice VULNERABLE: no access control — anyone can resolve any market
    /// @dev    BUG: There is no msg.sender authorization check of any kind.
    ///         Any externally owned account or contract can call this function
    ///         at any time (even before resolutionTime) and force a resolution.
    ///         Combined with oracle manipulation, this is a critical exploit path.
    /// @param marketId Target market to resolve
    function resolveMarket(uint256 marketId) external {
        Market storage market = markets[marketId];
        require(!market.resolved, "already resolved");
        // ❌ NO CHECK: block.timestamp >= market.resolutionTime
        // ❌ NO CHECK: msg.sender has RESOLVER_ROLE or any role at all

        uint8 winningOutcome = (market.mockOraclePrice > 0) ? 1 : 2;

        // State update
        market.resolved       = true;
        market.winningOutcome = winningOutcome;

        emit MarketResolved(marketId, winningOutcome);
    }
}
