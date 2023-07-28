//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusBorrowVoid.sol
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
import {ICygnusBorrowVoid} from "./interfaces/ICygnusBorrowVoid.sol";
import {CygnusBorrowModel} from "./CygnusBorrowModel.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";

// Strategy
import {IComet} from "./interfaces/BorrowableVoid/IComet.sol";
import {ICometRewards} from "./interfaces/BorrowableVoid/ICometRewards.sol";

// Overrides
import {CygnusTerminal} from "./CygnusTerminal.sol";

/**
 *  @title  CygnusBorrowVoid The strategy contract for the underlying stablecoin
 *  @author CygnusDAO
 *  @notice Strategy for the underlying stablecoin deposits.
 */
contract CygnusBorrowVoid is ICygnusBorrowVoid, CygnusBorrowModel {
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

    /**
     *  @notice CompoundV3's USDC
     */
    IComet private constant COMET_USDC = IComet(0xF25212E676D1F7F89Cd72fFEe66158f541246445);

    /**
     *  @notice Rewarder
     */
    ICometRewards private constant COMET_REWARDS = ICometRewards(0x45939657d1CA34A8FA39A924B71D28Fe8431e581);

    /**
     *  @notice Address of the COMP token on this chain
     */
    address private constant COMP = 0x8505b9d2254A7Ae468c0E9dd10Ccea3A837aef5c;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    address public override harvester;

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    uint256 public override lastHarvest;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Cygnus Void contract which handles the strategy for the borrowable`s underlying.
     */
    constructor() {}

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Overrides the previous modifier from CygnusTerminal to update before interactions too
     *  @notice CygnusTerminal override
     *  @custom:modifier update Updates the total balance var in terms of its underlying
     */
    modifier update() override(CygnusTerminal) {
        // Accrue interest before any state changing action
        _accrueInterest();
        // Update before deposit to prevent deposit spam for yield bearing tokens
        _update();
        _;
        // Update after deposit
        _update();
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    function rewarder() external pure override returns (address) {
        // Return the contract that rewards us with `rewardsToken`
        return address(COMET_REWARDS);
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    function rewardToken() external pure override returns (address) {
        // Return the address of the main reward tokn
        return COMP;
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
     *  @notice Gets the rewards from the stgRewarder contract
     */
    function getRewardsPrivate() private returns (address[] memory tokens, uint256[] memory amounts) {
        // Harvest COMP
        COMET_REWARDS.claim(address(COMET_USDC), address(this), true);

        // Single reward token array
        tokens = new address[](1);

        // Single reward amount
        amounts = new uint256[](1);

        // Get reward token
        tokens[0] = COMP;

        // We always return our balance of the reward token
        amounts[0] = _checkBalance(COMP);

        /// @custom:event RechargeVoid
        emit RechargeVoid(msg.sender, lastHarvest = block.timestamp);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Preview total balance from the Stargate strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function _previewTotalBalance() internal view override(CygnusTerminal) returns (uint256 balance) {
        // Return latest balance of Comet
        balance = COMET_USDC.balanceOf(address(this));
    }

    /**
     *  @notice Deposits underlying assets in the strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function _afterDeposit(uint256 assets) internal override(CygnusTerminal) {
        // Supply USD to Comet
        COMET_USDC.supply(underlying, assets);
    }

    /**
     *  @notice Withdraws underlying assets from the strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function _beforeWithdraw(uint256 assets) internal override(CygnusTerminal) {
        // Withdraw USD from Comet
        COMET_USDC.withdraw(underlying, assets);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security non-reentrant
     */
    function getRewards() external override nonReentrant update returns (address[] memory tokens, uint256[] memory amounts) {
        // The harvester contract calls this function to harvest the rewards. Anyone can call
        // this function, but the rewards can only be moved by the harvester contract itself
        return getRewardsPrivate();
    }

    /**
     *  @notice Not marked as non-reentrant since only trusted harvester can call which does safety checks
     *  @inheritdoc ICygnusBorrowVoid
     */
    function reinvestRewards_y7b(uint256 liquidity) external override update {
        /// @custom:error OnlyHarvesterAllowed Avoid call if msg.sender is not the harvester
        if (msg.sender != harvester) revert CygnusBorrowVoid__OnlyHarvesterAllowed();

        // After deposit hook
        _afterDeposit(liquidity);
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security only-admin 👽
     */
    function chargeVoid() external override cygnusAdmin {
        // Allow Stargate router to use our USDC to deposits
        approveTokenPrivate(underlying, address(COMET_USDC), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(underlying, shuttleId, msg.sender);
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
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
            if (tokens[i] != underlying && tokens[i] != address(COMET_USDC)) {
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
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security only-admin 👽
     */
    function sweepToken(address token, address to) external override cygnusAdmin {
        /// @custom;error CantSweepUnderlying Avoid sweeping underlying
        if (token == underlying || token == address(COMET_USDC)) revert CygnusBorrowVoid__TokenIsUnderlying();

        // Get balance of token
        uint256 balance = _checkBalance(token);

        // Transfer token balance to `to`
        token.safeTransfer(to, balance);
    }
}
