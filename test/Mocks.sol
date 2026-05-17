// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Simple ERC20 mintable mock for tests
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Mock OracleAdapter used in tests
contract MockOracleAdapter {
    int256 public price;
    uint256 public updatedAt;

    function setLatest(int256 _price, uint256 _updatedAt) external {
        price = _price;
        updatedAt = _updatedAt;
    }

    function getLatestPrice(address) external view returns (int256, uint256) {
        return (price, updatedAt);
    }

    function isStale(address, uint256) external pure returns (bool) {
        // not used in tests
        return false;
    }
}
