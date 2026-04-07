// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {DataConsumer} from "../src/DataConsumer.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract Deployment is Script {
    function run() external returns (DataConsumer, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address daiPriceFeed, address usdcPriceFeed, address wethPriceFeed, address wbtcPriceFeed) =
            helperConfig.activeNetworkConfig();

        vm.startBroadcast();
        DataConsumer dataConsumer = new DataConsumer(daiPriceFeed, usdcPriceFeed, wethPriceFeed, wbtcPriceFeed);
        vm.stopBroadcast();

        console.log("DAI Price Feed:", daiPriceFeed);
        console.log("USDC Price Feed:", usdcPriceFeed);
        console.log("WETH Price Feed:", wethPriceFeed);
        console.log("WBTC Price Feed:", wbtcPriceFeed);
        console.log("DataConsumer:", address(dataConsumer));

        return (dataConsumer, helperConfig);
    }
}
