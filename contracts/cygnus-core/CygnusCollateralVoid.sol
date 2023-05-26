// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusCollateralVoid} from "./interfaces/ICygnusCollateralVoid.sol";
import {CygnusCollateralModel} from "./CygnusCollateralModel.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IOrbiter} from "./interfaces/IOrbiter.sol";
import {IHangar18} from "./interfaces/IHangar18.sol";
import {ICygnusHarvester} from "./interfaces/ICygnusHarvester.sol";

// Strategy
import {IRewarder, IMiniChefV2} from "./interfaces/CollateralVoid/IMiniChefV2.sol";

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

    /**
     *  @notice Address of the Rewarder contract
     */
    IMiniChefV2 private constant REWARDER = IMiniChefV2(0xB25157bF349295a7Cd31D1751973f426182070D6);

    /**
     *  @notice Address of the main reward token
     */
    address private constant SUSHI = 0x3eaEb77b03dBc0F6321AE1b72b2E9aDb0F60112B;

    /**
     *  @notice Pool ID this lpTokenPair corresponds to in `rewarder`
     */
    uint256 private sushiPoolId = type(uint256).max;

    /*  ─────────────────────────────────────────────── Public ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    ICygnusHarvester public override harvester;

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
        // Return the contract that rewards us with `rewardsToken`
        return SUSHI;
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
        if (IERC20(token).allowance(address(this), to) >= amount) {
            return;
        }

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
        REWARDER.harvest(sushiPoolId, address(this));

        // Get bonus rewards address from the REWARDER contract
        address bonusRewarder = REWARDER.rewarder(sushiPoolId);

        // If there is a bonus rewarder, harvest and swap all rewards to the bonus reward token
        if (bonusRewarder != address(0)) {
            // Get all reward tokens and amounts from the bonus rewarder contract
            (address[] memory bonusTokens, ) = IRewarder(bonusRewarder).pendingTokens(sushiPoolId, address(this), 0);

            // Create array to hold the reward tokens
            tokens = new address[](2);
            // Create array to hold the reward amounts
            amounts = new uint256[](2);

            // Base token
            tokens[0] = SUSHI;
            // Base amount
            amounts[0] = contractBalanceOf(SUSHI);

            // Bonus reward token
            tokens[1] = bonusTokens[0];
            // Bonus reward amount
            amounts[1] = contractBalanceOf(bonusTokens[0]);
        }
        // Single reward
        else {
            // Create array to hold the reward tokens
            tokens = new address[](1);
            // Create array to hold the reward amounts
            amounts = new uint256[](1);

            // Add only the rewardToken token to the token array
            tokens[0] = SUSHI; // rewardToken token
            // Add the pending rewardToken amount to the amounts array
            amounts[0] = contractBalanceOf(SUSHI); // Pending rewardToken
        }
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Preview total balance from the LP strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function previewTotalBalance() internal view override(CygnusTerminal) returns (uint256 balance) {
        // Get this contracts deposited LP amount
        (balance, ) = REWARDER.userInfo(sushiPoolId, address(this));
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @param assets The amount of assets to withdraw from the strategy
     *  @inheritdoc CygnusTerminal
     */
    function beforeWithdrawInternal(uint256 assets) internal override(CygnusTerminal) {
        // Withdraw assets from the strategy
        REWARDER.withdraw(sushiPoolId, assets, address(this));
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @param assets The amount of assets to deposit in the strategy
     *  @inheritdoc CygnusTerminal
     */
    function afterDepositInternal(uint256 assets) internal override(CygnusTerminal) {
        // Deposit assets into the strategy
        REWARDER.deposit(sushiPoolId, assets, address(this));
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
     */
    function chargeVoid() external override nonReentrant {
        // Charge with pool ID only once (pool Id is never -1)
        if (sushiPoolId == type(uint256).max) {
            // Get total length
            uint256 rewarderLength = REWARDER.poolLength();

            // Loop through total length and get underlying LP
            for (uint256 i = 0; i < rewarderLength; i++) {
                // Get the underlying LP in rewarder at length `i`
                address _underlying = REWARDER.lpToken(i);

                // If same LP then assign pool ID to `i`
                if (_underlying == underlying) {
                    // Assign pool Id;
                    sushiPoolId = i;

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
     *  @custom:security non-reentrant
     */
    // prettier-ignore
    function getRewards() external override nonReentrant returns (address[] memory tokens, uint256[] memory amounts) {
        // Harvest rewards and return tokens and amounts
        return getRewardsPrivate();
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
     */
    function reinvestRewards_y7b(uint256 liquidity) external override nonReentrant update {
        /// @custom:error OnlyHarvesterAllowed Avoid call if msg.sender is not the harvester
        if (msg.sender != address(harvester)) revert CygnusCollateralVoid__OnlyHarvesterAllowed();

        // After deposit hook
        afterDepositInternal(liquidity);

        /// @custom:event RechargeVoid
        emit RechargeVoid(msg.sender, liquidity, lastReinvest = block.timestamp);
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security only-admin 👽
     */
    function setHarvester(ICygnusHarvester _harvester) external override cygnusAdmin {
        // Old harvester
        ICygnusHarvester oldHarvester = harvester;

        // Assign harvester.
        harvester = _harvester;

        // Get reward tokens for the harvester.
        // We harvest once to get the tokens and set approvals in case reward tokens/harvester change.
        // NOTE: This is safe because reward token is never underlying
        (address[] memory tokens, ) = getRewardsPrivate();

        // Loop through each token
        for (uint256 i = 0; i < tokens.length; i++) {
            // Approve harvester in token `i`
            if (tokens[i] != underlying) approveTokenPrivate(tokens[i], address(_harvester), type(uint256).max);
        }

        /// @custom:event NewHarvester
        emit NewHarvester(oldHarvester, _harvester);
    }
}
