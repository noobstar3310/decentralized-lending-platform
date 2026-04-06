// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract DataConsumer {
    error DataConsumer__AddressZero();

    AggregatorV3Interface internal daiDataFeed;
    AggregatorV3Interface internal usdcDataFeed;
    AggregatorV3Interface internal wethDataFeed;
    AggregatorV3Interface internal wbtcDataFeed;


    constructor (address _dai, address _usdc, address _weth, address _wbtc) {
        if (_dai == address(0) || _usdc == address(0) || _weth == address(0) || _wbtc == address(0)){
            revert DataConsumer__AddressZero();
        }
        daiDataFeed = AggregatorV3Interface(_dai);
        usdcDataFeed = AggregatorV3Interface(_usdc);
        wethDataFeed = AggregatorV3Interface(_weth);
        wbtcDataFeed = AggregatorV3Interface(_wbtc);
    }

     function getChainlinkDataFeedLatestAnswer(AggregatorV3Interface dataFeed) public view returns (int256) {
        // prettier-ignore
        (
        /* uint80 roundId */
        ,
        int256 answer,
        /*uint256 startedAt*/
        ,
        /*uint256 updatedAt*/
        ,
        /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return answer;
    }
}
