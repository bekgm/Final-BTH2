// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "src/tokens/GovernanceToken.sol";
import "src/vault/FeeVault.sol";
import "src/core/PredictionMarket.sol";
import "src/governance/GovernorTimelock.sol";
import "src/governance/PredictionGovernor.sol";
import "src/tokens/OutcomeToken.sol";

/// @title VerifyDeployment
/// @notice Post-deployment verification script for the Prediction Market Protocol
/// @dev Verifies governance parameters, role assignments, and ownership
///      Run with: forge script script/VerifyDeployment.s.sol --rpc-url <URL>
contract VerifyDeployment is Script {
    struct DeploymentConfig {
        address predictionMarket;
        address governanceToken;
        address timelock;
        address governor;
        address feeVault;
        address outcomeToken;
    }

    struct VerificationResult {
        bool passed;
        string check;
        string expected;
        string actual;
    }

    VerificationResult[] public results;

    // Expected governance parameters
    uint256 public constant EXPECTED_VOTING_DELAY = 1 days;
    uint256 public constant EXPECTED_VOTING_PERIOD = 7 days;
    uint256 public constant EXPECTED_QUORUM_NUMERATOR = 4; // 4%
    uint256 public constant EXPECTED_PROPOSAL_THRESHOLD = 1_000_000 * 1e18; // 1% of 100M
    uint256 public constant EXPECTED_TIMELOCK_DELAY = 2 days;

    function run() external {
        // Read addresses from environment
        DeploymentConfig memory config = DeploymentConfig({
            predictionMarket: vm.envAddress("PREDICTION_MARKET"),
            governanceToken: vm.envAddress("GOVERNANCE_TOKEN"),
            timelock: vm.envAddress("TIMELOCK"),
            governor: vm.envAddress("GOVERNOR"),
            feeVault: vm.envAddress("FEE_VAULT"),
            outcomeToken: vm.envAddress("OUTCOME_TOKEN")
        });

        console.log("\n=== Post-Deployment Verification ===\n");

        // ==========================================
        // 1. Verify Governor Parameters
        // ==========================================
        verifyGovernorParameters(config);

        // ==========================================
        // 2. Verify Timelock Configuration
        // ==========================================
        verifyTimelockConfiguration(config);

        // ==========================================
        // 3. Verify Ownership (Roles)
        // ==========================================
        verifyOwnership(config);

        // ==========================================
        // 4. Print Results Summary
        // ==========================================
        printResults();
    }

    function verifyGovernorParameters(DeploymentConfig memory config) internal {
        PredictionGovernor governor = PredictionGovernor(payable(config.governor));
        GovernanceToken token = GovernanceToken(config.governanceToken);

        // Check voting delay
        uint256 votingDelay = governor.votingDelay();
        addResult(
            votingDelay == EXPECTED_VOTING_DELAY,
            "Governor: votingDelay",
            vm.toString(EXPECTED_VOTING_DELAY),
            vm.toString(votingDelay)
        );

        // Check voting period
        uint256 votingPeriod = governor.votingPeriod();
        addResult(
            votingPeriod == EXPECTED_VOTING_PERIOD,
            "Governor: votingPeriod",
            vm.toString(EXPECTED_VOTING_PERIOD),
            vm.toString(votingPeriod)
        );

        // Check quorum
        uint256 currentTimestamp = block.timestamp;
        uint256 quorum = governor.quorum(currentTimestamp);
        uint256 totalSupply = token.totalSupply();
        uint256 expectedQuorum = (totalSupply * EXPECTED_QUORUM_NUMERATOR) / 100;
        addResult(
            quorum == expectedQuorum,
            "Governor: quorum",
            vm.toString(expectedQuorum),
            vm.toString(quorum)
        );

        // Check proposal threshold
        uint256 proposalThreshold = governor.proposalThreshold();
        addResult(
            proposalThreshold == EXPECTED_PROPOSAL_THRESHOLD,
            "Governor: proposalThreshold",
            vm.toString(EXPECTED_PROPOSAL_THRESHOLD),
            vm.toString(proposalThreshold)
        );

        // Check governance token integration
        address tokenAddress = address(governor.token());
        addResult(
            tokenAddress == config.governanceToken,
            "Governor: token",
            vm.toString(config.governanceToken),
            vm.toString(tokenAddress)
        );

        // Check timelock integration
        address timelockAddress = address(governor.timelock());
        addResult(
            timelockAddress == config.timelock,
            "Governor: timelock",
            vm.toString(config.timelock),
            vm.toString(timelockAddress)
        );
    }

    function verifyTimelockConfiguration(DeploymentConfig memory config) internal {
        GovernorTimelock timelock = GovernorTimelock(payable(config.timelock));

        // Check minimum delay
        uint256 minDelay = timelock.getMinDelay();
        addResult(
            minDelay == EXPECTED_TIMELOCK_DELAY,
            "Timelock: minDelay",
            vm.toString(EXPECTED_TIMELOCK_DELAY),
            vm.toString(minDelay)
        );

        // Check governor has PROPOSER_ROLE
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bool hasProposerRole = timelock.hasRole(proposerRole, config.governor);
        addResult(
            hasProposerRole,
            "Timelock: governor has PROPOSER_ROLE",
            "true",
            hasProposerRole ? "true" : "false"
        );

        // Check anyone can execute (EXECUTOR_ROLE granted to address(0))
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bool anyoneCanExecute = timelock.hasRole(executorRole, address(0));
        addResult(
            anyoneCanExecute,
            "Timelock: anyone has EXECUTOR_ROLE",
            "true",
            anyoneCanExecute ? "true" : "false"
        );

        // Check governor has CANCELLER_ROLE
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bool hasCancellerRole = timelock.hasRole(cancellerRole, config.governor);
        addResult(
            hasCancellerRole,
            "Timelock: governor has CANCELLER_ROLE",
            "true",
            hasCancellerRole ? "true" : "false"
        );
    }

    function verifyOwnership(DeploymentConfig memory config) internal {
        PredictionMarket market = PredictionMarket(config.predictionMarket);
        FeeVault feeVault = FeeVault(config.feeVault);
        OutcomeToken outcomeToken = OutcomeToken(config.outcomeToken);
        GovernanceToken govToken = GovernanceToken(config.governanceToken);

        // Check PredictionMarket admin role
        bytes32 defaultAdminRole = market.DEFAULT_ADMIN_ROLE();
        bool marketAdminIsTimelock = market.hasRole(defaultAdminRole, config.timelock);
        addResult(
            marketAdminIsTimelock,
            "PredictionMarket: timelock has DEFAULT_ADMIN_ROLE",
            "true",
            marketAdminIsTimelock ? "true" : "false"
        );

        // Check MARKET_CREATOR_ROLE
        bytes32 marketCreatorRole = market.MARKET_CREATOR_ROLE();
        bool timelockCanCreate = market.hasRole(marketCreatorRole, config.timelock);
        addResult(
            timelockCanCreate,
            "PredictionMarket: timelock has MARKET_CREATOR_ROLE",
            "true",
            timelockCanCreate ? "true" : "false"
        );

        // Check UPGRADER_ROLE
        bytes32 upgraderRole = market.UPGRADER_ROLE();
        bool timelockCanUpgrade = market.hasRole(upgraderRole, config.timelock);
        addResult(
            timelockCanUpgrade,
            "PredictionMarket: timelock has UPGRADER_ROLE",
            "true",
            timelockCanUpgrade ? "true" : "false"
        );

        // Check FeeVault admin
        bytes32 feeVaultAdminRole = feeVault.DEFAULT_ADMIN_ROLE();
        bool feeVaultAdminIsTimelock = feeVault.hasRole(feeVaultAdminRole, config.timelock);
        addResult(
            feeVaultAdminIsTimelock,
            "FeeVault: timelock has DEFAULT_ADMIN_ROLE",
            "true",
            feeVaultAdminIsTimelock ? "true" : "false"
        );

        // Check OutcomeToken admin
        bytes32 outcomeTokenAdminRole = outcomeToken.DEFAULT_ADMIN_ROLE();
        bool outcomeTokenAdminIsTimelock = outcomeToken.hasRole(outcomeTokenAdminRole, config.timelock);
        addResult(
            outcomeTokenAdminIsTimelock,
            "OutcomeToken: timelock has DEFAULT_ADMIN_ROLE",
            "true",
            outcomeTokenAdminIsTimelock ? "true" : "false"
        );

        // Check GovernanceToken admin
        bytes32 govTokenAdminRole = govToken.DEFAULT_ADMIN_ROLE();
        bool govTokenAdminIsTimelock = govToken.hasRole(govTokenAdminRole, config.timelock);
        addResult(
            govTokenAdminIsTimelock,
            "GovernanceToken: timelock has DEFAULT_ADMIN_ROLE",
            "true",
            govTokenAdminIsTimelock ? "true" : "false"
        );

        // Check GovernanceToken minter role
        bytes32 minterRole = govToken.MINTER_ROLE();
        bool timelockCanMint = govToken.hasRole(minterRole, config.timelock);
        addResult(
            timelockCanMint,
            "GovernanceToken: timelock has MINTER_ROLE",
            "true",
            timelockCanMint ? "true" : "false"
        );
    }

    function addResult(bool passed, string memory check, string memory expected, string memory actual) internal {
        results.push(VerificationResult({
            passed: passed,
            check: check,
            expected: expected,
            actual: actual
        }));
    }

    function printResults() internal view {
        uint256 passedCount = 0;
        uint256 failedCount = 0;

        console.log("\n=== Verification Results ===\n");

        for (uint256 i = 0; i < results.length; i++) {
            VerificationResult memory result = results[i];
            string memory status = result.passed ? "PASS" : "FAIL";
            console.log(string.concat("[", status, "] ", result.check));
            console.log(string.concat("  Expected: ", result.expected));
            console.log(string.concat("  Actual:   ", result.actual));

            if (result.passed) {
                passedCount++;
            } else {
                failedCount++;
            }
        }

        console.log("\n=== Summary ===");
        console.log(string.concat("Passed: ", vm.toString(passedCount)));
        console.log(string.concat("Failed: ", vm.toString(failedCount)));
        console.log(string.concat("Total:  ", vm.toString(results.length)));

        if (failedCount > 0) {
            console.log("\n*** VERIFICATION FAILED ***");
            revert("Post-deployment verification failed");
        } else {
            console.log("\n*** ALL CHECKS PASSED ***");
        }
    }
}
