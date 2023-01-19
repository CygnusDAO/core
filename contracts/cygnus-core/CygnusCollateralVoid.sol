// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralVoid } from "./interfaces/ICygnusCollateralVoid.sol";
import { CygnusCollateralControl } from "./CygnusCollateralControl.sol";

// Interfaces
import { CygnusTerminal } from "./CygnusTerminal.sol";
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";
import { IDexPair } from "./interfaces/IDexPair.sol";
import { IDexRouter02 } from "./interfaces/IDexRouter.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IRewarder, IMiniChef } from "./interfaces/IMiniChef.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IDenebOrbiter } from "./interfaces/IDenebOrbiter.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/**
 *  @title  CygnusCollateralVoid The strategy contract for the underlying LP Tokens
 *  @notice This contract is considered optional. Vanilla shuttles (ie those without masterchef/rewarders) should
 *          only have the constructor of this contract included and nothing else.
 *
 *          It is the only contract in Cygnus that should be changed according to the LP Token's masterchef/rewarder.
 *          As such most functions are kept private as they are only relevant to this contract and the others
 *          are indifferent to this. Do not modify constructor.
 */
contract CygnusCollateralVoid is ICygnusCollateralVoid, CygnusCollateralControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 For uint256 fixed point math, also imports the main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /**
     *  @custom:library SafeTransferLib Solady`s library for low level handling of Erc20 tokens
     */
    using SafeTransferLib for address;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    // Customizable

    /**
     *  @notice The token that is given as rewards by the dex' masterchef/rewarder contract
     */
    address private rewardsToken;

    /**
     *  @notice The address of this dex' router
     */
    IDexRouter02 private dexRouter;

    /**
     *  @notice Address of the Masterchef/Rewarder contract
     */
    IMiniChef private rewarder;

    /**
     *  @notice Pool ID this lpTokenPair corresponds to in `rewarder`
     */
    uint256 private pid;

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    // Non-customizable

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

    /*  ─────────────────────────────────────────────── Public ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public constant override REINVEST_REWARD = 0.02e18;

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public constant override DAO_REWARD = 0.01e18;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Cygnus Void contract which handles rewards reinvestments. The constructor
     *          for all voids should always be the same across all strategies, as such even if the strategy
     *          is empty (ie no rewarder) the constructor must always be left as is and remove all other functions.
     */
    constructor() {
        // Get factory, underlying, borrowable and lending pool id
        (address factory, address asset, , ) = IDenebOrbiter(_msgSender()).collateralParameters();

        // Token0 from the LP Token
        address tokenA = IDexPair(asset).token0();

        // Token1 from the LP Token
        address tokenB = IDexPair(asset).token1();

        // Name of this CygLP with each token symbols
        symbol = string(abi.encodePacked("CygLP ", IERC20(tokenA).symbol(), "/", IERC20(tokenB).symbol()));

        // This chain's native token read from the factory
        nativeToken = ICygnusFactory(factory).nativeToken();

        // Token0 from the underlying LP
        token0 = tokenA;

        // Token1
        token1 = tokenB;
    }

    /**
     *  @notice Accepts native deposits and immediately wraps in native contract
     */
    receive() external payable {
        // Deposit in nativeToken (WETH) contract
        IWETH(nativeToken).deposit{ value: msg.value }();
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
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return This contract's balance
     */
    function contractBalanceOf(address token) private view returns (uint256) {
        // Optimised safeTransferLib `balanceOf`
        return token.balanceOf(address(this));
    }

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
     *  @dev Compute swap amount of tokenA to swap to tokenB to mint Liquidity
     *  @notice Dex swap fee of 997 (This dex' swap fee of 0.3%)
     *  @param amountA amount of token A desired to deposit
     *  @param reservesA Reserves of token A from the DEX
     */
    function optimalDepositA(uint256 amountA, uint256 reservesA) private pure returns (uint256) {
        uint256 a = uint256(1997) * reservesA;
        uint256 b = amountA * 1000 * reservesA * 3988;
        uint256 c = PRBMath.sqrt(a * a + b);
        return (c - a) / 1994;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    function getCygnusVoid() external view override returns (IMiniChef, IDexRouter02, address, uint256) {
        // Return all the private storage variables from this contract
        return (rewarder, dexRouter, rewardsToken, pid);
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
    function approveDexRouter(address token, address router, uint256 amount) private {
        // Check allowance for `router` - Return if the allowance is higher than amount
        if (IERC20(token).allowance(address(this), router) >= amount) {
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
    function swapTokensPrivate(address tokenIn, address tokenOut, uint256 amount) private {
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
     *  @notice Function to add liquidity and mint LP Tokens
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

        // Mint the LP Token to this contract
        return IDexPair(underlying).mint(address(this));
    }

    /**
     *  @notice Gets the rewards from the masterchef's rewarder contract for multiple tokens and converts to rewardToken
     */
    function getRewardsPrivate() private returns (uint256) {
        // Get bonus rewards address
        address bonusRewarder = rewarder.rewarder(pid);

        // If active then harvest and swap all to reward token
        if (bonusRewarder != address(0)) {
            // Get all reward tokens and amounts
            (address[] memory rewardTokens, uint256[] memory rewardAmounts) = IRewarder(bonusRewarder).pendingTokens(
                pid,
                address(this),
                0
            );

            // Harvest Sushi
            rewarder.harvest(pid, address(this));

            // Harvest all tokens and swap to Sushi
            for (uint i = 0; i < rewardTokens.length; i++) {
                if (rewardAmounts[i] > 0) {
                    swapTokensPrivate(rewardTokens[i], rewardsToken, contractBalanceOf(rewardTokens[i]));
                }
            }
        } else {
            // Not active, harvest Sushi
            rewarder.harvest(pid, address(this));
        }

        return contractBalanceOf(rewardsToken);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Syncs total balance of this contract from our deposits in the masterchef
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
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
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of assets to deposit into the strategy
     */
    function afterDepositInternal(uint256 assets, uint256) internal override(CygnusTerminal) {
        // Deposit assets into the strategy
        rewarder.deposit(pid, assets, address(this));
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of shares to withdraw from the strategy
     */
    function beforeWithdrawInternal(uint256 assets, uint256) internal override(CygnusTerminal) {
        // Withdraw assets from the strategy
        rewarder.withdraw(pid, assets, address(this));
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
        uint256 pidVoid
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

        // Approve masterchef/rewarder in underlying
        underlying.safeApprove(address(rewarderVoid), type(uint256).max);

        // Approve dex router in rewards token
        rewardsTokenVoid.safeApprove(address(dexRouterVoid), type(uint256).max);

        // Approve dex router in wrapped native
        nativeToken.safeApprove(address(dexRouterVoid), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(dexRouterVoid, rewarderVoid, rewardsTokenVoid, pidVoid);
    }

    /**
     *  @notice Reinvests rewards token to buy more LP tokens and adds it back to position
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
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
        uint256 eoaReward = currentRewards.mul(REINVEST_REWARD);
        // Transfer the reward to the reinvestor
        rewardsToken.safeTransfer(_msgSender(), eoaReward);

        // Calculate reward for DAO (DAO_REWARD %)
        uint256 daoReward = currentRewards.mul(DAO_REWARD);
        // Get the current DAO reserves contract
        address daoReserves = ICygnusFactory(hangar18).daoReserves();
        // Transfer the reward to the DAO vault
        rewardsToken.safeTransfer(daoReserves, daoReward);

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
            swapTokensPrivate(rewardsToken, nativeToken, contractBalanceOf(rewardsToken));

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
        uint256 swapAmount = optimalDepositA(totalAmountA, reservesA);

        // Swap optimal amount to tokenA to tokenB for liquidity deposit
        swapTokensPrivate(tokenA, tokenB, swapAmount);

        // Add liquidity and get LP Token
        uint256 liquidity = addLiquidityPrivate(tokenA, tokenB, totalAmountA - swapAmount, contractBalanceOf(tokenB));

        // ─────────────────────── 5. Stake the LP Token
        // Deposit in rewarder
        rewarder.deposit(pid, liquidity, address(this));

        /// @custom:event RechargeVoid
        emit RechargeVoid(address(this), _msgSender(), currentRewards, eoaReward, daoReward);
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant
     */
    function smokeDust() external override nonReentrant {
        // Get dust amount of token0
        uint256 amountTokenA = contractBalanceOf(token0);

        // Swap to rewards token
        if (amountTokenA > 0) {
            swapTokensPrivate(token0, rewardsToken, amountTokenA);
        }

        // Get dust amount of token1
        uint256 amountTokenB = contractBalanceOf(token1);

        // Swap to rewards token
        if (amountTokenB > 0) {
            swapTokensPrivate(token1, rewardsToken, amountTokenB);
        }
    }
}
