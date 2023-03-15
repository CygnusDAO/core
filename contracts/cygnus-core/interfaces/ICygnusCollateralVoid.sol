// SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.4;

// Dependencies
import {ICygnusCollateralModel} from "./ICygnusCollateralModel.sol";

// Interfaces
import {IDexRouter02} from "./IDexRouter.sol";
import {IMiniChef} from "./IMiniChef.sol";

/**
 *  @title ICygnusCollateralVoid
 *  @notice Interface for `CygnusCollateralVoid` which is in charge of connecting the collateral LP Tokens with
 *          a specified strategy (for example connect to a rewarder contract to stake the LP Token, etc.)
 */
interface ICygnusCollateralVoid is ICygnusCollateralModel {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error OnlyAccountsAllowed Reverts when the transaction origin and sender are different
     */
    error CygnusCollateralVoid__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @custom:error VoidAlreadyInitialized Reverts when re-initalizing the strategy
     */
    error CygnusCollateralVoid__VoidAlreadyInitialized(uint256 poolId);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Emitted when admin implements strategy
     *  @param timestamp The current block timestamp
     *  @param shuttleId This lending pool ID
     *  @param underlying The underlying collateral asset (LP Token)
     *  @param rewarderPoolId The pool ID of the rewarder (Masterchef PID)
     *  @custom:event ChargeVoid Logs when the strategy is first initialized
     */
    event ChargeVoid(uint256 timestamp, uint256 shuttleId, address underlying, uint256 rewarderPoolId);

    /**
     *  @notice Emitted when user reinvests rewards
     *  @param shuttle The address of this lending pool
     *  @param reinvestor The address of the caller who reinvested reward and received bounty
     *  @param rewardBalance The amount reinvested
     *  @param reinvestReward The reward received by the reinvestor @param daoReward The reward received by the DAO
     *  @custom:event RechargeVoid Logs when rewards from the Masterchef/Rewarder are reinvested into more LP Tokens
     */
    event RechargeVoid(
        address indexed shuttle,
        address reinvestor,
        uint256 rewardBalance,
        uint256 reinvestReward,
        uint256 daoReward
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @return REINVEST_REWARD The % of rewards paid to the user who reinvested this shuttle's rewards to buy more LP
     */
    function REINVEST_REWARD() external pure returns (uint256);

    /**
     *  @return DAO_REWARD The % of rewards paid to the DAO from the harvest
     */
    function DAO_REWARD() external pure returns (uint256);

    /**
     *  @return lastReinvest The block timestamp of the last reinvest for this pool
     */
    function lastReinvest() external returns (uint256);

    /**
     *  @notice Getter for this contract's void values (if activated) showing the rewarder address, pool id, etc.
     *  @return rewarder The address of the rewarder
     *  @return dexRouter The address of the dex' router used to swap between tokens
     *  @return rewardsToken The address of the rewards token from the Dex
     *  @return pid The pool ID the collateral's underlying LP Token belongs to in the rewarder
     */
    function getCygnusVoid()
        external
        view
        returns (IMiniChef rewarder, IDexRouter02 dexRouter, address rewardsToken, uint256 pid);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Initializes the pool id for the strategy (Masterchef/Goose pool ID)
     *  @param _pid The Pool ID of this LP Token pair in Masterchef's contract
     *  @custom:security non-reentrant only-admin 👽
     */
    function chargeVoid(uint256 _pid) external;

    /**
     *  @notice Reinvests all rewards from the rewarder to buy more LP Tokens to then deposit back into the rewarder
     *          This makes totalBalance increase in this contract, increasing the exchangeRate between
     *          CygnusLP and underlying and thus lowering user's debt ratios
     *  @custom:security non-reentrant only-eoa
     */
    function reinvestRewards_y7b() external;

    /**
     *  @notice Manually get rewards from the rewarder
     *  @return pendingReward The amount of rewards in `rewardsToken` pending to harvest
     *  @custom:security non-reentrant only-eoa
     */
    function getRewards() external returns (uint256 pendingReward);

    /**
     *  @notice Converts all the dust we may have from token0/token1 to rewardsToken
     *  @notice No check for underlying since tokenA/tokenB can't be liquidity token
     *  @return amountTokenA The amount of tokenA swept
     *  @return amountTokenB The amount of tokenB swept
     *  @custom:security non-reentrant only-eoa
     */
    function smokeDust() external returns (uint256 amountTokenA, uint256 amountTokenB);
}
