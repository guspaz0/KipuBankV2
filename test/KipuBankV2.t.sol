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

    ///@notice Instância do Mock do CL Feeds
    MockV3Aggregator public s_clFeed;

    //Variables ~ Users
    address owner = address(77);
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    //Variables ~ Utils
    uint256 constant BANK_CAP = 10_000 * 10 ** 6;
    uint256 constant ETHER_INITIAL_BALANCE = 100 * 10 ** 18;
    uint256 constant USDC_INITIAL_BALANCE = 10_000 * 10 ** 6;
    address constant CL_FEED = address(0);

    //@notice Parâmetros do CL Feeds
    uint8 constant DECIMALS = 8;
    int256 constant INITIAL_ANSWER = 2500 * 10 ** 8;

    ///@notice Variáveis para Testes
    uint256 constant ONE_ETHER_TO_USD = 2500 * 10 ** 6;

    /*////////////////////////////////////
            * ENVIRONMENT SETUP * 
    ////////////////////////////////////*/

    function setUp() public {
        vm.startPrank(owner);
        s_usdc = new MockERC20("USDC", "USDC");
        s_clFeed = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER);

        bank = new KipuBankV2(BANK_CAP, address(s_clFeed), address(s_usdc), owner);
        vm.stopPrank();

        ///@notice Distribui ether
        s_usdc.mint(user1, USDC_INITIAL_BALANCE);
        s_usdc.mint(user2, USDC_INITIAL_BALANCE);

        vm.deal(user1, ETHER_INITIAL_BALANCE);
        vm.deal(user2, ETHER_INITIAL_BALANCE);
    }

    modifier processDepositEther() {
        uint256 amount = 1 * 10 ** 18;
        vm.prank(user1);
        bank.depositEther{value: amount}(amount);
        _;
    }

    /// @notice Error personalizado para manejo de excedentes del límite del banco
    error BankCapLimitExceeded(uint256 bankCap);

    function test_depositEtherFailsWhenBankCapIsReached() public {
        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                BankCapLimitExceeded.selector,
                BANK_CAP
            )
        );
        bank.depositEther{value: ETHER_INITIAL_BALANCE}(ETHER_INITIAL_BALANCE);
    }

    function test_depositEtherSucceed() public {
        uint256 amount = 1 * 10 ** 18;
        uint256 userBalance = user1.balance;

        vm.startPrank(user1);
        s_usdc.approve(address(bank), amount);

        vm.expectEmit();
        emit KipuBankV2.Deposit(user1, amount, amount);
        bank.depositEther{value: amount}(amount);

        assertEq(user1.balance, userBalance - amount);
        assertEq(bank.depositosCount(), 1);

        assertEq(bank.balances(user1, address(0)), amount);
        assertEq(address(bank).balance, amount);
    }

    error InsufficientUserBalance(uint256, uint256);
    error WithdrawalLimitExceeded(address, uint256);

    function test_withdrawEtherFailedBecauseOfUserBalance() public processDepositEther {
        uint256 complaintAmount = 1 * 10 ** 14;
        uint256 exceedingAmount = 1 * 10 ** 18;

        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientUserBalance.selector,
                complaintAmount,
                0
            )
        );
        bank.withdrawEther(complaintAmount);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalLimitExceeded.selector,
                user1,
                exceedingAmount
            )
        );
        bank.withdrawEther(exceedingAmount);

        assertEq(bank.withdrawalCount(), 0);
        assertEq(bank.balances(user1, address(0)), exceedingAmount);
        assertEq(address(bank).balance, exceedingAmount);
    }

    function test_WithdrawEtherSucceed() public processDepositEther {
        uint256 complaintAmount = 1 * 10 ** 14;
        uint256 amountAfterWithdrawal = 1 * 10 ** 18 - complaintAmount;

        vm.prank(user1);
        vm.expectEmit();
        emit KipuBankV2.Withdrawal(user1, complaintAmount, amountAfterWithdrawal);
        bank.withdrawEther(complaintAmount);

        assertEq(bank.withdrawalCount(), 1);

        assertEq(bank.balances(user1, address(0)), amountAfterWithdrawal);
        assertEq(address(bank).balance, amountAfterWithdrawal);
    }


    function test_depositUSDCFailedBecauseOfBankCapLimitExceeded() public {
        uint256 complainUSDCAmount = ONE_ETHER_TO_USD * 6;
        vm.startPrank(user1);
        s_usdc.approve(address(bank), complainUSDCAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                BankCapLimitExceeded.selector,
                BANK_CAP
            )
        );
        bank.depositUSDC(complainUSDCAmount);
    }

    modifier approveUSDC(){
        vm.prank(user1);
        s_usdc.approve(address(bank), ONE_ETHER_TO_USD);
        _;
    }

    function test_depositUSDCSucceed() public approveUSDC {
        vm.prank(user1);
        vm.expectEmit();
        emit KipuBankV2.Deposit(user1, ONE_ETHER_TO_USD, ONE_ETHER_TO_USD);
        bank.depositUSDC(ONE_ETHER_TO_USD);

        assertEq(bank.balances(user1, address(s_usdc)), ONE_ETHER_TO_USD);
        assertEq(s_usdc.balanceOf(user1), USDC_INITIAL_BALANCE - ONE_ETHER_TO_USD);
        assertEq(bank.contractBalanceInUSD(), ONE_ETHER_TO_USD);
    }

    function test_witdrawUSDCFailedBecauseOfUserBalance() public {
        uint256 complainUSDCAmount = ONE_ETHER_TO_USD * 10;
        vm.startPrank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientUserBalance.selector,
                complainUSDCAmount,
                0
            )
        );
        bank.withdrawUSDC(complainUSDCAmount);
    }


    function test_withdrawUSDCSucceed() public approveUSDC {
        vm.startPrank(user1);
        vm.expectEmit();
        emit KipuBankV2.Deposit(user1, ONE_ETHER_TO_USD, ONE_ETHER_TO_USD);
        bank.depositUSDC(ONE_ETHER_TO_USD);

        assertEq(bank.balances(user1,address(s_usdc)), ONE_ETHER_TO_USD);
        assertEq(s_usdc.balanceOf(address(user1)), USDC_INITIAL_BALANCE - ONE_ETHER_TO_USD);
        assertEq(s_usdc.balanceOf(address(bank)), ONE_ETHER_TO_USD);
        assertEq(bank.contractBalanceInUSD(), ONE_ETHER_TO_USD);

        vm.expectEmit();
        emit KipuBankV2.Withdrawal(user1, ONE_ETHER_TO_USD, 0);
        bank.withdrawUSDC(ONE_ETHER_TO_USD);

        assertEq(bank.balances(user1,address(s_usdc)), 0);    
        assertEq(s_usdc.balanceOf(address(user1)), USDC_INITIAL_BALANCE);
    }

}
