// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "src/oracle/OracleAdapter.sol";

contract DeployOracleAdapterScript is Script {
    function run() external returns (address) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        require(deployerKey != 0, "PRIVATE_KEY env required");

        vm.startBroadcast(deployerKey);

        OracleAdapter adapter = new OracleAdapter(vm.addr(deployerKey));

        console.log("OracleAdapter:", address(adapter));

        vm.stopBroadcast();

        return address(adapter);
    }
}
