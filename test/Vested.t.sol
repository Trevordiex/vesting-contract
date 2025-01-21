// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { Vested } from "src/Vested.sol";
import {ERC20Mock } from "./mocks/ERC20Mock.sol";

contract VestedTest is Test {

    Vested vault;
    ERC20Mock token;
    address USER = makeAddr('user');
    
    address recipient1 = makeAddr("recipient1");
    address recipient2 = makeAddr("recipeint2");

    address[] recipients;
    uint256 constant AMOUNT_TO_SEND = 50 ether;
    uint256 constant DURATION = 5 days;
    uint256 constant WAIT_TIME = 0 days;

    uint256 INITIAL_BALANCE = 10 ether;

    function setUp() public {
        token = new ERC20Mock();
        vault = new Vested();
        vm.prank(USER);
        token.mint(INITIAL_BALANCE);

        recipients.push(recipient1);
        recipients.push(recipient2);
    }

    modifier userApproved {
        vm.prank(USER);
        token.approve(address(vault), INITIAL_BALANCE);
        _;
    }

    function testDepositLockedReturnsId() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;
        vm.prank(USER);
        uint256 id = vault.depositLocked(amount, address(token), recipient1, 0, duration);
        assertEq(id, 1);
    }

    function testDepositLockedReturnsUniqueId() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;

        vm.startPrank(USER);
        uint256 id1 = vault.depositLocked(amount, address(token), recipient1, 0, duration);
        uint256 id2 = vault.depositLocked(amount, address(token), recipient1, 0, duration);
        vm.stopPrank();
        assertNotEq(id1, id2);
    }

    function testDepositLockedRevertsIfAmountIsLessThanMinimum() external userApproved {
        uint256 amount = 1 ether;
        uint256 duration = 2 days;

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Vested.Vested__InvalidAmount.selector, amount));
        vault.depositLocked(amount, address(token), recipient1, 0, duration);
    }

    function testDepositLockedCatchesZeroAddress() external {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;

        vm.prank(USER);
        vm.expectRevert(Vested.Vested__ZeroAddress.selector);
        vault.depositLocked(amount, address(0), recipient1, 0, duration);

        vm.prank(USER);
        vm.expectRevert(Vested.Vested__ZeroAddress.selector);
        vault.depositLocked(amount, address(token), address(0), 0, duration);
    }

    function testDepositLockedCorrectlyInitializesState() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;
        vm.prank(USER);
        uint256 id = vault.depositLocked(amount, address(token), recipient1, 0, duration);
        
        
        Vested.Transfer memory transfer = vault.getTransfer(id);
        assertEq(transfer.id, 1);
        assertEq(transfer.sender, USER);
        assertEq(transfer.recipient, recipient1);
        assertEq(transfer.amount, amount);
        assertEq(transfer.token, address(token));
        assertEq(transfer.lastWithdrawTime, block.timestamp);
        assertEq(transfer.startTime, block.timestamp);
        assertEq(transfer.duration, duration);
        assertEq(transfer.dailyReward, 1 ether);
    }

    function testWithdrawRevertsIfAccruedIsZero() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;
        vm.prank(USER);
        uint256 id = vault.depositLocked(amount, address(token), recipient1, 0, duration);

        vm.expectRevert(Vested.Vested__WithdrawalFailed.selector);
        vault.withdraw(id);
    }

    function testWithdrawUpdatesLastWithdrawTime() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;

        vm.prank(USER);
        uint256 id = vault.depositLocked(amount, address(token), recipient1, 0, duration);

        vm.warp(1 days + 1 seconds);
        vm.roll(100);
        vm.prank(recipient1);
        vault.withdraw(id);

        Vested.Transfer memory transfer = vault.getTransfer(id);
        assertEq(transfer.lastWithdrawTime, block.timestamp);
        vm.stopPrank();
    }

    function testWithdrawTransferCorrectAmountOfToken() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;

        vm.prank(USER);
        uint256 id = vault.depositLocked(amount, address(token), recipient1, 0, duration);

        vm.warp(1 days + 1 seconds);
        vm.roll(100);
        vm.startPrank(recipient1);

        uint256 balanceBefore = token.balanceOf(recipient1);
        uint256 amountAccrued = vault.accrued(id);
        vault.withdraw(id);

        assertEq(token.balanceOf(recipient1), balanceBefore + amountAccrued);
    }

    function testWithdrawCompletesTransferWhenDue() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;

        vm.prank(USER);
        uint256 id = vault.depositLocked(amount, address(token), recipient1, 0, duration);

        vm.warp(1 days + 1 seconds);
        vm.roll(100);
        vm.startPrank(recipient1);
        vault.withdraw(id);

        uint256 status = uint256(vault.getStatus(id));
        assertEq(status, uint256(Vested.TransferStatus.ONGOING));

        vm.warp(2 days + 2 seconds);
        vm.roll(100);
        vault.withdraw(id);

        status = uint256(vault.getStatus(id));
        assertEq(status, uint256(Vested.TransferStatus.ENDED));
        vm.stopPrank();
    }

    // modifier approved {
    //     vm.startPrank(USER);
    //     token.mint(INITIAL_BALANCE);
    //     token.approve(address(vault), INITIAL_BALANCE);
    //     vm.stopPrank();
    //     _;
    // }

    // function test_deposit_transfers_token() external approved {
    //     vm.prank(USER);
    //     vault.deposit(INITIAL_BALANCE);

    //     assertEq(token.balanceOf(USER), 0);
    //     assertEq(token.balanceOf(address(vault)), INITIAL_BALANCE);
    // }

    // function test_deposit_increases_balance() external approved {
    //     vm.prank(USER);
    //     vault.deposit(INITIAL_BALANCE);

    //     assertEq(vault.balance(), INITIAL_BALANCE);
    // }

    // function test_deposit_reverts_if_transfer_fails() external approved {
    //     vm.prank(USER);
    //     vm.expectRevert();
    //     vault.deposit(INITIAL_BALANCE + 2);
    // }

    // function test_deposit_emits_appropriate_event() external approved {
    //     vm.prank(USER);
    //     vm.expectEmit(true, true, false, true, address(vault));
    //     emit Deposit(USER, USER, INITIAL_BALANCE);
    //     vault.deposit(INITIAL_BALANCE);
    // }

    function testAccruedReturnsTheCorrectAmountUserCanWithdraw() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;

        vm.startPrank(USER);
        uint256 id = vault.depositLocked(amount, address(token), USER, 0, duration);

        uint256 accrued = vault.accrued(id);
        assertEq(accrued, 0);

        vm.warp(1 days + 1 seconds);
        vm.roll(50);
        accrued = vault.accrued(id);
        assertEq(accrued, 1 ether);

        vm.warp(2 days);
        vm.roll(50);
        accrued = vault.accrued(id);
        assertEq(accrued, 2 ether);
        vm.stopPrank();
    }

    function testAccruedRevertsIfTransferHasEnded() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;

        vm.prank(USER);
        uint256 id = vault.depositLocked(amount, address(token), recipient1, 0, duration);

        vm.warp(2 days + 1 seconds);
        vm.roll(100);
        vm.startPrank(recipient1);
        vault.withdraw(id);

        uint256 status = uint256(vault.getStatus(id));
        assertEq(status, uint256(Vested.TransferStatus.ENDED));

        vm.expectRevert(Vested.Vested__TransferEnded.selector);
        vault.accrued(id);
    }

    function testAccruedReturnsZeroIfTransferIsPending() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;
        uint256 delay = 20 days;

        vm.startPrank(USER);
        uint256 id = vault.depositLocked(amount, address(token), USER, delay, duration);

        vm.warp(delay);
        vm.roll(100);

        uint256 accrued = vault.accrued(id);
        assertEq(accrued, 0);
    }

    function testReceivedTransferIdsReturnsCorrectIds() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;

        vm.startPrank(USER);
        uint256[] memory ids = vault.getReceivedTransferIds();
        assertEq(ids.length, 0);

        vault.depositLocked(amount, address(token), USER, 0, duration);
        ids = vault.getReceivedTransferIds();
        assertEq(ids.length, 1);

        vault.depositLocked(amount, address(token), USER, 0, duration);
        ids = vault.getReceivedTransferIds();
        assertEq(ids.length, 2);
        vm.stopPrank();
    }

    function testGetTransferReturnsCorrectObject() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;

        vm.startPrank(USER);
        uint256 id = vault.depositLocked(amount, address(token), USER, 0, duration);
        
        Vested.Transfer memory transfer = vault.getTransfer(id);
        assertEq(transfer.id, id);
    }

    function testGetTransferRevertsOnNonExistentId() external userApproved {
        uint256 amount = 2 ether;
        uint256 duration = 2 days;

        vm.startPrank(USER);
        uint256 id = vault.depositLocked(amount, address(token), USER, 0, duration);
        
        Vested.Transfer memory transfer = vault.getTransfer(id);
        assertEq(transfer.id, id);

        vm.expectRevert(Vested.Vested__TransferNotFound.selector);
        vault.getTransfer(2);
    }
}