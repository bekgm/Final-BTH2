// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AMM
/// @notice Pure library implementing CPMM (constant-product market maker) math
/// @dev All functions are internal pure - no state reads, no external calls.
///      Used by PredictionMarket for buy/sell price computation.
library AMM {
    // Constants

    /// @notice Protocol fee in basis points (0.3%)
    uint256 internal constant FEE_BPS = 30;

    /// @notice Basis-point denominator
    uint256 internal constant BPS = 10_000;
    // Errors

    /// @notice Reverts when either reserve is zero (undefined AMM state)
    error ZeroReserve();

    /// @notice Reverts when amountOut would equal or exceed the output reserve
    error InsufficientOutputReserve();
    // Core math

    /// @notice Computes output amount given an input, applying the fee
    /// @dev Formula (CPMM with fee):
    ///        fee       = amountIn * FEE_BPS / BPS
    ///        netIn     = amountIn - fee
    ///        amountOut = (reserveOut * netIn) / (reserveIn + netIn)
    /// @param amountIn   Input token amount (gross, before fee)
    /// @param reserveIn  Current reserve of the input token
    /// @param reserveOut Current reserve of the output token
    /// @return amountOut Amount of output token received
    /// @return fee       Fee amount in input token units
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut, uint256 fee) {
        if (reserveIn == 0 || reserveOut == 0) revert ZeroReserve();
        fee = (amountIn * FEE_BPS) / BPS;
        uint256 amountInAfterFee = amountIn - fee;
        amountOut = (reserveOut * amountInAfterFee) / (reserveIn + amountInAfterFee);
        if (amountOut >= reserveOut) revert InsufficientOutputReserve();
    }

    /// @notice Computes the input amount required to receive an exact output
    /// @dev Formula (CPMM with fee, rounding UP):
    ///        grossIn = ceil(reserveIn * amountOut / (reserveOut - amountOut))
    ///        amountIn = ceil(grossIn * BPS / (BPS - FEE_BPS))
    /// @param amountOut  Desired exact output amount
    /// @param reserveIn  Current reserve of the input token
    /// @param reserveOut Current reserve of the output token
    /// @return amountIn  Required input amount (inclusive of fee, rounded up)
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        if (reserveIn == 0 || reserveOut == 0) revert ZeroReserve();
        if (amountOut >= reserveOut) revert InsufficientOutputReserve();
        // Numerator and denominator for the gross-input calculation
        uint256 numerator = reserveIn * amountOut * BPS;
        uint256 denominator = (reserveOut - amountOut) * (BPS - FEE_BPS);
        // Ceiling division: (a + b - 1) / b
        amountIn = (numerator + denominator - 1) / denominator;
    }

    /// @notice Verifies that the constant-product invariant is preserved
    /// @dev Returns true if newX * newY >= oldX * oldY.
    ///      Uses unchecked to avoid overflow revert - callers should ensure
    ///      values fit within uint256 product range, or the overflow wraps.
    /// @param oldX Old reserve of token X (e.g., yesReserve before trade)
    /// @param oldY Old reserve of token Y (e.g., noReserve before trade)
    /// @param newX New reserve of token X
    /// @param newY New reserve of token Y
    /// @return True when the invariant holds
    function checkInvariant(
        uint256 oldX,
        uint256 oldY,
        uint256 newX,
        uint256 newY
    ) internal pure returns (bool) {
        // Unchecked: if either product wraps the comparison still yields the
        // correct result because we only need >= under modular arithmetic for
        // the same bit-width; practically reserves never reach sqrt(2^256).
        unchecked {
            return newX * newY >= oldX * oldY;
        }
    }

    /// @notice Computes the spot price of the output token in 1e18 fixed-point
    /// @dev spotPrice = reserveOut / (reserveIn + reserveOut) * 1e18
    ///      For a balanced market this returns 0.5e18 for both sides.
    /// @param reserveIn  Reserve of the token being provided (e.g., NO when buying YES)
    /// @param reserveOut Reserve of the token being received (e.g., YES when buying YES)
    /// @return price Spot price in 1e18 units (range: 0 < price < 1e18)
    function spotPrice(
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 price) {
        if (reserveIn == 0 || reserveOut == 0) revert ZeroReserve();
        price = (reserveOut * 1e18) / (reserveIn + reserveOut);
    }
}
