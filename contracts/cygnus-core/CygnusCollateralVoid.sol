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

// Strategy
import {IMiniChefV2} from "./interfaces/CollateralVoid/IMiniChef.sol";
import {IDQuick} from "./interfaces/CollateralVoid/IDQuick.sol";

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
     *  @notice Dragon's lair quick
     */
    address private constant DQUICK = 0x958d208Cdf087843e9AD98d23823d32E17d723A1;

    /**
     *  @notice Pool ID this lpTokenPair corresponds to in `rewarder`
     */
    uint256 private gammaId = type(uint256).max;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    address[] public override allRewardTokens;

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

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return amount This contract's `token` balance
     */
    function _checkBalance(address token) internal view returns (uint256) {
        // Our balance of `token`
        return token.balanceOf(address(this));
    }

    /**
     *  @notice Preview total balance from the LP strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function _previewTotalBalance() internal view override(CygnusTerminal) returns (uint256 balance) {
        // Get this contracts deposited LP amount from Velo gauge
        (balance, ) = REWARDER.userInfo(gammaId, address(this));
    }

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
    function rewardTokensLength() external view override returns (uint256) {
        // Return total reward tokens length
        return allRewardTokens.length;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Harvest the rewards from the strategy
     */
    function harvestRewardsPrivate() private {
        // Harvest rewards first
        REWARDER.harvest(gammaId, address(this));

        // Check for dquick balance
        uint256 dquickBalance = _checkBalance(DQUICK);

        // Redeem dQuick and receive Quick
        if (dquickBalance > 0) IDQuick(DQUICK).leave(dquickBalance);
    }

    /**
     *  @notice Harvest and return the pending reward tokens and mounts interally, used by reinvest function.
     *  @return tokens Array of reward token addresses
     *  @return amounts Array of reward token amounts
     */
    function getRewardsPrivate() private returns (address[] memory tokens, uint256[] memory amounts) {
        // Harvest the rewards from the strategy
        harvestRewardsPrivate();

        // Assign reward tokens and gas savings
        tokens = allRewardTokens;

        // Create array of amounts
        amounts = new uint256[](tokens.length);

        // Loop over each reward token and return balance
        for (uint256 i = 0; i < tokens.length; ) {
            // Assign balance of reward token `i`
            amounts[i] = _checkBalance(tokens[i]);

            // Next iteration
            unchecked {
                i++;
            }
        }

        /// @custom:event RechargeVoid
        emit RechargeVoid(msg.sender, tokens, amounts, lastHarvest = block.timestamp);
    }

    /**
     *  @notice Removes allowances from the harvester
     *  @param _harvester The address of the harvester
     *  @param tokens The old reward tokens
     */
    function removeHarvesterPrivate(address _harvester, address[] memory tokens) private {
        // If no harvester then return
        if (_harvester == address(0)) return;

        // Loop through each token
        for (uint256 i = 0; i < tokens.length; i++) {
            // Remove the harvester's allowance of old tokens
            tokens[i].safeApprove(_harvester, 0);
        }
    }

    /**
     *  @notice Add allowances to the new harvester
     *  @param _harvester The address of the new harvester
     *  @param tokens The new reward tokens
     */
    function addHarvesterPrivate(address _harvester, address[] calldata tokens) private {
        // If no harvester then return
        if (_harvester == address(0)) return;

        // Loop through each token
        for (uint256 i = 0; i < tokens.length; i++) {
            // Check for underlying
            if (tokens[i] != underlying) {
                // Approve harvester in token
                tokens[i].safeApprove(_harvester, type(uint256).max);
            }
        }
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */


    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of assets to deposit in the strategy
     */
    function _afterDeposit(uint256 assets) internal override(CygnusTerminal) {
        // Deposit assets into the strategy
        REWARDER.deposit(gammaId, assets, address(this));
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of assets to withdraw from the strategy
     */
    function _beforeWithdraw(uint256 assets) internal override(CygnusTerminal) {
        // Withdraw assets from the strategy
        REWARDER.withdraw(gammaId, assets, address(this));
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
     */
    function getRewards() external override nonReentrant returns (address[] memory tokens, uint256[] memory amounts) {
        // The harvester contract calls this function to harvest the rewards. Anyone can call
        // this function, but the rewards can only be moved by the harvester contract itself.
        return getRewardsPrivate();
    }

    /**
     *  @notice Updates `_totalBalance` increasing amount of underlying liquidity tokens we own
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant only-harvester
     */
    function reinvestRewards_y7b(uint256 liquidity) external override nonReentrant update {
        /// @custom:error OnlyHarvesterAllowed Avoid call if msg.sender is not the harvester
        if (msg.sender != harvester) revert CygnusCollateralVoid__OnlyHarvesterAllowed();

        // After deposit hook, doesn't mint any shares. The contract should have already received
        // the underlying LP from the harvester.
        _afterDeposit(liquidity);
    }

    /*  ────────  Admin  ────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security only-admin 👽
     */
    function chargeVoid() external override cygnusAdmin {
        // Charge with pool ID only once (pool Id is never -1)
        if (gammaId == type(uint256).max) {
            // Get total length
            uint256 rewarderLength = REWARDER.poolLength();

            // Loop through total length and get underlying LP
            for (uint256 i = 0; i < rewarderLength; i++) {
                // Get the underlying LP in rewarder at length `i`
                address _underlying = REWARDER.lpToken(i);

                // If same LP then assign pool ID to `i`
                if (_underlying == underlying) {
                    // Assign pool Id;
                    gammaId = i;

                    // Exit
                    break;
                }
            }
        }

        // Allow rewarder to access our underlying
        underlying.safeApprove(address(REWARDER), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(underlying, shuttleId, address(REWARDER));
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security only-admin 👽
     */
    function setHarvester(address newHarvester, address[] calldata rewardTokens) external override cygnusAdmin {
        // Old harvester
        address oldHarvester = harvester;

        // Remove allowances from the harvester for `allRewardTokens` up to this point
        removeHarvesterPrivate(oldHarvester, allRewardTokens);

        // Allow new harvester to access the new reward tokens passed
        addHarvesterPrivate(newHarvester, rewardTokens);

        /// @custom:event NewHarvester
        emit NewHarvester(oldHarvester, harvester = newHarvester, allRewardTokens = rewardTokens);
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
