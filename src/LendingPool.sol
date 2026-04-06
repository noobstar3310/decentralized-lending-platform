// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {DataConsumer} from "./DataConsumer.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
}

/**
 * @title LendingPool
 * @author Eggwae
 * @notice This is the core of the project, allowing users to deposit selected ERC20 and borrow DAI. Repayment from loans and withdrawing deposits are also possible.
 */
contract LendingPool {
    // Custom Errors
    error LendingPool__AddressIsZero();
    error LendingPool__AmountIsZero();
    error LendingPool__TokenNotSupported();
    error LendingPool__TransferFailed();

    // Events
    event Deposited(address indexed user, address indexed token, uint256 amount);

    // Constants
    uint256 public constant LIQUIDATION_THRESHOLD = 8e17; // 80% in 1e18 precision
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_HEALTH_FACTOR = type(uint256).max;

    // Immutables
    address public immutable i_dai; // 0x14866185B1962B63C3Ea9E03Bc1da838bab34C19
    address public immutable i_usdc; // 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E
    address public immutable i_weth; // 0x694AA1769357215DE4FAC081bf1f309aDC325306
    address public immutable i_wbtc; // 0x5fb1616F78dA7aFC9FF79e0371741a747D2a7F22

    // State variables
    address[] public s_supportedTokens;
    mapping(address => address) public s_tokenToPriceFeed;
    mapping(address => uint256) public s_poolReservesBasedOnToken;
    mapping(address => uint256) public s_userBorrows;
    mapping(address => mapping(address => uint256)) public s_userDepositsBasedOnToken;
    mapping(address => uint256) public s_userHealthFactor;

    constructor(
        address dai,
        address usdc,
        address weth,
        address wbtc,
        address daiPriceFeed,
        address usdcPriceFeed,
        address wethPriceFeed,
        address wbtcPriceFeed
    ) {
        i_dai = dai;
        i_usdc = usdc;
        i_weth = weth;
        i_wbtc = wbtc;

        s_supportedTokens.push(dai);
        s_supportedTokens.push(usdc);
        s_supportedTokens.push(weth);
        s_supportedTokens.push(wbtc);

        s_tokenToPriceFeed[dai] = daiPriceFeed;
        s_tokenToPriceFeed[usdc] = usdcPriceFeed;
        s_tokenToPriceFeed[weth] = wethPriceFeed;
        s_tokenToPriceFeed[wbtc] = wbtcPriceFeed;

        DataConsumer dataConsumer = new DataConsumer(daiPriceFeed, usdcPriceFeed, wethPriceFeed, wbtcPriceFeed);
    }

    modifier revertIfZeroAddress(address _contractAddress) {
        if (_contractAddress == address(0)) {
            revert LendingPool__AddressIsZero();
        }
        _;
    }

    modifier revertIfZeroAmount(uint256 _amount) {
        if (_amount == 0) {
            revert LendingPool__AmountIsZero();
        }
        _;
    }

    modifier revertIfTokenNotSupported(address _token) {
        if (s_tokenToPriceFeed[_token] == address(0)) {
            revert LendingPool__TokenNotSupported();
        }
        _;
    }

    /**
     * @param _assetContractAddress The ERC20 token user intends to deposit
     * @param _amount The amount of token user wishes to deposit
     * @notice Deposit funds into the lending protocol to earn yield or use as collateral to boost health factor
     */
    function deposit(address _assetContractAddress, uint256 _amount)
        external
        revertIfZeroAddress(_assetContractAddress)
        revertIfZeroAmount(_amount)
        revertIfTokenNotSupported(_assetContractAddress)
    {
        s_userDepositsBasedOnToken[msg.sender][_assetContractAddress] += _amount;
        s_poolReservesBasedOnToken[_assetContractAddress] += _amount;

        _updateHealthFactor(msg.sender);

        bool success = IERC20(_assetContractAddress).transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert LendingPool__TransferFailed();
        }

        emit Deposited(msg.sender, _assetContractAddress, _amount);
    }

    function withdraw(address _assetContractAddress) external {
        // check if removed asset, will health factor be below liquidation, if it is revert
    }

    function borrow() external {}

    function repay() external {}

    function liquidate() external {}

    /**
     * @param _user The address of the user to calculate health factor for
     * @return healthFactor The health factor scaled by 1e18
     * @notice Health Factor = (Total Collateral Value in USD * Liquidation Threshold) / Total Borrow Value in USD
     *         If user has no borrows, returns MAX_HEALTH_FACTOR
     */
    function _calculateHealthFactor(address _user) internal view returns (uint256) {
        uint256 totalBorrowValueUsd = s_userBorrows[_user]; // already in USD since borrows are in DAI
        if (totalBorrowValueUsd == 0) {
            return MAX_HEALTH_FACTOR;
        }

        uint256 totalCollateralValueUsd = _getTotalCollateralValueInUsd(_user);

        // healthFactor = (collateral * threshold) / borrows
        // All values scaled by 1e18
        return (totalCollateralValueUsd * LIQUIDATION_THRESHOLD) / totalBorrowValueUsd;
    }

    /**
     * @param _user The address of the user whose health factor should be updated
     */
    function _updateHealthFactor(address _user) internal {
        s_userHealthFactor[_user] = _calculateHealthFactor(_user);
    }

    /**
     * @param _user The address of the user
     * @return totalValueUsd The total collateral value in USD scaled by 1e18
     */
    function _getTotalCollateralValueInUsd(address _user) internal view returns (uint256 totalValueUsd) {
        uint256 length = s_supportedTokens.length;
        for (uint256 i = 0; i < length; i++) {
            address token = s_supportedTokens[i];
            uint256 depositAmount = s_userDepositsBasedOnToken[_user][token];
            if (depositAmount == 0) continue;

            totalValueUsd += _getUsdValue(token, depositAmount);
        }
    }

    /**
     * @param _token The token address
     * @param _amount The token amount (in token's native decimals)
     * @return valueUsd The USD value scaled by 1e18
     */
    function _getUsdValue(address _token, uint256 _amount) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 priceFeedDecimals = priceFeed.decimals();
        uint8 tokenDecimals = IERC20(_token).decimals();

        // Normalize: (amount * price * 1e18) / (10^tokenDecimals * 10^priceFeedDecimals)
        return (_amount * uint256(price) * PRECISION) / (10 ** tokenDecimals * 10 ** priceFeedDecimals);
    }

    function getHealthFactorOfUser(address _user) external view returns (uint256) {
        return s_userHealthFactor[_user];
    }
}