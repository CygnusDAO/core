// SPDX-License-Identifier: Unlicensed

pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralControl } from "./ICygnusCollateralControl.sol";

// Interfaces
import { IDexRouter02 } from "./IDexRouter.sol";
import { IMiniChef } from "./IMiniChef.sol";

/**
 *  @title ICygnusCollateralVoid
 *  @notice Interface for `CygnusCollateralVoid` which is in charge of connecting the collateral LP Tokens with
 *          a specified strategy (for example connect to a rewarder contract to stake the LP Token, etc.)
 */
interface ICygnusCollateralVoid is ICygnusCollateralControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error OnlyAccountsAllowed Reverts when the transaction origin and sender are different
     */
    error CygnusCollateralChef__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @custom:error InvalidRewardsToken Reverts when initializing the Void twice
     */
    error CygnusCollateralChef__VoidAlreadyInitialized(address tokenReward);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @param _dexRouter The address of the router that is used by the DEX (must be UniswapV2 compatible)
     *  @param _rewarder The address of the rewarder contract
     *  @param _rewardsToken The address of the token that rewards are paid in
     *  @param _pid The Pool ID of this LP Token pair in Masterchef's contract
     *  @param _swapFeeFactor The swap fee factor used by this DEX
     *  @custom:event ChargeVoid Logs when the strategy is first initialized
     */
    event ChargeVoid(
        IDexRouter02 _dexRouter,
        IMiniChef _rewarder,
        address _rewardsToken,
        uint256 _pid,
        uint256 _swapFeeFactor
    );

    /**
     *  @param shuttle The address of this lending pool
     *  @param reinvestor The address of the caller who reinvested reward and received bounty
     *  @param rewardBalance The amount reinvested
     *  @param reinvestReward The reward received by the reinvestor
     *  @custom:event RechargeVoid Logs when rewards from the Masterchef/Rewarder are reinvested into more LP Tokens
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
     *  @notice Getter for this contract's void values (if activated) showing the rewarder address, pool id, etc.
     *  @return _rewarder The address of the rewarder
     *  @return _dexRouter The address of the dex' router used to swap between tokens
     *  @return _rewardsToken The address of the rewards token from the Dex
     *  @return _pid The pool ID the collateral's underlying LP Token belongs to in the rewarder
     *  @return _dexSwapFee The fee the dex charges for swaps (divided by 1000 ie Uniswap charges 0.3%, swap fee is 997)
     */
    function getCygnusVoid()
        external
        view
        returns (
            IMiniChef _rewarder,
            IDexRouter02 _dexRouter,
            address _rewardsToken,
            uint256 _pid,
            uint256 _dexSwapFee
        );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice 👽
     *  @notice Initializes the rewarder for this pool
     *  @param _dexRouter The address of the router that is used by the DEX that owns the liquidity pool
     *  @param _rewarder The address of the rewarder contract
     *  @param _rewardsToken The address of the token that rewards are paid in
     *  @param _pid The Pool ID of this LP Token pair in Masterchef's contract
     *  @param _swapFeeFactor The swap fee factor used by this DEX
     *  @custom:security non-reentrant
     */
    function chargeVoid(
        IDexRouter02 _dexRouter,
        IMiniChef _rewarder,
        address _rewardsToken,
        uint256 _pid,
        uint256 _swapFeeFactor
    ) external;

    /**
     *  @notice Reinvests all rewards from the rewarder to buy more LP Tokens to then deposit back into the rewarder
     *          This makes totalBalance increase in this contract, increasing the exchangeRate between
     *          CygnusLP and underlying, thus lowering user's debt ratios
     *  @custom:security non-reentrant
     */
    function reinvestRewards_y7b() external;
}
