// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PhiiCoin} from "../src/PhiiCoin.sol";
import {SalaryEWA} from "../src/SalaryEWA.sol";

contract DeploySalaryEWAAll is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy PHII (1 juta token)
        PhiiCoin phii = new PhiiCoin(1_000_000 ether);

        // Deploy SalaryEWA
        SalaryEWA salary = new SalaryEWA(IERC20(address(phii)));

        vm.stopBroadcast();

        console.log("Deployer:  ", vm.addr(deployerPrivateKey));
        console.log("PHII:      ", address(phii));
        console.log("SalaryEWA: ", address(salary));
    }
}

contract DeploySalaryEWAOnly is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address salaryToken = vm.envAddress("SALARY_TOKEN");

        vm.startBroadcast(deployerPrivateKey);

        SalaryEWA salary = new SalaryEWA(IERC20(salaryToken));

        vm.stopBroadcast();

        console.log("Deployer:  ", vm.addr(deployerPrivateKey));
        console.log("Token:     ", salaryToken);
        console.log("SalaryEWA: ", address(salary));
    }
}
