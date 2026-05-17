// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title GovernanceToken
/// @notice ERC-20 governance token with on-chain voting power (ERC20Votes) and
///         gasless approvals (ERC20Permit). Used to govern the PredictionMarket
///         protocol via PredictionGovernor.
/// @dev    Uses block.timestamp as the voting clock (TIMESTAMP mode) instead of
///         block.number for more predictable voting windows.
///         Supply starts at 0 and is minted by addresses holding MINTER_ROLE.
///         Hard cap: 100,000,000 PGOV (1e26 raw units).
/// @custom:security-contact security@predictionprotocol.xyz
contract GovernanceToken is ERC20, ERC20Votes, ERC20Permit, AccessControl {
    // Constants

    /// @notice Role that authorises minting new PGOV tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Hard cap on total supply (100,000,000 PGOV)
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18;
    // Errors

    /// @notice Reverts when a mint would breach MAX_SUPPLY
    /// @param requested Amount requested to mint
    /// @param available Remaining mintable supply
    error SupplyCapExceeded(uint256 requested, uint256 available);
    // Constructor

    /// @notice Deploys the GovernanceToken and grants admin + minter to initialAdmin
    /// @param initialAdmin Address that receives DEFAULT_ADMIN_ROLE and MINTER_ROLE
    constructor(address initialAdmin)
        ERC20("PredictionGov", "PGOV")
        ERC20Permit("PredictionGov")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MINTER_ROLE, initialAdmin);
    }
    // Minting

    /// @notice Mints PGOV tokens to `to`
    /// @dev Only callable by addresses holding MINTER_ROLE.
    ///      Reverts with SupplyCapExceeded if the cap would be breached.
    /// @param to     Recipient of the newly minted tokens
    /// @param amount Number of tokens to mint (in 1e18 units)
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        uint256 available = MAX_SUPPLY - totalSupply();
        if (amount > available) revert SupplyCapExceeded(amount, available);
        _mint(to, amount);
    }
    // ERC20Votes clock overrides (timestamp mode)

    /// @notice Returns current time as block.timestamp for voting snapshots
    /// @dev Overrides the default block.number clock of ERC20Votes.
    /// @return Current block timestamp (uint48 cast)
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @notice Describes the clock mode as timestamp-based
    /// @dev Required by ERC-6372 when overriding clock().
    /// @return Machine-readable clock mode string
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }
    // Internal hook - OZ v5 pattern

    /// @notice Hook called on every token transfer, mint, and burn
    /// @dev Calls both ERC20._update (balance accounting) and
    ///      ERC20Votes._update (checkpoint accounting) as required by OZ v5.
    /// @param from   Sender (address(0) on mint)
    /// @param to     Recipient (address(0) on burn)
    /// @param value  Amount transferred
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /// @notice Returns the current nonce for `owner` (ERC20Permit / Nonces)
    /// @param owner Address to query
    /// @return Current nonce
    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
