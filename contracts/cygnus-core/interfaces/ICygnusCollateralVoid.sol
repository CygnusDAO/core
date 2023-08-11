//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusCollateralVoid.sol
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

// Dependencies
import {ICygnusCollateralModel} from "./ICygnusCollateralModel.sol";

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

    /**
     *  @dev Reverts if the token we are sweeping is the underlying LP
     *
     *  @custom:error TokenIsUnderlying
     */
    error CygnusCollateralVoid__TokenIsUnderlying();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when the strategy is first initialized or re-approves contracts
     *
     *  @param underlying The address of the underlying stablecoin
     *  @param shuttleId The unique ID of the lending pool
     *  @param whitelisted The contract we approved to use our underlying
     *
     *  @custom:event ChargeVoid
     */
    event ChargeVoid(address underlying, uint256 shuttleId, address whitelisted);

    /**
     *  @dev Logs when a user claims rewards
     *
     *  @param reinvestor The address of the caller who claimed the rewards
     *  @param timestamp The timestamp of the harvest
     *
     *  @custom:event RechargeVoid
     */
    event RechargeVoid(address indexed reinvestor, uint256 timestamp);

    /**
     *  @dev Logs when admin sets a new harvester to reinvest rewards
     *
     *  @param oldHarvester The address of the old harvester
     *  @param newHarvester The address of the new harvester
     *
     *  @custom:event NewHarvester
     */
    event NewHarvester(address oldHarvester, address newHarvester);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return harvester The address of the harvester contract
     */
    function harvester() external view returns (address);

    /**
     *  @return lastHarvest Timestamp of the last harvest performed by the harvester contract
     */
    function lastHarvest() external view returns (uint256);

    /**
     *  @notice Array of reward tokens for this pool
     *  @param index The index of the token in the array
     *  @return rewardToken The reward token
     */
    function allRewardTokens(uint256 index) external view returns (address rewardToken);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @return rewarder The address of the rewarder contract
     */
    function rewarder() external view returns (address);

    /**
     *  @return rewardTokensLength Length of reward tokens
     */
    function rewardTokensLength() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Get the pending rewards manually - helpful to get rewards through static calls
     *
     *  @return tokens The addresses of the reward tokens earned by harvesting rewards
     *  @return amounts The amounts of each token received
     *
     *  @custom:security non-reentrant
     */
    function getRewards() external returns (address[] memory tokens, uint256[] memory amounts);

    /**
     *  @notice Only the harvester can reinvest
     *  @notice Reinvests all rewards from the rewarder to buy more LP to then deposit back into the rewarder
     *          This makes totalBalance increase in this contract, increasing the exchangeRate between
     *          CygLP and underlying and thus lowering debt ratio for all borrwers in the pool as they own more LP.
     *
     *  @custom:security only-harvester
     */
    function reinvestRewards_y7b(uint256 liquidity) external;

    /**
     *  @notice Admin 👽
     *  @notice Can be called by anyone. Charges approvals needed for deposits and withdrawals, and any other function
     *          needed to get the vault started. ie, setting a pool ID from a MasterChef, a gauge, etc.
     *  @custom:security only-admin
     */
    function chargeVoid() external;

    /**
     *  @notice Admin 👽
     *  @notice Sets the harvester address to harvest and reinvest rewards into more underlying
     *
     *  @param _harvester The address of the new harvester contract
     *
     *  @custom:security only-admin
     */
    function setHarvester(address _harvester, address[] calldata rewardTokens) external;

    /**
     *  @notice Admin 👽
     *  @notice Sweeps a token that was sent to this address by mistake, or a bonus reward token we are not tracking. Cannot
     *          sweep the underlying LP
     *  @custom:security only-admin
     */
    function sweepToken(address token, address to) external;
}
