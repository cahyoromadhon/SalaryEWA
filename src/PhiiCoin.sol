// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
forge fmt --check

contract PhiiCoin is ERC20 {
    constructor(uint256 initialSupply) ERC20("Phii Coin", "PHII") {
        _mint(msg.sender, initialSupply);
    }
}