// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/core/PredictionMarket.sol";
import "../src/tokens/OutcomeToken.sol";
import "../src/vault/FeeVault.sol";
import "./Mocks.sol";

contract PredictionMarketTest is Test {
    PredictionMarket market;
    OutcomeToken outcome;
    FeeVault vault;
    MockERC20 usdc;
    MockOracleAdapter oracle;

    address admin = address(0xABBA);
    address alice = address(0x1);

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

        // Grant MARKET_ROLE on outcome and DEPOSITOR_ROLE on vault to market
        outcome.grantRole(keccak256("MARKET_ROLE"), address(market));
        vault.grantRole(keccak256("DEPOSITOR_ROLE"), address(market));

        // Fund test contract (MARKET_CREATOR) and alice
        usdc.mint(address(this), 10_000_000 ether);
        usdc.mint(alice, 1_000_000 ether);

        // Approve market to pull USDC from test contract
        usdc.approve(address(market), type(uint256).max);
    }

    function test_createMarket_and_buy() public {
        // create market with initial liquidity 1_000 USDC
        uint256 initial = 1_000 ether;
        uint256 resolution = block.timestamp + 3600;
        uint256 id = market.createMarket("Will X happen?", address(oracle), resolution, initial);

        // Verify market was created
        IPredictionMarket.Market memory m = market.getMarket(id);
        assertEq(m.totalCollateral, initial);
        assertGt(m.yesReserve, 0);
        assertGt(m.noReserve, 0);
    }

    function test_resolveMarket_revertsIfStalePrice() public {
        uint256 initial = 1_000 ether;
        uint256 resolutionTime = block.timestamp + 7200; // Set future time
        uint256 id = market.createMarket("Q", address(oracle), resolutionTime, initial);
        // Warp forward first to avoid underflow
        vm.warp(block.timestamp + 5000);
        // set oracle with stale timestamp
        oracle.setLatest(1, block.timestamp - 3600 - 10);

        // warp to after resolution time
        vm.warp(resolutionTime + 1);

        vm.expectRevert();
        market.resolveMarket(id);
    }
}
