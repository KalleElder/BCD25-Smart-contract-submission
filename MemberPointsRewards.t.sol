// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {MemberPointsRewards} from "../src/MemberPointsRewards.sol";

contract RevertingReceiver {
    receive() external payable {
        revert("nope");
    }
}

contract ReentrantReceiver {
    MemberPointsRewards public target;

    constructor(MemberPointsRewards _target) {
        target = _target;
    }

    receive() external payable {
        target.withdrawDonations(payable(address(this)));
    }
}

contract MemberPointsRewardsTest is Test {
    MemberPointsRewards c;

    address kalle = makeAddr("kalle");
    address samuel = makeAddr("samuel");
    address patricia = makeAddr("patricia");

    event MemberJoined(address indexed user, uint256 joinedAt);
    event PointsEarned(address indexed user, uint256 amount);
    event PointsTransferred(address indexed from, address indexed to, uint256 amount);
    event PointsGranted(address indexed admin, address indexed to, uint256 amount);
    event RewardRedeemed(address indexed user, MemberPointsRewards.Reward reward, uint256 cost);
    event RewardCostUpdated(MemberPointsRewards.Reward reward, uint256 newCost);
    event DonationReceived(address indexed from, uint256 amount);
    event DonationsWithdrawn(address indexed admin, uint256 amount);

    function setUp() public {
        c = new MemberPointsRewards(100, 500, 300);

        vm.deal(address(this), 10 ether);
        vm.deal(kalle, 10 ether);
        vm.deal(samuel, 10 ether);
        vm.deal(patricia, 10 ether);
    }

    function _join(address user) internal {
        vm.prank(user);
        c.join();
    }

    function _earn(address user, uint128 amount) internal {
        vm.prank(user);
        c.earnPoints(amount);
    }

    function testViewsAndConstructorState() public view {
        // owner + rewardCost auto-getter
        assertEq(c.owner(), address(this));
        assertEq(c.rewardCost(MemberPointsRewards.Reward.TSHIRT), 100);
        assertEq(c.rewardCost(MemberPointsRewards.Reward.VIP), 500);
        assertEq(c.rewardCost(MemberPointsRewards.Reward.HOODIE), 300);

        // members auto-getter (returns: points, joinedAt, exists)
        (uint128 pts, uint64 joined, bool exists) = c.members(kalle);
        assertEq(pts, 0);
        assertEq(joined, 0);
        assertFalse(exists);
    }

    function testJoinAndJoinTwice() public {
        vm.prank(kalle);
        vm.expectEmit(true, false, false, false);
        emit MemberJoined(kalle, 0);
        c.join();

        (, , bool exists) = c.members(kalle);
        assertTrue(exists);

        vm.prank(kalle);
        vm.expectRevert(MemberPointsRewards.AlreadyMember.selector);
        c.join();
    }

    function testEarnPointsPaths() public {
        vm.prank(kalle);
        vm.expectRevert(MemberPointsRewards.NotMember.selector);
        c.earnPoints(1);

        _join(kalle);

        vm.prank(kalle);
        vm.expectRevert(MemberPointsRewards.ZeroAmount.selector);
        c.earnPoints(0);

        vm.prank(kalle);
        vm.expectEmit(true, false, false, true);
        emit PointsEarned(kalle, 42);
        c.earnPoints(42);

        (uint128 pts,,) = c.members(kalle);
        assertEq(pts, 42);
        assertEq(c.totalPointsIssued(), 42);
    }

    function testTransferPointsPaths() public {
        vm.prank(patricia);
        vm.expectRevert(MemberPointsRewards.NotMember.selector);
        c.transferPoints(samuel, 1);

        _join(kalle);
        _join(samuel);
        _earn(kalle, 50);

        vm.prank(kalle);
        vm.expectRevert(MemberPointsRewards.InvalidAddress.selector);
        c.transferPoints(address(0), 1);

        vm.prank(kalle);
        vm.expectRevert(MemberPointsRewards.TransferToSelf.selector);
        c.transferPoints(kalle, 1);

        vm.prank(kalle);
        vm.expectRevert(MemberPointsRewards.NotMember.selector);
        c.transferPoints(patricia, 1);

        vm.prank(kalle);
        vm.expectRevert(MemberPointsRewards.ZeroAmount.selector);
        c.transferPoints(samuel, 0);

        vm.prank(kalle);
        vm.expectRevert(
            abi.encodeWithSelector(
                MemberPointsRewards.InsufficientPoints.selector,
                uint256(50),
                uint256(200)
            )
        );
        c.transferPoints(samuel, 200);

        vm.prank(kalle);
        vm.expectEmit(true, true, false, true);
        emit PointsTransferred(kalle, samuel, 20);
        c.transferPoints(samuel, 20);

        (uint128 kPts,,) = c.members(kalle);
        (uint128 sPts,,) = c.members(samuel);
        assertEq(kPts, 30);
        assertEq(sPts, 20);
    }

    function testOwnerOnlyFunctions() public {
        _join(kalle);

        vm.prank(kalle);
        vm.expectRevert();
        c.grantPoints(kalle, 1);

        vm.prank(kalle);
        vm.expectRevert();
        c.setRewardCost(MemberPointsRewards.Reward.TSHIRT, 123);

        vm.prank(kalle);
        vm.expectRevert();
        c.withdrawDonations(payable(kalle));
    }

    function testGrantPointsPaths() public {
        _join(kalle);

        vm.expectRevert(MemberPointsRewards.InvalidAddress.selector);
        c.grantPoints(address(0), 1);

        vm.expectRevert(MemberPointsRewards.NotMember.selector);
        c.grantPoints(samuel, 1);

        vm.expectRevert(MemberPointsRewards.ZeroAmount.selector);
        c.grantPoints(kalle, 0);

        vm.expectEmit(true, true, false, true);
        emit PointsGranted(address(this), kalle, 99);
        c.grantPoints(kalle, 99);

        (uint128 pts,,) = c.members(kalle);
        assertEq(pts, 99);
        assertEq(c.totalPointsIssued(), 99);
    }

    function testSetRewardCostPaths() public {
        vm.expectRevert(MemberPointsRewards.ZeroAmount.selector);
        c.setRewardCost(MemberPointsRewards.Reward.TSHIRT, 0);

        vm.expectEmit(false, false, false, true);
        emit RewardCostUpdated(MemberPointsRewards.Reward.TSHIRT, 222);
        c.setRewardCost(MemberPointsRewards.Reward.TSHIRT, 222);

        assertEq(c.rewardCost(MemberPointsRewards.Reward.TSHIRT), 222);
    }

    function testRedeemPaths() public {
        vm.prank(kalle);
        vm.expectRevert(MemberPointsRewards.NotMember.selector);
        c.redeem(MemberPointsRewards.Reward.TSHIRT);

        _join(kalle);
        _earn(kalle, 150);

        vm.prank(kalle);
        vm.expectRevert(
            abi.encodeWithSelector(
                MemberPointsRewards.InsufficientPoints.selector,
                uint256(150),
                uint256(500)
            )
        );
        c.redeem(MemberPointsRewards.Reward.VIP);

        vm.prank(kalle);
        vm.expectEmit(true, false, false, true);
        emit RewardRedeemed(kalle, MemberPointsRewards.Reward.TSHIRT, 100);
        c.redeem(MemberPointsRewards.Reward.TSHIRT);

        (uint128 pts,,) = c.members(kalle);
        assertEq(pts, 50);
        assertEq(c.totalPointsIssued(), 150);
        assertEq(c.totalPointsRedeemed(), 100);
    }

    function testRedeemInvalidRewardWhenCostIsZero() public {
        MemberPointsRewards c2 = new MemberPointsRewards(100, 500, 0);

        vm.prank(kalle);
        c2.join();

        vm.prank(kalle);
        vm.expectRevert(MemberPointsRewards.InvalidReward.selector);
        c2.redeem(MemberPointsRewards.Reward.HOODIE);
    }

    function testReceiveAndFallback() public {
        vm.expectEmit(true, false, false, true);
        emit DonationReceived(kalle, 1 ether);

        vm.prank(kalle);
        (bool ok1,) = address(c).call{value: 1 ether}("");
        assertTrue(ok1);
        assertEq(address(c).balance, 1 ether);

        bytes memory data = hex"1234";

        vm.expectEmit(true, false, false, true);
        emit DonationReceived(samuel, 2 ether);

        vm.prank(samuel);
        (bool ok2,) = address(c).call{value: 2 ether}(data);
        assertTrue(ok2);
        assertEq(address(c).balance, 3 ether);
    }

    function testWithdrawDonationPaths() public {
        vm.expectRevert(MemberPointsRewards.InvalidAddress.selector);
        c.withdrawDonations(payable(address(0)));

        vm.expectRevert(bytes("No donations"));
        c.withdrawDonations(payable(address(this)));

        vm.prank(kalle);
        (bool ok,) = address(c).call{value: 1 ether}("");
        assertTrue(ok);

        RevertingReceiver rr = new RevertingReceiver();
        vm.expectRevert(bytes("WITHDRAW_FAILED"));
        c.withdrawDonations(payable(address(rr)));

        ReentrantReceiver attacker = new ReentrantReceiver(c);
        c.transferOwnership(address(attacker));

        vm.prank(kalle);
        (bool ok2,) = address(c).call{value: 1 ether}("");
        assertTrue(ok2);

        vm.expectRevert(bytes("WITHDRAW_FAILED"));
        vm.prank(address(attacker));
        c.withdrawDonations(payable(address(attacker)));
    }

    function testWithdrawSuccess() public {
        vm.prank(kalle);
        (bool ok,) = address(c).call{value: 3 ether}("");
        assertTrue(ok);

        uint256 beforeBal = samuel.balance;

        vm.expectEmit(true, false, false, true);
        emit DonationsWithdrawn(address(this), 3 ether);

        c.withdrawDonations(payable(samuel));

        assertEq(address(c).balance, 0);
        assertEq(samuel.balance, beforeBal + 3 ether);
    }
}
