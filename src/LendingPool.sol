// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract LendingPool {
    address public immutable DAI_CONTRACT_ADDRESS;
    address public immutable USDC_CONTRACT_ADDRESS;
    address public immutable USDT_CONTRACT_ADDRESS;
    address public immutable WETH_CONTRACT_ADDRESS;
    address public immutable WBTC_CONTRACT_ADDRESS;
    

    mapping(address => uint256) public s_poolReservesBasedOnToken;

    mapping(address => uint256) public s_userBorrows;

    mapping(address => mapping(address => uint256)) public s_userDepositsBasedOnToken;

    constructor(address dai, address usdc, address usdt, address weth, address wbtc) {
        DAI_CONTRACT_ADDRESS = dai;
        USDC_CONTRACT_ADDRESS = usdc;
        USDT_CONTRACT_ADDRESS = usdt;
        WETH_CONTRACT_ADDRESS = weth;
        WBTC_CONTRACT_ADDRESS = wbtc;
    }

    function deposit(address _assetContractAddress, uint256 _amount) external {

    }

    function withdraw() external {}

    function borrow() external {}

    function repay() external {}

    function liquidate() external {}

    function calculateHealthFactor() internal {}
}