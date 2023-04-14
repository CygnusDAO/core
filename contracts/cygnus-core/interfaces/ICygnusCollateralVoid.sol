// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusCollateralModel} from "./ICygnusCollateralModel.sol";

// One inch
import {IAggregationRouterV5} from "./IAggregationRouterV5.sol";

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
     *  @custom:error DstReceiverNotValid Reverts if the receiver of the swap is not this contract
     */
    error CygnusCollateralVoid__DstReceiverNotValid(address dstReceiver, address receiver);

    /**
     *  @custom:error SwapNotAllowed Reverts if the token received is not underlying
     */
    error CygnusCollateralVoid__DstTokenNotValid(address dstToken, address token);

    /**
     *  @custom:error SrcTokenNotValid Reverts if the src token we are swapping is not the rewards token
     */
    error CygnusCollateralVoid__SrcTokenNotValid(address srcToken, address token);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Emitted when admin implements strategy
     *  @param underlying The address of the underlying LP token
     *  @param shuttleId The unique ID of the lending pool
     *  @param sender The address of the msg.sender (admin)
     *  @custom:event ChargeVoid Logs when the strategy is first initialized
     */
    event ChargeVoid(address underlying, uint256 shuttleId, address sender);

    /**
     *  @notice Emitted when user reinvests rewards
     *  @param reinvestor The address of the caller who reinvested reward and received bounty
     *  @param rewardBalance The amount of `rewardsToken` reinvested
     *  @param daoReward The reward received by the DAO
     *  @param underlyingReceived The amount of underlying LP reinvested
     *  @custom:event RechargeVoid Logs when rewards from the Masterchef/Rewarder are reinvested into more LP Tokens
     */
    event RechargeVoid(
        address indexed reinvestor,
        uint256 rewardBalance,
        uint256 daoReward,
        uint256 underlyingReceived
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @return AGGREGATION_ROUTER_V5 The address of the 1inch router used for the swaps
     */
    function AGGREGATION_ROUTER_V5() external pure returns (IAggregationRouterV5);

    /**
     *  @return DAO_REWARD The % of rewards paid to the DAO from the harvest
     */
    function DAO_REWARD() external pure returns (uint256);

    /**
     *  @return lastReinvest The block timestamp of the last reinvest for this pool
     */
    function lastReinvest() external view returns (uint256);

    /**
     *  @notice Getter for this contract's void values (if activated) showing the rewarder address, pool id, etc.
     */
    function getCygnusVoid() external view returns (address token, address rewarder, address dexRouter, uint256 id);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Initializes the pool id for the strategy (Masterchef/Goose pool ID)
     *  @custom:security non-reentrant only-admin 👽
     */
    function chargeVoid(uint256 poolId) external;

    /**
     *  @notice Manually get rewards from the rewarder
     *  @return pendingReward The amount of rewards in `rewardsToken` pending to harvest
     *  @custom:security non-reentrant only-eoa
     */
    function getRewards() external returns (uint256 pendingReward);

    /**
     *  @notice Reinvests all rewards from the rewarder to buy more LP Tokens to then deposit back into the rewarder
     *          This makes totalBalance increase in this contract, increasing the exchangeRate between
     *          CygnusLP and underlying and thus lowering user's debt ratios
     *  @custom:security non-reentrant only-eoa
     */
    function reinvestRewards_y7b(bytes memory swapData) external;
}
