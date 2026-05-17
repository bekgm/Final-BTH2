// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "src/tokens/OutcomeToken.sol";
import "src/vault/FeeVault.sol";
import "src/core/PredictionMarket.sol";
import "test/Mocks.sol";

contract LocalDeployScript is Script {
    function run() external returns (address marketProxy, address usdc, address oracleAdapter) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        require(deployerKey != 0, "PRIVATE_KEY env required");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        MockERC20 mockUsdc = new MockERC20("USDC", "USDC");
        MockOracleAdapter mockOracle = new MockOracleAdapter();

        // Seed the deployer so the local setup can create markets immediately.
        mockUsdc.mint(deployer, 1_000_000 ether);
        mockOracle.setLatest(2e18, block.timestamp);

        OutcomeToken outcomeToken = new OutcomeToken(deployer, "");
        FeeVault feeVault = new FeeVault(address(mockUsdc), deployer);
        PredictionMarket impl = new PredictionMarket();

        bytes memory initData = abi.encodeWithSelector(
            PredictionMarket.initialize.selector,
            address(mockUsdc),
            address(outcomeToken),
            address(feeVault),
            address(mockOracle),
            deployer
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        feeVault.grantRole(feeVault.DEPOSITOR_ROLE(), address(proxy));
        outcomeToken.grantRole(outcomeToken.MARKET_ROLE(), address(proxy));

        console.log("Mock USDC:", address(mockUsdc));
        console.log("Mock Oracle:", address(mockOracle));
        console.log("OutcomeToken:", address(outcomeToken));
        console.log("FeeVault:", address(feeVault));
        console.log("PredictionMarket proxy:", address(proxy));

        vm.stopBroadcast();

        return (address(proxy), address(mockUsdc), address(mockOracle));
    }
}
