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

    /*  ──────── Strategy ────────  */

    /**
     *  @notice CompoundV3's USDC
     */
    IComet private constant COMET_USDC = IComet(0xF25212E676D1F7F89Cd72fFEe66158f541246445);

    /**
     *  @notice Rewarder
     */
    ICometRewards private constant COMET_REWARDS = ICometRewards(0x45939657d1CA34A8FA39A924B71D28Fe8431e581);

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    address[] public override allRewardTokens;

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
        // Harvest COMP
        COMET_REWARDS.claim(address(COMET_USDC), address(this), true);
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
            // Check for underlying/strategy token
            if (tokens[i] != underlying && tokens[i] != address(COMET_USDC)) {
                // Approve harvester
                tokens[i].safeApprove(_harvester, type(uint256).max);
            }
        }
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

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
    function getRewards() external override nonReentrant returns (address[] memory tokens, uint256[] memory amounts) {
        // The harvester contract calls this function to harvest the rewards. Anyone can call
        // this function, but the rewards can only be moved by the harvester contract itself
        return getRewardsPrivate();
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security non-reentrant
     */
    function reinvestRewards_y7b(uint256 liquidity) external override nonReentrant update {
        /// @custom:error OnlyHarvesterAllowed Avoid call if msg.sender is not the harvester
        if (msg.sender != harvester) revert CygnusBorrowVoid__OnlyHarvesterAllowed();

        // After deposit hook, doesn't mint any shares. The contract should have already received
        // the underlying stablecoin
        _afterDeposit(liquidity);
    }

    /*  ────────── Admin ─────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security only-admin 👽
     */
    function chargeVoid() external override cygnusAdmin {
        // Allow Stargate router to use our USDC to deposits
        underlying.safeApprove(address(COMET_USDC), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(underlying, shuttleId, address(COMET_USDC));
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
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
