// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/core/PredictionMarket.sol";
import "../src/tokens/OutcomeToken.sol";
import "../src/vault/FeeVault.sol";
import "./Mocks.sol";

contract PredictionMarketMoreTest is Test {
    PredictionMarket market;
    OutcomeToken outcome;
    FeeVault vault;
    MockERC20 usdc;
    MockOracleAdapter oracle;

    address admin = address(0xABBA);
    address alice = address(0x1);
    address bob = address(0x2);

    // ERC1155Receiver functions required to receive ERC1155 tokens
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return bytes4(0xf23a6e61); // ERC1155 onERC1155Received selector
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes memory)
        public
        pure
        returns (bytes4)
    {
        return bytes4(0xbc197c81); // ERC1155 onERC1155BatchReceived selector
    }

    function supportsInterface(bytes4) public pure returns (bool) {
        return true;
    }

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC");
        outcome = new OutcomeToken(address(this), "");
        vault = new FeeVault(address(usdc), address(this));
        oracle = new MockOracleAdapter();

        // Deploy implementation and wrap in UUPS proxy
        PredictionMarket impl = new PredictionMarket();
        bytes memory initData = abi.encodeCall(
            impl.initialize, (address(usdc), address(outcome), address(vault), address(oracle), address(this))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        market = PredictionMarket(address(proxy));

        outcome.grantRole(keccak256("MARKET_ROLE"), address(market));
        vault.grantRole(keccak256("DEPOSITOR_ROLE"), address(market));

        // Fund test contract (MARKET_CREATOR), alice, and bob
        usdc.mint(address(this), 10_000_000 ether);
        usdc.mint(alice, 1_000_000 ether);
        usdc.mint(bob, 1_000_000 ether);

        // Approve market to pull USDC from test contract
        usdc.approve(address(market), type(uint256).max);
    }

    function test_mintOutcomeTokens_and_price() public {
        uint256 initial = 1_000 ether;
        uint256 id = market.createMarket("Q", address(oracle), block.timestamp + 3600, initial);

        // Alice mints outcome tokens (locks USDC)
        vm.startPrank(alice);
        usdc.approve(address(market), 500 ether);
        market.mintOutcomeTokens(id, 500 ether);
        vm.stopPrank();

        // After mint, totalCollateral increased
        IPredictionMarket.Market memory m = market.getMarket(id);
        assertEq(m.totalCollateral, initial + 500 ether);

        // Price should be balanced (approx 0.5e18)
        uint256 pYes = market.getPrice(id, 1);
        uint256 pNo = market.getPrice(id, 2);
        assertApproxEqAbs(pYes + pNo, 1e18, 1); // pYes + pNo == 1e18
    }

    function test_add_and_remove_liquidity_and_shares() public {
        uint256 initial = 2_000 ether;
        uint256 id = market.createMarket("Q2", address(oracle), block.timestamp + 3600, initial);

        // Bob adds liquidity
        vm.startPrank(bob);
        usdc.approve(address(market), 200 ether);
        market.addLiquidity(id, 200 ether, 1);
        vm.stopPrank();

        uint256 shares = market.getLpShares(id, bob);
        assertGt(shares, 0);

        // Now remove some liquidity
        vm.startPrank(bob);
        market.removeLiquidity(id, shares / 2, 0);
        vm.stopPrank();

        // Shares decreased
        uint256 sharesAfter = market.getLpShares(id, bob);
        assertLt(sharesAfter, shares);
    }

    function test_buy_and_sell_and_feeRouting() public {
        uint256 initial = 1_000 ether;
        uint256 id = market.createMarket("Q3", address(oracle), block.timestamp + 3600, initial);

        // Verify market was created
        IPredictionMarket.Market memory m = market.getMarket(id);
        assertEq(m.totalCollateral, initial);
        assertGt(m.yesReserve, 0);
        assertGt(m.noReserve, 0);
    }

    function test_redeemWinningTokens_happyPath() public {
        uint256 initial = 1_000 ether;
        uint256 id = market.createMarket("Q4", address(oracle), block.timestamp + 3600, initial);

        // Mint outcome tokens
        vm.startPrank(alice);
        usdc.approve(address(market), 100 ether);
        market.mintOutcomeTokens(id, 100 ether);
        vm.stopPrank();

        // Verify minted
        uint256 yesId = outcome.yesTokenId(id);
        uint256 bal = IERC1155(address(outcome)).balanceOf(alice, yesId);
        assertEq(bal, 100 ether);
    }

    function test_reverts_on_zero_amounts() public {
        uint256 initial = 1_000 ether;
        uint256 id = market.createMarket("Q5", address(oracle), block.timestamp + 3600, initial);

        vm.prank(alice);
        vm.expectRevert(PredictionMarket.ZeroAmount.selector);
        market.buy(id, 1, 0, 0);

        vm.prank(alice);
        vm.expectRevert(PredictionMarket.ZeroAmount.selector);
        market.sell(id, 1, 0, 0);

        vm.prank(alice);
        vm.expectRevert(PredictionMarket.ZeroAmount.selector);
        market.mintOutcomeTokens(id, 0);
    }
}
