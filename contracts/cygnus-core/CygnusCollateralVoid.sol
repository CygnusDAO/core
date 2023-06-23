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
import {IVeloGauge} from "./interfaces/CollateralVoid/IVeloGauge.sol";
import {IVeloVoter} from "./interfaces/CollateralVoid/IVeloVoter.sol";

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
     *  @notice Velodrome voter to get gauge
     */
    IVeloVoter private constant VOTER = IVeloVoter(0x09236cfF45047DBee6B921e00704bed6D6B8Cf7e);

    /**
     *  @notice Address of the Rewarder contract
     */
    IVeloGauge private immutable gauge;

    /**
     *  @notice Rewards token - gas savings since the other tokens in `rewards(i)` do not earn rewards
     */
    address private constant VELO = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    address public override harvester;

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public override lastReinvest;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Cygnus Void contract which handles the strategy for the collateral`s underlying.
     */
    constructor() {
        // Get asset from factory to get the gauge (underlying is immutable so can't read)
        (, address asset, , , ) = IOrbiter(msg.sender).shuttleParameters();

        // Store pool ID from rewarder contract
        gauge = IVeloGauge(VOTER.gauges(asset));
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    function rewarder() external view override returns (address) {
        // Return the contract that rewards us with `rewardsToken`
        return address(gauge);
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    function rewardToken() external pure override returns (address) {
        // Return the address of the main reward tokn
        return VELO;
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
        // Create array of reward tokens length
        tokens = new address[](1);

        // Create array of reward amounts length
        amounts = new uint256[](1);

        // Get address of reward token `i` from gauge
        tokens[0] = VELO;

        // Harvest VELO rewards
        gauge.getReward(address(this), tokens);

        // Get our balance
        amounts[0] = _checkBalance(VELO);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Preview total balance from the LP strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function _previewTotalBalance() internal view override(CygnusTerminal) returns (uint256 balance) {
        // Get this contracts deposited LP amount from Velo gauge
        balance = _checkBalance(address(gauge));
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of assets to deposit in the strategy
     */
    function _afterDeposit(uint256 assets) internal override(CygnusTerminal) {
        // Deposit assets into the strategy with no tokenId
        gauge.deposit(assets, 0);
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of assets to withdraw from the strategy
     */
    function _beforeWithdraw(uint256 assets) internal override(CygnusTerminal) {
        // Withdraw assets from the strategy
        gauge.withdraw(assets);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    function chargeVoid() external override {
        // Allow rewarder to access our underlying
        approveTokenPrivate(underlying, address(gauge), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(underlying, shuttleId, msg.sender);
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
     */
    function getRewards() external override nonReentrant returns (address[] memory tokens, uint256[] memory amounts) {
        // Harvest rewards and return tokens and amounts
        return getRewardsPrivate();
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    function reinvestRewards_y7b(uint256 liquidity) external override update {
        /// @custom:error OnlyHarvesterAllowed Avoid call if msg.sender is not the harvester
        if (msg.sender != address(harvester)) revert CygnusCollateralVoid__OnlyHarvesterAllowed();

        // After deposit hook
        _afterDeposit(liquidity);

        /// @custom:event RechargeVoid
        emit RechargeVoid(msg.sender, liquidity, lastReinvest = block.timestamp);
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security only-admin 👽
     */
    function setHarvester(address _harvester) external override cygnusAdmin {
        // Old harvester
        address oldHarvester = harvester;

        // Assign harvester.
        harvester = _harvester;

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

        /// @custom:event NewHarvester
        emit NewHarvester(oldHarvester, _harvester);
    }
}
