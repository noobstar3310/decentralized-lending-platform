// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract LendingPoolTest is Test {
    LendingPool public lendingPool;

    MockERC20 public dai;
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public wbtc;

    MockV3Aggregator public daiPriceFeed;
    MockV3Aggregator public usdcPriceFeed;
    MockV3Aggregator public wethPriceFeed;
    MockV3Aggregator public wbtcPriceFeed;

    address public USER = makeAddr("user");
    uint256 public constant DEPOSIT_AMOUNT = 1000e18; // 1000 DAI
    uint8 public constant PRICE_FEED_DECIMALS = 8;

    function setUp() public {
        // Deploy mock tokens
        dai = new MockERC20("DAI", "DAI", 18);
        usdc = new MockERC20("USDC", "USDC", 6);
        weth = new MockERC20("WETH", "WETH", 18);
        wbtc = new MockERC20("WBTC", "WBTC", 8);

        // Deploy mock price feeds
        daiPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, 1e8); // $1
        usdcPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, 1e8); // $1
        wethPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, 3500e8); // $3500
        wbtcPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, 95000e8); // $95000

        // Deploy LendingPool
        lendingPool = new LendingPool(
            address(dai),
            address(usdc),
            address(weth),
            address(wbtc),
            address(daiPriceFeed),
            address(usdcPriceFeed),
            address(wethPriceFeed),
            address(wbtcPriceFeed)
        );

        // Mint tokens to user and approve
        dai.mint(USER, 10_000e18);
        weth.mint(USER, 10e18);

        vm.startPrank(USER);
        dai.approve(address(lendingPool), type(uint256).max);
        weth.approve(address(lendingPool), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DepositUpdatesUserBalance() public {
        console.log("--- test_DepositUpdatesUserBalance ---");
        console.log("User deposit before:", lendingPool.s_userDepositsBasedOnToken(USER, address(dai)));

        vm.prank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Deposited DAI amount:", DEPOSIT_AMOUNT);

        uint256 userDeposit = lendingPool.s_userDepositsBasedOnToken(USER, address(dai));
        console.log("User deposit after:", userDeposit);
        assertEq(userDeposit, DEPOSIT_AMOUNT);
    }

    function test_DepositUpdatesPoolReserves() public {
        console.log("--- test_DepositUpdatesPoolReserves ---");
        console.log("Pool reserves before:", lendingPool.s_poolReservesBasedOnToken(address(dai)));

        vm.prank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Deposited DAI amount:", DEPOSIT_AMOUNT);

        uint256 reserves = lendingPool.s_poolReservesBasedOnToken(address(dai));
        console.log("Pool reserves after:", reserves);
        assertEq(reserves, DEPOSIT_AMOUNT);
    }

    function test_DepositTransfersTokensFromUser() public {
        console.log("--- test_DepositTransfersTokensFromUser ---");
        uint256 userBalanceBefore = dai.balanceOf(USER);
        uint256 poolBalanceBefore = dai.balanceOf(address(lendingPool));
        console.log("User DAI balance before:", userBalanceBefore);
        console.log("Pool DAI balance before:", poolBalanceBefore);

        vm.prank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Deposited DAI amount:", DEPOSIT_AMOUNT);

        uint256 userBalanceAfter = dai.balanceOf(USER);
        uint256 poolBalanceAfter = dai.balanceOf(address(lendingPool));
        console.log("User DAI balance after:", userBalanceAfter);
        console.log("Pool DAI balance after:", poolBalanceAfter);
        assertEq(userBalanceAfter, userBalanceBefore - DEPOSIT_AMOUNT);
        assertEq(poolBalanceAfter, DEPOSIT_AMOUNT);
    }

    function test_DepositUpdatesHealthFactor() public {
        console.log("--- test_DepositUpdatesHealthFactor ---");
        console.log("Health factor before:", lendingPool.getHealthFactorOfUser(USER));

        vm.prank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Deposited DAI amount:", DEPOSIT_AMOUNT);

        uint256 healthFactor = lendingPool.getHealthFactorOfUser(USER);
        console.log("Health factor after:", healthFactor);
        console.log("Expected: type(uint256).max (no borrows)");
        // No borrows, so health factor should be MAX
        assertEq(healthFactor, type(uint256).max);
    }

    function test_DepositEmitsEvent() public {
        console.log("--- test_DepositEmitsEvent ---");
        console.log("Expecting Deposited event with user:", USER);
        console.log("Token:", address(dai));
        console.log("Amount:", DEPOSIT_AMOUNT);

        vm.prank(USER);
        vm.expectEmit(true, true, false, true);
        emit LendingPool.Deposited(USER, address(dai), DEPOSIT_AMOUNT);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Event emitted successfully");
    }

    function test_DepositMultipleTimesAccumulates() public {
        console.log("--- test_DepositMultipleTimesAccumulates ---");

        vm.startPrank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("First deposit:", DEPOSIT_AMOUNT);
        console.log("User deposit after 1st:", lendingPool.s_userDepositsBasedOnToken(USER, address(dai)));

        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Second deposit:", DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 totalDeposit = lendingPool.s_userDepositsBasedOnToken(USER, address(dai));
        console.log("User deposit after 2nd:", totalDeposit);
        console.log("Expected:", DEPOSIT_AMOUNT * 2);
        assertEq(totalDeposit, DEPOSIT_AMOUNT * 2);
    }

    function test_DepositRevertsIfZeroAddress() public {
        console.log("--- test_DepositRevertsIfZeroAddress ---");
        console.log("Attempting deposit with address(0)");

        vm.prank(USER);
        vm.expectRevert(LendingPool.LendingPool__AddressIsZero.selector);
        lendingPool.deposit(address(0), DEPOSIT_AMOUNT);
        console.log("Reverted with LendingPool__AddressIsZero as expected");
    }

    function test_DepositRevertsIfZeroAmount() public {
        console.log("--- test_DepositRevertsIfZeroAmount ---");
        console.log("Attempting deposit with amount = 0");

        vm.prank(USER);
        vm.expectRevert(LendingPool.LendingPool__AmountIsZero.selector);
        lendingPool.deposit(address(dai), 0);
        console.log("Reverted with LendingPool__AmountIsZero as expected");
    }

    function test_DepositRevertsIfTokenNotSupported() public {
        console.log("--- test_DepositRevertsIfTokenNotSupported ---");
        address fakeToken = makeAddr("fakeToken");
        console.log("Attempting deposit with unsupported token:", fakeToken);

        vm.prank(USER);
        vm.expectRevert(LendingPool.LendingPool__TokenNotSupported.selector);
        lendingPool.deposit(fakeToken, DEPOSIT_AMOUNT);
        console.log("Reverted with LendingPool__TokenNotSupported as expected");
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_WithdrawReturnsTokensToUser() public {
        console.log("--- test_WithdrawReturnsTokensToUser ---");

        vm.startPrank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Deposited DAI:", DEPOSIT_AMOUNT);

        uint256 balanceBefore = dai.balanceOf(USER);
        console.log("User DAI balance before withdraw:", balanceBefore);

        lendingPool.withdraw(address(dai), DEPOSIT_AMOUNT);
        console.log("Withdrew DAI:", DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 balanceAfter = dai.balanceOf(USER);
        console.log("User DAI balance after withdraw:", balanceAfter);
        assertEq(balanceAfter, balanceBefore + DEPOSIT_AMOUNT);
    }

    function test_WithdrawUpdatesUserBalance() public {
        console.log("--- test_WithdrawUpdatesUserBalance ---");

        vm.startPrank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Deposited DAI:", DEPOSIT_AMOUNT);
        console.log("User deposit after deposit:", lendingPool.s_userDepositsBasedOnToken(USER, address(dai)));

        lendingPool.withdraw(address(dai), DEPOSIT_AMOUNT);
        console.log("Withdrew DAI:", DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 userDeposit = lendingPool.s_userDepositsBasedOnToken(USER, address(dai));
        console.log("User deposit after withdraw:", userDeposit);
        assertEq(userDeposit, 0);
    }

    function test_WithdrawUpdatesPoolReserves() public {
        console.log("--- test_WithdrawUpdatesPoolReserves ---");

        vm.startPrank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Deposited DAI:", DEPOSIT_AMOUNT);
        console.log("Pool reserves after deposit:", lendingPool.s_poolReservesBasedOnToken(address(dai)));

        lendingPool.withdraw(address(dai), DEPOSIT_AMOUNT);
        console.log("Withdrew DAI:", DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 reserves = lendingPool.s_poolReservesBasedOnToken(address(dai));
        console.log("Pool reserves after withdraw:", reserves);
        assertEq(reserves, 0);
    }

    function test_WithdrawPartialAmount() public {
        console.log("--- test_WithdrawPartialAmount ---");
        uint256 withdrawAmount = 400e18;

        vm.startPrank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Deposited DAI:", DEPOSIT_AMOUNT);

        lendingPool.withdraw(address(dai), withdrawAmount);
        console.log("Withdrew DAI:", withdrawAmount);
        vm.stopPrank();

        uint256 remainingDeposit = lendingPool.s_userDepositsBasedOnToken(USER, address(dai));
        uint256 remainingReserves = lendingPool.s_poolReservesBasedOnToken(address(dai));
        console.log("Remaining user deposit:", remainingDeposit);
        console.log("Remaining pool reserves:", remainingReserves);
        console.log("Expected remaining:", DEPOSIT_AMOUNT - withdrawAmount);
        assertEq(remainingDeposit, DEPOSIT_AMOUNT - withdrawAmount);
        assertEq(remainingReserves, DEPOSIT_AMOUNT - withdrawAmount);
    }

    function test_WithdrawEmitsEvent() public {
        console.log("--- test_WithdrawEmitsEvent ---");

        vm.startPrank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Deposited DAI:", DEPOSIT_AMOUNT);

        console.log("Expecting Withdrawn event with user:", USER);
        console.log("Token:", address(dai));
        console.log("Amount:", DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit LendingPool.Withdrawn(USER, address(dai), DEPOSIT_AMOUNT);
        lendingPool.withdraw(address(dai), DEPOSIT_AMOUNT);
        vm.stopPrank();
        console.log("Event emitted successfully");
    }

    function test_WithdrawRevertsIfInsufficientBalance() public {
        console.log("--- test_WithdrawRevertsIfInsufficientBalance ---");

        vm.startPrank(USER);
        lendingPool.deposit(address(dai), DEPOSIT_AMOUNT);
        console.log("Deposited DAI:", DEPOSIT_AMOUNT);
        console.log("Attempting to withdraw:", DEPOSIT_AMOUNT + 1);

        vm.expectRevert(LendingPool.LendingPool__InsufficientBalance.selector);
        lendingPool.withdraw(address(dai), DEPOSIT_AMOUNT + 1);
        vm.stopPrank();
        console.log("Reverted with LendingPool__InsufficientBalance as expected");
    }

    function test_WithdrawRevertsIfZeroAmount() public {
        console.log("--- test_WithdrawRevertsIfZeroAmount ---");
        console.log("Attempting withdraw with amount = 0");

        vm.prank(USER);
        vm.expectRevert(LendingPool.LendingPool__AmountIsZero.selector);
        lendingPool.withdraw(address(dai), 0);
        console.log("Reverted with LendingPool__AmountIsZero as expected");
    }

    function test_WithdrawRevertsIfTokenNotSupported() public {
        console.log("--- test_WithdrawRevertsIfTokenNotSupported ---");
        address fakeToken = makeAddr("fakeToken");
        console.log("Attempting withdraw with unsupported token:", fakeToken);

        vm.prank(USER);
        vm.expectRevert(LendingPool.LendingPool__TokenNotSupported.selector);
        lendingPool.withdraw(fakeToken, DEPOSIT_AMOUNT);
        console.log("Reverted with LendingPool__TokenNotSupported as expected");
    }

    function test_WithdrawFullAmountWithNoBorrows() public {
        console.log("--- test_WithdrawFullAmountWithNoBorrows ---");

        vm.startPrank(USER);
        console.log("User WETH balance before deposit:", weth.balanceOf(USER));

        lendingPool.deposit(address(weth), 5e18);
        console.log("Deposited WETH: 5e18");
        console.log("User WETH balance after deposit:", weth.balanceOf(USER));
        console.log("Health factor:", lendingPool.getHealthFactorOfUser(USER));

        lendingPool.withdraw(address(weth), 5e18);
        console.log("Withdrew WETH: 5e18");
        vm.stopPrank();

        uint256 userDeposit = lendingPool.s_userDepositsBasedOnToken(USER, address(weth));
        uint256 userBalance = weth.balanceOf(USER);
        console.log("User WETH deposit after withdraw:", userDeposit);
        console.log("User WETH balance after withdraw:", userBalance);
        assertEq(userDeposit, 0);
        assertEq(userBalance, 10e18); // back to original balance
    }
}
