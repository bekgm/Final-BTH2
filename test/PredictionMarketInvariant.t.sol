// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PredictionMarket, IPredictionMarket} from "../src/core/PredictionMarket.sol";
import {OutcomeToken} from "../src/tokens/OutcomeToken.sol";
import {FeeVault} from "../src/vault/FeeVault.sol";
import {MockERC20, MockOracleAdapter} from "./Mocks.sol";

contract PredictionMarketHandler is Test {
    PredictionMarket public market;
    MockERC20 public usdc;
    MockOracleAdapter public oracle;
    address[] public actors;
    uint256[] public marketIds;

    constructor(PredictionMarket _market, MockERC20 _usdc, MockOracleAdapter _oracle, address[] memory _actors) {
        market = _market;
        usdc = _usdc;
        oracle = _oracle;
        actors = _actors;
    }

    function getMarketIds() external view returns (uint256[] memory) {
        return marketIds;
    }

    function actionCreateMarket(uint256 initialLiquidity, uint256 delay) public {
        if (marketIds.length >= 3) return;

        uint256 liq = bound(initialLiquidity, 1 ether, 1_000_000 ether);
        uint256 resolution = block.timestamp + bound(delay, 1, 30 days);

        uint256 id = market.createMarket("Q", address(oracle), resolution, liq);
        marketIds.push(id);
    }

    function actionMint(uint256 marketSeed, uint256 amount, uint256 actorSeed) public {
        if (marketIds.length == 0) return;

        uint256 id = marketIds[marketSeed % marketIds.length];
        address actor = actors[actorSeed % actors.length];
        uint256 mintAmount = bound(amount, 1 ether, 50_000 ether);

        vm.startPrank(actor);
        usdc.approve(address(market), mintAmount);
        market.mintOutcomeTokens(id, mintAmount);
        vm.stopPrank();
    }

    function actionAddLiquidity(uint256 marketSeed, uint256 amount, uint256 actorSeed) public {
        if (marketIds.length == 0) return;

        uint256 id = marketIds[marketSeed % marketIds.length];
        address actor = actors[actorSeed % actors.length];
        uint256 liqAmount = bound(amount, 1 ether, 50_000 ether);

        vm.startPrank(actor);
        usdc.approve(address(market), liqAmount);
        market.addLiquidity(id, liqAmount, 1);
        vm.stopPrank();
    }

    function actionRemoveLiquidity(uint256 marketSeed, uint256 bps, uint256 actorSeed) public {
        if (marketIds.length == 0) return;

        uint256 id = marketIds[marketSeed % marketIds.length];
        address actor = actors[actorSeed % actors.length];
        uint256 portionBps = bound(bps, 1, 10_000);

        uint256 shares = market.getLpShares(id, actor);
        if (shares == 0) return;

        uint256 toRemove = (shares * portionBps) / 10_000;
        if (toRemove == 0) return;

        vm.startPrank(actor);
        market.removeLiquidity(id, toRemove, 0);
        vm.stopPrank();
    }
}

contract PredictionMarketInvariantTest is StdInvariant, Test {
    PredictionMarket market;
    OutcomeToken outcome;
    FeeVault vault;
    MockERC20 usdc;
    MockOracleAdapter oracle;
    PredictionMarketHandler handler;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC0C0A);

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

        usdc.mint(alice, 5_000_000 ether);
        usdc.mint(bob, 5_000_000 ether);
        usdc.mint(charlie, 5_000_000 ether);

        address[] memory actors = new address[](3);
        actors[0] = alice;
        actors[1] = bob;
        actors[2] = charlie;

        handler = new PredictionMarketHandler(market, usdc, oracle, actors);
        market.grantRole(market.MARKET_CREATOR_ROLE(), address(handler));

        targetContract(address(handler));
    }

    function invariant_reserves_leq_totalCollateral() public view {
        uint256[] memory ids = handler.getMarketIds();
        for (uint256 i = 0; i < ids.length; i++) {
            IPredictionMarket.Market memory m = market.getMarket(ids[i]);
            assertTrue(m.yesReserve + m.noReserve <= m.totalCollateral);
        }
    }

    function invariant_lpShares_sum_leq_total() public view {
        uint256[] memory ids = handler.getMarketIds();
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 totalShares = market.getTotalLpShares(ids[i]);
            uint256 sumShares = market.getLpShares(ids[i], alice) + market.getLpShares(ids[i], bob)
                + market.getLpShares(ids[i], charlie);
            assertTrue(sumShares <= totalShares);
        }
    }

    function invariant_marketIds_matchStruct() public view {
        uint256[] memory ids = handler.getMarketIds();
        for (uint256 i = 0; i < ids.length; i++) {
            IPredictionMarket.Market memory m = market.getMarket(ids[i]);
            assertEq(m.id, ids[i]);
        }
    }

    function invariant_markets_notResolved() public view {
        uint256[] memory ids = handler.getMarketIds();
        for (uint256 i = 0; i < ids.length; i++) {
            IPredictionMarket.Market memory m = market.getMarket(ids[i]);
            assertTrue(!m.resolved);
        }
    }

    function invariant_totalLpShares_nonzero_implies_collateral() public view {
        uint256[] memory ids = handler.getMarketIds();
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 totalShares = market.getTotalLpShares(ids[i]);
            IPredictionMarket.Market memory m = market.getMarket(ids[i]);
            if (totalShares > 0) {
                assertTrue(m.totalCollateral > 0);
            }
        }
    }
}
