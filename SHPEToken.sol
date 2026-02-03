// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ShibaPepe Token ($SHPE)
 * @dev ERC-20 Token - Total Supply: 1 Trillion
 * @notice For Base Network
 * @custom:security-note This token is a standard ERC20 without fee-on-transfer or rebasing mechanics
 */
contract SHPEToken is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000_000 * 10**18; // 1 Trillion

    constructor() ERC20("Shiba Pepe", "SHPE") Ownable(msg.sender) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    /**
     * @dev Burn (destroy) tokens
     * @param amount Amount to burn
     * @notice Only owner can burn tokens to prevent accidental burns by users
     * @custom:security-note Access control intentionally added - owner-only function
     */
    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }
}
