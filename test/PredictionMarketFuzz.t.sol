// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PredictionMarket, IPredictionMarket} from "../src/core/PredictionMarket.sol";
import {OutcomeToken} from "../src/tokens/OutcomeToken.sol";
import {FeeVault} from "../src/vault/FeeVault.sol";
import {MockERC20, MockOracleAdapter} from "./Mocks.sol";
import {AMM} from "../src/core/AMM.sol";

contract PredictionMarketFuzzTest is Test {
    PredictionMarket market;
    OutcomeToken outcome;
    FeeVault vault;
    MockERC20 usdc;
    MockOracleAdapter oracle;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

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

    function _createMarket(uint256 initialLiquidity, uint256 delay) internal returns (uint256) {
        uint256 liq = bound(initialLiquidity, 1 ether, 1_000_000 ether);
        uint256 resolution = block.timestamp + bound(delay, 1, 30 days);
        return market.createMarket("Q", address(oracle), resolution, liq);
    }

    function testFuzz_createMarket_validInputs(uint96 initialLiquidity, uint32 delay) public {
        uint256 id = _createMarket(initialLiquidity, delay);
        IPredictionMarket.Market memory m = market.getMarket(id);
        assertGt(m.totalCollateral, 0);
        assertGt(m.yesReserve, 0);
        assertGt(m.noReserve, 0);
    }

    function testFuzz_mintOutcomeTokens_increaseCollateral(uint96 amount) public {
        uint256 id = _createMarket(1_000 ether, 1 hours);
        uint256 mintAmount = bound(uint256(amount), 1 ether, 100_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), mintAmount);
        market.mintOutcomeTokens(id, mintAmount);
        vm.stopPrank();

        IPredictionMarket.Market memory m = market.getMarket(id);
        assertGt(m.totalCollateral, 1_000 ether);
    }

    function testFuzz_addLiquidity_increasesShares(uint96 amount) public {
        uint256 id = _createMarket(2_000 ether, 2 hours);
        uint256 liqAmount = bound(uint256(amount), 1 ether, 50_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), liqAmount);
        market.addLiquidity(id, liqAmount, 1);
        vm.stopPrank();

        uint256 shares = market.getLpShares(id, alice);
        assertGt(shares, 0);
    }

    function testFuzz_removeLiquidity_partial(uint96 amount, uint8 portion) public {
        uint256 id = _createMarket(2_000 ether, 2 hours);
        uint256 liqAmount = bound(uint256(amount), 1 ether, 100_000 ether);
        uint256 part = bound(uint256(portion), 2, 10);

        vm.startPrank(alice);
        usdc.approve(address(market), liqAmount);
        market.addLiquidity(id, liqAmount, 1);
        uint256 shares = market.getLpShares(id, alice);
        if (shares > 0) {
            market.removeLiquidity(id, shares / part, 0);
        }
        vm.stopPrank();

        uint256 sharesAfter = market.getLpShares(id, alice);
        assertLt(sharesAfter, shares);
    }

    function testFuzz_getPrice_sumToOne(uint96 amount) public {
        uint256 id = _createMarket(1_000 ether, 1 hours);
        uint256 mintAmount = bound(uint256(amount), 1 ether, 10_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), mintAmount);
        market.mintOutcomeTokens(id, mintAmount);
        vm.stopPrank();

        uint256 pYes = market.getPrice(id, 1);
        uint256 pNo = market.getPrice(id, 2);
        assertApproxEqAbs(pYes + pNo, 1e18, 2);
    }

    function testFuzz_pause_blocks_create(uint96 initialLiquidity) public {
        uint256 liq = bound(uint256(initialLiquidity), 1 ether, 1_000_000 ether);
        market.pause();
        vm.expectRevert();
        market.createMarket("Q", address(oracle), block.timestamp + 1 hours, liq);
    }

    function testFuzz_resolution_stalePrice(uint32 delay) public {
        uint256 id = _createMarket(1_000 ether, delay);

        vm.warp(block.timestamp + 3 hours);
        oracle.setLatest(1, block.timestamp - 3600 - 10);

        vm.expectRevert();
        market.resolveMarket(id);
    }

    function testFuzz_redeem_payoutNonZero(uint96 amount) public {
        uint256 id = _createMarket(1_000 ether, 1 hours);
        uint256 mintAmount = bound(uint256(amount), 1 ether, 10_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), mintAmount);
        market.mintOutcomeTokens(id, mintAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);
        oracle.setLatest(10, block.timestamp);
        market.resolveMarket(id);

        uint256 balBefore = usdc.balanceOf(alice);
        vm.startPrank(alice);
        market.redeemWinningTokens(id);
        vm.stopPrank();

        uint256 balAfter = usdc.balanceOf(alice);
        assertGt(balAfter, balBefore);
    }

    function testFuzz_buy_sell_roundtrip(uint96 amountIn) public {
        uint256 id = _createMarket(10_000 ether, 2 hours);
        uint256 spend = bound(uint256(amountIn), 1 ether, 100 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), spend);
        uint256 out = market.buy(id, 1, spend, 0);
        if (out > 1) {
            market.sell(id, 1, out / 2, 0);
        }
        vm.stopPrank();
    }

    function testFuzz_buy_slippageReverts(uint96 amountIn) public {
        uint256 id = _createMarket(10_000 ether, 2 hours);
        uint256 spend = bound(uint256(amountIn), 1 ether, 100 ether);

        IPredictionMarket.Market memory m = market.getMarket(id);
        (uint256 amountOut,) = AMM.getAmountOut(spend, m.noReserve, m.yesReserve);

        vm.startPrank(alice);
        usdc.approve(address(market), spend);
        vm.expectRevert();
        market.buy(id, 1, spend, amountOut + 1);
        vm.stopPrank();
    }

    function testFuzz_addLiquidity_slippageReverts(uint96 amount) public {
        uint256 id = _createMarket(2_000 ether, 2 hours);
        uint256 liqAmount = bound(uint256(amount), 1 ether, 50_000 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), liqAmount);
        vm.expectRevert();
        market.addLiquidity(id, liqAmount, type(uint256).max);
        vm.stopPrank();
    }

    function testFuzz_sell_invalidOutcomeReverts(uint96 amountIn) public {
        uint256 id = _createMarket(10_000 ether, 2 hours);
        uint256 spend = bound(uint256(amountIn), 1 ether, 100 ether);

        vm.startPrank(alice);
        usdc.approve(address(market), spend);
        market.buy(id, 1, spend, 0);
        vm.expectRevert();
        market.sell(id, 3, 1 ether, 0);
        vm.stopPrank();
    }

    function testFuzz_getPrice_invalidOutcomeReverts(uint8 outcomeId) public {
        uint8 outcomeValue = uint8(bound(uint256(outcomeId), 3, 255));
        uint256 id = _createMarket(1_000 ether, 1 hours);

        vm.expectRevert();
        market.getPrice(id, outcomeValue);
    }
}
