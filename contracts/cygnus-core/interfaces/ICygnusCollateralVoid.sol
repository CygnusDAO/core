// SPDX-License-Identifier: Unlicensed

pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralControl } from "./ICygnusCollateralControl.sol";

// Interfaces
import { IDexPair } from "./IDexPair.sol";
import { IDexRouter02 } from "./IDexRouter.sol";
import { IMiniChef } from "./IMiniChef.sol";

/**
 *  @title ICygnusCollateralVoid The interface for the masterchef
 */
interface ICygnusCollateralVoid is ICygnusCollateralControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error InvalidRewardsToken The rewards token can't be the zero address
     */
    error CygnusCollateralChef__VoidAlreadyInitialized(address tokenReward);

    /**
     *  @custom:error OnlyAccountsAllowed Avoid contracts
     */
    error CygnusCollateralChef__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @custom:error NotNativeTokenSender Avoid receiving unless sender is native token
     */
    error CygnusCollateralVoid__NotNativeTokenSender(address sender, address origin);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Logs when the chef is initialized and rewards can be reinvested
     *  @param _dexRouter The address of the router that is used by the DEX (must be UniswapV2 compatible)
     *  @param _rewarder The address of the masterchef or rewarder contract (Must be compatible with masterchef)
     *  @param _rewardsToken The address of the token that rewards are paid in
     *  @param _pid The Pool ID of this LP Token pair in Masterchef's contract
     *  @param _swapFeeFactor The swap fee factor used by this DEX
     *  @custom:event Reinvest Emitted when reinvesting rewards from Masterchef
     */
    event ChargeVoid(
        IDexRouter02 _dexRouter,
        IMiniChef _rewarder,
        address _rewardsToken,
        uint256 _pid,
        uint256 _swapFeeFactor
    );

    /**
     *  @notice Logs when rewards are reinvested
     *  @param shuttle The address of this shuttle
     *  @param reinvestor The address of the caller who reinvested reward and receives bounty
     *  @param rewardBalance The amount reinvested
     *  @param reinvestReward The reward received by the reinvestor
     *  @custom:event Reinvest Emitted when reinvesting rewards from Masterchef
     */
    event RechargeVoid(address indexed shuttle, address reinvestor, uint256 rewardBalance, uint256 reinvestReward);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @return REINVEST_REWARD The % of rewards paid to the user who reinvested this shuttle's rewards to buy more LP
     */
    function REINVEST_REWARD() external view returns (uint256);

    /**
     *  @notice Returns this contract's void values (if activated) showing the masterchef address, pool id, etc.
     *  @return rewarder_ The address of the masterchef/rewarder
     *  @return pid_ The pool ID the collateral's underlying LP Token belongs to in the masterchef/rewarder
     *  @return voidActivated_ Whether or not this contract has the void activated
     *  @return rewardsToken_ The address of the rewards token from the Dex
     *  @return dexSwapFee_ The fee the dex charges for swaps (divided by 1000 ie Uniswap charges 0.3%, swap fee is 997)
     *  @return dexRouter_ The address of the dex' router used to swap between tokens
     */
    function getCygnusVoid()
        external
        view
        returns (
            IMiniChef rewarder_,
            uint256 pid_,
            bool voidActivated_,
            address rewardsToken_,
            uint256 dexSwapFee_,
            IDexRouter02 dexRouter_
        );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Initializes the chef to reinvest rewards
     *  @param _dexRouter The address of the router that is used by the DEX that owns the liquidity pool
     *  @param _rewarder The address of the masterchef or rewarder contract (Must be compatible with masterchef)
     *  @param _rewardsToken The address of the token that rewards are paid in
     *  @param _pid The Pool ID of this LP Token pair in Masterchef's contract
     *  @param _swapFeeFactor The swap fee factor used by this DEX
     *  @custom:security non-reentrant
     */
    function initializeVoid(
        IDexRouter02 _dexRouter,
        IMiniChef _rewarder,
        address _rewardsToken,
        uint256 _pid,
        uint256 _swapFeeFactor
    ) external;

    /**
     *  @notice Reinvests all rewards from the masterchef to buy more LP Tokens to deposit in the masterchef.
     *          This makes totalBalance increase in this contract, increasing the exchangeRate between
     *          CygnusLP and underlying, thus lowering user's debt ratios
     *  @custom:security non-reentrant
     */
    function reinvestRewards() external;
}
