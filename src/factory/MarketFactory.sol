// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PredictionMarket} from "../core/PredictionMarket.sol";

contract MarketFactory is AccessControl {
    // Roles
    bytes32 public constant FACTORY_ADMIN_ROLE = keccak256("FACTORY_ADMIN_ROLE");
    // State

    /// @notice Current PredictionMarket implementation address used for new proxies
    address public implementation;

    /// @notice Array of all deployed market proxy addresses in creation order
    address[] public allMarkets;

    /// @notice Maps CREATE2 salt -> deployed proxy address (address(0) if unused)
    mapping(bytes32 => address) public saltToMarket;
    // Immutable deploy parameters forwarded to every proxy initializer

    /// @notice USDC token address forwarded to every market proxy
    address public immutable usdc;

    /// @notice OutcomeToken address forwarded to every market proxy
    address public immutable outcomeToken;

    /// @notice FeeVault address forwarded to every market proxy
    address public immutable feeVault;

    /// @notice OracleAdapter address forwarded to every market proxy
    address public immutable oracleAdapter;

    /// @notice Admin address forwarded to every market proxy's initialize()
    address public immutable marketAdmin;
    // Errors

    /// @notice Reverts when a salt has already been used for a prior deployment
    /// @param salt The duplicate salt value
    error SaltAlreadyUsed(bytes32 salt);

    /// @notice Reverts when no implementation has been deployed yet
    error NoImplementation();
    // Events

    /// @notice Emitted when a new market proxy is deployed
    /// @param proxy    Address of the deployed ERC1967Proxy
    /// @param salt     CREATE2 salt used
    /// @param question The market question string
    event MarketDeployed(address indexed proxy, bytes32 indexed salt, string question);

    /// @notice Emitted when a new PredictionMarket implementation is deployed
    /// @param impl Address of the deployed implementation contract
    event ImplementationDeployed(address indexed impl);

    // Constructor

    /// @notice Deploys MarketFactory and grants FACTORY_ADMIN_ROLE to admin
    /// @param admin_        Address receiving FACTORY_ADMIN_ROLE and DEFAULT_ADMIN_ROLE
    /// @param usdc_         USDC token address
    /// @param outcomeToken_ OutcomeToken (ERC-1155) address
    /// @param feeVault_     FeeVault (ERC-4626) address
    /// @param oracleAdapter_ OracleAdapter address
    /// @param marketAdmin_  Admin forwarded to each proxy's initialize()
    constructor(
        address admin_,
        address usdc_,
        address outcomeToken_,
        address feeVault_,
        address oracleAdapter_,
        address marketAdmin_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(FACTORY_ADMIN_ROLE, admin_);

        usdc = usdc_;
        outcomeToken = outcomeToken_;
        feeVault = feeVault_;
        oracleAdapter = oracleAdapter_;
        marketAdmin = marketAdmin_;
    }

    // Deployment functions

    /// @notice Deploys a new PredictionMarket implementation contract via CREATE
    /// @dev    Updates `implementation` to the newly deployed address.
    ///         The implementation must have its initializers disabled (done in
    ///         PredictionMarket constructor via _disableInitializers()).
    /// @return impl Address of the newly deployed implementation
    function deployImplementation() external onlyRole(FACTORY_ADMIN_ROLE) returns (address impl) {
        PredictionMarket newImpl = new PredictionMarket();
        impl = address(newImpl);
        implementation = impl;
        emit ImplementationDeployed(impl);
    }

    function deployMarket(
        string calldata question,
        address,
        /* oracleFeed */
        uint256,
        /* resolutionTime */
        uint256,
        /* initialLiquidity */
        bytes32 salt
    )
        external
        onlyRole(FACTORY_ADMIN_ROLE)
        returns (address proxy)
    {
        if (implementation == address(0)) revert NoImplementation();
        if (saltToMarket[salt] != address(0)) revert SaltAlreadyUsed(salt);

        // Encode the initialize() call that will be delegated to the implementation
        bytes memory initData = abi.encodeWithSelector(
            PredictionMarket.initialize.selector, usdc, outcomeToken, feeVault, oracleAdapter, marketAdmin
        );

        // Deploy proxy with CREATE2
        ERC1967Proxy deployedProxy = new ERC1967Proxy{salt: salt}(implementation, initData);

        proxy = address(deployedProxy);

        // Record the deployment
        saltToMarket[salt] = proxy;
        allMarkets.push(proxy);

        emit MarketDeployed(proxy, salt, question);
    }

    // Views

    /// @notice Predicts the CREATE2 address for a given salt without deploying
    /// @dev    Uses the standard CREATE2 formula:
    ///         address = keccak256(0xff ++ factory ++ salt ++ keccak256(initcode))[12:]
    /// @param salt CREATE2 salt to predict for
    /// @return predicted The deterministic proxy address that would be deployed
    function predictMarketAddress(bytes32 salt) external view returns (address predicted) {
        // initcode = type(ERC1967Proxy).creationCode ++ abi.encode(implementation, initData)
        bytes memory initData = abi.encodeWithSelector(
            PredictionMarket.initialize.selector, usdc, outcomeToken, feeVault, oracleAdapter, marketAdmin
        );

        bytes memory creationCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initData));

        bytes32 initcodeHash = keccak256(creationCode);

        predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initcodeHash)))));
    }

    /// @notice Returns the number of deployed market proxies
    /// @return count Total markets deployed by this factory
    function allMarketsLength() external view returns (uint256 count) {
        return allMarkets.length;
    }
}
