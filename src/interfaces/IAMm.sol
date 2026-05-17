// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAMm
/// @notice Interface for the AMM library used in prediction markets
/// @dev All functions are pure - no state reads or writes
interface IAMm {
    /// @notice Computes the output amount given an input amount and reserves
    /// @param amountIn   Amount of input token
    /// @param reserveIn  Reserve of the input token
    /// @param reserveOut Reserve of the output token
    /// @return amountOut Amount of output token received
    /// @return fee       Fee deducted from amountIn (in input token units)
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountOut, uint256 fee);

    /// @notice Computes the input amount required to receive an exact output
    /// @param amountOut  Desired output amount
    /// @param reserveIn  Reserve of the input token
    /// @param reserveOut Reserve of the output token
    /// @return amountIn  Input amount required (inclusive of fee)
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountIn);

    /// @notice Checks that the constant-product invariant is maintained
    /// @param oldX Old reserve of token X
    /// @param oldY Old reserve of token Y
    /// @param newX New reserve of token X
    /// @param newY New reserve of token Y
    /// @return True if newX * newY >= oldX * oldY
    function checkInvariant(uint256 oldX, uint256 oldY, uint256 newX, uint256 newY) external pure returns (bool);

    /// @notice Computes the spot price of the output token in 1e18 fixed-point
    /// @param reserveIn  Reserve of the token being sold
    /// @param reserveOut Reserve of the token being bought
    /// @return Spot price in 1e18 representation
    function spotPrice(uint256 reserveIn, uint256 reserveOut) external pure returns (uint256);
}
