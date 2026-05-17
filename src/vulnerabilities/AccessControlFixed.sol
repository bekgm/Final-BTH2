// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AccessControlFixed
/// @notice AUDIT CASE STUDY - Fixed version of AccessControlVulnerable.sol.
///         Demonstrates proper role-based access control using OpenZeppelin
///         AccessControl on a simplified resolveMarket function.
/// @dev    Two fixes are applied:
///           1. RESOLVER_ROLE: only addresses explicitly granted this role by
///              the DEFAULT_ADMIN_ROLE holder may call resolveMarket().
///           2. Timestamp guard: resolution is blocked before resolutionTime
///              to prevent premature settlement.
///         In production (PredictionMarket.sol), resolution is permissionless
///         after resolutionTime but uses a Chainlink oracle for the price data,
///         making it manipulation-resistant without needing a privileged caller.
contract AccessControlFixed is AccessControl {
    // Roles

    /// @notice Role required to call resolveMarket()
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    // Errors

    /// @notice Reverts when attempting to resolve before resolutionTime
    /// @param resolutionTime Allowed resolution timestamp
    /// @param blockTimestamp Current block timestamp
    error ResolutionTooEarly(uint256 resolutionTime, uint256 blockTimestamp);

    /// @notice Reverts when the market has already been resolved
    /// @param marketId The already-resolved market
    error MarketAlreadyResolved(uint256 marketId);
    // State

    struct Market {
        uint256 resolutionTime;
        bool resolved;
        uint8 winningOutcome;
        int256 mockOraclePrice;
    }

    /// @dev marketId -> Market
    mapping(uint256 => Market) public markets;
    // Events

    /// @notice Emitted when a market is resolved
    event MarketResolved(uint256 indexed marketId, uint8 winningOutcome);
    // Constructor

    /// @notice Grants DEFAULT_ADMIN_ROLE (and optionally RESOLVER_ROLE) to admin
    /// @param admin Address receiving DEFAULT_ADMIN_ROLE
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RESOLVER_ROLE, admin);
    }
    // Setup helpers

    /// @notice Creates a demo market (restricted to DEFAULT_ADMIN_ROLE)
    /// @param marketId       Market identifier
    /// @param resolutionTime Earliest resolution timestamp
    /// @param mockPrice      Initial mock oracle price
    function createMarket(
        uint256 marketId,
        uint256 resolutionTime,
        int256 mockPrice
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        markets[marketId] = Market({
            resolutionTime:  resolutionTime,
            resolved:        false,
            winningOutcome:  0,
            mockOraclePrice: mockPrice
        });
    }
    // FIXED function - role-gated + timestamp-guarded

    /// @notice FIXED: only RESOLVER_ROLE after resolutionTime can resolve a market
    /// @dev    Fix 1 - onlyRole(RESOLVER_ROLE): any caller without the role reverts.
    ///         Fix 2 - timestamp guard: resolving before resolutionTime is blocked.
    ///         Both checks occur before any state change (Checks-Effects pattern).
    /// @param marketId Target market to resolve
    function resolveMarket(
        uint256 marketId
    ) external onlyRole(RESOLVER_ROLE) {
        Market storage market = markets[marketId];

        // OK: CHECK 1: not already resolved
        if (market.resolved) revert MarketAlreadyResolved(marketId);

        // OK: CHECK 2: resolution time has passed
        if (block.timestamp < market.resolutionTime) {
            revert ResolutionTooEarly(market.resolutionTime, block.timestamp);
        }

        uint8 winningOutcome = (market.mockOraclePrice > 0) ? 1 : 2;

        // OK: EFFECTS: update state before any interactions
        market.resolved       = true;
        market.winningOutcome = winningOutcome;

        emit MarketResolved(marketId, winningOutcome);
    }
}
