//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusStrategyBase.sol
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

// Hangar18
import {IHangar18} from "./IHangar18.sol";

interface ICygnusVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts if the msg.sender is not a borrowable or collateral
     *
     *  @custom:error MsgSenderNotCygnus
     */
    error CygnusVoid__MsgSenderNotCygnus();
    error CygnusVoid__DstReceiverNotValid();
    error CygnusVoid__SrcTokenNotValid();
    error CygnusVoid__DstTokenNotValid();
    error CygnusVoid__MsgSenderNotAdmin();
    error CygnusVoid__CantSweepUnderlying();
    error CygnusVoid__ParaswapTransactionFailed();
    error CygnusVoid__CantReinvestZero();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @notice Enum for choosing dex aggregators to perform leverage, deleverage and liquidations
    /// @custom:member PARASWAP Pass 0 to use Paraswap
    /// @custom:member ONE_INCH_LEGACY Pass 1 to use 1Inch
    enum DexAggregator {
        PARASWAP,
        ONE_INCH_LEGACY
    }

    /**
     *  @return ONE_INCH_ROUTER_V5 The address of 1inch router on this chain
     */
    function ONE_INCH_ROUTER_V5() external pure returns (address);

    /**
     *  @return PARASWAP_AUGUSTUS_SWAPPER_V5 The address of Paraswap's router on this chain
     */
    function PARASWAP_AUGUSTUS_SWAPPER_V5() external pure returns (address);

    /**
     *  @return underlying The underlying asset (USD stablecoin or Liquidity token)
     */
    function underlying() external view returns (address);

    /**
     *  @return cygnusTerminal The address of the core borrowable or collateral contract
     */
    function cygnusTerminal() external view returns (address);

    /**
     *  @return hangar18 The address of hangar18 in this chain
     */
    function hangar18() external view returns (IHangar18);

    /**
     *  @return nativeToken The address of this chain's native token (WETH, WFTM, etc.)
     */
    function nativeToken() external view returns (address);

    /**
     *  @return usd The address of USDC in this chain
     */
    function usd() external view returns (address);

    /**
     *  @return shuttleId The id of the lending pool
     */
    function shuttleId() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Sweeps a token that was incorrectly sent to this address
     *
     *  @param token The address of the token being swept
     *  @custom:security only-admin
     */
    function sweepToken(address token) external;

    // To implement

    /**
     *  @return name The name for this strategy
     */
    function name() external view returns (string memory);

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
     *  @notice Reinvests all rewards from the rewarder to buy more USD to then deposit back into the rewarder
     *          This makes totalBalance increase in this contract, increasing the exchangeRate between
     *          CygUSD and underlying and thus lowering utilization rate and borrow rate
     *
     *  @custom:security non-reentrant
     */
    function reinvestRewards_y7b(DexAggregator dexAggregator, bytes[] calldata swapdata) external;

    /**
     *  @notice Deposits tokens in the strategy, only callable by core
     */
    function deposit(uint256 assets) external;

    /**
     *  @notice Withdraws assets from the strategy
     */
    function redeem(uint256 assets) external;
}
