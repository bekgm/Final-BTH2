// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "src/tokens/OutcomeToken.sol";
import "src/tokens/GovernanceToken.sol";
import "src/vault/FeeVault.sol";
import "src/oracle/OracleAdapter.sol";
import "src/oracle/MockAggregator.sol";
import "src/core/PredictionMarket.sol";
import "src/governance/GovernorTimelock.sol";
import "src/governance/PredictionGovernor.sol";

/// @title DeployScript
/// @notice Full protocol deployment including market contracts, oracle, and governance
/// @dev Governance parameters:
///      - Voting Delay: 1 day (86400 seconds)
///      - Voting Period: 1 week (604800 seconds)
///      - Quorum: 4% of total supply
///      - Proposal Threshold: 1% of total supply
///      - Timelock Delay: 2 days (172800 seconds)
contract DeployScript is Script {
    struct Deployment {
        address mockAggregator;
        address oracleAdapter;
        address outcomeToken;
        address feeVault;
        address predictionMarket;
        address governanceToken;
        address timelock;
        address governor;
    }

    function run() external returns (Deployment memory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        require(deployerKey != 0, "PRIVATE_KEY env required");
        address deployer = vm.addr(deployerKey);

        address usdc = vm.envAddress("USDC");
        require(usdc != address(0), "USDC env required");

        Deployment memory deployed;

        vm.startBroadcast(deployerKey);

        // ==========================================
        // 1. Deploy Oracle Infrastructure
        // ==========================================
        MockAggregator mockFeed = new MockAggregator(200000000000, 8); // $2000 with 8 decimals
        deployed.mockAggregator = address(mockFeed);
        console.log("1. MockAggregator:", deployed.mockAggregator);

        OracleAdapter oracle = new OracleAdapter(deployer);
        deployed.oracleAdapter = address(oracle);
        console.log("2. OracleAdapter:", deployed.oracleAdapter);

        // ==========================================
        // 2. Deploy Market Infrastructure
        // ==========================================
        OutcomeToken outcomeToken = new OutcomeToken(deployer, "");
        deployed.outcomeToken = address(outcomeToken);
        console.log("3. OutcomeToken:", deployed.outcomeToken);

        FeeVault feeVault = new FeeVault(usdc, deployer);
        deployed.feeVault = address(feeVault);
        console.log("4. FeeVault:", deployed.feeVault);

        PredictionMarket impl = new PredictionMarket();
        console.log("5. PredictionMarket impl:", address(impl));

        bytes memory initData = abi.encodeWithSelector(
            PredictionMarket.initialize.selector,
            usdc,
            address(outcomeToken),
            address(feeVault),
            address(oracle),
            deployer // Will transfer to timelock after governance setup
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        deployed.predictionMarket = address(proxy);
        console.log("6. PredictionMarket proxy:", deployed.predictionMarket);

        // Grant roles: allow proxy to mint/burn outcome tokens and deposit fees
        feeVault.grantRole(feeVault.DEPOSITOR_ROLE(), address(proxy));
        outcomeToken.grantRole(outcomeToken.MARKET_ROLE(), address(proxy));

        // ==========================================
        // 3. Deploy Governance Token (PGOV)
        // ==========================================
        GovernanceToken governanceToken = new GovernanceToken(deployer);
        deployed.governanceToken = address(governanceToken);
        console.log("7. GovernanceToken (PGOV):", deployed.governanceToken);

        // Mint initial supply (10% of max = 10M PGOV)
        uint256 initialSupply = 10_000_000 * 1e18;
        governanceToken.mint(deployer, initialSupply);

        // ==========================================
        // 4. Deploy Timelock
        // ==========================================
        uint256 timelockDelay = 2 days;
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);

        GovernorTimelock timelock = new GovernorTimelock(timelockDelay, proposers, executors, deployer);
        deployed.timelock = address(timelock);
        console.log("8. GovernorTimelock:", deployed.timelock);

        // ==========================================
        // 5. Deploy Governor with Spec Parameters
        // ==========================================
        // Spec: voting delay 1 day, voting period 1 week, quorum 4%, proposal threshold 1%
        uint48 votingDelay = 1 days;          // 86400 seconds
        uint32 votingPeriod = 7 days;          // 604800 seconds
        uint256 quorumNumerator = 4;          // 4%
        uint256 proposalThreshold = 1_000_000 * 1e18; // 1% of 100M max supply

        PredictionGovernor governor = new PredictionGovernor(
            governanceToken,
            timelock,
            votingDelay,
            votingPeriod,
            proposalThreshold,
            quorumNumerator
        );
        deployed.governor = address(governor);
        console.log("9. PredictionGovernor:", deployed.governor);

        // ==========================================
        // 6. Configure Governance Roles
        // ==========================================
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0)); // Anyone can execute
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // ==========================================
        // 7. Transfer Protocol Ownership to Timelock
        // ==========================================
        // PredictionMarket roles
        PredictionMarket(address(proxy)).grantRole(
            PredictionMarket(address(proxy)).DEFAULT_ADMIN_ROLE(),
            address(timelock)
        );
        PredictionMarket(address(proxy)).grantRole(
            PredictionMarket(address(proxy)).MARKET_CREATOR_ROLE(),
            address(timelock)
        );
        PredictionMarket(address(proxy)).grantRole(
            PredictionMarket(address(proxy)).UPGRADER_ROLE(),
            address(timelock)
        );

        // Other contract admin roles
        feeVault.grantRole(feeVault.DEFAULT_ADMIN_ROLE(), address(timelock));
        outcomeToken.grantRole(outcomeToken.DEFAULT_ADMIN_ROLE(), address(timelock));
        governanceToken.grantRole(governanceToken.DEFAULT_ADMIN_ROLE(), address(timelock));
        governanceToken.grantRole(governanceToken.MINTER_ROLE(), address(timelock));

        vm.stopBroadcast();

        // ==========================================
        // 8. Log Summary
        // ==========================================
        console.log("\n=== Deployment Complete ===");
        console.log("Oracle:");
        console.log("  MockAggregator:", deployed.mockAggregator);
        console.log("  OracleAdapter:", deployed.oracleAdapter);
        console.log("Market Contracts:");
        console.log("  OutcomeToken:", deployed.outcomeToken);
        console.log("  FeeVault:", deployed.feeVault);
        console.log("  PredictionMarket:", deployed.predictionMarket);
        console.log("Governance Contracts:");
        console.log("  GovernanceToken (PGOV):", deployed.governanceToken);
        console.log("  GovernorTimelock:", deployed.timelock);
        console.log("  PredictionGovernor:", deployed.governor);
        console.log("\nGovernance Parameters:");
        console.log("  Voting Delay: 1 day (86400 seconds)");
        console.log("  Voting Period: 1 week (604800 seconds)");
        console.log("  Quorum: 4% of total supply");
        console.log("  Proposal Threshold: 1M PGOV (1% of max)");
        console.log("  Timelock Delay: 2 days (172800 seconds)");
        console.log("\nOwnership: All contracts controlled by Timelock");

        return deployed;
    }
}