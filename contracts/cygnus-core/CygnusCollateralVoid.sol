// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralVoid } from "./interfaces/ICygnusCollateralVoid.sol";
import { CygnusCollateralModel } from "./CygnusCollateralModel.sol";

// Libraries
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { FixedPointMathLib } from "./libraries/FixedPointMathLib.sol";
import { CygnusDexLib } from "./libraries/CygnusDexLib.sol";

// Interfaces
import { IERC20 } from "./interfaces/IERC20.sol";
import { IDexPair } from "./interfaces/IDexPair.sol";
import { IOrbiter } from "./interfaces/IOrbiter.sol";
import { IHangar18 } from "./interfaces/IHangar18.sol";

// Strategy
import { IDexRouter02 } from "./interfaces/CollateralVoid/IDexRouter.sol";
import { IRewarder, IMiniChef } from "./interfaces/CollateralVoid/IMiniChef.sol";

// Overrides
import { CygnusTerminal } from "./CygnusTerminal.sol";

/**
 *  @title  CygnusCollateralVoid The strategy contract for the underlying LP Tokens
 *  @author CygnusDAO
 *  @notice This contract is considered optional. Vanilla pools (ie those without rewarders) should
 *          only have the constructor of this contract included and nothing else.
 *
 *          It is the only contract in Cygnus that should be changed according to the LP Token's rewarder.
 *          As such most functions are kept private as they are only relevant to this contract and the others
 *          are indifferent to this.
 */
contract CygnusCollateralVoid is ICygnusCollateralVoid, CygnusCollateralModel {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
     */
    using SafeTransferLib for address;

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Pool ID this lpTokenPair corresponds to in `rewarder`
     */
    uint256 private sushiPoolId = type(uint256).max;

    /**
     *  @notice The token that is given as rewards by the dex' rewarder contract
     */
    address private constant REWARDS_TOKEN = 0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a;

    /**
     *  @notice The address of this dex' router
     */
    IDexRouter02 private constant DEX_ROUTER = IDexRouter02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    /**
     *  @notice Address of the Rewarder contract
     */
    IMiniChef private constant REWARDER = IMiniChef(0x0769fd68dFb93167989C6f7254cd0D766Fb2841F);

    /*  ─────────── Immutables for all 2 token pools */

    /**
     *  @notice The chain's native token (WETH) taken from factory
     */
    address private immutable nativeToken;

    /**
     *  @notice The first token from the underlying LP Token
     */
    address private immutable token0;

    /**
     *  @notice The second token from the underlying LP Token
     */
    address private immutable token1;

    /*  ─────────────────────────────────────────────── Public ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public constant override REINVEST_REWARD = 0.04e18;

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public constant override DAO_REWARD = 0.02e18;

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
        // Get factory for nativeToken, and asset for token0 and token1
        (IHangar18 hangar, address asset, , , ) = IOrbiter(_msgSender()).shuttleParameters();

        // Assign as immutables for gas savings
        (token0, token1, nativeToken) = (IDexPair(asset).token0(), IDexPair(asset).token1(), hangar.nativeToken());
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier onlyEOA Modifier which reverts transaction if msg.sender is considered a contract
     */
    modifier onlyEOA() {
        checkEOA();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Reverts if it is not considered an EOA
     */
    function checkEOA() private view {
        /// @custom:error OnlyEOAAllowed Avoid if not called by an externally owned account
        // solhint-disable-next-line
        if (_msgSender() != tx.origin) {
            // solhint-disable-next-line
            revert CygnusCollateralVoid__OnlyEOAAllowed({ sender: _msgSender(), origin: tx.origin });
        }
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    function getCygnusVoid() external view override returns (address, address, address, uint256) {
        // Return all the private storage variables from this contract
        return (address(REWARDER), address(DEX_ROUTER), REWARDS_TOKEN, sushiPoolId);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     * @notice Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract
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
     *  @notice Swap tokens function used by Reinvest to turn reward token into more LP Tokens
     *  @param tokenIn Address of the token we are swapping
     *  @param tokenOut Address of the token we are receiving
     *  @param amount Amount of TokenIn we are swapping
     */
    function swapTokensPrivate(address tokenIn, address tokenOut, uint256 amount) private {
        // Create the path to swap from tokenIn to tokenOut
        address[] memory path = new address[](2);

        // Create path for tokenIn to tokenOut
        (path[0], path[1]) = (tokenIn, tokenOut);

        // Safe Approve router
        approveTokenPrivate(tokenIn, address(DEX_ROUTER), amount);

        // Swap tokens
        DEX_ROUTER.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);
    }

    /**
     *  @notice Gets the rewards from the rewarder contract for multiple tokens and converts to rewardToken
     */
    function getRewardsPrivate() private returns (uint256) {
        // Get bonus rewards address
        address bonusRewarder = REWARDER.rewarder(sushiPoolId);

        // If active then harvest and swap all to reward token
        if (bonusRewarder != address(0)) {
            // Get all reward tokens and amounts
            (address[] memory rewardTokens, uint256[] memory rewardAmounts) = IRewarder(bonusRewarder).pendingTokens(
                sushiPoolId,
                address(this),
                0
            );

            // Harvest Sushi
            REWARDER.harvest(sushiPoolId, address(this));

            // Harvest all tokens and swap to Sushi
            for (uint i = 0; i < rewardTokens.length; i++) {
                if (rewardAmounts[i] > 0) swapTokensPrivate(rewardTokens[i], REWARDS_TOKEN, rewardAmounts[i]);
            }
        }
        // Bonus token rewards not active, Harvest sushi
        else REWARDER.harvest(sushiPoolId, address(this));

        // Return balance harvested
        return contractBalanceOf(REWARDS_TOKEN);
    }

    /**
     *  @notice Function to add liquidity and mint LP Tokens
     *  @param tokenA Address of the LP Token's token0
     *  @param tokenB Address of the LP Token's token1
     *  @param amountA Amount of token A to add as liquidity
     *  @param amountB Amount of token B to add as liquidity
     *  @return liquidity The total LP Tokens minted
     */
    function addLiquidityPrivate(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) private returns (uint256 liquidity) {
        // Check token0 allowance and approve if needed
        approveTokenPrivate(tokenA, address(DEX_ROUTER), amountA);

        // Check token0 allowance and approve if needed
        approveTokenPrivate(tokenB, address(DEX_ROUTER), amountB);

        // Mint liquidity
        (, , liquidity) = DEX_ROUTER.addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp
        );
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
     *  @notice Syncs total balance of this contract with LP token deposits from the rewarder
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function updateInternal() internal override(CygnusTerminal) {
        // Get total balance of LP in the rewarder
        uint256 amountLP = previewTotalBalance();

        // Assign to totalBalance
        totalBalance = amountLP;

        /// @custom:event Sync
        emit Sync(totalBalance);
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of assets to withdraw from the strategy
     */
    function beforeWithdrawInternal(uint256 assets) internal override(CygnusTerminal) {
        // Withdraw assets from the strategy
        REWARDER.withdraw(sushiPoolId, assets, address(this));
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of assets to deposit in the strategy
     */
    function afterDepositInternal(uint256 assets) internal override(CygnusTerminal) {
        // Deposit assets into the strategy
        REWARDER.deposit(sushiPoolId, assets, address(this));
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant only-admin 👽
     */
    function chargeVoid(uint256 _sushiPoolId) external override nonReentrant cygnusAdmin {
        // Avoid initializing pool twice (pool id is never -1)
        if (sushiPoolId == type(uint256).max) {
            // Store pool ID from rewarder contract
            sushiPoolId = _sushiPoolId;
        }

        // Allow rewarder to access our underlying
        approveTokenPrivate(underlying, address(REWARDER), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(underlying, shuttleId, _msgSender());
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant only-eoa
     */
    function getRewards() external override nonReentrant onlyEOA returns (uint256) {
        // Harvest rewards and return `rewardToken` amount
        return getRewardsPrivate();
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant only-eoa
     */
    function reinvestRewards_y7b() external override nonReentrant onlyEOA update {
        // ─────────────────────── 1. Withdraw all rewards
        // Harvest rewards accrued of `rewardToken`
        uint256 currentRewards = getRewardsPrivate();

        // If none accumulated return and do nothing
        if (currentRewards == 0) {
            return;
        }

        // ─────────────────────── 2. Send reward to the reinvestor and vault
        // Calculate reward for user (REINVEST_REWARD %)
        uint256 eoaReward = currentRewards.mulWad(REINVEST_REWARD);
        // Transfer the reward to the reinvestor
        REWARDS_TOKEN.safeTransfer(_msgSender(), eoaReward);

        // Calculate reward for DAO (DAO_REWARD %)
        uint256 daoReward = currentRewards.mulWad(DAO_REWARD);
        // Get the current DAO reserves contract
        address daoReserves = IHangar18(hangar18).daoReserves();
        // Transfer the reward to the DAO vault
        REWARDS_TOKEN.safeTransfer(daoReserves, daoReward);

        // ─────────────────────── 3. Convert all rewardsToken to tokenA and assign
        // Placeholders to sort tokens
        address tokenA;
        address tokenB;

        // Check if rewards token is already token0 or token1 from LP
        if (token0 == REWARDS_TOKEN || token1 == REWARDS_TOKEN) {
            // Check which token is rewardsToken
            (tokenA, tokenB) = token0 == REWARDS_TOKEN ? (token0, token1) : (token1, token0);
        } else {
            // Swap token reward token to native token
            swapTokensPrivate(REWARDS_TOKEN, nativeToken, currentRewards - eoaReward - daoReward);

            // Check if token0 or token1 is native token
            if (token0 == nativeToken || token1 == nativeToken) {
                // Check which token is nativeToken
                (tokenA, tokenB) = token0 == nativeToken ? (token0, token1) : (token1, token0);
            } else {
                // Swap native token to token0
                swapTokensPrivate(nativeToken, token0, contractBalanceOf(nativeToken));

                // Assign tokenA and tokenB to token0 and token1 respectively
                (tokenA, tokenB) = (token0, token1);
            }
        }

        // ─────────────────────── 4. Convert Token A to LP Token underlying
        // Total amunt of token A
        uint256 totalAmountA = contractBalanceOf(tokenA);

        // prettier-ignore
        (uint256 reserves0, uint256 reserves1, /* BlockTimestamp */) = IDexPair(underlying).getReserves();

        // Get reserves of tokenA for optimal deposit
        uint256 reservesA = tokenA == token0 ? reserves0 : reserves1;

        // Get optimal swap amount for token A
        uint256 swapAmount = CygnusDexLib.optimalDepositA(totalAmountA, reservesA, 997);

        // Swap optimal amount to tokenA to tokenB for liquidity deposit
        swapTokensPrivate(tokenA, tokenB, swapAmount);

        // Add liquidity and get LP Token
        uint256 liquidity = addLiquidityPrivate(tokenA, tokenB, totalAmountA - swapAmount, contractBalanceOf(tokenB));

        // ─────────────────────── 5. Stake the LP Token
        // Deposit in rewarder
        REWARDER.deposit(sushiPoolId, liquidity, address(this));

        // Store last harvest timestamp
        lastReinvest = block.timestamp;

        /// @custom:event RechargeVoid
        emit RechargeVoid(_msgSender(), currentRewards, eoaReward, daoReward, liquidity);
    }
}
