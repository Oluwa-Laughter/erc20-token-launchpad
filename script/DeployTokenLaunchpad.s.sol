// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {TokenLaunchpad} from "../src/TokenLaunchpad.sol";

contract DeployTokenLaunchpad is Script {
    TokenLaunchpad public tokenLaunchpad;

    uint256 public constant PLATFORM_FEE_BPS = 200; // 2%

    function run() public returns (TokenLaunchpad) {
        vm.startBroadcast();

        address feeRecipient = msg.sender;

        tokenLaunchpad = new TokenLaunchpad(feeRecipient, PLATFORM_FEE_BPS);

        vm.stopBroadcast();

        return tokenLaunchpad;
    }
}
