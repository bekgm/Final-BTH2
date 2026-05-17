// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PredictionMarket, IPredictionMarket} from "../src/core/PredictionMarket.sol";
import {PredictionMarketV2} from "../src/core/PredictionMarketV2.sol";
import {OutcomeToken} from "../src/tokens/OutcomeToken.sol";
import {FeeVault} from "../src/vault/FeeVault.sol";
import {MockERC20, MockOracleAdapter} from "./Mocks.sol";

/// @notice Coverage gap tests for uncovered branches in PredictionMarket
contract CoverageGapsTest is Test {
    PredictionMarket market;
    OutcomeToken outcome;
    FeeVault vault;
    MockERC20 usdc;
    MockOracleAdapter oracle;

    address alice = address(0x1111);
    address bob = address(0x2222);

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC");
        outcome = new OutcomeToken(address(this), "ipfs://");
        vault = new FeeVault(address(usdc), address(this));
        oracle = new MockOracleAdapter();

        PredictionMarket impl = new PredictionMarket();
        bytes memory initData = abi.encodeCall(
            PredictionMarket.initialize,
            (address(usdc), address(outcome), address(vault), address(oracle), address(this))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        market = PredictionMarket(address(proxy));

        outcome.grantRole(keccak256("MARKET_ROLE"), address(market));
        vault.grantRole(keccak256("DEPOSITOR_ROLE"), address(market));

        usdc.mint(address(this), 10_000_000 ether);
        usdc.mint(alice, 5_000_000 ether);
        usdc.mint(bob, 5_000_000 ether);

        usdc.approve(address(market), type(uint256).max);
    }

    // ========== BRANCH COVERAGE TESTS ==========

    /// @notice Gap: buy() with outcome == 2 (NO branch)
    function test_buyOutcome2() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100_000 ether);
        uint256 out = market.buy(marketId, 2, 5_000 ether, 0); // outcome == 2
        assertGt(out, 0);
        vm.stopPrank();
    }

    /// @notice Gap: sell() with outcome == 2 (NO branch)
    function test_sellOutcome2() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100_000 ether);
        market.buy(marketId, 2, 5_000 ether, 0);

        uint256 noId = outcome.noTokenId(marketId);
        outcome.setApprovalForAll(address(market), true);
        uint256 usdcOut = market.sell(marketId, 2, 2_000 ether, 0);
        assertGt(usdcOut, 0);
        vm.stopPrank();
    }

    /// @notice Gap: addLiquidity bootstrap path (totalShares == 0)
    function test_addLiquidityBootstrapPath() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 1_000 ether);

        // Remove all LP to trigger bootstrap
        uint256 lpShares = market.getLpShares(marketId, address(this));
        market.removeLiquidity(marketId, lpShares, 0);

        // Add again to trigger bootstrap path (totalShares == 0)
        market.addLiquidity(marketId, 5_000 ether, 0);
    }

    /// @notice Gap: Pause/unpause with attempted operations
    function test_pauseBlocksOperations() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 1_000 ether);

        market.pause();

        // Attempt create while paused
        vm.expectRevert();
        market.createMarket("Q2?", address(oracle), resTime, 1_000 ether);

        // Attempt mint while paused
        vm.expectRevert();
        market.mintOutcomeTokens(marketId, 100 ether);

        // Unpause and verify works
        market.unpause();
        market.createMarket("Q3?", address(oracle), resTime, 1_000 ether);
    }

    /// @notice Gap: removeLiquidity works when paused (no whenNotPaused guard)
    function test_removeLiquidityIgnoresPause() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 1_000 ether);

        market.pause();

        // removeLiquidity should still work
        uint256 lpShares = market.getLpShares(marketId, address(this));
        market.removeLiquidity(marketId, lpShares / 2, 0);
    }

    /// @notice Gap: buy() slippage revert
    function test_buySlippageReverts() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        vm.expectRevert();
        market.buy(marketId, 1, 100 ether, 1_000_000 ether);
    }

    /// @notice Gap: addLiquidity slippage revert
    function test_addLiquiditySlippageReverts() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        vm.expectRevert();
        market.addLiquidity(marketId, 1_000 ether, 1_000_000 ether);
    }

    /// @notice Gap: removeLiquidity slippage revert
    function test_removeLiquiditySlippageReverts() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        uint256 lpShares = market.getLpShares(marketId, address(this));

        vm.expectRevert();
        market.removeLiquidity(marketId, lpShares / 2, 1_000_000 ether);
    }

    /// @notice Gap: resolve with outcome 1 and outcome 2
    function test_resolveOutcome1And2() public {
        uint256 resTime = block.timestamp + 1 days;
        uint256 id1 = market.createMarket("Q1?", address(oracle), resTime, 100_000 ether);
        uint256 id2 = market.createMarket("Q2?", address(oracle), resTime, 100_000 ether);

        vm.warp(resTime + 1);

        oracle.setLatest(int256(uint256(1)), block.timestamp);
        market.resolveMarket(id1);

        oracle.setLatest(int256(uint256(2)), block.timestamp);
        market.resolveMarket(id2);

        IPredictionMarket.Market memory m1 = market.getMarket(id1);

        assertEq(m1.winningOutcome, 1);
    }

    /// @notice Gap: fee accumulation across trades
    function test_feeAccumulation() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100_000 ether);

        for (uint256 i = 0; i < 3; i++) {
            market.buy(marketId, 1, 1_000 ether, 0);
            uint256 yesId = outcome.yesTokenId(marketId);
            uint256 bal = outcome.balanceOf(alice, yesId);
            if (bal > 100) {
                outcome.setApprovalForAll(address(market), true);
                market.sell(marketId, 1, bal / 3, 0);
            }
        }

        IPredictionMarket.Market memory m = market.getMarket(marketId);
        assertGt(m.feesAccrued, 0);
        vm.stopPrank();
    }

    /// @notice Gap: multiple liquidity providers
    function test_multipleLP() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        // Alice adds liquidity
        vm.startPrank(alice);
        usdc.approve(address(market), 50_000 ether);
        market.addLiquidity(marketId, 50_000 ether, 0);
        uint256 aliceShares = market.getLpShares(marketId, alice);
        assertGt(aliceShares, 0);
        vm.stopPrank();

        // Bob adds liquidity
        vm.startPrank(bob);
        usdc.approve(address(market), 30_000 ether);
        market.addLiquidity(marketId, 30_000 ether, 0);
        uint256 bobShares = market.getLpShares(marketId, bob);
        assertGt(bobShares, 0);
        vm.stopPrank();
    }

    /// @notice Gap: resolve and redeem with mixed outcomes
    function test_resolveAndRedeemMixed() public {
        uint256 resTime = block.timestamp + 1 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 10_000 ether);
        market.buy(marketId, 1, 5_000 ether, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), 10_000 ether);
        market.buy(marketId, 2, 5_000 ether, 0);
        vm.stopPrank();

        // Resolve YES wins
        vm.warp(resTime + 1);
        oracle.setLatest(1, block.timestamp);
        market.resolveMarket(marketId);

        // Alice redeems
        vm.startPrank(alice);
        uint256 yesId = outcome.yesTokenId(marketId);
        uint256 aliceYesBefore = outcome.balanceOf(alice, yesId);
        market.redeemWinningTokens(marketId);
        uint256 aliceYesAfter = outcome.balanceOf(alice, yesId);
        assertEq(aliceYesAfter, 0);
        vm.stopPrank();
    }

    /// @notice Gap: insufficient LP shares revert
    function test_insufficientLPSharesReverts() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        vm.startPrank(alice);
        vm.expectRevert();
        market.removeLiquidity(marketId, 1_000_000 ether, 0);
        vm.stopPrank();
    }

    /// @notice Gap: resolve before resolution time reverts
    function test_resolveBeforeTimeReverts() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        vm.expectRevert();
        market.resolveMarket(marketId);
    }

    /// @notice Gap: resolve already resolved reverts
    function test_resolveAlreadyResolvedReverts() public {
        uint256 resTime = block.timestamp + 1 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        vm.warp(resTime + 1);
        oracle.setLatest(1, block.timestamp);
        market.resolveMarket(marketId);

        vm.expectRevert();
        market.resolveMarket(marketId);
    }

    /// @notice Gap: redeem when unresolved reverts
    function test_redeemUnresolvedReverts() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        vm.startPrank(alice);
        vm.expectRevert();
        market.redeemWinningTokens(marketId);
        vm.stopPrank();
    }

    /// @notice Gap: PredictionMarketV2 upgrade and fee control
    function test_v2UpgradeAndFeeControl() public {
        uint256 resTime = block.timestamp + 7 days;
        uint256 marketId = market.createMarket("Q?", address(oracle), resTime, 100_000 ether);

        PredictionMarketV2 v2Impl = new PredictionMarketV2();
        market.upgradeToAndCall(address(v2Impl), abi.encodeWithSignature("initializeV2()"));

        PredictionMarketV2(address(market)).setFeeBps(50);

        // Create market with new fee
        uint256 marketId2 =
            PredictionMarketV2(address(market)).createMarket("Q2?", address(oracle), resTime, 100_000 ether);
        assertGt(marketId2, marketId);
    }
}
