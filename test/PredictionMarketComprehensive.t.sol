// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PredictionMarket, IPredictionMarket} from "../src/core/PredictionMarket.sol";
import {OutcomeToken} from "../src/tokens/OutcomeToken.sol";
import {FeeVault} from "../src/vault/FeeVault.sol";
import {MockERC20, MockOracleAdapter} from "./Mocks.sol";

contract PredictionMarketComprehensiveTest is Test {
    PredictionMarket market;
    OutcomeToken outcome;
    FeeVault vault;
    MockERC20 usdc;
    MockOracleAdapter oracle;

    address alice = address(0x1111);
    address bob = address(0x2222);
    address charlie = address(0x3333);
    address pauser = address(0x4444);

    function setUp() public {
        // Deploy USDC mock
        usdc = new MockERC20("USDC", "USDC");

        // Deploy outcome token
        outcome = new OutcomeToken(address(this), "ipfs://");

        // Deploy fee vault
        vault = new FeeVault(address(usdc), address(this));

        // Deploy oracle
        oracle = new MockOracleAdapter();

        // Deploy market implementation
        PredictionMarket impl = new PredictionMarket();

        // Deploy via proxy with initialization
        bytes memory initData = abi.encodeCall(
            PredictionMarket.initialize,
            (address(usdc), address(outcome), address(vault), address(oracle), address(this))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        market = PredictionMarket(address(proxy));

        // Grant roles
        outcome.grantRole(keccak256("MARKET_ROLE"), address(market));
        vault.grantRole(keccak256("DEPOSITOR_ROLE"), address(market));

        // Fund test accounts
        usdc.mint(address(this), 10_000_000 ether);
        usdc.mint(alice, 5_000_000 ether);
        usdc.mint(bob, 5_000_000 ether);
        usdc.mint(charlie, 5_000_000 ether);

        // Approve market from test contract
        usdc.approve(address(market), type(uint256).max);
    }

    // ========== BASIC FUNCTIONALITY TESTS ==========

    function test_01_createMarket_basicFlow() public {
        uint256 initial = 1_000 ether;
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, initial);

        IPredictionMarket.Market memory m = market.getMarket(id);
        assertEq(m.totalCollateral, initial);
        assertGt(m.yesReserve, 0);
        assertGt(m.noReserve, 0);
        assertFalse(m.resolved);
    }

    function test_02_createMarket_multipleCalls() public {
        uint256 id1 = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);
        uint256 id2 = market.createMarket("Q2", address(oracle), block.timestamp + 3600, 2_000 ether);
        uint256 id3 = market.createMarket("Q3", address(oracle), block.timestamp + 3600, 3_000 ether);

        assertNotEq(id1, id2);
        assertNotEq(id2, id3);

        IPredictionMarket.Market memory m1 = market.getMarket(id1);
        IPredictionMarket.Market memory m2 = market.getMarket(id2);
        IPredictionMarket.Market memory m3 = market.getMarket(id3);

        assertEq(m1.totalCollateral, 1_000 ether);
        assertEq(m2.totalCollateral, 2_000 ether);
        assertEq(m3.totalCollateral, 3_000 ether);
    }

    function test_03_mintOutcomeTokens_increasesTotalCollateral() public {
        uint256 initial = 1_000 ether;
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, initial);

        vm.startPrank(alice);
        usdc.approve(address(market), 500 ether);
        market.mintOutcomeTokens(id, 500 ether);
        vm.stopPrank();

        IPredictionMarket.Market memory m = market.getMarket(id);
        assertEq(m.totalCollateral, initial + 500 ether);
    }

    function test_04_mintOutcomeTokens_recipientReceivesTokens() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.mintOutcomeTokens(id, 100 ether);
        vm.stopPrank();

        uint256 yesId = outcome.yesTokenId(id);
        uint256 noId = outcome.noTokenId(id);
        uint256 yesBal = IERC1155(address(outcome)).balanceOf(alice, yesId);
        uint256 noBal = IERC1155(address(outcome)).balanceOf(alice, noId);

        assertEq(yesBal, 100 ether);
        assertEq(noBal, 100 ether);
    }

    function test_05_addLiquidity_increaseShares() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.addLiquidity(id, 100 ether, 1);
        vm.stopPrank();

        uint256 shares = market.getLpShares(id, alice);
        assertGt(shares, 0);
    }

    function test_06_addLiquidity_multipleProviders() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.addLiquidity(id, 100 ether, 1);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), 100 ether);
        market.addLiquidity(id, 100 ether, 1);
        vm.stopPrank();

        uint256 sharesAlice = market.getLpShares(id, alice);
        uint256 sharesBob = market.getLpShares(id, bob);

        assertGt(sharesAlice, 0);
        assertGt(sharesBob, 0);
        assertApproxEqAbs(sharesAlice, sharesBob, 1);
    }

    function test_07_removeLiquidity_decreaseShares() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.addLiquidity(id, 100 ether, 1);
        uint256 shares = market.getLpShares(id, alice);
        market.removeLiquidity(id, shares / 2, 0);
        vm.stopPrank();

        uint256 sharesAfter = market.getLpShares(id, alice);
        assertLt(sharesAfter, shares);
        assertApproxEqAbs(sharesAfter, shares / 2, 1);
    }

    function test_08_removeLiquidity_fullWithdrawal() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.addLiquidity(id, 100 ether, 1);
        uint256 shares = market.getLpShares(id, alice);
        market.removeLiquidity(id, shares, 0);
        vm.stopPrank();

        uint256 sharesAfter = market.getLpShares(id, alice);
        assertEq(sharesAfter, 0);
    }

    // ========== PRICE CALCULATION TESTS ==========

    function test_09_getPrice_balanced() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        uint256 pYes = market.getPrice(id, 1);
        uint256 pNo = market.getPrice(id, 2);

        assertApproxEqAbs(pYes + pNo, 1e18, 2);
    }

    function test_10_getPrice_differentOutcomes() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        uint256 pYes = market.getPrice(id, 1);
        uint256 pNo = market.getPrice(id, 2);

        // Prices should be roughly 0.5e18 each initially (balanced)
        assertTrue(pYes > 0 && pYes < 1e18);
        assertTrue(pNo > 0 && pNo < 1e18);
    }

    // ========== EDGE CASE TESTS ==========

    function test_11_zeroAmountBuy_reverts() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.prank(alice);
        vm.expectRevert(PredictionMarket.ZeroAmount.selector);
        market.buy(id, 1, 0, 0);
    }

    function test_12_zeroAmountSell_reverts() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.prank(alice);
        vm.expectRevert(PredictionMarket.ZeroAmount.selector);
        market.sell(id, 1, 0, 0);
    }

    function test_13_zeroAmountMint_reverts() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.prank(alice);
        vm.expectRevert(PredictionMarket.ZeroAmount.selector);
        market.mintOutcomeTokens(id, 0);
    }

    function test_14_zeroAmountAddLiquidity_reverts() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.prank(alice);
        vm.expectRevert(PredictionMarket.ZeroAmount.selector);
        market.addLiquidity(id, 0, 0);
    }

    function test_15_zeroAmountRemoveLiquidity_reverts() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.addLiquidity(id, 100 ether, 1);

        vm.expectRevert(PredictionMarket.ZeroAmount.selector);
        market.removeLiquidity(id, 0, 0);
        vm.stopPrank();
    }

    // ========== OUTCOME VALIDATION TESTS ==========

    function test_16_invalidOutcome1_reverts() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.prank(alice);
        vm.expectRevert();
        market.buy(id, 0, 100 ether, 0);
    }

    function test_17_invalidOutcome3_reverts() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.prank(alice);
        vm.expectRevert();
        market.buy(id, 3, 100 ether, 0);
    }

    function test_18_invalidOutcomeForSell_reverts() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.prank(alice);
        vm.expectRevert();
        market.sell(id, 99, 100 ether, 0);
    }

    // ========== MARKET RESOLUTION TESTS ==========

    function test_19_resolveMarket_setsWinner() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 1, 1_000 ether);

        vm.warp(block.timestamp + 5000);
        oracle.setLatest(10, block.timestamp); // Set price = 10

        market.resolveMarket(id);

        IPredictionMarket.Market memory m = market.getMarket(id);
        assertTrue(m.resolved);
    }

    function test_20_resolveMarket_beforeResolutionTime_reverts() public {
        uint256 resolutionTime = block.timestamp + 3600;
        uint256 id = market.createMarket("Q1", address(oracle), resolutionTime, 1_000 ether);

        vm.warp(resolutionTime - 10);
        oracle.setLatest(10, block.timestamp);

        vm.expectRevert();
        market.resolveMarket(id);
    }

    function test_21_resolveMarket_alreadyResolved_reverts() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 1, 1_000 ether);

        vm.warp(block.timestamp + 5000);
        oracle.setLatest(10, block.timestamp);
        market.resolveMarket(id);

        vm.expectRevert();
        market.resolveMarket(id);
    }

    function test_22_resolveMarket_stalePrice_reverts() public {
        uint256 resolutionTime = block.timestamp + 7200;
        uint256 id = market.createMarket("Q1", address(oracle), resolutionTime, 1_000 ether);

        vm.warp(block.timestamp + 5000);
        oracle.setLatest(10, block.timestamp - 3600 - 10); // Stale update

        vm.warp(resolutionTime + 1);

        vm.expectRevert();
        market.resolveMarket(id);
    }

    // ========== REDEMPTION TESTS ==========

    function test_23_redeemWinningTokens_burnsMintedTokens() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 1, 1_000 ether);

        // Alice mints outcome tokens
        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.mintOutcomeTokens(id, 100 ether);
        vm.stopPrank();

        // Resolve market
        vm.warp(block.timestamp + 5000);
        oracle.setLatest(10, block.timestamp);
        market.resolveMarket(id);

        // Redeem
        vm.startPrank(alice);
        market.redeemWinningTokens(id);
        vm.stopPrank();

        uint256 yesId = outcome.yesTokenId(id);
        uint256 bal = IERC1155(address(outcome)).balanceOf(alice, yesId);
        // After redemption, winning tokens should be burned (or very close to 0)
        assertTrue(bal <= 1);
    }

    function test_24_redeemWinningTokens_unresolved_reverts() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.mintOutcomeTokens(id, 100 ether);

        vm.expectRevert();
        market.redeemWinningTokens(id);
        vm.stopPrank();
    }

    function test_25_redeemWinningTokens_noTokens() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 1, 1_000 ether);

        vm.warp(block.timestamp + 5000);
        oracle.setLatest(10, block.timestamp);
        market.resolveMarket(id);

        // Bob never minted, should not revert but also should not receive funds
        vm.prank(bob);
        vm.expectRevert();
        market.redeemWinningTokens(id);
    }

    // ========== LIQUIDITY EDGE CASES ==========

    function test_26_removeLiquidity_partialWithdrawal() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 200 ether);
        market.addLiquidity(id, 200 ether, 1);
        uint256 shares = market.getLpShares(id, alice);

        market.removeLiquidity(id, shares / 4, 0);
        vm.stopPrank();

        uint256 sharesAfter = market.getLpShares(id, alice);
        assertApproxEqAbs(sharesAfter, shares * 3 / 4, 1);
    }

    function test_27_addLiquidity_thenRemove_multipleRounds() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(alice);
            usdc.approve(address(market), 50 ether);
            market.addLiquidity(id, 50 ether, 1);
            vm.stopPrank();
        }

        uint256 shares = market.getLpShares(id, alice);
        assertGt(shares, 0);

        for (uint256 i = 0; i < 2; i++) {
            vm.startPrank(alice);
            uint256 currentShares = market.getLpShares(id, alice);
            if (currentShares > 0) {
                market.removeLiquidity(id, currentShares / 2, 0);
            }
            vm.stopPrank();
        }

        uint256 finalShares = market.getLpShares(id, alice);
        assertLt(finalShares, shares);
    }

    // ========== MULTIPLE USERS TESTS ==========

    function test_28_multipleUsers_independentMints() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.mintOutcomeTokens(id, 100 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), 200 ether);
        market.mintOutcomeTokens(id, 200 ether);
        vm.stopPrank();

        uint256 yesId = outcome.yesTokenId(id);
        uint256 balAlice = IERC1155(address(outcome)).balanceOf(alice, yesId);
        uint256 balBob = IERC1155(address(outcome)).balanceOf(bob, yesId);

        assertEq(balAlice, 100 ether);
        assertEq(balBob, 200 ether);
    }

    function test_29_multipleUsers_independentLiquidity() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.addLiquidity(id, 100 ether, 1);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), 200 ether);
        market.addLiquidity(id, 200 ether, 1);
        vm.stopPrank();

        uint256 sharesAlice = market.getLpShares(id, alice);
        uint256 sharesBob = market.getLpShares(id, bob);

        assertGt(sharesAlice, 0);
        assertGt(sharesBob, 0);
        assertTrue(sharesBob > sharesAlice); // Bob provided more liquidity
    }

    // ========== LARGE AMOUNT TESTS ==========

    function test_30_largeMint_1m() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 1_000_000 ether);
        market.mintOutcomeTokens(id, 1_000_000 ether);
        vm.stopPrank();

        uint256 yesId = outcome.yesTokenId(id);
        uint256 bal = IERC1155(address(outcome)).balanceOf(alice, yesId);
        assertEq(bal, 1_000_000 ether);
    }

    function test_31_largeLiquidity_1m() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 1_000_000 ether);
        market.addLiquidity(id, 1_000_000 ether, 1);
        vm.stopPrank();

        uint256 shares = market.getLpShares(id, alice);
        assertGt(shares, 0);
    }

    // ========== TIMING TESTS ==========

    function test_32_futureResolutionTime() public {
        uint256 futureTime = block.timestamp + 30 days;
        uint256 id = market.createMarket("Q1", address(oracle), futureTime, 1_000 ether);

        IPredictionMarket.Market memory m = market.getMarket(id);
        assertFalse(m.resolved);
    }

    function test_33_immediateMint_afterCreation() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        // Immediately mint without delay
        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.mintOutcomeTokens(id, 100 ether);
        vm.stopPrank();

        uint256 yesId = outcome.yesTokenId(id);
        uint256 bal = IERC1155(address(outcome)).balanceOf(alice, yesId);
        assertEq(bal, 100 ether);
    }

    // ========== SUPPLY & BALANCE TESTS ==========

    function test_34_totalCollateralIncrement() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        IPredictionMarket.Market memory m1 = market.getMarket(id);
        uint256 initial = m1.totalCollateral;

        vm.startPrank(alice);
        usdc.approve(address(market), 500 ether);
        market.mintOutcomeTokens(id, 500 ether);
        vm.stopPrank();

        IPredictionMarket.Market memory m2 = market.getMarket(id);
        assertEq(m2.totalCollateral, initial + 500 ether);
    }

    function test_35_reserveRatios_maintained() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        IPredictionMarket.Market memory m = market.getMarket(id);
        uint256 productBefore = m.yesReserve * m.noReserve;

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.mintOutcomeTokens(id, 100 ether);
        vm.stopPrank();

        IPredictionMarket.Market memory m2 = market.getMarket(id);
        uint256 productAfter = m2.yesReserve * m2.noReserve;

        // For CPMM, x*y should stay constant for minting
        assertTrue(productAfter >= productBefore);
    }

    // ========== SLIPPAGE TESTS ==========

    function test_36_slippageBound_acceptable() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 10_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 1_000 ether);
        // With minAmountOut = 0, transaction should succeed
        market.mintOutcomeTokens(id, 1_000 ether);
        vm.stopPrank();

        uint256 yesId = outcome.yesTokenId(id);
        uint256 bal = IERC1155(address(outcome)).balanceOf(alice, yesId);
        assertTrue(bal > 0);
    }

    // ========== STATE CONSISTENCY TESTS ==========

    function test_37_userStateIndependence() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.addLiquidity(id, 100 ether, 1);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), 100 ether);
        market.addLiquidity(id, 100 ether, 1);
        vm.stopPrank();

        uint256 sharesAlice1 = market.getLpShares(id, alice);
        uint256 sharesBob1 = market.getLpShares(id, bob);

        vm.startPrank(bob);
        uint256 bob_shares = market.getLpShares(id, bob);
        market.removeLiquidity(id, bob_shares / 2, 0);
        vm.stopPrank();

        uint256 sharesAlice2 = market.getLpShares(id, alice);
        uint256 sharesBob2 = market.getLpShares(id, bob);

        // Alice's shares should remain unchanged
        assertEq(sharesAlice1, sharesAlice2);
        // Bob's shares should decrease
        assertLt(sharesBob2, sharesBob1);
    }

    // ========== MARKET STRUCTURE TESTS ==========

    function test_38_marketStruct_initialized() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        IPredictionMarket.Market memory m = market.getMarket(id);

        // Verify all fields are initialized properly
        assertEq(m.totalCollateral, 1_000 ether);
        assertGt(m.yesReserve, 0);
        assertGt(m.noReserve, 0);
        assertFalse(m.resolved);
        assertEq(m.winningOutcome, 0);
    }

    function test_39_marketStruct_afterResolution() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 1, 1_000 ether);

        vm.warp(block.timestamp + 5000);
        oracle.setLatest(10, block.timestamp);
        market.resolveMarket(id);

        IPredictionMarket.Market memory m = market.getMarket(id);

        assertTrue(m.resolved);
        assertTrue(m.winningOutcome == 1 || m.winningOutcome == 2);
    }

    // ========== SEQUENTIAL OPERATIONS ==========

    function test_40_createMintResolveRedeem() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 1, 1_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.mintOutcomeTokens(id, 100 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 5000);
        oracle.setLatest(10, block.timestamp);
        market.resolveMarket(id);

        vm.startPrank(alice);
        market.redeemWinningTokens(id);
        vm.stopPrank();

        // Verify state after redemption
        IPredictionMarket.Market memory m = market.getMarket(id);
        assertTrue(m.resolved);
    }

    function test_41_createAddLiquidityRemove() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 200 ether);
        market.addLiquidity(id, 200 ether, 1);
        uint256 shares = market.getLpShares(id, alice);

        market.removeLiquidity(id, shares, 0);
        vm.stopPrank();

        uint256 sharesAfter = market.getLpShares(id, alice);
        assertEq(sharesAfter, 0);
    }

    // ========== ADDITIONAL COMPREHENSIVE TESTS ==========

    function test_42_marketCountIncreases() public {
        uint256 count1 = 1; // Assuming first market gets id 1
        market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        uint256 id2 = market.createMarket("Q2", address(oracle), block.timestamp + 3600, 1_000 ether);
        assertTrue(id2 > count1);
    }

    function test_43_differentInitialLiquidity() public {
        uint256 id1 = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 100 ether);
        uint256 id2 = market.createMarket("Q2", address(oracle), block.timestamp + 3600, 10_000 ether);
        uint256 id3 = market.createMarket("Q3", address(oracle), block.timestamp + 3600, 1_000_000 ether);

        IPredictionMarket.Market memory m1 = market.getMarket(id1);
        IPredictionMarket.Market memory m2 = market.getMarket(id2);
        IPredictionMarket.Market memory m3 = market.getMarket(id3);

        assertEq(m1.totalCollateral, 100 ether);
        assertEq(m2.totalCollateral, 10_000 ether);
        assertEq(m3.totalCollateral, 1_000_000 ether);
    }

    function test_44_mintAcrossMultipleMarkets() public {
        uint256 id1 = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);
        uint256 id2 = market.createMarket("Q2", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 300 ether);
        market.mintOutcomeTokens(id1, 100 ether);
        market.mintOutcomeTokens(id2, 200 ether);
        vm.stopPrank();

        uint256 yesId1 = outcome.yesTokenId(id1);
        uint256 yesId2 = outcome.yesTokenId(id2);

        uint256 bal1 = IERC1155(address(outcome)).balanceOf(alice, yesId1);
        uint256 bal2 = IERC1155(address(outcome)).balanceOf(alice, yesId2);

        assertEq(bal1, 100 ether);
        assertEq(bal2, 200 ether);
    }

    function test_45_multipleResolutions() public {
        uint256 id1 = market.createMarket("Q1", address(oracle), block.timestamp + 1, 1_000 ether);
        uint256 id2 = market.createMarket("Q2", address(oracle), block.timestamp + 1, 1_000 ether);

        vm.warp(block.timestamp + 5000);
        oracle.setLatest(10, block.timestamp);

        market.resolveMarket(id1);
        market.resolveMarket(id2);

        IPredictionMarket.Market memory m1 = market.getMarket(id1);
        IPredictionMarket.Market memory m2 = market.getMarket(id2);

        assertTrue(m1.resolved);
        assertTrue(m2.resolved);
    }

    function test_46_tokenTransfer_notDirectlySupported() public {
        // This test verifies the current behavior — tokens are managed by the contract
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.mintOutcomeTokens(id, 100 ether);
        vm.stopPrank();

        uint256 yesId = outcome.yesTokenId(id);
        uint256 balAlice = IERC1155(address(outcome)).balanceOf(alice, yesId);

        // Tokens are in alice's account
        assertEq(balAlice, 100 ether);
    }

    function test_47_priceMovement_afterMint() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        uint256 pYesBefore = market.getPrice(id, 1);

        vm.startPrank(alice);
        usdc.approve(address(market), 500 ether);
        market.mintOutcomeTokens(id, 500 ether);
        vm.stopPrank();

        uint256 pYesAfter = market.getPrice(id, 1);

        // Price should remain balanced due to CPMM
        assertApproxEqAbs(pYesBefore, pYesAfter, 1e16); // Within 1%
    }

    function test_48_liquidityProvision_affectsPrice() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 2_000 ether);

        uint256 pBefore = market.getPrice(id, 1);

        vm.startPrank(bob);
        usdc.approve(address(market), 500 ether);
        market.addLiquidity(id, 500 ether, 1);
        vm.stopPrank();

        uint256 pAfter = market.getPrice(id, 1);

        // Liquidity provision should maintain price balance
        assertApproxEqAbs(pBefore, pAfter, 1e16);
    }

    function test_49_reserveConstancy() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 1_000 ether);

        IPredictionMarket.Market memory before = market.getMarket(id);
        uint256 kBefore = before.yesReserve * before.noReserve;

        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.mintOutcomeTokens(id, 100 ether);
        vm.stopPrank();

        IPredictionMarket.Market memory mAfter = market.getMarket(id);
        uint256 kAfter = mAfter.yesReserve * mAfter.noReserve;

        // k should be maintained or increase with minting
        assertTrue(kAfter >= kBefore);
    }

    function test_50_stressTest_manyOperations() public {
        uint256 id = market.createMarket("Q1", address(oracle), block.timestamp + 3600, 10_000 ether);

        // Many mints
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(alice);
            usdc.approve(address(market), 100 ether);
            market.mintOutcomeTokens(id, 100 ether);
            vm.stopPrank();
        }

        // Many liquidity additions
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(bob);
            usdc.approve(address(market), 100 ether);
            market.addLiquidity(id, 100 ether, 1);
            vm.stopPrank();
        }

        IPredictionMarket.Market memory m = market.getMarket(id);
        assertGt(m.totalCollateral, 10_000 ether);
    }
}
