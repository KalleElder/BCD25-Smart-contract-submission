// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MemberPointsRewards is Ownable, ReentrancyGuard {
    // Custom errors (billigare än revert strings)
    error NotMember();
    error AlreadyMember();
    error ZeroAmount();
    error InvalidAddress();
    error TransferToSelf();
    error InsufficientPoints(uint256 have, uint256 need);
    error InvalidReward();

    struct Member {
        uint128 points;   // packed
        uint64 joinedAt;  // packed
        bool exists;
    }

    enum Reward {
        TSHIRT,
        VIP,
        HOODIE
    }

    // Public => auto-getters (enklare att läsa i Remix/Etherscan)
    mapping(address => Member) public members;
    mapping(Reward => uint128) public rewardCost;

    uint256 public totalPointsIssued;
    uint256 public totalPointsRedeemed;

    event MemberJoined(address indexed user, uint256 joinedAt);
    event PointsEarned(address indexed user, uint256 amount);
    event PointsTransferred(address indexed from, address indexed to, uint256 amount);
    event PointsGranted(address indexed admin, address indexed to, uint256 amount);
    event RewardRedeemed(address indexed user, Reward reward, uint256 cost);
    event RewardCostUpdated(Reward reward, uint256 newCost);
    event DonationReceived(address indexed from, uint256 amount);
    event DonationsWithdrawn(address indexed admin, uint256 amount);

    // Egen modifier (för VG-kravet "custom modifier")
    modifier onlyMember() {
        if (!members[msg.sender].exists) revert NotMember();
        _;
    }

    constructor(uint128 tshirtCost, uint128 vipCost, uint128 hoodieCost)
        Ownable(msg.sender)
    {
        rewardCost[Reward.TSHIRT] = tshirtCost;
        rewardCost[Reward.VIP] = vipCost;
        rewardCost[Reward.HOODIE] = hoodieCost;
    }

    receive() external payable {
        emit DonationReceived(msg.sender, msg.value);
    }

    fallback() external payable {
        emit DonationReceived(msg.sender, msg.value);
    }

    function join() external {
        if (members[msg.sender].exists) revert AlreadyMember();

        members[msg.sender] = Member({
            points: 0,
            joinedAt: uint64(block.timestamp),
            exists: true
        });

        emit MemberJoined(msg.sender, block.timestamp);
    }

    function earnPoints(uint128 amount) external onlyMember {
        if (amount == 0) revert ZeroAmount();

        members[msg.sender].points += amount;
        totalPointsIssued += amount;

        emit PointsEarned(msg.sender, amount);
    }

    function transferPoints(address to, uint128 amount) external onlyMember {
        if (to == address(0)) revert InvalidAddress();
        if (to == msg.sender) revert TransferToSelf();
        if (!members[to].exists) revert NotMember();
        if (amount == 0) revert ZeroAmount();

        Member storage fromM = members[msg.sender];
        uint128 fromBal = fromM.points;

        if (fromBal < amount) revert InsufficientPoints(fromBal, amount);

        unchecked {
            fromM.points = fromBal - amount;
        }
        members[to].points += amount;

        emit PointsTransferred(msg.sender, to, amount);
    }

    function grantPoints(address to, uint128 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (!members[to].exists) revert NotMember();
        if (amount == 0) revert ZeroAmount();

        members[to].points += amount;
        totalPointsIssued += amount;

        emit PointsGranted(msg.sender, to, amount);
    }

    function setRewardCost(Reward reward, uint128 newCost) external onlyOwner {
        if (newCost == 0) revert ZeroAmount();

        rewardCost[reward] = newCost;
        emit RewardCostUpdated(reward, newCost);
    }

    function redeem(Reward reward) external onlyMember {
        uint128 cost = rewardCost[reward];
        if (cost == 0) revert InvalidReward();

        Member storage m = members[msg.sender];
        uint128 bal = m.points;

        if (bal < cost) revert InsufficientPoints(bal, cost);

        unchecked {
            m.points = bal - cost;
        }

        totalPointsRedeemed += cost;
        assert(totalPointsRedeemed <= totalPointsIssued);

        emit RewardRedeemed(msg.sender, reward, cost);
    }

    function withdrawDonations(address payable to) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidAddress();

        uint256 bal = address(this).balance;
        if (bal == 0) revert("No donations"); // revert-string (krav)

        (bool ok, ) = to.call{value: bal}("");
        require(ok, "WITHDRAW_FAILED"); // require (krav)

        emit DonationsWithdrawn(msg.sender, bal);
    }
}
