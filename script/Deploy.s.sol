// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "src/tokens/OutcomeToken.sol";
import "src/vault/FeeVault.sol";
import "src/oracle/OracleAdapter.sol";
import "src/oracle/MockAggregator.sol";
import "src/core/PredictionMarket.sol";

contract DeployScript is Script {
    function run() external returns (address proxy) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        require(deployerKey != 0, "PRIVATE_KEY env required");
        address deployer = vm.addr(deployerKey);

        address usdc = vm.envAddress("USDC");
        require(usdc != address(0), "USDC env required");

        vm.startBroadcast(deployerKey);

        // 1. Deploy MockAggregator (testnet: no real Chainlink feed needed)
        // constructor(int256 initialAnswer, uint8 decimals_)
        MockAggregator mockFeed = new MockAggregator(200000000000, 8); // $2000 with 8 decimals
        console.log("MockAggregator:", address(mockFeed));

        // 2. Deploy OracleAdapter
        OracleAdapter oracle = new OracleAdapter(deployer);
        console.log("OracleAdapter:", address(oracle));

        // 3. Deploy OutcomeToken (ERC-1155)
        OutcomeToken outcomeToken = new OutcomeToken(deployer, "");
        console.log("OutcomeToken:", address(outcomeToken));

        // 4. Deploy FeeVault (ERC-4626)
        FeeVault feeVault = new FeeVault(usdc, deployer);
        console.log("FeeVault:", address(feeVault));

        // 5. Deploy PredictionMarket implementation + ERC1967 proxy
        PredictionMarket impl = new PredictionMarket();
        console.log("PredictionMarket impl:", address(impl));

        bytes memory initData = abi.encodeWithSelector(
            PredictionMarket.initialize.selector,
            usdc,
            address(outcomeToken),
            address(feeVault),
            address(oracle),
            deployer
        );

        proxy = address(new ERC1967Proxy(address(impl), initData));
        console.log("PredictionMarket proxy:", proxy);

        // 6. Grant roles
        feeVault.grantRole(feeVault.DEPOSITOR_ROLE(), proxy);
        outcomeToken.grantRole(outcomeToken.MARKET_ROLE(), proxy);

        vm.stopBroadcast();

        console.log("---");
        console.log("Deploy complete. Deployer:", deployer);
        console.log("MockAggregator feed:", address(mockFeed));
        console.log("USDC:", usdc);
    }
}
