// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PredictionMarket} from "../src/core/PredictionMarket.sol";
import {OutcomeToken} from "../src/tokens/OutcomeToken.sol";
import {FeeVault} from "../src/vault/FeeVault.sol";
import {MockERC20, MockOracleAdapter} from "./Mocks.sol";

contract PredictionMarketForkTest is Test {
    function _maybeFork() internal returns (bool) {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            return false;
        }
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);
        return true;
    }

    function _deployOnFork() internal returns (PredictionMarket market, MockERC20 usdc, MockOracleAdapter oracle) {
        usdc = new MockERC20("USDC", "USDC");
        OutcomeToken outcome = new OutcomeToken(address(this), "ipfs://");
        FeeVault vault = new FeeVault(address(usdc), address(this));
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
    }

    function testFork_createMarket_and_mint() public {
        if (!_maybeFork()) return;

        (PredictionMarket market, MockERC20 usdc,) = _deployOnFork();
        usdc.mint(address(this), 1_000_000 ether);
        usdc.approve(address(market), type(uint256).max);

        uint256 id = market.createMarket("Q", address(0x1234), block.timestamp + 3600, 1_000 ether);
        market.mintOutcomeTokens(id, 100 ether);
    }

    function testFork_add_and_remove_liquidity() public {
        if (!_maybeFork()) return;

        (PredictionMarket market, MockERC20 usdc,) = _deployOnFork();
        usdc.mint(address(this), 1_000_000 ether);
        usdc.approve(address(market), type(uint256).max);

        uint256 id = market.createMarket("Q", address(0x1234), block.timestamp + 3600, 2_000 ether);
        market.addLiquidity(id, 500 ether, 1);
        uint256 shares = market.getLpShares(id, address(this));
        market.removeLiquidity(id, shares / 2, 0);
    }

    function testFork_resolve_and_redeem() public {
        if (!_maybeFork()) return;

        (PredictionMarket market, MockERC20 usdc, MockOracleAdapter oracle) = _deployOnFork();
        usdc.mint(address(this), 1_000_000 ether);
        usdc.approve(address(market), type(uint256).max);

        uint256 id = market.createMarket("Q", address(0x1234), block.timestamp + 1, 1_000 ether);
        market.mintOutcomeTokens(id, 100 ether);

        vm.warp(block.timestamp + 2 hours);
        oracle.setLatest(10, block.timestamp);
        market.resolveMarket(id);
        market.redeemWinningTokens(id);
    }
}
