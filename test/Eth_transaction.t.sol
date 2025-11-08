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

    ///@notice Instancia de Mock de CL Feeds
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

    /*////////////////////////////////////
            * ENVIRONMENT SETUP * 
    ////////////////////////////////////*/

    function setUp() public {
        vm.startPrank(owner);
        s_usdc = new MockERC20("USDC", "USDC");
        s_clFeed = new MockV3Aggregator(8, INITIAL_ANSWER);

        bank = new KipuBankV2(BANK_CAP, address(s_clFeed));
        vm.stopPrank();

        vm.deal(user1, ETHER_INITIAL_BALANCE);
        vm.deal(user2, ETHER_INITIAL_BALANCE);
    }

    modifier processDepositEther() {
        uint256 amount = 50 * 10 ** 14;
        vm.prank(user1);
        bank.deposit{value: amount}(ETH_ADDRESS,amount);
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

        bank.deposit{value: ETHER_INITIAL_BALANCE}(ETH_ADDRESS, ETHER_INITIAL_BALANCE);
    }

    function test_depositEtherSucceed() public {
        uint256 amount = ONE_USD_TO_WEI;
        uint256 userBalance = user1.balance;

        vm.startPrank(user1);

        vm.expectEmit();
        emit KipuBankV2.Deposit(user1, amount, amount);
        bank.deposit{value: amount}(ETH_ADDRESS,amount);
        vm.stopPrank();

        assertEq(user1.balance, userBalance - amount);
        assertEq(bank.depositosCount(), 1);

        assertEq(bank.balances(user1, ETH_ADDRESS), amount);
        assertEq(address(bank).balance, amount);
    }

    error InsufficientUserBalance(uint256, uint256);
    error WithdrawalLimitExceeded(address, uint256);

    function test_withdrawEtherFailedBecauseOfUserBalance() public processDepositEther {
        uint256 complaintAmount = 2.5 * 10 ** 14;
        uint256 exceedingAmount = 50 * 10 ** 14;

        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientUserBalance.selector,
                complaintAmount,
                0
            )
        );
        bank.withdraw(ETH_ADDRESS,complaintAmount);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalLimitExceeded.selector,
                user1,
                exceedingAmount
            )
        );
        bank.withdraw(ETH_ADDRESS, exceedingAmount);

        assertEq(bank.withdrawalCount(), 0);
        assertEq(bank.balances(user1, ETH_ADDRESS), exceedingAmount);
        assertEq(address(bank).balance, exceedingAmount);
    }

    function test_WithdrawEtherSucceed() public processDepositEther {
        uint256 complaintAmount = 1 * 10 ** 14;
        uint256 amountAfterWithdrawal = 50 * 10 ** 14 - complaintAmount;

        vm.prank(user1);
        vm.expectEmit();
        emit KipuBankV2.Withdrawal(user1, complaintAmount, amountAfterWithdrawal);
        bank.withdraw(ETH_ADDRESS, complaintAmount);

        assertEq(bank.withdrawalCount(), 1);

        assertEq(bank.balances(user1, ETH_ADDRESS), amountAfterWithdrawal);
        assertEq(address(bank).balance, amountAfterWithdrawal);
    }

}
