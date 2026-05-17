// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "src/tokens/OutcomeToken.sol";
import "src/vault/FeeVault.sol";
import "src/core/PredictionMarket.sol";

contract DeployScript is Script {
    function run() external returns (address) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        require(deployerKey != 0, "PRIVATE_KEY env required");
        address deployer = vm.addr(deployerKey);

        address usdc = vm.envAddress("USDC");
        require(usdc != address(0), "USDC env required");

        address oracleAdapter = vm.envAddress("ORACLE_ADAPTER");
        require(oracleAdapter != address(0), "ORACLE_ADAPTER env required");

        vm.startBroadcast(deployerKey);

        OutcomeToken outcomeToken = new OutcomeToken(deployer, "");
        FeeVault feeVault = new FeeVault(usdc, deployer);

        PredictionMarket impl = new PredictionMarket();

        bytes memory initData = abi.encodeWithSelector(
            PredictionMarket.initialize.selector,
            usdc,
            address(outcomeToken),
            address(feeVault),
            oracleAdapter,
            deployer
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Grant roles: allow proxy to mint/burn outcome tokens and deposit fees
        feeVault.grantRole(feeVault.DEPOSITOR_ROLE(), address(proxy));
        outcomeToken.grantRole(outcomeToken.MARKET_ROLE(), address(proxy));

        console.log("OutcomeToken:", address(outcomeToken));
        console.log("FeeVault:", address(feeVault));
        console.log("PredictionMarket proxy:", address(proxy));

        vm.stopBroadcast();

        return address(proxy);
    }
}
