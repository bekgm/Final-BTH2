// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PredictionMarket} from "./PredictionMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AMM} from "./AMM.sol";
import {OutcomeToken} from "../tokens/OutcomeToken.sol";
import {FeeVault} from "../vault/FeeVault.sol";

/// @title PredictionMarketV2
/// @notice Upgraded implementation of PredictionMarket with a governable fee rate
/// @dev    Demonstrates a real V1→V2 upgrade path:
///           • Adds `version` storage variable (initialised to 2 via reinitializer)
///           • Adds `feeBps` governable fee (replaces the V1 FEE_BPS constant)
///           • Overrides `buy()` to use the new dynamic fee
///         Storage layout rule: new variables are appended AFTER the V1 __gap.
///         The __gap in PredictionMarket is reduced by the number of slots used here.
/// @custom:security-contact security@predictionprotocol.xyz
contract PredictionMarketV2 is PredictionMarket {
    using SafeERC20 for IERC20;
    // New V2 storage (appended after V1 __gap — upgrade safe)

    /// @notice Semantic version set to 2 during initializeV2()
    uint256 public version;

    /// @notice Governable fee rate in basis points (replaces constant FEE_BPS)
    /// @dev    Default is 30 (0.3%). Governance can reduce or raise up to 100 (1%).
    uint256 public feeBps;
    // Errors

    /// @notice Reverts when a proposed fee exceeds the 1% maximum
    /// @param proposed The fee value that was rejected
    error FeeTooHigh(uint256 proposed);
    // Events

    /// @notice Emitted when governance updates the protocol fee
    /// @param oldFee Previous fee in basis points
    /// @param newFee New fee in basis points
    event FeeBpsUpdated(uint256 oldFee, uint256 newFee);
    // Re-initializer

    /// @notice Upgrades a V1 proxy to V2 state
    /// @dev    Uses reinitializer(2) — can only be called once per proxy after V1.
    ///         Sets version = 2 and feeBps = 30 (same default as V1 constant).
    function initializeV2() public reinitializer(2) {
        version = 2;
        feeBps = 30;
    }
    // Governance-controlled fee setter

    /// @notice Updates the protocol fee rate
    /// @dev    Only DEFAULT_ADMIN_ROLE (set by governance via Timelock).
    ///         Maximum allowed fee is 100 bps (1%) to protect traders.
    /// @param newFee New fee in basis points (0–100 inclusive)
    function setFeeBps(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFee > 100) revert FeeTooHigh(newFee);
        uint256 oldFee = feeBps;
        feeBps = newFee;
        emit FeeBpsUpdated(oldFee, newFee);
    }
    // Overridden buy() — uses dynamic feeBps instead of FEE_BPS constant

    /// @notice Buys outcome tokens using USDC, applying the dynamic fee rate
    /// @dev    Identical logic to V1 buy() except FEE_BPS is replaced with feeBps.
    ///         CEI pattern:
    ///           Checks (market state, outcome validity, slippage)
    ///           → Effects (reserve update, fee accrual)
    ///           → Interactions (pull USDC, send fee, transfer outcome tokens)
    /// @param marketId     Target market ID
    /// @param outcome      1 = YES, 2 = NO
    /// @param amountIn     USDC amount to spend (must be pre-approved)
    /// @param minAmountOut Minimum outcome tokens to receive (slippage protection)
    /// @return amountOut   Actual outcome tokens received
    function buy(
        uint256 marketId,
        uint8 outcome,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        // --- Checks ---
        if (amountIn == 0) revert ZeroAmount();
        if (outcome != 1 && outcome != 2) revert InvalidOutcome(outcome);

        // Read market state directly from internal storage
        Market storage market = _markets[marketId];
        if (market.resolved) revert MarketAlreadyResolved(marketId);

        uint256 oldYes = market.yesReserve;
        uint256 oldNo  = market.noReserve;
        uint256 currentFeeBps = feeBps; // dynamic

        uint256 reserveIn;
        uint256 reserveOut;

        if (outcome == 1) {
            reserveIn  = oldNo;
            reserveOut = oldYes;
        } else {
            reserveIn  = oldYes;
            reserveOut = oldNo;
        }

        // Apply dynamic fee
        uint256 fee = (amountIn * currentFeeBps) / BPS;
        uint256 amountInAfterFee = amountIn - fee;
        amountOut = (reserveOut * amountInAfterFee) / (reserveIn + amountInAfterFee);

        if (amountOut >= reserveOut) revert InsufficientLiquidity(reserveOut, amountOut);
        if (amountOut < minAmountOut) revert SlippageExceeded(minAmountOut, amountOut);

        uint256 newYes;
        uint256 newNo;

        if (outcome == 1) {
            newNo  = oldNo  + amountInAfterFee;
            newYes = oldYes - amountOut;
        } else {
            newYes = oldYes + amountInAfterFee;
            newNo  = oldNo  - amountOut;
        }

        if (!AMM.checkInvariant(oldYes, oldNo, newYes, newNo)) {
            revert InsufficientLiquidity(0, 0);
        }

        // --- Effects ---
        market.yesReserve   = newYes;
        market.noReserve    = newNo;
        market.feesAccrued += fee;

        // --- Interactions ---
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amountIn);

        IERC20(usdc).safeIncreaseAllowance(feeVault, fee);
        FeeVault(feeVault).depositFees(fee);

        uint256 tokenId = (outcome == 1)
            ? OutcomeToken(outcomeToken).yesTokenId(marketId)
            : OutcomeToken(outcomeToken).noTokenId(marketId);

        IERC1155(outcomeToken).safeTransferFrom(
            address(this), msg.sender, tokenId, amountOut, ""
        );

        emit TokensPurchased(marketId, msg.sender, outcome, amountIn, amountOut);
    }
}
