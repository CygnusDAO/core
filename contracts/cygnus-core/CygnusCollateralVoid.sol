// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralVoid } from "./interfaces/ICygnusCollateralVoid.sol";
import { CygnusCollateralControl } from "./CygnusCollateralControl.sol";

// Interfaces
import { ICygnusTerminal, CygnusTerminal } from "./CygnusTerminal.sol";
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";
import { IDexPair } from "./interfaces/IDexPair.sol";
import { IDexRouter02 } from "./interfaces/IDexRouter.sol";
import { IErc20 } from "./interfaces/IErc20.sol";
import { IRewarder, IMiniChef } from "./interfaces/IMiniChef.sol";
import { IWAVAX } from "./interfaces/IWAVAX.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/**
 *  @title  CygnusCollateralVoid Assigns the masterchef/rewards contract (if any) to harvest and reinvest rewards
 *  @notice This contract is considered optional and default state is offline (bool `voidActivated`). Vanilla
 *          shuttles should not have this contract included (for example UniswapV2) as they dont have a masterchef
 *          contract behind them.
 *
 *          It is the only contract in Cygnus that should be changed according to the LP Token's masterchef/rewarder.
 *          As such most functions are kept private as they are only relevant to this contract and the others
 *          are indifferent to this.
 */
contract CygnusCollateralVoid is ICygnusCollateralVoid, CygnusCollateralControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 For uint256 fixed point math, also imports the main library `PRBMath`.
     */
    using PRBMathUD60x18 for uint256;

    /**
     *  @custom:library SafeTransferLib Solady`s library for low level handling of Erc20 tokens
     */
    using SafeTransferLib for address;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    // Constructor - Should always be constructed wtih these 3 variables

    /**
     *  @notice Address of the chain's native token (ie WETH)
     */
    address internal immutable nativeToken;

    /**
     *  @notice The first token from the underlying LP Token
     */
    address internal immutable token0;

    /**
     *  @notice The second token from the underlying LP Token
     */
    address internal immutable token1;

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    // Strategy - Customizable

    /**
     *  @notice The token that is given as rewards by the dex' masterchef/rewarder contract
     */
    address private rewardsToken;

    /**
     *  @notice The address of this dex' router
     */
    IDexRouter02 private dexRouter;

    /**
     *  @notice The fee this dex charges for each swap divided by 1000 (ie uniswap charges 0.3%, swap fee is 997)
     */
    uint256 private dexSwapFee;

    /**
     *  @notice Address of the Masterchef/Rewarder contract
     */
    IMiniChef private rewarder;

    /**
     *  @notice Pool ID this lpTokenPair corresponds to in `rewarder`
     */
    uint256 private pid;

    /*  ─────────────────────────────────────────────── Public ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public constant override REINVEST_REWARD = 0.02e18;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Cygnus Void contract which handles rewards reinvestments
     *  @notice Assign token0 and token1 as the underlying is always a univ2 LP Token + assign this chain's nativeToken
     */
    constructor() {
        // Token0 of the underlying
        token0 = IDexPair(underlying).token0();

        // Token1 of the underlying
        token1 = IDexPair(underlying).token1();

        // This chains native token
        nativeToken = ICygnusFactory(hangar18).nativeToken();
    }

    /**
     *  @notice Accepts AVAX and immediately deposits in WAVAX contract to receive wrapped avax
     */
    receive() external payable {
        // Deposit in nativeToken (WAVAX) contract
        IWAVAX(nativeToken).deposit{ value: msg.value }();
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
     *  @notice Reverts if it is not considered a EOA
     */
    function checkEOA() private view {
        /// @custom:error OnlyEOAAllowed Avoid if not called by an externally owned account
        // solhint-disable-next-line
        if (_msgSender() != tx.origin) {
            // solhint-disable-next-line
            revert CygnusCollateralChef__OnlyEOAAllowed({ sender: _msgSender(), origin: tx.origin });
        }
    }

    /**
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return This contract's balance
     */
    function contractBalanceOf(address token) private view returns (uint256) {
        return IErc20(token).balanceOf(address(this));
    }

    /**
     *  @dev Compute optimal deposit amount of token0 to mint an LP Token
     *  @param amountA amount of token A desired to deposit
     *  @param reservesA Reserves of token A from the DEX
     *  @param _dexSwapFee The fee charged by this dex for a swap (ie Uniswap = 997/1000 = 0.3%)
     */
    function optimalDepositA(
        uint256 amountA,
        uint256 reservesA,
        uint256 _dexSwapFee
    ) internal pure returns (uint256) {
        // Calculate with dex swap fee
        uint256 a = (1000 + _dexSwapFee) * reservesA;
        uint256 b = amountA * 1000 * reservesA * 4 * _dexSwapFee;
        uint256 c = PRBMath.sqrt(a * a + b);
        uint256 d = 2 * _dexSwapFee;
        return (c - a) / d;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    function getCygnusVoid()
        external
        view
        override
        returns (
            IMiniChef,
            uint256,
            address,
            uint256,
            IDexRouter02
        )
    {
        // Return all the private storage variables from this contract
        return (rewarder, pid, rewardsToken, dexSwapFee, dexRouter);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Grants allowance to the dex' router to handle our rewards
     *  @param token The address of the token we are approving
     *  @param amount The amount to approve
     */
    function approveDexRouter(
        address token,
        address router,
        uint256 amount
    ) internal {
        // Check allowance for `router` - Return if the allowance is higher than amount
        if (IErc20(token).allowance(address(this), router) >= amount) {
            return;
        }

        // Else safe approve max
        token.safeApprove(router, type(uint256).max);
    }

    /**
     *  @notice Swap tokens function used by Reinvest to turn reward token into more LP Tokens
     *  @param tokenIn address of the token we are swapping
     *  @param tokenOut Address of the token we are receiving
     *  @param amount Amount of TokenIn we are swapping
     */
    function swapTokensPrivate(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) private {
        // Create the path to swap from tokenIn to tokenOut
        address[] memory path = new address[](2);

        // Create path for tokenIn to tokenOut
        (path[0], path[1]) = (tokenIn, tokenOut);

        // Safe Approve router
        approveDexRouter(tokenIn, address(dexRouter), amount);

        // Swap tokens
        dexRouter.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);
    }

    /**
     *  @notice Function to add liquidity, called after `optimalDepositA` to transfer the optimal amount and mint LP
     *  @param tokenA The address of the LP Token's token0
     *  @param tokenB The address of the LP Token's token1
     *  @param amountA The amount of token A to add as liquidity
     *  @param amountB The amount of token B to add as liquidity
     *  @return liquidity The total LP Tokens minted
     */
    function addLiquidityPrivate(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) private returns (uint256 liquidity) {
        // Transfer token0 to LP Token contract
        tokenA.safeTransfer(underlying, amountA);

        // Transfer token1 to LP Token contract
        tokenB.safeTransfer(underlying, amountB);

        // Explicit return - Mint the LP Token to this contract
        return IDexPair(underlying).mint(address(this));
    }

    /**
     *  @notice Gets the rewards from the masterchef's rewarder contract for multiple tokens and converts to rewardToken
     */
    function getRewardsPrivate() private returns (uint256) {
        // Harvest rewards from the masterchef by withdrawing 0 amount
        IMiniChef(rewarder).withdraw(pid, 0);

        // Get the contract that pays the bonus AVAX rewards (if any) from the dex
        (, , , , , IRewarder bonusRewarder, , , ) = IMiniChef(rewarder).poolInfo(pid);

        // Check if this LP is paying additional rewards
        if (address(bonusRewarder) != address(0)) {
            // Check on contract to see if the reward is AVAX
            bool isNative = bonusRewarder.isNative();

            // If is AVAX, bonus reward is WAVAX due to receive() function else get bonus reward token
            address bonusRewardToken = isNative ? nativeToken : address(bonusRewarder.rewardToken());

            // Get the balance of the bonus reward token
            uint256 bonusRewardBalance = contractBalanceOf(bonusRewardToken);

            // If we have any, swap everything to this shuttle's rewardsToken
            if (bonusRewardBalance > 0) {
                swapTokensPrivate(bonusRewardToken, rewardsToken, bonusRewardBalance);
            }
        }

        // Return this contract's total rewards balance
        return contractBalanceOf(rewardsToken);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Syncs total balance of this contract from our deposits in the masterchef
     *  @notice CygnusTerminal override
     */
    function updateInternal() internal override(CygnusTerminal) {
        // Get this contracts deposited LP amount
        (uint256 rewarderBalance, ) = rewarder.userInfo(pid, address(this));

        // Store to totalBalance
        totalBalance = rewarderBalance;

        /// @custom:event Sync
        emit Sync(totalBalance);
    }

    /**
     *  @notice Internal hook for deposits into strategies
     *  @param assets The amount of assets to deposit into the strategy
     */
    function afterDepositInternal(uint256 assets, uint256) internal override {
        // Deposit assets into the strategy
        rewarder.deposit(pid, assets);
    }

    /**
     *  @notice Internal hook for withdrawals from strategies
     *  @param assets The amount of shares to withdraw from the strategy
     */
    function beforeWithdrawInternal(uint256 assets, uint256) internal override {
        // Withdraw assets from the strategy
        rewarder.withdraw(pid, assets);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
     */
    function chargeVoid(
        IDexRouter02 dexRouterVoid,
        IMiniChef rewarderVoid,
        address rewardsTokenVoid,
        uint256 pidVoid,
        uint256 dexSwapFeeVoid
    ) external override nonReentrant cygnusAdmin {
        /// @custom:error VoidAlreadyInitialized Avoid setting cygnus void twice
        if (rewardsToken != address(0)) {
            revert CygnusCollateralChef__VoidAlreadyInitialized({ tokenReward: rewardsTokenVoid });
        }

        // Store Router
        dexRouter = dexRouterVoid;

        // Store Masterchef for this pool
        rewarder = rewarderVoid;

        // Store pool ID
        pid = pidVoid;

        // Store rewardsToken
        rewardsToken = rewardsTokenVoid;

        // Swap fee for this dex
        dexSwapFee = dexSwapFeeVoid;

        // Approve masterchef/rewarder in underlying
        underlying.safeApprove(address(rewarderVoid), type(uint256).max);

        // Approve dex router in rewards token
        rewardsTokenVoid.safeApprove(address(dexRouterVoid), type(uint256).max);

        // Approve dex router in wavax
        nativeToken.safeApprove(address(dexRouterVoid), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(dexRouterVoid, rewarderVoid, rewardsTokenVoid, pidVoid, dexSwapFeeVoid);
    }

    /**
     *  @notice Reinvests rewards token to buy more LP tokens and adds it back to position
     *          As a result the debt owned by borrowers diminish on every reinvestment as their LP Token amount increase
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
     */
    function reinvestRewards_y7b() external override nonReentrant onlyEOA update {
        // ─────────────────────── 1. Withdraw all rewards
        // Harvest rewards accrued
        uint256 currentRewards = getRewardsPrivate();

        // If none accumulated return and do nothing
        if (currentRewards == 0) {
            return;
        }

        // ─────────────────────── 2. Send reward to the reinvestor and whoever created strategy

        // Calculate reward for user (rewards harvested * REINVEST_REWARD)
        uint256 eoaReward = currentRewards.mul(REINVEST_REWARD);

        // Transfer the reward to the reinvestor
        rewardsToken.safeTransfer(_msgSender(), eoaReward);

        // ─────────────────────── 3. Convert all rewardsToken to token0 or token1

        // Placeholders to sort tokens
        address tokenA;
        address tokenB;

        // Check if rewards token is already token0 or token1 from LP
        if (token0 == rewardsToken || token1 == rewardsToken) {
            // Check which token is rewardsToken
            (tokenA, tokenB) = token0 == rewardsToken ? (token0, token1) : (token1, token0);
        } else {
            // Swap token reward token to native token
            swapTokensPrivate(rewardsToken, nativeToken, currentRewards - eoaReward);
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
        uint256 swapAmount = optimalDepositA(totalAmountA, reservesA, dexSwapFee);

        // Swap optimal amount to tokenA to tokenB for liquidity deposit
        swapTokensPrivate(tokenA, tokenB, swapAmount);

        // Add liquidity and get LP Token
        uint256 liquidity = addLiquidityPrivate(tokenA, tokenB, totalAmountA - swapAmount, contractBalanceOf(tokenB));

        // ─────────────────────── 5. Stake the LP Token

        // Deposit in rewarder
        rewarder.deposit(pid, liquidity);

        /// @custom:event RechargeVoid
        emit RechargeVoid(address(this), _msgSender(), currentRewards, eoaReward);
    }
}
