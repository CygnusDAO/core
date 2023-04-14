// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusCollateralVoid} from "./interfaces/ICygnusCollateralVoid.sol";
import {CygnusCollateralModel} from "./CygnusCollateralModel.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {CygnusDexLib} from "./libraries/CygnusDexLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IDexPair} from "./interfaces/IDexPair.sol";
import {IOrbiter} from "./interfaces/IOrbiter.sol";
import {IHangar18} from "./interfaces/IHangar18.sol";
import {IAggregationRouterV5, IAggregationExecutor} from "./interfaces/IAggregationRouterV5.sol";

// Strategy
import {IDexRouter} from "./interfaces/CollateralVoid/IDexRouter.sol";
import {IRewarder, IMiniChef} from "./interfaces/CollateralVoid/IMiniChef.sol";

// Overrides
import {CygnusTerminal} from "./CygnusTerminal.sol";

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
    address private constant REWARDS_TOKEN = 0xd4d42F0b6DEF4CE0383636770eF773390d85c61A;

    /**
     *  @notice The address of this dex' router
     */
    IDexRouter private constant DEX_ROUTER = IDexRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    /**
     *  @notice Address of the Rewarder contract
     */
    IMiniChef private constant REWARDER = IMiniChef(0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3);

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
    IAggregationRouterV5 public constant override AGGREGATION_ROUTER_V5 =
        IAggregationRouterV5(0x1111111254EEB25477B68fb85Ed929f73A960582);

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public constant override DAO_REWARD = 0.05e18;

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
            revert CygnusCollateralVoid__OnlyEOAAllowed({sender: _msgSender(), origin: tx.origin});
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
     *  @notice Swap tokens function used by Reinvest to turn reward token into more LP Tokens
     *  @param swapData The 1inch swap data to swap from `rewardsToken` to `underlying`
     *  @param updatedAmount The updated amount in case it's different by some mini tokens
     *  @return amountOut The amount of `underlying` received
     */
    function swapTokensPrivate(bytes memory swapData, uint256 updatedAmount) private returns (uint256 amountOut) {
        // Get aggregation executor, swap params and the encoded calls for the executor from 1inch API call
        (address caller, IAggregationRouterV5.SwapDescription memory desc /* permit */, , bytes memory data) = abi
            .decode(swapData, (address, IAggregationRouterV5.SwapDescription, bytes, bytes));

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != updatedAmount) desc.amount = updatedAmount;

        /// @custom:error SrcTokenNotValid Avoid swapping anything but rewards token
        if (address(desc.srcToken) != REWARDS_TOKEN) {
            revert CygnusCollateralVoid__SrcTokenNotValid({srcToken: address(desc.srcToken), token: REWARDS_TOKEN});
        }

        /// @custom:error DstTokenNotValid Avoid swapping to anything but underlying
        if (address(desc.dstToken) != token0 && address(desc.dstToken) != token1) {
            revert CygnusCollateralVoid__DstTokenNotValid({dstToken: address(desc.dstToken), token: underlying});
        }

        /// @custom:error DstReceiverNotValid Avoid swapping to another address
        if (desc.dstReceiver != address(this)) {
            revert CygnusCollateralVoid__DstReceiverNotValid({dstReceiver: desc.dstReceiver, receiver: address(this)});
        }

        // Allow 1inch router to access our `srcToken` (REWARDS_TOKEN)
        approveTokenPrivate(address(desc.srcToken), address(AGGREGATION_ROUTER_V5), desc.amount);

        // Swap `srcToken` to `dstToken` with no permit
        (amountOut, ) = AGGREGATION_ROUTER_V5.swap(IAggregationExecutor(caller), desc, new bytes(0), data);
    }

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
    function swapExactTokensForTokens(address tokenIn, address tokenOut, uint256 amount) private {
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
                if (rewardAmounts[i] > 0) swapExactTokensForTokens(rewardTokens[i], REWARDS_TOKEN, rewardAmounts[i]);
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

        // Allow 1inch router to access our `srcToken` (REWARDS_TOKEN)
        approveTokenPrivate(address(REWARDS_TOKEN), address(AGGREGATION_ROUTER_V5), type(uint256).max);

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
    function reinvestRewards_y7b(bytes memory swapData) external override nonReentrant onlyEOA update {
        // ─────────────────────── 1. Withdraw all rewards
        // Harvest rewards accrued of `rewardToken`
        uint256 currentRewards = getRewardsPrivate();

        // If none accumulated return and do nothing
        if (currentRewards == 0) {
            return;
        }

        // ─────────────────────── 2. Send reward to the vault
        // Calculate reward for DAO (DAO_REWARD %)
        uint256 daoReward = currentRewards.mulWad(DAO_REWARD);

        // Get the current DAO reserves contract
        address daoReserves = IHangar18(hangar18).daoReserves();

        // Transfer the reward to the DAO vault
        REWARDS_TOKEN.safeTransfer(daoReserves, daoReward);

        // ─────────────────────── 3. Convert all rewardsToken to tokenA
        // Placeholders to sort tokens
        address tokenA;
        address tokenB;

        // Check if rewards token is already token0 or token1 from LP
        if (token0 == REWARDS_TOKEN || token1 == REWARDS_TOKEN) {
            // Check which token is rewardsToken
            (tokenA, tokenB) = token0 == REWARDS_TOKEN ? (token0, token1) : (token1, token0);
        } else {
            // Check if token0 or token1 is native token
            if (token0 == nativeToken || token1 == nativeToken) {
                // Check which token is nativeToken
                (tokenA, tokenB) = token0 == nativeToken ? (token0, token1) : (token1, token0);
            } else {
                // Assign tokenA and tokenB to token0 and token1 respectively
                (tokenA, tokenB) = (token0, token1);
            }
            // Perform first swap with 1inch data
            swapTokensPrivate(swapData, currentRewards - daoReward);
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
        swapExactTokensForTokens(tokenA, tokenB, swapAmount);

        // Add liquidity and get LP Token
        uint256 liquidity = addLiquidityPrivate(tokenA, tokenB, totalAmountA - swapAmount, contractBalanceOf(tokenB));

        // ─────────────────────── 5. Stake the LP Token
        // Deposit in rewarder
        REWARDER.deposit(sushiPoolId, liquidity, address(this));

        // Store last harvest timestamp
        lastReinvest = block.timestamp;

        /// @custom:event RechargeVoid
        emit RechargeVoid(_msgSender(), currentRewards, daoReward, liquidity);
    }
}
