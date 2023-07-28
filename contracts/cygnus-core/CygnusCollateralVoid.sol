//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusCollateralVoid.sol
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
import {ICygnusCollateralVoid} from "./interfaces/ICygnusCollateralVoid.sol";
import {CygnusCollateralModel} from "./CygnusCollateralModel.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IOrbiter} from "./interfaces/IOrbiter.sol";

// Strategy
import {IMiniChefV2, IRewarder} from "./interfaces/CollateralVoid/IMiniChef.sol";

// Overrides
import {CygnusTerminal} from "./CygnusTerminal.sol";

/**
 *  @title  CygnusCollateralVoid The strategy contract for the underlying LP Tokens
 *  @author CygnusDAO
 *  @notice Strategy for the underlying LP deposits.
 */
contract CygnusCollateralVoid is ICygnusCollateralVoid, CygnusCollateralModel {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
     */
    using SafeTransferLib for address;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /*  ─────────── Strategy */

    /**
     *  @notice Gamma's MiniChef
     */
    IMiniChefV2 private constant REWARDER = IMiniChefV2(0x20ec0d06F447d550fC6edee42121bc8C1817b97D);

    /**
     *  @notice Rewards token (Quickswap's DQUICK)
     */
    address private constant DQUICK = 0x958d208Cdf087843e9AD98d23823d32E17d723A1;

    /**
     *  @notice Bonus rewards token
     */
    address private constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    /**
     *  @notice Pool ID this lpTokenPair corresponds to in `rewarder`
     */
    uint256 private masterChefId = type(uint256).max;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    address public override harvester;

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public override lastHarvest;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Cygnus Void contract which handles the strategy for the collateral`s underlying.
     */
    constructor() {}

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    function rewarder() external pure override returns (address) {
        // Return the contract that rewards us with `rewardsToken`
        return address(REWARDER);
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    function rewardToken() external pure override returns (address) {
        // Return the address of the main reward tokn
        return DQUICK;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract
     *  @param token The address of the token we are approving
     *  @param amount The amount to approve
     */
    function approveTokenPrivate(address token, address to, uint256 amount) private {
        // Check allowance for `router` for deposit
        if (IERC20(token).allowance(address(this), to) >= amount) return;

        // Is less than amount, safe approve max
        token.safeApprove(to, type(uint256).max);
    }

    /**
     *  @notice Harvest and return the pending reward tokens and mounts interally, used by reinvest function.
     *  @return tokens Array of reward token addresses
     *  @return amounts Array of reward token amounts
     */
    function getRewardsPrivate() private returns (address[] memory tokens, uint256[] memory amounts) {
        // Harvest rewards first
        REWARDER.harvest(masterChefId, address(this));

        // Tokens harvested
        tokens = new address[](2);

        // Amounts harvested
        amounts = new uint256[](2);

        // Token is always dQuick
        tokens[0] = DQUICK;

        // Bonus token is always Matic
        tokens[1] = WMATIC;

        // Amount harvested of dQuick
        amounts[0] = _checkBalance(DQUICK);

        // Amount harvested of wMatic
        amounts[1] = _checkBalance(WMATIC);

        /// @custom:event RechargeVoid
        emit RechargeVoid(msg.sender, lastHarvest = block.timestamp);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Preview total balance from the LP strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function _previewTotalBalance() internal view override(CygnusTerminal) returns (uint256 balance) {
        // Get this contracts deposited LP amount from Velo gauge
        (balance, ) = REWARDER.userInfo(masterChefId, address(this));
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of assets to deposit in the strategy
     */
    function _afterDeposit(uint256 assets) internal override(CygnusTerminal) {
        // Deposit assets into the strategy
        REWARDER.deposit(masterChefId, assets, address(this));
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of assets to withdraw from the strategy
     */
    function _beforeWithdraw(uint256 assets) internal override(CygnusTerminal) {
        // Withdraw assets from the strategy
        REWARDER.withdraw(masterChefId, assets, address(this));
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
     */
    function getRewards() external override nonReentrant update returns (address[] memory tokens, uint256[] memory amounts) {
        // The harvester contract calls this function to harvest the rewards. Anyone can call
        // this function, but the rewards can only be moved by the harvester contract itself
        return getRewardsPrivate();
    }

    /**
     *  @notice Not marked as non-reentrant since only trusted harvester can call which does safety checks
     *  @inheritdoc ICygnusCollateralVoid
     */
    function reinvestRewards_y7b(uint256 liquidity) external override update {
        /// @custom:error OnlyHarvesterAllowed Avoid call if msg.sender is not the harvester
        if (msg.sender != harvester) revert CygnusCollateralVoid__OnlyHarvesterAllowed();

        // After deposit hook
        _afterDeposit(liquidity);
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security only-admin 👽
     */
    function chargeVoid() external override cygnusAdmin {
        // Charge with pool ID only once (pool Id is never -1)
        if (masterChefId == type(uint256).max) {
            // Get total length
            uint256 rewarderLength = REWARDER.poolLength();

            // Loop through total length and get underlying LP
            for (uint256 i = 0; i < rewarderLength; i++) {
                // Get the underlying LP in rewarder at length `i`
                address _underlying = REWARDER.lpToken(i);

                // If same LP then assign pool ID to `i`
                if (_underlying == underlying) {
                    // Assign pool Id;
                    masterChefId = i;

                    // Exit
                    break;
                }
            }
        }

        // Allow rewarder to access our underlying
        approveTokenPrivate(underlying, address(REWARDER), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(underlying, shuttleId, msg.sender);
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security only-admin 👽
     */
    function setHarvester(address _harvester) external override cygnusAdmin {
        // Old harvester
        address oldHarvester = harvester;

        // Get reward tokens for the harvester.
        // We harvest once to get the tokens and set approvals in case reward tokens/harvester change.
        // NOTE: This is safe because approved token is never underlying
        (address[] memory tokens, ) = getRewardsPrivate();

        // Loop through each token
        for (uint256 i = 0; i < tokens.length; i++) {
            // Approve harvester in token `i`
            if (tokens[i] != underlying) {
                // Remove allowance for old harvester
                if (oldHarvester != address(0)) approveTokenPrivate(tokens[i], oldHarvester, 0);

                // Approve new harvester
                approveTokenPrivate(tokens[i], _harvester, type(uint256).max);
            }
        }

        // Assign harvester.
        harvester = _harvester;

        /// @custom:event NewHarvester
        emit NewHarvester(oldHarvester, _harvester);
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security only-admin 👽
     */
    function sweepToken(address token, address to) external override cygnusAdmin {
        /// @custom;error CantSweepUnderlying Avoid sweeping underlying
        if (token == underlying) revert CygnusCollateralVoid__TokenIsUnderlying();

        // Get balance of token
        uint256 balance = _checkBalance(token);

        // Transfer token balance to `to`
        token.safeTransfer(to, balance);
    }
}
