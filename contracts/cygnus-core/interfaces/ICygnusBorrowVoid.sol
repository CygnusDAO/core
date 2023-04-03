// SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.4;

// Dependencies
import {ICygnusBorrowModel} from "./ICygnusBorrowModel.sol";
// Stargate
import {IAggregationRouterV5} from "./IAggregationRouterV5.sol";
import {IStargatePool} from "./BorrowableVoid/IStargatePool.sol";
import {IStargateRouter} from "./BorrowableVoid/IStargateRouter.sol";
import {IStargateLPStaking} from "./BorrowableVoid/IStargateLPStaking.sol";

/**
 *  @title ICygnusBorrowVoid
 */
interface ICygnusBorrowVoid is ICygnusBorrowModel {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error OnlyAccountsAllowed Reverts when the transaction origin and sender are different
     */
    error CygnusBorrowVoid__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @custom:error DstReceiverNotValid Reverts if the receiver of the swap is not this contract
     */
    error CygnusBorrowVoid__DstReceiverNotValid(address dstReceiver, address receiver);

    /**
     *  @custom:error SwapNotAllowed Reverts if the token received is not underlying
     */
    error CygnusBorrowVoid__DstTokenNotValid(address dstToken, address token);

    /**
     *  @custom:error SrcTokenNotValid Reverts if the src token we are swapping is not the rewards token
     */
    error CygnusBorrowVoid__SrcTokenNotValid(address srcToken, address token);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Emitted when admin implements strategy or re-approves contracts
     *  @param underlying The address of the underlying stablecoin
     *  @param shuttleId The unique ID of the lending pool
     *  @param sender The address of the msg.sender (admin)
     *  @custom:event ChargeVoid Logs when the strategy is first initialized or re-approves contracts
     */
    event ChargeVoid(address underlying, uint256 shuttleId, address sender);

    /**
     *  @notice Emitted when user reinvests rewards
     *  @param reinvestor The address of the caller who reinvested reward and received bounty
     *  @param rewardBalance The amount of `rewardsToken` reinvested
     *  @param reinvestReward The reward received by the reinvestor
     *  @param daoReward The reward received by the DAO
     *  @param underlyingReceived The amount of underlying stablecoin reinvested
     *  @custom:event RechargeVoid Logs when rewards from the STG rewarder to buy more underlying
     */
    event RechargeVoid(
        address indexed reinvestor,
        uint256 rewardBalance,
        uint256 reinvestReward,
        uint256 daoReward,
        uint256 underlyingReceived
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
     *  @notice Returns the borrowable strategy
     *  @return stgPid The Pool ID for the S*Underlying token
     *  @return stgRouterPoolId The Pool ID for the Stargate Router for underlying deposits (stablecoin)
     *  @return stgPool The address of Stargate's pool for the underlying
     *  @return stgRouter The address of Stargate's router on this chain
     *  @return stgRewarder The address of the rewarder (STG/OP/etc.)
     *  @return rewardsToken The address of the rewards token
     *  @return aggregationRouterV5 The address of the router used to perform the swaps form rewards into underlying
     */
    function getCygnusVoid()
        external
        view
        returns (
            uint256 stgPid,
            uint256 stgRouterPoolId,
            IStargatePool stgPool,
            IStargateRouter stgRouter,
            IStargateLPStaking stgRewarder,
            address rewardsToken,
            IAggregationRouterV5 aggregationRouterV5
        );

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
     *  @notice Get the pending rewards manually
     *  @return pendingReward The amount of rewards in `rewardsToken` pending to harvest
     *  @custom:security non-reentrant only-eoa
     */
    function getRewards() external returns (uint256 pendingReward);

    /**
     *  @notice Reinvests all rewards from the rewarder to buy more USD to then deposit back into the rewarder
     *          This makes totalBalance increase in this contract, increasing the exchangeRate between
     *          CygUSD and underlying and thus lowering utilization rate and borrow arte
     *  @param swapData 1inch calldata for swapping rewards to underlying
     *  @custom:security non-reentrant only-eoa
     */
    function reinvestRewards_y7b(bytes memory swapData) external;
}
