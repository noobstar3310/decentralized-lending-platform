// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {DataConsumer} from "../src/DataConsumer.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract Deployment is Script {
    function run() external returns (DataConsumer, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config;

        if (block.chainid == 11155111) {
            config = helperConfig.getSepoliaConfig();
        }

        vm.startBroadcast();

        if (block.chainid != 11155111) {
            MockV3Aggregator daiPriceFeed =
                new MockV3Aggregator(helperConfig.PRICE_FEED_DECIMALS(), helperConfig.DAI_USD_PRICE());
            MockV3Aggregator usdcPriceFeed =
                new MockV3Aggregator(helperConfig.PRICE_FEED_DECIMALS(), helperConfig.USDC_USD_PRICE());
            MockV3Aggregator wethPriceFeed =
                new MockV3Aggregator(helperConfig.PRICE_FEED_DECIMALS(), helperConfig.ETH_USD_PRICE());
            MockV3Aggregator wbtcPriceFeed =
                new MockV3Aggregator(helperConfig.PRICE_FEED_DECIMALS(), helperConfig.BTC_USD_PRICE());

            config = HelperConfig.NetworkConfig({
                daiPriceFeed: address(daiPriceFeed),
                usdcPriceFeed: address(usdcPriceFeed),
                wethPriceFeed: address(wethPriceFeed),
                wbtcPriceFeed: address(wbtcPriceFeed)
            });
        }

        DataConsumer dataConsumer =
            new DataConsumer(config.daiPriceFeed, config.usdcPriceFeed, config.wethPriceFeed, config.wbtcPriceFeed);

        vm.stopBroadcast();

        console.log("DAI Price Feed:", config.daiPriceFeed);
        console.log("USDC Price Feed:", config.usdcPriceFeed);
        console.log("WETH Price Feed:", config.wethPriceFeed);
        console.log("WBTC Price Feed:", config.wbtcPriceFeed);
        console.log("DataConsumer:", address(dataConsumer));

        return (dataConsumer, helperConfig);
    }
}
