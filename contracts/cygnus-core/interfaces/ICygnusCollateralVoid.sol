// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusCollateralModel} from "./ICygnusCollateralModel.sol";
import {ICygnusHarvester} from "./ICygnusHarvester.sol";

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
     *  @dev Reverts if msg.sender is not the harvester
     *
     *  @custom:error OnlyHarvesterAllowed
     */
    error CygnusCollateralVoid__OnlyHarvesterAllowed();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when the strategy is first initialized or re-approves contracts
     *
     *  @param underlying The address of the underlying stablecoin
     *  @param shuttleId The unique ID of the lending pool
     *  @param sender The address of the msg.sender (admin)
     *
     *  @custom:event ChargeVoid
     */
    event ChargeVoid(address underlying, uint256 shuttleId, address sender);

    /**
     *  @dev Logs when user reinvests rewards
     *
     *  @param reinvestor The address of the caller who reinvested reward and received bounty
     *  @param liquidity The amount of underlying LP received and reinvested
     *  @param timestamp The timestamp of the reinvest
     *
     *  @custom:event RechargeVoid
     */
    event RechargeVoid(address indexed reinvestor, uint256 liquidity, uint256 timestamp);

    /**
     *  @dev Logs when admin sets a new harvester to reinvest rewards
     *
     *  @param oldHarvester The address of the old harvester
     *  @param newHarvester The address of the new harvester
     *
     *  @custom:event NewHarvester
     */
    event NewHarvester(ICygnusHarvester oldHarvester, ICygnusHarvester newHarvester);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return harvester The address of the harvester contract
     */
    function harvester() external view returns (ICygnusHarvester);

    /**
     *  @return lastReinvest Timestamp of the last reinvest performed by the harvester contract
     */
    function lastReinvest() external view returns (uint256);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @return rewarder The address of the rewarder contract
     */
    function rewarder() external view returns (address);

    /**
     *  @return rewardToken The address of the main reward token
     */
    function rewardToken() external view returns (address);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Can be called by anyone
     *  @notice Charges approvals needed for deposits and withdrawals along with setting rewarders (if any)
     *
     *  @custom:security non-reentrant
     */
    function chargeVoid() external;

    /**
     *  @notice Only EOA can call
     *  @notice Get the pending rewards manually - helpful to get rewards through static calls
     *
     *  @return tokens The addresses of the reward tokens earned by harvesting rewards
     *  @return amounts The amounts of each token received
     *
     *  @custom:security non-reentrant
     */
    function getRewards() external returns (address[] memory tokens, uint256[] memory amounts);

    /**
     *  @notice Only EOA can call
     *  @notice Reinvests all rewards from the rewarder to buy more USD to then deposit back into the rewarder
     *          This makes totalBalance increase in this contract, increasing the exchangeRate between
     *          CygUSD and underlying and thus lowering utilization rate and borrow rate
     *
     *  @custom:security non-reentrant
     */
    function reinvestRewards_y7b(uint256 liquidity) external;

    // Admin

    /**
     *  @notice Admin 👽
     *  @notice Sets the harvester address to harvest and reinvest rewards into more underlying
     *
     *  @param _harvester The address of the new harvester contract
     *
     *  @custom:security non-reentrant only-admin
     */
    function setHarvester(ICygnusHarvester _harvester) external;
}
