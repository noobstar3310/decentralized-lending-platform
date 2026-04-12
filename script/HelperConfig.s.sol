// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address daiPriceFeed;
        address usdcPriceFeed;
        address wethPriceFeed;
        address wbtcPriceFeed;
    }

    // Chainlink price feeds use 8 decimals
    uint8 public constant PRICE_FEED_DECIMALS = 8;

    // Mock prices (8 decimals)
    int256 public constant DAI_USD_PRICE = 1e8; // $1
    int256 public constant USDC_USD_PRICE = 1e8; // $1
    int256 public constant ETH_USD_PRICE = 3500e8; // $3500
    int256 public constant BTC_USD_PRICE = 95000e8; // $95000

    function getSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            daiPriceFeed: 0x14866185B1962B63C3Ea9E03Bc1da838bab34C19,
            usdcPriceFeed: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E,
            wethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcPriceFeed: 0x5fb1616F78dA7aFC9FF79e0371741a747D2a7F22
        });
    }
}
