// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import {MyToken} from "../src/MyToken.sol";

contract MultiSigWalletTest is Test {
    MultiSigWallet public msw;
    MyToken public mytoken;

    Account owner = makeAccount("owner");
    Account bob = makeAccount("bob");
    Account alice = makeAccount("alice");
    Account charlie = makeAccount("charlie");

    address[] public owners = [owner.addr, bob.addr, alice.addr];
    uint256 public threshold = 2;

    event TestReceived(address sender, uint256 amount);

    function setUp() public {
        mytoken = new MyToken(owner.addr);
        msw = new MultiSigWallet(owners, threshold);

        vm.deal(owner.addr, 1 ether);
        vm.deal(bob.addr, 1 ether);
        vm.deal(alice.addr, 1 ether);
        vm.deal(charlie.addr, 1 ether);
        vm.deal(address(msw), 1 ether);
    }

    function testSubmitProposal() public {
        vm.startPrank(owner.addr);
        msw.submitProposal(charlie.addr, 1 ether, "transfer");
        assertEq(msw.getProposalsLength(), 1);
        (address target, uint256 value, bytes memory data, bool executed, uint256 confirmations) = msw.getProposal(0);
        assertEq(target, charlie.addr);
        assertEq(value, 1 ether);
        assertEq(data, "transfer");
        assertEq(executed, false);
        assertEq(confirmations, 0);

        vm.stopPrank();
    }

    function testConfirmProposal() public {
        vm.startPrank(owner.addr);
        msw.submitProposal(address(mytoken), 1 ether, "");
        msw.confirmProposal(0);
        vm.stopPrank();
        vm.prank(bob.addr);
        msw.confirmProposal(0);

        assertEq(msw.getProposalsLength(), 1);
        (address target, uint256 value, bytes memory data, bool executed, uint256 confirmations) = msw.getProposal(0);
        assertEq(target, address(mytoken));
        assertEq(value, 1 ether);
        assertEq(data, "");
        assertEq(executed, true);
        assertEq(confirmations, 2);

        require(confirmations >= threshold, "Confirmations should be greater than or equal to the threshold");
        assertGe(confirmations, msw.threshold(), "Confirmations should be greater than or equal to threshold");
        require(msw.isConfirmed(0, owner.addr), "Proposal not confirmed");
    }

    function testConfirmProposalSuccessful() public {
        vm.startPrank(owner.addr);

        msw.submitProposal(charlie.addr, 1 ether, "");
        msw.confirmProposal(0);
        vm.stopPrank();
        vm.prank(bob.addr);
        msw.confirmProposal(0);

        assertEq(msw.getProposalsLength(), 1);
        (address target, uint256 value, bytes memory data, bool executed, uint256 confirmations) = msw.getProposal(0);
        assertEq(target, charlie.addr);
        assertEq(value, 1 ether);
        assertEq(data, "");
        assertEq(executed, true);
        assertEq(confirmations, 2);

        require(confirmations >= threshold, "Confirmations should be greater than or equal to the threshold");
        assertGe(confirmations, msw.threshold(), "Confirmations should be greater than or equal to threshold");
        require(msw.isConfirmed(0, owner.addr), "Proposal not confirmed");
    }

    function testConfirmProposalBelowThreshold() public {
        vm.startPrank(owner.addr);
        msw.submitProposal(charlie.addr, 1 ether, "");
        msw.confirmProposal(0);
        vm.stopPrank();

        assertEq(msw.getProposalsLength(), 1);
        (address target, uint256 value, bytes memory data, bool executed, uint256 confirmations) = msw.getProposal(0);
        assertEq(target, charlie.addr);
        assertEq(value, 1 ether);
        assertEq(data, "");
        assertEq(executed, false);
        assertEq(confirmations, 1); // Only one confirmation

        require(confirmations < threshold, "Confirmations should be less than the threshold");
    }

    function testRepeatedConfirmation() public {
        vm.startPrank(owner.addr);
        msw.submitProposal(charlie.addr, 1 ether, "");
        msw.confirmProposal(0);
        vm.stopPrank();
        vm.prank(bob.addr);
        msw.confirmProposal(0);

        // Attempt to confirm again
        vm.prank(bob.addr);
        try msw.confirmProposal(0) {
            revert("Bob should not be able to confirm the proposal again");
        } catch {}

        // Confirm proposal status
        (address target, uint256 value, bytes memory data, bool executed, uint256 confirmations) = msw.getProposal(0);
        assertEq(target, charlie.addr);
        assertEq(value, 1 ether);
        assertEq(data, "");
        assertEq(executed, true);
        assertEq(confirmations, 2); // Ensure confirmations remain 2
    }

    function testConfirmProposalByDifferentOwners() public {
        vm.startPrank(owner.addr);
        msw.submitProposal(address(mytoken), 1 ether, "");
        msw.confirmProposal(0);
        vm.stopPrank();

        vm.prank(bob.addr);
        msw.confirmProposal(0);

        vm.prank(alice.addr);
        vm.expectRevert("Proposal already executed");
        msw.confirmProposal(0);

        assertEq(msw.getProposalsLength(), 1);
        (address target, uint256 value, bytes memory data, bool executed, uint256 confirmations) = msw.getProposal(0);
        assertEq(target, address(mytoken));
        assertEq(value, 1 ether);
        assertEq(data, "");
        assertEq(executed, true);
        assertEq(confirmations, 2);
    }

    function testInvalidProposal() public {
        vm.startPrank(owner.addr);
        vm.expectRevert("Proposal with invalid address or value should fail");
        try msw.submitProposal(address(0), 0, "invalid") {
            revert("Proposal with invalid address or value should fail");
        } catch {}
        vm.stopPrank();
    }

    function testCancelProposal() public {
        // 提交一个新的提案
        vm.startPrank(owner.addr);
        msw.submitProposal(charlie.addr, 1 ether, ""); // 提交提案
        uint256 proposalId = msw.getProposalsLength() - 1; // 获取提案ID

        // 确保提案已提交
        assertEq(msw.getProposalsLength(), 1);

        // 取消提案
        msw.cancelProposal(proposalId);

        // 确保提案已取消
        // 使用 delete 操作符： 数组的长度不会改变。删除的元素会被重置为默认值
        assertEq(msw.getProposalsLength(), 1, "Proposal should be cancelled");
        vm.stopPrank();

        // 验证提案是否已从映射中删除
        (address target, uint256 value, bytes memory data, bool executed, uint256 confirmations) =
            msw.getProposal(proposalId);
        assertEq(target, address(0));
        assertEq(value, 0);
        assertEq(data, "");
        assertEq(executed, false);
        assertEq(confirmations, 0);
    }
}
