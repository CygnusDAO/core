//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  IPillarsOfCreation.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity >=0.8.17;

import {IHangar18} from "./IHangar18.sol";

/**
 *  @notice Interface to interact with CYG rewards
 */
interface IPillarsOfCreation {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts if the cyg per block passed is above max
     *
     *  @param max The maximum cyg per block allowed
     *  @param value The value passed
     *
     *  @custom:error CygPerBlockExceedsLimit
     */
    error PillarsOfCreation__CygPerBlockExceedsLimit(uint256 max, uint256 value);

    /**
     *  @dev Reverts when attempting to call Admin-only functions
     *
     *  @param admin The address of the admin of hangar18
     *  @param sender Address of msg.sender
     *
     *  @custom:error MsgSenderNotAdmin
     */
    error PillarsOfCreation__MsgSenderNotAdmin(address admin, address sender);

    /**
     *  @dev Reverts if tx.origin is not msg.sender
     *
     *  @param sender The sender of the transaction
     *  @param origin The origin of the transaction
     *
     *  @custom:error OnlyAccountsAllowed
     */
    error PillarsOfCreation__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @dev Reverts if msg.sender is not a CygnusBorrow contract
     *
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param sender Address of msg.sender
     *
     *  @custom:error MsgSenderNotAdmin
     */
    error PillarsOfCreation__MsgSenderNotBorrowable(address borrowable, address sender);

    /**
     *  @dev Reverts if borrowable is not initialized in the rewarder
     *
     *  @param shuttleId The ID of this lending pool
     *  @param borrowable The address of the CygnusBorrow contract
     *
     *  @custom:error ShuttleNotInitialized
     */
    error PillarsOfCreation__ShuttleNotInitialized(uint256 shuttleId, address borrowable);

    /**
     *  @dev Reverts if borrowable is already initialized
     *
     *  @param shuttleId The ID of this lending pool
     *  @param borrowable The address of the CygnusBorrow contract
     *
     *  @custom:error ShuttleAlreadyInitialized
     */
    error PillarsOfCreation__ShuttleAlreadyInitialized(uint256 shuttleId, address borrowable);

    /**
     *  @dev Reverts when trying to sweep the underlying asset from this contract
     *
     *  @param token The address of the token we are trying to sweep
     *  @param underlying The address of CYG, which cannot be swept
     *
     *  @custom:error CantSweepUnderlying
     */
    error PillarsOfCreation__CantSweepUnderlying(address token, address underlying);

    /**
     *  @dev Reverts when the total weight is above 100% when setting lender/borrower splits
     *
     *  @custom:error InvalidTotalWeight
     */
    error PillarsOfCreation__InvalidTotalWeight();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when a new `cygPerBlock` is set manually by Admin
     *
     *  @param lastRewardRate The previous `cygPerBlock rate`
     *  @param newRewardRate The new `cygPerBlock` rate
     *
     *  @custom:event NewCygPerBlock
     */
    event NewCygPerBlock(uint256 lastRewardRate, uint256 newRewardRate);

    /**
     *  @dev Logs when we add a new lending pool to the rewarder
     *
     *  @param shuttleId The `shuttleId` of the borrowable
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param allocPoints The alloc points
     *
     *  @custom:event NewShuttleReward
     */
    event NewShuttleReward(uint256 indexed shuttleId, address indexed borrowable, uint256 allocPoints);

    /**
     *  @dev Logs when a lending pool is updated
     *
     *  @param borrowable Address of the CygnusBorrow contract
     *  @param lastRewardTime The last reward time for this pool
     *  @param totalShares The pool's total shares
     *  @param accRewardPerShare The accumulated reward per share based on the reward distributed
     *
     *  @custom:event UpdateShuttle
     */
    event UpdateShuttle(address indexed borrowable, uint256 lastRewardTime, uint256 totalShares, uint256 accRewardPerShare);

    /**
     *  @notice Legs when `sender` harvests and receives CYG
     *
     *  @param borrowable Address of the CygnusBorrow contract
     *  @param epoch The current epoch
     *  @param sender msg.sender
     *  @param reward CYG reward collected
     *
     *  @custom:event CollectReward
     */
    event CollectReward(address indexed borrowable, uint256 indexed epoch, address sender, uint256 reward);

    /**
     *  @dev Logs when the complex rewarder tracks a lender or a borrower
     *
     *  @param borrowable The address of the borrowable asset.
     *  @param account The address of the lender or borrower
     *  @param balance The updated balance of the account
     *  @param adjustmentFactor The updated borrow index of the borrowable asset or 1e18 for lenders
     *  @param position Whether the account has a borrow or lend position
     *
     *  @custom:event TrackShuttle
     */
    event TrackRewards(address indexed borrowable, address indexed account, uint256 balance, uint256 adjustmentFactor, Position position);

    /**
     *  @dev Emitted when the contract self-destructs (can only self-destruct after the death unix timestamp)
     *
     *  @param sender msg.sender
     *  @param _birth The birth of this contract
     *  @param _death The planned death of this contract
     *  @param timestamp The current timestamp
     *
     *  @custom:event WeAreTheWormsThatCrawlOnTheBrokenWingsOfAnAngel
     */
    event Supernova(address sender, uint256 _birth, uint256 _death, uint256 timestamp);

    /**
     *  @dev Logs when we advance an epoch
     *
     *  @param previousEpoch The number of the previous epoch
     *  @param newEpoch The new epoch
     *  @param _oldCygPerBlock The old CYG per block
     *  @param _newCygPerBlock The new CYG per block
     *
     *  @custom:event NewEpoch
     */
    event NewEpoch(uint256 previousEpoch, uint256 newEpoch, uint256 _oldCygPerBlock, uint256 _newCygPerBlock);

    /**
     *  @dev Logs when the contract sweeps an ERC20 token
     *
     *  @param token The address of the ERC20 token that was swept.
     *  @param sender The address of the account that triggered the token sweep.
     *  @param amount The amount of tokens that were swept from the contract's balance.
     *  @param currentEpoch The current epoch at the time of the token sweep.
     *
     *  @custom:event SweepToken
     */
    event SweepToken(address indexed token, address indexed sender, uint256 amount, uint256 currentEpoch);

    /**
     *  @dev Logs when the allocation point of a borrowable asset in a Shuttle pool is updated.
     *
     *  @param shuttleId The ID of the Shuttle pool where the allocation point was updated.
     *  @param borrowable The address of the borrowable asset whose allocation point was updated.
     *  @param oldAllocPoint The old allocation point of the borrowable asset in the Shuttle pool.
     *  @param newAllocPoint The new allocation point of the borrowable asset in the Shuttle pool.
     *
     *  @custom:event NewShuttleAllocPoint
     */
    event NewShuttleAllocPoint(uint256 indexed shuttleId, address borrowable, uint256 oldAllocPoint, uint256 newAllocPoint);

    /**
     *  @dev Logs when the allocation point of a borrowable asset in a Shuttle pool is updated.
     *
     *  @param shuttleId The ID of the Shuttle pool where the allocation point was updated.
     *  @param borrowable The address of the borrowable asset whose allocation point was updated.
     *  @param oldAllocPoint The old allocation point of the borrowable asset in the Shuttle pool.
     *
     *  @custom:event RemoveShuttleReward
     */
    event RemoveShuttleReward(uint256 indexed shuttleId, address borrowable, uint256 oldAllocPoint, uint256 currentEpoch);

    /**
     *  @dev Logs when all pools get updated
     *
     *  @param shuttlesLength The total number of shuttles updated
     *  @param sender The msg.sender
     *  @param epoch The current epoch
     *
     *  @custom:event AccelerateTheUniverse
     */
    event AccelerateTheUniverse(uint256 shuttlesLength, address sender, uint256 epoch);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:enum Position Lending or Borrowing shuttle
     *  @custom:member LENDER Pass 0 to claim from lender pools
     *  @custom:memebr BROROWER Pass 1 to claim from borrower pools
     */
    enum Position {
        LENDER,
        BORROWER
    }

    /**
     *  @notice Mapping to keep track of PoolInfo for each borrowable asset
     *  @param borrowable The address of the Cygnus Borrow contract
     *  @param position 0 for borrower, 1 for lender
     *  @return active Whether the pool has been initialized or not (can only be set once)
     *  @return shuttleId The ID for this shuttle to identify in hangar18
     *  @return totalShares The total number of shares held in the pool
     *  @return accRewardPerShare The accumulated reward per share of the pool
     *  @return lastRewardTime The timestamp of the last reward distribution
     *  @return allocPoint The allocation points of the pool
     *  @return bonusRewarder The rewarder contract to receive bonus token rewards apart from CYG
     */
    function getShuttleInfo(
        address borrowable,
        Position position
    ) external view returns (bool, uint256, uint256, uint256, uint256, uint256, address);

    /**
     *  @notice Mapping to keep track of UserInfo for each user's deposit and borrow activity
     *  @param borrowable The address of the borrowable contract.
     *  @param position The borrower or lender pool (0 for borrowers, 1 for lenders)
     *  @param user The address of the user to check rewards for.
     *  @return shares The number of shares held by the user
     *  @return rewardDebt The amount of reward debt the user has accrued
     */
    function getUserInfo(address borrowable, Position position, address user) external view returns (uint256, int256);

    /**
     *  @notice Mapping to keep track of EpochInfo for each epoch
     *  @param id The epoch number (limited by TOTAL_EPOCHS)
     *  @return epoch The ID for this epoch
     *  @return rewardRate The CYG reward rate for this epoch
     *  @return totalRewards The total amount of CYG estimated to be rewarded in this epoch
     *  @return totalClaimed The total amount of claimed CYG
     *  @return start The unix timestamp of when this epoch started
     *  @return end The unix timestamp of when it ended or is estimated to end
     */
    function getEpochInfo(
        uint256 id
    ) external view returns (uint256 epoch, uint256 rewardRate, uint256 totalRewards, uint256 totalClaimed, uint256 start, uint256 end);

    /**
     *  @return Get the total amount of pools we have initialized
     */
    function shuttlesLength() external view returns (uint256);

    /**
     *  @return ACC_PRECISION Constant used for precision calculations
     */
    function ACC_PRECISION() external pure returns (uint256);

    /**
     *  @return SHARES_PRECISION is a constant used for precision calculations
     */
    function SHARES_PRECISION() external pure returns (uint256);

    /**
     *  @return MAX_CYG_PER_BLOCK The maximum amount of CYG per block this contract can give to users
     */
    function MAX_CYG_PER_BLOCK() external pure returns (uint256);

    /**
     *  @return BLOCKS_PER_YEAR Constant variable representing the number of blocks in a year
     */
    function BLOCKS_PER_YEAR() external pure returns (uint256);

    /**
     *  @return Constant variable representing the duration of the contract in seconds
     */
    function DURATION() external pure returns (uint256);

    /**
     *  @return TOTAL_EPOCHS The total number of epochs.
     */
    function TOTAL_EPOCHS() external pure returns (uint256);

    /**
     *  @return BLOCKS_PER_EPOCH The duration of each epoch.
     */
    function BLOCKS_PER_EPOCH() external pure returns (uint256);

    /**
     *  @return Human readable name for this rewarder
     */
    function name() external pure returns (string memory);

    /**
     *  @return Version of the rewarder
     */
    function version() external pure returns (string memory);

    /**
     *  @return REDUCTION_FACTOR_PER_EPOCH The reduction factor per epoch (945 / 1000 = 5.5%).
     */
    function REDUCTION_FACTOR_PER_EPOCH() external pure returns (uint256);

    /**
     *  @return hangar18 Address of hangar18 in this chain
     */
    function hangar18() external view returns (IHangar18);

    /**
     *  @return birth Unix timestamp representing the time of contract deployment
     */
    function birth() external view returns (uint256);

    /**
     *  @return death Unix timestamp representing the time of contract destruction
     */
    function death() external view returns (uint256);

    /**
     *  @return cygToken The address of the CYG ERC20 Token
     */
    function cygToken() external view returns (address);

    /**
     *  @return cygPerBlock The amount of CYG this contract gives out to per block
     */
    function cygPerBlock() external view returns (uint256);

    /**
     *  @return totalAllocPoint Total allocation points across all pools
     */
    function totalAllocPoint() external view returns (uint256);

    /**
     *  @return lastEpochTime The timestamp of the end of the last epoch.
     */
    function lastEpochTime() external view returns (uint256);

    /**
     *  @return totalCygRewards The total amount of CYG tokens to be distributed by the end of this contract's lifetime.
     */
    function totalCygRewards() external view returns (uint256);

    /**
     *  @return totalCygClaimed Total rewards given out by this contract up to this point.
     */
    function totalCygClaimed() external view returns (uint256);

    /**
     *  @dev Calculates the emission curve for CYG emissions.
     *
     *  @param epoch The epoch we are calculating the curve for
     *  @return emissionsCurve The CYG emissions curve at `epoch`
     */
    function emissionsCurve(uint256 epoch) external pure returns (uint256);

    /**
     *  @return getBlockTimestamp The current block timestamp.
     */
    function getBlockTimestamp() external view returns (uint256);

    /**
     *  @return This function calculates the current epoch based on the current time and the contract deployment time
     *          It checks if the contract has expired and returns the total number of epochs if it has
     */
    function getCurrentEpoch() external view returns (uint256);

    /**
     *  @return currentEpochRewards The current epoch rewards as per the emissions curve
     */
    function currentEpochRewards() external view returns (uint256);

    /**
     *  @return previousEpochRewards The previous epoch rewards as per the emissions curve
     */
    function previousEpochRewards() external view returns (uint256);

    /**
     *  @return nextEpochRewards The amount of rewards to be released in the next epoch.
     */
    function nextEpochRewards() external view returns (uint256);

    /**
     *  @dev Returns the amount of CYG tokens that are pending to be claimed by the user.
     *
     *  @param borrowable The address of the Cygnus borrow contract.
     *  @param position Whether the user is lending or borrowing
     *  @param _user The address of the user.
     *  @return The amount of CYG tokens pending to be claimed by `_user`.
     */
    function pendingCyg(address borrowable, Position position, address _user) external view returns (uint256);

    /**
     *  @dev Get the time in seconds until this contract self-destructs
     */
    function blocksUntilSupernova() external view returns (uint256);

    /**
     *  @dev Array of all pools earning rewards
     */
    function allShuttles(uint256) external view returns (address);

    /**
     *  @dev Calculates the amount of CYG tokens that should be emitted per block for a given epoch.
     *  @param epoch The epoch for which to calculate the emissions rate.
     *  @return The amount of CYG tokens to be emitted per block.
     */
    function calculateCygPerBlock(uint256 epoch) external view returns (uint256);

    /**
     *  @dev Calculates the total amount of CYG tokens that should be emitted during a given epoch.
     *  @param epoch The epoch for which to calculate the total emissions.
     *  @return The total amount of CYG tokens to be emitted during the epoch.
     */
    function calculateEpochRewards(uint256 epoch) external view returns (uint256);

    // Simple view functions

    /**
     * @return epochProgression The current epoch progression.
     */
    function epochProgression() external view returns (uint256);

    /**
     * @return totalProgression The total contract progression.
     */
    function totalProgression() external view returns (uint256);

    /**
     * @return blocksThisEpoch The distance travelled in blocks this epoch.
     */
    function blocksThisEpoch() external view returns (uint256);

    /**
     *  @return timeUntilNextEpoch The time left until the next epoch starts.
     */
    function blocksUntilNextEpoch() external view returns (uint256);

    /**
     *  @return epochRewardsPacing The pacing of rewards for the current epoch as a percentage
     */
    function epochRewardsPacing() external view returns (uint256);

    /**
     *  @return borrowRewardsWeight The percentage of total CYG rewards that goes to borrowers, the rest being given to lenders
     */
    function borrowRewardsWeight() external view returns (uint256);

    /**
     *  @return doomSwitch Whether the doom which is enabled or not
     */
    function doomSwitch() external view returns (bool);

    /**
     *  @return daoReserves The latest address of the dao reserves in the hangar18 contract
     */
    function daoReserves() external view returns (address);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Harvests the accumulated reward for the specified user from the specified borrowable address's pool, and transfers
     *  it to the specified recipient address.
     *
     *  @param borrowable Address of the borrowable contract for which to harvest rewards.
     *  @param position Collect lending or borrowing position (0 for lending, 1 for borrowing)
     *  @param to Address to which to transfer the harvested rewards.
     *
     *  Effects:
     *  - Updates the user's reward debt to reflect the current accumulated reward.
     *
     *  Interactions:
     *  - Transfers the user's pending reward to the specified recipient address.
     *
     *  @custom:security non-reentrant
     */
    function collect(address borrowable, Position position, address to) external;

    /**
     *  @dev Harvests the accumulated reward for the specified user from all initialized borrowables;
     *
     *  @param to Address to which to transfer the harvested rewards.
     *
     *  Effects:
     *  - Updates the user's reward debt to reflect the current accumulated reward.
     *
     *  Interactions:
     *  - Transfers the user's pending reward to the specified recipient address.
     *
     *  @custom:security non-reentrant
     */
    function collectAll(Position position, address to) external;

    /**
     *  @dev Tracks rewards for lenders and borrowers.
     *
     *  @param account The address of the lender or borrower
     *  @param balance The updated balance of the account
     *  @param adjustmentFactor The updated borrow index of the borrowable asset or 1e18 for lenders
     *  @param position Whether the account has a borrow or lend position
     *
     *  Effects:
     *  - Updates the shares and reward debt of the borrower in the borrowable asset's pool.
     *  - Updates the total shares of the borrowable asset's pool.
     */
    function trackRewards(address account, uint256 balance, uint256 adjustmentFactor, Position position) external;

    /**
     *  @dev Updates all the pool rewards, callable by anyone
     *
     *  @custom:security non-reentrant
     */
    function accelerateTheUniverse() external;

    /**
     *  @notice Update the specified shuttle's reward variables to the current timestamp.
     *  @notice Updates the reward information for a specific borrowable asset. It retrieves the current
     *          ShuttleInfo for the asset, calculates the reward to be distributed based on the time elapsed
     *          since the last distribution and the pool's allocation point, updates the accumulated reward
     *          per share based on the reward distributed, and stores the updated ShuttleInfo for the asset.
     *
     *  @param borrowable The address of the borrowable asset to update.
     *
     *  @custom:security non-reentrant
     */
    function updateShuttle(address borrowable) external;

    /**
     *  @dev Advances the epoch for CYG emissions.
     *
     *  @custom:security non-reentrant
     */
    function advanceEpoch() external;

    /**
     *  @dev Destroys the contract and transfers remaining funds to the owner. Can only be called after 4 years from deployment.
     *
     *  @custom:security non-reentrant
     */
    function supernova() external;

    // Admin //

    /**
     *  @notice Admin 👽
     *  @notice Initializes lending pool in the rewarder
     *
     *  @dev Sets the allocation point for a specific shuttle. The allocation point determines the proportion of rewards that
     *       will be distributed to this shuttle's pool relative to the others. Only hangar Admin can call this function.
     *
     *  @param shuttleId ID of the shuttle to set the allocation point for.
     *  @param allocPoint New allocation point for the shuttle.
     *
     *  @custom:security non-reentrant only-admin
     */
    function initializeShuttleRewards(uint256 shuttleId, uint256 allocPoint) external;

    /**
     *  @notice Admin 👽
     *  @notice This function is used to adjust the amount of CYG rewards that are distributed to each shuttle
     *
     *  @param shuttleId The ID of the shuttle to adjust the allocation points for.
     *  @param allocPoint The new allocation points for the shuttle.
     *
     *  @custom:security non-reentrant only-admin
     */
    function adjustShuttleRewards(uint256 shuttleId, uint256 allocPoint) external;

    /**
     *  @notice Admin 👽
     *  @notice Sets a bonus rewarder to reward borrowers in a bonsu token (this is only applicable for borrowers)
     *  @param shuttleId The lending pool ID
     *  @param bonusRewarder The address of the bonus rewarder
     *  @custom:security only-admin
     */
    function setBonusRewarder(uint256 shuttleId, address bonusRewarder) external;

    /**
     *  @notice Admin 👽
     *  @notice Updates the `cygPerBlock`
     *
     *  @param _cygPerBlock The new `cygPerBLock`
     *
     *  @custom:security non-reentrant only-admin
     */
    function setCygPerBlock(uint256 _cygPerBlock) external;

    /**
     *  @notice Admin 👽
     *  @notice Updates the `borrowerRewardWeight`
     *
     *  @param _newRewardWeight The new reward weight given to the borrowers
     *
     *  @custom:security non-reentrant only-admin
     */
    function setRewardWeights(uint256 _newRewardWeight) external;

    /**
     *  @notice Admin 👽
     *  @notice Recovers any ERC20 token accidentally sent to this contract, sent to msg.sender
     *
     *  @param token The address of the token we are recovering
     *
     *  @custom:security only-admin
     */
    function sweepToken(address token) external;

    /**
     *  @notice Admin 👽
     *  @notice Set the doom switch on the last epoch
     *  @custom:security only-admin
     *
     */
    function setDoomSwitch() external;
}
