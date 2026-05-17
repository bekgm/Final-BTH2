// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {AMM} from "../src/core/AMM.sol";
import {PredictionMarket} from "../src/core/PredictionMarket.sol";
import {PredictionMarketV2} from "../src/core/PredictionMarketV2.sol";
import {MarketFactory} from "../src/factory/MarketFactory.sol";
import {PredictionGovernor} from "../src/governance/PredictionGovernor.sol";
import {OracleAdapter} from "../src/oracle/OracleAdapter.sol";
import {MockAggregator} from "../src/oracle/MockAggregator.sol";
import {GovernanceToken} from "../src/tokens/GovernanceToken.sol";
import {OutcomeToken} from "../src/tokens/OutcomeToken.sol";
import {FeeVault} from "../src/vault/FeeVault.sol";
import {AccessControlFixed} from "../src/vulnerabilities/AccessControlFixed.sol";
import {AccessControlVulnerable} from "../src/vulnerabilities/AccessControlVulnerable.sol";
import {ReentrancyFixed} from "../src/vulnerabilities/ReentrancyFixed.sol";
import {ReentrancyVulnerable} from "../src/vulnerabilities/ReentrancyVulnerable.sol";
import {IOracleAdapter} from "../src/interfaces/IOracleAdapter.sol";
import {MockERC20, MockOracleAdapter} from "./Mocks.sol";

contract AMMHarness {
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256, uint256)
    {
        return AMM.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return AMM.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function spotPrice(uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return AMM.spotPrice(reserveIn, reserveOut);
    }
}

contract AMMCoverageTest is Test {
    AMMHarness harness;

    function setUp() public {
        harness = new AMMHarness();
    }

    function test_amm_getAmountOut_basic() public {
        (uint256 out, uint256 fee) = harness.getAmountOut(1_000, 10_000, 10_000);
        assertGt(out, 0);
        assertEq(fee, 3);
    }

    function test_amm_getAmountOut_zeroReserve_reverts() public {
        vm.expectRevert();
        harness.getAmountOut(1, 0, 1);
    }

    function test_amm_getAmountIn_basic() public {
        uint256 amountIn = harness.getAmountIn(100, 10_000, 10_000);
        assertGt(amountIn, 100);
    }

    function test_amm_getAmountIn_zeroReserve_reverts() public {
        vm.expectRevert();
        harness.getAmountIn(1, 0, 1);
    }

    function test_amm_getAmountIn_insufficientOutput_reverts() public {
        vm.expectRevert();
        harness.getAmountIn(10_000, 10_000, 10_000);
    }

    function test_amm_checkInvariant_true_false() public {
        assertTrue(AMM.checkInvariant(10, 10, 11, 10));
        assertTrue(!AMM.checkInvariant(10, 10, 9, 9));
    }

    function test_amm_spotPrice_basic_and_zero_revert() public {
        uint256 price = harness.spotPrice(1, 1);
        assertEq(price, 5e17);

        vm.expectRevert();
        harness.spotPrice(0, 1);
    }
}

contract FeeVaultCoverageTest is Test {
    MockERC20 usdc;
    FeeVault vault;

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC");
        vault = new FeeVault(address(usdc), address(this));
        vault.grantRole(vault.DEPOSITOR_ROLE(), address(this));
    }

    function test_feeVault_depositFees_and_previews() public {
        usdc.mint(address(this), 1_000 ether);
        usdc.approve(address(vault), 500 ether);

        vault.depositFees(500 ether);

        assertEq(vault.totalAssets(), 500 ether);
        assertGt(vault.balanceOf(address(this)), 0);

        uint256 shares = vault.previewDeposit(100 ether);
        uint256 assets = vault.previewMint(100 ether);
        uint256 withdrawShares = vault.previewWithdraw(100 ether);
        uint256 redeemAssets = vault.previewRedeem(100 ether);
        assertGt(shares + assets + withdrawShares + redeemAssets, 0);

        assertGt(vault.convertToShares(100 ether), 0);
        assertGt(vault.convertToAssets(100 ether), 0);
    }

    function test_feeVault_depositFees_unauthorized_reverts() public {
        usdc.mint(address(this), 100 ether);
        usdc.approve(address(vault), 100 ether);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        vault.depositFees(10 ether);
    }
}

contract OracleCoverageTest is Test {
    OracleAdapter adapter;
    MockAggregator agg;

    function setUp() public {
        adapter = new OracleAdapter(address(this));
        agg = new MockAggregator(100, 8);
    }

    function test_oracleAdapter_getLatestPrice_and_isStale() public {
        vm.warp(1 days);
        agg.setAnswer(100);
        (int256 price, uint256 updatedAt) = adapter.getLatestPrice(address(agg));
        assertEq(price, 100);
        assertGt(updatedAt, 0);

        bool stale = adapter.isStale(address(agg), 10_000);
        assertTrue(!stale);
    }

    function test_oracleAdapter_invalidPrice_reverts() public {
        agg.setAnswer(0);
        vm.expectRevert();
        adapter.getLatestPrice(address(agg));
    }

    function test_oracleAdapter_stale_reverts() public {
        vm.warp(1 days);
        agg.setAnswer(100);
        agg.setUpdatedAt(block.timestamp - adapter.MAX_STALENESS() - 1);

        vm.expectRevert();
        adapter.getLatestPrice(address(agg));
    }
}

contract MockAggregatorCoverageTest is Test {
    function test_mockAggregator_roundData() public {
        MockAggregator agg = new MockAggregator(123, 8);
        assertEq(agg.decimals(), 8);
        assertEq(agg.description(), "MockAggregator");
        assertEq(agg.version(), 1);

        vm.warp(1 days);
        agg.setAnswer(456);
        agg.setUpdatedAt(block.timestamp - 10);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            agg.latestRoundData();
        assertEq(answer, 456);
        assertEq(roundId, answeredInRound);
        assertEq(startedAt, updatedAt);

        (uint80 r2, int256 a2, uint256 s2, uint256 u2, uint80 ar2) = agg.getRoundData(99);
        assertEq(r2, 99);
        assertEq(a2, 0);
        assertEq(s2, 0);
        assertEq(u2, 0);
        assertEq(ar2, 0);
    }
}

contract GovernanceTokenCoverageTest is Test {
    GovernanceToken token;

    function setUp() public {
        token = new GovernanceToken(address(this));
    }

    function test_governanceToken_mint_and_cap() public {
        token.mint(address(this), token.MAX_SUPPLY());
        assertEq(token.totalSupply(), token.MAX_SUPPLY());

        vm.expectRevert();
        token.mint(address(this), 1);
    }

    function test_governanceToken_clock_and_nonce() public {
        assertEq(token.CLOCK_MODE(), "mode=timestamp");
        assertEq(token.clock(), uint48(block.timestamp));
        assertEq(token.nonces(address(this)), 0);
    }
}

contract PredictionGovernorCoverageTest is Test {
    function test_predictionGovernor_basic_views() public {
        GovernanceToken token = new GovernanceToken(address(this));
        token.mint(address(this), 1_000_000 ether);

        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(this);
        TimelockController timelock = new TimelockController(1, proposers, executors, address(this));

        PredictionGovernor gov = new PredictionGovernor(token, timelock, 1, 10, 0, 4);

        assertEq(gov.votingDelay(), 1);
        assertEq(gov.votingPeriod(), 10);
        assertEq(gov.proposalThreshold(), 0);
    }
}

contract PredictionMarketV2CoverageTest is Test {
    MockERC20 usdc;
    OutcomeToken outcome;
    FeeVault vault;
    MockOracleAdapter oracle;

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC");
        outcome = new OutcomeToken(address(this), "ipfs://");
        vault = new FeeVault(address(usdc), address(this));
        oracle = new MockOracleAdapter();
    }

    function test_predictionMarketV2_upgrade_and_buy() public {
        PredictionMarket implV1 = new PredictionMarket();
        bytes memory initData = abi.encodeCall(
            PredictionMarket.initialize,
            (address(usdc), address(outcome), address(vault), address(oracle), address(this))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), initData);
        PredictionMarket market = PredictionMarket(address(proxy));

        outcome.grantRole(keccak256("MARKET_ROLE"), address(market));
        vault.grantRole(vault.DEPOSITOR_ROLE(), address(market));

        usdc.mint(address(this), 1_000_000 ether);
        usdc.approve(address(market), type(uint256).max);

        uint256 marketId = market.createMarket("Q", address(0x1234), block.timestamp + 3600, 10_000 ether);

        PredictionMarketV2 implV2 = new PredictionMarketV2();
        market.upgradeToAndCall(address(implV2), "");

        PredictionMarketV2 marketV2 = PredictionMarketV2(address(proxy));
        marketV2.initializeV2();
        assertEq(marketV2.version(), 2);

        vm.expectRevert();
        marketV2.setFeeBps(200);
        marketV2.setFeeBps(50);
        assertEq(marketV2.feeBps(), 50);

        address trader = address(0xA11CE);
        usdc.mint(trader, 1000 ether);

        vm.startPrank(trader);
        usdc.approve(address(marketV2), 100 ether);
        uint256 out = marketV2.buy(marketId, 1, 100 ether, 0);
        vm.stopPrank();

        assertGt(out, 0);
        assertGt(marketV2.getMarket(marketId).feesAccrued, 0);
    }
}

contract MarketFactoryCoverageTest is Test {
    MockERC20 usdc;
    OutcomeToken outcome;
    FeeVault vault;
    MockOracleAdapter oracle;

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC");
        outcome = new OutcomeToken(address(this), "ipfs://");
        vault = new FeeVault(address(usdc), address(this));
        oracle = new MockOracleAdapter();
    }

    function test_marketFactory_deploy_and_predict() public {
        MarketFactory factory = new MarketFactory(
            address(this), address(usdc), address(outcome), address(vault), address(oracle), address(this)
        );

        vm.expectRevert();
        factory.deployMarket("Q", address(oracle), block.timestamp + 1, 1 ether, bytes32("salt1"));

        address impl = factory.deployImplementation();
        assertTrue(impl != address(0));

        bytes32 salt = keccak256("salt2");
        address predicted = factory.predictMarketAddress(salt);
        address deployed = factory.deployMarket("Q", address(oracle), block.timestamp + 1, 1 ether, salt);
        assertEq(predicted, deployed);
        assertEq(factory.allMarketsLength(), 1);

        vm.expectRevert();
        factory.deployMarket("Q", address(oracle), block.timestamp + 1, 1 ether, salt);
    }
}

contract VulnerabilityCoverageTest is Test {
    receive() external payable {}

    function test_accessControl_vulnerable_and_fixed() public {
        AccessControlVulnerable vuln = new AccessControlVulnerable();
        vuln.createMarket(1, block.timestamp + 1 days, 10);
        vuln.resolveMarket(1);

        AccessControlFixed fixedMarket = new AccessControlFixed(address(this));
        fixedMarket.createMarket(1, block.timestamp + 1 days, 10);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        fixedMarket.resolveMarket(1);

        vm.warp(block.timestamp + 2 days);
        fixedMarket.resolveMarket(1);
    }

    function test_reentrancy_fixed_and_vulnerable() public {
        ReentrancyVulnerable vuln = new ReentrancyVulnerable();
        vuln.seedBalance{value: 1 ether}(1, address(this), 10);
        vuln.redeemWinningTokens(1);

        ReentrancyFixed fixedMarket = new ReentrancyFixed();
        fixedMarket.seedBalance{value: 1 ether}(1, address(this), 10);
        fixedMarket.redeemWinningTokens(1);
    }
}
