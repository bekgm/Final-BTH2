// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/core/AMM.sol";

/// @title GasComparison
/// @notice Benchmarks Solidity vs Yul assembly implementations
/// @dev Run with: forge test --match-test "GasComparison" --gas-report -vv
contract GasComparisonTest is Test {
    using AMM for *;

    // Test parameters
    uint256 constant AMOUNT_IN = 1e18;      // 1 token
    uint256 constant RESERVE_IN = 100e18;   // 100 tokens
    uint256 constant RESERVE_OUT = 100e18; // 100 tokens

    /// @notice Benchmark Solidity implementation
    function testGetAmountOutSolidity() public pure {
        (uint256 amountOut, uint256 fee) = AMM.getAmountOutSolidity(
            AMOUNT_IN,
            RESERVE_IN,
            RESERVE_OUT
        );
        
        // Prevent optimization
        vm.assume(amountOut > 0);
        vm.assume(fee > 0);
    }

    /// @notice Benchmark Yul assembly implementation
    function testGetAmountOutAssembly() public pure {
        (uint256 amountOut, uint256 fee) = AMM.getAmountOutAssembly(
            AMOUNT_IN,
            RESERVE_IN,
            RESERVE_OUT
        );
        
        // Prevent optimization
        vm.assume(amountOut > 0);
        vm.assume(fee > 0);
    }

    /// @notice Verify both implementations return identical results
    function testImplementationEquivalence() public pure {
        (uint256 amountOutSolidity, uint256 feeSolidity) = AMM.getAmountOutSolidity(
            AMOUNT_IN,
            RESERVE_IN,
            RESERVE_OUT
        );

        (uint256 amountOutAssembly, uint256 feeAssembly) = AMM.getAmountOutAssembly(
            AMOUNT_IN,
            RESERVE_IN,
            RESERVE_OUT
        );

        assertEq(amountOutSolidity, amountOutAssembly, "Amount out mismatch");
        assertEq(feeSolidity, feeAssembly, "Fee mismatch");
    }

    /// @notice Benchmark with fuzzing
    /// @param amountIn Fuzzed amount (1 to 1000 tokens)
    /// @param reserveIn Fuzzed reserve (100 to 10000 tokens)
    /// @param reserveOut Fuzzed reserve (100 to 10000 tokens)
    function testFuzzGasEquivalence(
        uint64 amountIn,
        uint128 reserveIn,
        uint128 reserveOut
    ) public pure {
        // Bound inputs to realistic values
        amountIn = uint64(bound(amountIn, 1e6, 1000e18));
        reserveIn = uint128(bound(reserveIn, 100e18, 10000e18));
        reserveOut = uint128(bound(reserveOut, 100e18, 10000e18));

        // Ensure we don't break CPMM invariants
        vm.assume(amountIn < reserveIn / 10);
        vm.assume(amountIn < reserveOut / 10);

        (uint256 out1, uint256 fee1) = AMM.getAmountOutSolidity(amountIn, reserveIn, reserveOut);
        (uint256 out2, uint256 fee2) = AMM.getAmountOutAssembly(amountIn, reserveIn, reserveOut);

        assertEq(out1, out2, "Fuzz amount out mismatch");
        assertEq(fee1, fee2, "Fuzz fee mismatch");
    }
}
