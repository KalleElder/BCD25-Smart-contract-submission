// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Script, console2} from "forge-std/Script.sol";
import {MemberPointsRewards} from "../src/MemberPointsRewards.sol";

contract DeploySepolia is Script {
    function run() external returns (MemberPointsRewards deployed) {
        uint128 tshirtCost = 100;
        uint128 vipCost = 500;
        uint128 hoodieCost = 300;

        vm.startBroadcast();
        deployed = new MemberPointsRewards(tshirtCost, vipCost, hoodieCost);
        vm.stopBroadcast();

        console2.log(" Deployed contract address:", address(deployed));
    }
}
