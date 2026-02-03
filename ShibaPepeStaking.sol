// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ShibaPepe Staking Contract
 * @dev Staking functionality - 2 Plans
 * @notice For Base Network only
 * @custom:security-note SHPE token must not be a fee-on-transfer or rebasing token.
 *         This contract assumes transfer amounts equal recorded amounts.
 *
 * Plans:
 * - Plan 0: Flexible - 15% APY, no lock
 * - Plan 1: 6-month Lock - 80% APY, 180-day lock
 */
contract ShibaPepeStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ===== Token =====
    IERC20 public shpeToken;

    // ===== Constants =====
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // ===== Plan Configuration =====
    struct StakingPlan {
        string name;           // Plan name
        uint256 lockDuration;  // Lock duration (seconds)
        uint256 apyBasisPoints; // Annual rate (10000 = 100%)
        uint256 bonusRate;     // Bonus rate (10000 = 100%)
        bool isActive;         // Active flag
    }

    mapping(uint256 => StakingPlan) public stakingPlans;
    uint256 public planCount;

    // ===== User Stake Info =====
    struct Stake {
        uint256 amount;           // Staked amount
        uint256 planId;           // Plan ID
        uint256 startTime;        // Stake start time
        uint256 lockEndTime;      // Lock end time
        uint256 lastClaimTime;    // Last reward claim time
        bool isActive;            // Active flag
    }

    // User address => Stake ID => Stake info
    mapping(address => mapping(uint256 => Stake)) public userStakes;
    // User address => Stake count
    mapping(address => uint256) public userStakeCount;

    // ===== Statistics =====
    uint256 public totalStaked;              // Total staked amount
    uint256 public totalRewardsPaid;         // Total rewards paid
    uint256 public rewardPool;               // Reward pool balance

    // ===== Events =====
    event Staked(address indexed user, uint256 stakeId, uint256 amount, uint256 planId);
    event Unstaked(address indexed user, uint256 stakeId, uint256 amount, uint256 reward);
    event RewardClaimed(address indexed user, uint256 stakeId, uint256 reward);
    event RewardPoolFunded(uint256 amount);
    event PlanUpdated(uint256 planId, uint256 apyBasisPoints, uint256 bonusRate);
    event EmergencyRewardPoolWithdrawn(address indexed to, uint256 amount);

    // ===== Constructor =====
    constructor(address _shpeToken) Ownable(msg.sender) {
        require(_shpeToken != address(0), "Invalid token address");
        shpeToken = IERC20(_shpeToken);

        // Plan 0: Flexible (15% APY, no lock)
        stakingPlans[0] = StakingPlan({
            name: "Flexible",
            lockDuration: 0,
            apyBasisPoints: 1500,  // 15%
            bonusRate: 0,
            isActive: true
        });

        // Plan 1: 6-month Lock (80% APY, 180-day lock)
        stakingPlans[1] = StakingPlan({
            name: "6-month Lock",
            lockDuration: 15552000, // 180 days * 86400 seconds
            apyBasisPoints: 8000,   // 80%
            bonusRate: 0,           // No bonus
            isActive: true
        });

        planCount = 2;
    }

    // ===== User Functions =====

    /**
     * @dev Stake tokens
     * @param amount Amount to stake
     * @param planId Plan ID (0 or 1)
     * @notice PUBLIC FUNCTION - Users call this directly to stake tokens.
     *         No access control is required as this is a user-facing function.
     * @custom:security-note Access control intentionally omitted - user-facing function
     */
    function stake(uint256 amount, uint256 planId) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(planId < planCount, "Invalid plan ID");
        require(stakingPlans[planId].isActive, "Plan is not active");

        // Transfer tokens
        shpeToken.safeTransferFrom(msg.sender, address(this), amount);

        // Create stake info
        uint256 stakeId = userStakeCount[msg.sender];
        StakingPlan memory plan = stakingPlans[planId];

        userStakes[msg.sender][stakeId] = Stake({
            amount: amount,
            planId: planId,
            startTime: block.timestamp,
            lockEndTime: block.timestamp + plan.lockDuration,
            lastClaimTime: block.timestamp,
            isActive: true
        });

        userStakeCount[msg.sender]++;
        totalStaked += amount;

        emit Staked(msg.sender, stakeId, amount, planId);
    }

    /**
     * @dev Unstake (after lock period ends)
     * @param stakeId Stake ID
     * @notice PUBLIC FUNCTION - Users call this directly to unstake tokens.
     *         Principal is always returned even if reward pool is insufficient.
     * @custom:security-note Access control intentionally omitted - user-facing function
     */
    function unstake(uint256 stakeId) external nonReentrant {
        Stake storage userStake = userStakes[msg.sender][stakeId];
        require(userStake.isActive, "Stake is not active");
        require(block.timestamp >= userStake.lockEndTime, "Still locked");

        // Calculate reward
        uint256 reward = _calculateReward(msg.sender, stakeId);

        // Add bonus (on lock period completion)
        uint256 bonus = 0;
        if (stakingPlans[userStake.planId].bonusRate > 0) {
            bonus = (userStake.amount * stakingPlans[userStake.planId].bonusRate) / 10000;
        }

        // If reward pool is insufficient, pay what's available
        uint256 totalRewardRequested = reward + bonus;
        uint256 actualReward = totalRewardRequested;
        if (rewardPool < totalRewardRequested) {
            actualReward = rewardPool; // Pay what's available
        }

        // Principal + actual reward
        uint256 totalAmount = userStake.amount + actualReward;

        // Update stake info
        userStake.isActive = false;
        totalStaked -= userStake.amount;
        rewardPool -= actualReward;
        totalRewardsPaid += actualReward;

        // Return tokens (principal is always returned)
        shpeToken.safeTransfer(msg.sender, totalAmount);

        emit Unstaked(msg.sender, stakeId, userStake.amount, actualReward);
    }

    /**
     * @dev Claim reward only (stake continues)
     * @param stakeId Stake ID
     * @notice PUBLIC FUNCTION - Users call this directly to claim rewards.
     *         If reward pool is insufficient, pays available amount.
     * @custom:security-note Access control intentionally omitted - user-facing function
     */
    function claimReward(uint256 stakeId) external nonReentrant {
        Stake storage userStake = userStakes[msg.sender][stakeId];
        require(userStake.isActive, "Stake is not active");

        uint256 reward = _calculateReward(msg.sender, stakeId);
        require(reward > 0, "No reward to claim");

        // If reward pool is insufficient, pay what's available
        uint256 actualReward = reward;
        if (rewardPool < reward) {
            actualReward = rewardPool;
        }

        require(actualReward > 0, "Reward pool is empty");

        // Update reward info
        userStake.lastClaimTime = block.timestamp;
        rewardPool -= actualReward;
        totalRewardsPaid += actualReward;

        // Send reward
        shpeToken.safeTransfer(msg.sender, actualReward);

        emit RewardClaimed(msg.sender, stakeId, actualReward);
    }

    // ===== Internal Functions =====

    /**
     * @dev Calculate reward (real-time per second)
     * @custom:security-note Precision loss is negligible for 18-decimal tokens with large stakes
     */
    function _calculateReward(address user, uint256 stakeId) internal view returns (uint256) {
        Stake memory userStake = userStakes[user][stakeId];
        if (!userStake.isActive) return 0;

        uint256 apyBasisPoints = stakingPlans[userStake.planId].apyBasisPoints;
        uint256 timeElapsed = block.timestamp - userStake.lastClaimTime;

        // Reward = Principal * APY * Time Elapsed / 1 Year
        uint256 reward = (userStake.amount * apyBasisPoints * timeElapsed) / (SECONDS_PER_YEAR * 10000);

        return reward;
    }

    // ===== View Functions =====

    /**
     * @dev Get pending reward
     */
    function getPendingReward(address user, uint256 stakeId) external view returns (uint256) {
        return _calculateReward(user, stakeId);
    }

    /**
     * @dev Get all stake info for a user
     */
    function getUserStakes(address user) external view returns (Stake[] memory) {
        uint256 count = userStakeCount[user];
        Stake[] memory stakes = new Stake[](count);

        for (uint256 i = 0; i < count; i++) {
            stakes[i] = userStakes[user][i];
        }

        return stakes;
    }

    /**
     * @dev Get plan info
     */
    function getPlanInfo(uint256 planId) external view returns (StakingPlan memory) {
        return stakingPlans[planId];
    }

    /**
     * @dev Get all plans info
     */
    function getAllPlans() external view returns (StakingPlan[] memory) {
        StakingPlan[] memory plans = new StakingPlan[](planCount);
        for (uint256 i = 0; i < planCount; i++) {
            plans[i] = stakingPlans[i];
        }
        return plans;
    }

    /**
     * @dev Get staking statistics
     */
    function getStakingStats() external view returns (
        uint256 _totalStaked,
        uint256 _totalRewardsPaid,
        uint256 _rewardPool
    ) {
        return (totalStaked, totalRewardsPaid, rewardPool);
    }

    // ===== Owner-Only Functions =====

    /**
     * @dev Fund reward pool
     */
    function fundRewardPool(uint256 amount) external onlyOwner {
        shpeToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardPool += amount;
        emit RewardPoolFunded(amount);
    }

    /**
     * @dev Update plan
     * @notice APY changes affect future reward calculations for existing stakes.
     *         Users can claim rewards periodically to lock in current rates.
     * @custom:security-note This is intentional design for operational flexibility
     */
    function updatePlan(
        uint256 planId,
        uint256 apyBasisPoints,
        uint256 bonusRate,
        bool isActive
    ) external onlyOwner {
        require(planId < planCount, "Invalid plan ID");
        stakingPlans[planId].apyBasisPoints = apyBasisPoints;
        stakingPlans[planId].bonusRate = bonusRate;
        stakingPlans[planId].isActive = isActive;
        emit PlanUpdated(planId, apyBasisPoints, bonusRate);
    }

    /**
     * @dev Emergency: Withdraw tokens from reward pool
     */
    function emergencyWithdrawRewardPool(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(amount <= rewardPool, "Amount exceeds reward pool");
        rewardPool -= amount;
        shpeToken.safeTransfer(to, amount);
        emit EmergencyRewardPoolWithdrawn(to, amount);
    }
}
