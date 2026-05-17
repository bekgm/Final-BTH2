// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title OutcomeToken
/// @notice ERC-1155 multi-token representing YES and NO positions in each
///         prediction market. Token IDs are deterministically derived from the
///         market ID: YES = marketId * 2, NO = marketId * 2 + 1.
/// @dev    Only addresses holding MARKET_ROLE (the PredictionMarket contract)
///         are permitted to mint or burn tokens. ReentrancyGuard is included
///         because ERC-1155 safe-transfer callbacks call external contracts.
/// @custom:security-contact security@predictionprotocol.xyz
contract OutcomeToken is ERC1155, AccessControl, ReentrancyGuard {
    // Constants / Roles

    /// @notice Role that authorises minting and burning outcome tokens
    bytes32 public constant MARKET_ROLE = keccak256("MARKET_ROLE");
    // Events

    /// @notice Emitted after outcome tokens are minted for a market position
    /// @param marketId Market the tokens belong to
    /// @param to       Recipient address
    /// @param outcome  0 = YES position, 1 = NO position (derived from token ID parity)
    /// @param amount   Number of tokens minted
    event OutcomeMinted(
        uint256 indexed marketId,
        address indexed to,
        uint8 outcome,
        uint256 amount
    );

    /// @notice Emitted after outcome tokens are burned
    /// @param marketId Market the tokens belong to
    /// @param from     Address whose tokens were burned
    /// @param outcome  0 = YES position, 1 = NO position
    /// @param amount   Number of tokens burned
    event OutcomeBurned(
        uint256 indexed marketId,
        address indexed from,
        uint8 outcome,
        uint256 amount
    );
    // Constructor

    /// @notice Deploys OutcomeToken, grants DEFAULT_ADMIN_ROLE to admin
    /// @param admin  Address that receives DEFAULT_ADMIN_ROLE (can grant MARKET_ROLE)
    /// @param uri_   ERC-1155 metadata URI template (e.g. "ipfs://.../")
    constructor(address admin, string memory uri_) ERC1155(uri_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }
    // Token-ID helpers

    /// @notice Returns the ERC-1155 token ID for the YES position of a market
    /// @param marketId Market identifier
    /// @return Token ID for YES outcome
    function yesTokenId(uint256 marketId) public pure returns (uint256) {
        return marketId * 2;
    }

    /// @notice Returns the ERC-1155 token ID for the NO position of a market
    /// @param marketId Market identifier
    /// @return Token ID for NO outcome
    function noTokenId(uint256 marketId) public pure returns (uint256) {
        return marketId * 2 + 1;
    }
    // Minting

    /// @notice Mints a single outcome token type to `to`
    /// @dev Only callable by MARKET_ROLE. Emits OutcomeMinted with the
    ///      outcome derived from id parity (even = YES, odd = NO).
    /// @param to     Recipient address
    /// @param id     ERC-1155 token ID (use yesTokenId / noTokenId helpers)
    /// @param amount Number of tokens to mint
    /// @param data   Forwarded to ERC-1155 receiver hook
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyRole(MARKET_ROLE) nonReentrant {
        _mint(to, id, amount, data);
        uint256 marketId = id / 2;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 outcome = uint8(id % 2); // safe: id % 2 is always 0 or 1
        emit OutcomeMinted(marketId, to, outcome, amount);
    }

    /// @notice Burns outcome tokens from `from`
    /// @dev Only callable by MARKET_ROLE. The caller is responsible for
    ///      ensuring `from` has approved the MARKET_ROLE holder, or calling
    ///      from a context where the market contract holds the tokens.
    /// @param from   Address whose tokens will be burned
    /// @param id     ERC-1155 token ID
    /// @param amount Number of tokens to burn
    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external onlyRole(MARKET_ROLE) nonReentrant {
        _burn(from, id, amount);
        uint256 marketId = id / 2;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 outcome = uint8(id % 2); // safe: id % 2 is always 0 or 1
        emit OutcomeBurned(marketId, from, outcome, amount);
    }

    /// @notice Mints multiple outcome token types to `to` in a single call
    /// @dev Only callable by MARKET_ROLE.
    /// @param to      Recipient address
    /// @param ids     Array of ERC-1155 token IDs
    /// @param amounts Array of amounts (parallel to ids)
    /// @param data    Forwarded to ERC-1155 receiver hook
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external onlyRole(MARKET_ROLE) nonReentrant {
        _mintBatch(to, ids, amounts, data);
        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 marketId = ids[i] / 2;
            uint8 outcome = uint8(ids[i] % 2);
            emit OutcomeMinted(marketId, to, outcome, amounts[i]);
        }
    }
    // Interface support

    /// @notice Checks interface support (ERC-1155 + AccessControl)
    /// @param interfaceId ERC-165 interface identifier
    /// @return True if the interface is supported
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
