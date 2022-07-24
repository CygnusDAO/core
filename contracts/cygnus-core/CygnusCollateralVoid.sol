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
import { VoidHelper } from "./libraries/VoidHelper.sol";
import { PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";
import { SafeErc20 } from "./libraries/SafeErc20.sol";

/**
 *  @title  CygnusCollateralVoid Assigns the masterchef/rewards contract (if any) to harvest and reinvest rewards
 *  @notice This contract is considered optional and default state is offline (bool `voidActivated`)
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
     *  @custom:library SafeErc20 Low level handling of Erc20 tokens
     */
    using SafeErc20 for IErc20;

    /**
     *  @custom:library VoidHelper Helper functions for interacting with dexes and handling rewards
     */
    using VoidHelper for address;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Address of the chain's native token
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

    /*  ─────────────────────────────────────────────── Public ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public constant override REINVEST_REWARD = 0.025e18;

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
        // Receive AVAX and deposit in WAVAX contract to immediately convert to WAVAX
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
        /// @custom:error OnlyAccountsAllowed Avoid if not called by EOA
        // solhint-disable-next-line
        if (_msgSender() != tx.origin) {
            // solhint-disable-next-line
            revert CygnusCollateralChef__OnlyEOAAllowed({ sender: _msgSender(), origin: tx.origin });
        }
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
            IMiniChef rewarder_,
            uint256 pid_,
            bool voidActivated_,
            address rewardsToken_,
            uint256 dexSwapFee_,
            IDexRouter02 dexRouter_
        )
    {
        // Return all the private storage variables
        return (rewarder, pid, voidActivated, rewardsToken, dexSwapFee, dexRouter);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

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

        // Assign tokenIn to path 0
        path[0] = address(tokenIn);

        // Assign tokenOut to path 1
        path[1] = address(tokenOut);

        // Safe Approve router
        tokenIn.approveDexRouter(address(dexRouter), amount);

        // Swap tokens
        dexRouter.swapExactTokensForTokens(amount, 0, path, address(this), type(uint256).max);
    }

    /**
     *  @notice Function to add liquidity to DEX
     *  @param tokenA The address of the LP Token's token0
     *  @param tokenB The address of the LP Token's token1
     *  @param amountA The amount of token A to add as liquidity
     *  @param amountB The amount of token B to add as liquidity
     *  @return liquidity The total liquidity amount added
     */
    function addLiquidityPrivate(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) private returns (uint256 liquidity) {
        // Approve token A
        tokenA.approveDexRouter(address(dexRouter), amountA);

        // Approve token B
        tokenB.approveDexRouter(address(dexRouter), amountB);

        // prettier-ignore
        (
            /* amountA */,
            /* amountB */,
            liquidity
        ) = dexRouter.addLiquidity(tokenA, tokenB, amountA, amountB, 0, 0, address(this), type(uint256).max);
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
            uint256 bonusRewardBalance = bonusRewardToken.contractBalanceOf();

            // If we have any, swap everything to this shuttle's rewardsToken
            if (bonusRewardBalance > 0) {
                swapTokensPrivate(bonusRewardToken, rewardsToken, bonusRewardBalance);
            }
        }

        // Return this contract's total rewards balance
        return rewardsToken.contractBalanceOf();
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Syncs total balance of this contract from our deposits in the masterchef, else this contract's deposit
     *  @dev Overrides CygnusTerminal
     */
    function updateInternal() internal override(CygnusTerminal) {
        // Get total balance held by this contract
        if (!voidActivated) {
            // Update from terminal
            super.updateInternal();
        }
        // Else return our balance held in the masterchef
        else {
            // prettier-ignore
            (totalBalance, /* reward debt */) = rewarder.userInfo(pid, address(this));

            /// @custom:event Sync
            emit Sync(totalBalance);
        }
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
     */
    function initializeVoid(
        IDexRouter02 dexRouterVoid,
        IMiniChef rewarderVoid,
        address rewardsTokenVoid,
        uint256 pidVoid,
        uint256 dexSwapFeeVoid
    ) external override nonReentrant cygnusAdmin {
        /// @custom:error InvalidRewardsToken Avoid setting cygnus void twice
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

        // Approve dex router in rewards token
        rewardsTokenVoid.safeApprove(address(dexRouterVoid), type(uint256).max);

        // Approve dex router in wavax
        nativeToken.safeApprove(address(dexRouterVoid), type(uint256).max);

        // Approve masterchef/rewarder in underlying
        underlying.safeApprove(address(rewarderVoid), type(uint256).max);

        // Activate
        voidActivated = true;

        /// @custom:event ChargeVoid
        emit ChargeVoid(dexRouterVoid, rewarderVoid, rewardsTokenVoid, pidVoid, dexSwapFeeVoid);
    }

    /**
     *  @notice Reinvests rewards token to buy more LP tokens and adds it back to position
     *          As a result the debt owned by borrowers diminish on every reinvestment as their LP Token amount increase
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
     */
    function reinvestRewards() external override nonReentrant onlyEOA update {
        // ─────────────────────── 1. Withdraw all rewards

        uint256 currentRewards = getRewardsPrivate();

        // If none accumulated return and do nothing
        if (currentRewards == 0) {
            return;
        }

        // ─────────────────────── 2. Send reward to the reinvestor

        // Calculate reward for user (rewards harvested * REINVEST_REWARD)
        uint256 eoaReward = currentRewards.mul(REINVEST_REWARD);

        // Transfer the reward to the reinvestor
        IErc20(rewardsToken).safeTransfer(_msgSender(), eoaReward);

        // ─────────────────────── 3. Convert all rewardsToken to token0 or token1

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
                swapTokensPrivate(nativeToken, token0, nativeToken.contractBalanceOf());

                // Assign tokenA and tokenB to token0 and token1 respectively
                (tokenA, tokenB) = (token0, token1);
            }
        }

        // ─────────────────────── 4. Convert Token A to LP Token underlying

        // Total amunt of token A
        uint256 totalAmountA = tokenA.contractBalanceOf();

        // prettier-ignore
        (uint256 reserves0, uint256 reserves1, /* BlockTimestamp */) = IDexPair(underlying).getReserves();

        // Get reserves of tokenA for optimal deposit
        uint256 reservesA = tokenA == token0 ? reserves0 : reserves1;

        // Get optimal swap amount for token A
        uint256 swapAmount = VoidHelper.optimalDepositA(totalAmountA, reservesA, dexSwapFee);

        // Swap optimal amount to tokenA to tokenB for liquidity deposit
        swapTokensPrivate(tokenA, tokenB, swapAmount);

        // Add liquidity and get LP Token
        uint256 liquidity = addLiquidityPrivate(tokenA, tokenB, totalAmountA - swapAmount, tokenB.contractBalanceOf());

        // ─────────────────────── 5. Stake the LP Token

        rewarder.deposit(pid, liquidity);

        /// @custom:event RechargeVoid
        emit RechargeVoid(address(this), _msgSender(), currentRewards, eoaReward);
    }
}
