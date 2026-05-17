// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IFeeVault} from "../interfaces/IFeeVault.sol";

/// @title FeeVault
/// @notice ERC-4626 tokenised vault that accumulates protocol fees (USDC) from
///         PredictionMarket contracts and distributes them to shareholders.
/// @dev    Only addresses holding DEPOSITOR_ROLE may call depositFees().
///         All standard ERC-4626 deposit/withdraw/redeem functions are
///         inherited from OpenZeppelin's ERC4626.
///         Rounding invariants follow ERC-4626 spec:
///           - previewDeposit  -> round DOWN (shares)
///           - previewMint     -> round UP   (assets)
///           - previewWithdraw -> round UP   (shares)
///           - previewRedeem   -> round DOWN (assets)
/// @custom:security-contact security@predictionprotocol.xyz
contract FeeVault is ERC4626, AccessControl, ReentrancyGuard, IFeeVault {
    using SafeERC20 for IERC20;
    // Roles

    /// @notice Role that permits calling depositFees()
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    // Constructor

    /// @notice Deploys FeeVault with USDC as the underlying asset
    /// @param usdc  ERC-20 token used as the vault's underlying asset (USDC)
    /// @param admin Address receiving DEFAULT_ADMIN_ROLE (can grant DEPOSITOR_ROLE)
    constructor(
        address usdc,
        address admin
    )
        ERC4626(IERC20(usdc))
        ERC20("Fee Vault Shares", "FVS")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }
    // IFeeVault - fee deposit entry-point

    /// @notice Accepts protocol fees from an authorised PredictionMarket contract
    /// @dev    Pulls `amount` USDC from msg.sender (caller must have pre-approved
    ///         this contract). Mints vault shares to msg.sender proportionally.
    ///         Only addresses holding DEPOSITOR_ROLE may call this.
    /// @param amount USDC amount to deposit as fees
    function depositFees(
        uint256 amount
    ) external override onlyRole(DEPOSITOR_ROLE) nonReentrant {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        _deposit(msg.sender, msg.sender, amount, previewDeposit(amount));
        emit FeesDeposited(msg.sender, amount);
    }
    // ERC-4626 rounding overrides

    /// @notice Preview shares minted for a given asset deposit (round DOWN)
    /// @dev ERC-4626 requires previewDeposit to round DOWN in favour of the vault.
    /// @param assets Amount of USDC to deposit
    /// @return shares Shares that would be minted
    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256 shares) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @notice Preview assets required to mint an exact number of shares (round UP)
    /// @dev ERC-4626 requires previewMint to round UP in favour of the vault.
    /// @param shares Exact number of shares desired
    /// @return assets Assets required to mint those shares
    function previewMint(
        uint256 shares
    ) public view override returns (uint256 assets) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    /// @notice Preview shares to burn when withdrawing exact assets (round UP)
    /// @dev ERC-4626 requires previewWithdraw to round UP in favour of the vault.
    /// @param assets Exact USDC amount to withdraw
    /// @return shares Shares that would be burned
    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256 shares) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /// @notice Preview assets returned when redeeming an exact share amount (round DOWN)
    /// @dev ERC-4626 requires previewRedeem to round DOWN in favour of the vault.
    /// @param shares Number of shares to redeem
    /// @return assets USDC that would be returned
    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256 assets) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }
    // IFeeVault view helpers (delegate to ERC4626 internals)

    /// @notice Returns total USDC held in the vault
    /// @return Total asset balance
    function totalAssets()
        public
        view
        override(ERC4626, IFeeVault)
        returns (uint256)
    {
        return super.totalAssets();
    }

    /// @notice Converts shares to assets (rounded down)
    /// @param shares Number of vault shares
    /// @return assets Equivalent USDC amount
    function convertToAssets(
        uint256 shares
    ) public view override(ERC4626, IFeeVault) returns (uint256 assets) {
        return super.convertToAssets(shares);
    }

    /// @notice Converts assets to shares (rounded down)
    /// @param assets USDC amount
    /// @return shares Equivalent vault shares
    function convertToShares(
        uint256 assets
    ) public view override(ERC4626, IFeeVault) returns (uint256 shares) {
        return super.convertToShares(assets);
    }
    // Interface support

    /// @notice Checks interface support (ERC-4626 + AccessControl)
    /// @param interfaceId ERC-165 interface identifier
    /// @return True if the interface is supported
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
