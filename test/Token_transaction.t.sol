// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {Test, console} from "forge-std/Test.sol";
import {KipuBankV2} from "../contracts/KipuBankV2.sol";

import {MockERC20} from "./mocks/MockERC20.sol";

///@notice Mock Chainlink
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";


contract KipuBankV2Test is Test {
    ///@notice instancia del contrato KipuBankV2
    KipuBankV2 public bank;

    ///@notice Instancia de Mock para USDC
    MockERC20 public s_usdc;

    ///@notice Instância de Mock de CL Feeds
    MockV3Aggregator public s_clFeed;

    //Variables ~ Users
    address owner = address(77);
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    //Variables ~ Utils
    //@notice Parametros de CL Feeds
    uint8 constant DECIMALS = 6;
    int256 constant INITIAL_ANSWER = 2500 * 10 ** 8;
    // ------ conversion --------
    // dado que 1 USDC = 250,000,000,000 wei
    // y dado que 1 ETH = 1,000,000,000,000,000,000 wei
    // entonces 1 USDC = 0.00025 ETH 
    uint256 constant ONE_ETHER_TO_USD = 4000;
    uint256 constant ONE_USD_TO_WEI = 0.00025 ether;

    uint256 constant BANK_CAP = ONE_ETHER_TO_USD; // Banco Capacidad en USD 4000 o 1 ETH

    uint256 constant ETHER_INITIAL_BALANCE = 2 ether; // 40 million USD
    address constant ETH_ADDRESS = address(0);

    uint256 constant USDC_INITIAL_BALANCE = 10_000 * 10 ** 6;

    /*////////////////////////////////////
            * ENVIRONMENT SETUP * 
    ////////////////////////////////////*/

    function setUp() public {
        vm.startPrank(owner);
        s_usdc = new MockERC20("USDC", "USDC");
        s_clFeed = new MockV3Aggregator(8, INITIAL_ANSWER);

        bank = new KipuBankV2(BANK_CAP, address(s_clFeed));
        vm.stopPrank();

        ///@notice Distribui ether
        s_usdc.mint(user1, USDC_INITIAL_BALANCE);
        s_usdc.mint(user2, USDC_INITIAL_BALANCE);

        vm.deal(user1, ETHER_INITIAL_BALANCE);
        vm.deal(user2, ETHER_INITIAL_BALANCE);
    }

    function test_addSupportedToken() public {
        vm.startPrank(owner);
        vm.expectEmit();
        emit KipuBankV2.TokenSupported(address(s_usdc), address(s_clFeed), DECIMALS);
        bank.addSupportedToken(address(s_usdc), address(s_clFeed), DECIMALS);
        vm.stopPrank();
    }

    modifier addSupportedToken() {
        uint8 tokenDecimals = s_usdc.decimals();
        vm.prank(owner);
        bank.addSupportedToken(address(s_usdc), address(s_clFeed), tokenDecimals);
        _;
    }

    /// @notice Error personalizado para manejo de excedentes del límite del banco
    error BankCapLimitExceeded(uint256 bankCap);
    error InsufficientUserBalance(uint256, uint256);
    error WithdrawalLimitExceeded(address, uint256);

    function test_depositTokenFailedBecauseOfBankCapLimitExceeded() public addSupportedToken {
        uint256 complainUSDCAmount = ONE_ETHER_TO_USD * 6;
        vm.startPrank(user1);
        s_usdc.approve(address(bank), complainUSDCAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                BankCapLimitExceeded.selector,
                BANK_CAP
            )
        );
        bank.deposit{value: 0}(address(s_usdc), complainUSDCAmount);
    }

    modifier approveToken(){
        vm.prank(user1);
        s_usdc.approve(address(bank), ONE_ETHER_TO_USD);
        _;
    }

    function test_depositTokenSucceed() public approveToken addSupportedToken {
        vm.prank(user1);
        uint256 depositAmountUSDC = 1;
        vm.expectEmit();
        emit KipuBankV2.Deposit(user1, depositAmountUSDC, depositAmountUSDC);
        bank.deposit{value: 0}(address(s_usdc), depositAmountUSDC);

        assertEq(bank.balances(user1, address(s_usdc)), depositAmountUSDC);
        assertEq(s_usdc.balanceOf(user1), USDC_INITIAL_BALANCE - depositAmountUSDC);

        (,int256 ethUSDPrice,,,) = s_clFeed.latestRoundData();

        uint256 factor = 1 * 10 ** (s_usdc.decimals() + s_clFeed.decimals() - DECIMALS);
        uint256 amountTokenUSD = (depositAmountUSDC * uint256(ethUSDPrice)) / factor;
        assertEq(bank.contractBalanceInUSD(), amountTokenUSD);
    }

    function test_witdrawTokenFailedBecauseOfUserBalance() public addSupportedToken {
        uint256 complainUSDCAmount = ONE_ETHER_TO_USD * 10;
        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientUserBalance.selector,
                complainUSDCAmount,
                0
            )
        );
        bank.withdraw(address(s_usdc), complainUSDCAmount);
    }

    function test_withdrawTokenSucceed() public approveToken addSupportedToken {
        vm.startPrank(user1);
        uint256 depositAmountUSDC = 1;
        vm.expectEmit();
        emit KipuBankV2.Deposit(user1, depositAmountUSDC, depositAmountUSDC);
        bank.deposit{value: 0}(address(s_usdc),depositAmountUSDC);

        assertEq(bank.balances(user1, address(s_usdc)), depositAmountUSDC);
        assertEq(s_usdc.balanceOf(address(user1)), USDC_INITIAL_BALANCE - depositAmountUSDC);
        assertEq(s_usdc.balanceOf(address(bank)), depositAmountUSDC);

        (,int256 ethUSDPrice,,,) = s_clFeed.latestRoundData();

        uint256 factor = 1 * 10 ** (s_usdc.decimals() + s_clFeed.decimals() - DECIMALS);
        uint256 amountTokenUSD = (depositAmountUSDC * uint256(ethUSDPrice)) / factor;
        assertEq(bank.contractBalanceInUSD(), amountTokenUSD);

        vm.expectEmit();
        emit KipuBankV2.Withdrawal(user1, depositAmountUSDC, 0);
        bank.withdraw(address(s_usdc), depositAmountUSDC);

        assertEq(bank.balances(user1,address(s_usdc)), 0);    
        assertEq(s_usdc.balanceOf(address(user1)), USDC_INITIAL_BALANCE);
    }

}
