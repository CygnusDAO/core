// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {CygnusBorrowModel} from "./CygnusBorrowModel.sol";
import {ICygnusBorrowVoid} from "./interfaces/ICygnusBorrowVoid.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IDexRouter02} from "./interfaces/IDexRouter.sol";
import {ICygnusFactory} from "./interfaces/ICygnusFactory.sol";
// Stargate
import {IStargatePool} from "./interfaces/IStargatePool.sol";
import {IStargateRouter} from "./interfaces/IStargateRouter.sol";
import {IStargateLPStaking} from "./interfaces/IStargateLPStaking.sol";
import {IAggregationRouterV5, IAggregationExecutor} from "./interfaces/IAggregationRouterV5.sol";

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

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Stargate Rewarder Pool Id
     */
    uint256 private constant STG_POOL_ID = 0;

    /**
     *  @notice Stargate Router Pool Id to add liquidity after reinvesting rewards
     */
    uint256 private constant STG_ROUTER_POOL_ID = 1;

    /**
     *  @notice Rewards Token
     */
    address private constant REWARDS_TOKEN = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    /**
     *  @notice Stargate pool for the underlying 0x1205f31718499dBf1fCa446663B532Ef87481fe1
     */
    IStargatePool private constant STG_POOL = IStargatePool(0x1205f31718499dBf1fCa446663B532Ef87481fe1);

    /**
     *  @notice Stargate Router
     */
    IStargateRouter private constant STG_ROUTER = IStargateRouter(0x45A01E4e04F14f7A4a6702c74187c5F6222033cd);

    /**
     *  @notice Stargate LP Staking rewards
     */
    IStargateLPStaking private constant REWARDER = IStargateLPStaking(0x8731d54E9D02c286767d56ac03e8037C07e01e98);

    /**
     *  @notice 1Inch aggregation router v5
     */
    IAggregationRouterV5 private constant AGGREGATION_ROUTER_V5 =
        IAggregationRouterV5(0x1111111254EEB25477B68fb85Ed929f73A960582);

    /*  ─────────────────────────────────────────────── Public ───────────────────────────────────────────────  */

    /**
     *  @notice Reinvest rewards 2%
     */
    uint256 public constant override REINVEST_REWARD = 0.02e18;

    /**
     *  @notice DAO rewards 2%
     */
    uint256 public constant override DAO_REWARD = 0.01e18;

    /**
     *  @notice Timestamp of the last reinvest
     */
    uint256 public override lastReinvest;

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
     *  @notice Reverts if caller is not considered an EOA
     */
    function checkEOA() private view {
        /// @custom:error OnlyEOAAllowed Avoid if not called by an externally owned account
        // solhint-disable-next-line
        if (_msgSender() != tx.origin) {
            // solhint-disable-next-line
            revert CygnusBorrowVoid__OnlyEOAAllowed({sender: _msgSender(), origin: tx.origin});
        }
    }

    /*  ────────────────────────────────────────────── External ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    function getCygnusVoid()
        external
        pure
        override
        returns (uint256, uint256, IStargatePool, IStargateRouter, IStargateLPStaking, address, IAggregationRouterV5)
    {
        return (STG_POOL_ID, STG_ROUTER_POOL_ID, STG_POOL, STG_ROUTER, REWARDER, REWARDS_TOKEN, AGGREGATION_ROUTER_V5);
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
     *  @param swapData The 1inch swap data to swap from `rewardsToken` to `underlying`
     *  @param updatedAmount The updated amount in case it's different by some mini tokens
     *  @return amountOut The amount of `underlying` received
     */
    function swapTokensPrivate(bytes memory swapData, uint256 updatedAmount) private returns (uint256 amountOut) {
        // Get aggregation executor, swap params and the encoded calls for the executor from 1inch API call
        (address caller, IAggregationRouterV5.SwapDescription memory desc, bytes memory permit, bytes memory data) = abi
            .decode(swapData, (address, IAggregationRouterV5.SwapDescription, bytes, bytes));

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != updatedAmount) desc.amount = updatedAmount;

        /// @custom:error SwapNotAllowed Avoid swapping to another address and swapping to except underlying
        if (desc.dstReceiver != address(this) || address(desc.dstToken) != underlying) {
            revert CygnusBorrowVoid__SwapNotAllowed({dstReceiver: desc.dstReceiver, dstToken: address(desc.dstToken)});
        }

        /// @custom:error SrcTokenNotValid Avoid swapping anything but rewards token
        if (address(desc.srcToken) != REWARDS_TOKEN) {
            revert CygnusBorrowVoid__SrcTokenNotValid({srcToken: address(desc.srcToken), rewardsToken: REWARDS_TOKEN});
        }

        // Approve 1Inch Router in `srcToken` if necessary - rewardsToken is fixed
        approveTokenPrivate(address(desc.srcToken), address(AGGREGATION_ROUTER_V5), desc.amount);

        // Swap `srcToken` to `dstToken`
        (amountOut, ) = AGGREGATION_ROUTER_V5.swap(IAggregationExecutor(caller), desc, permit, data);
    }

    /**
     *  @notice Gets the rewards from the stgRewarder contract
     */
    function getRewardsPrivate() private returns (uint256) {
        // Get rewards by depositing 0
        REWARDER.deposit(STG_POOL_ID, 0);

        // Return balance
        return contractBalanceOf(REWARDS_TOKEN);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Syncs total balance of this contract with USD deposits from the rewarder
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function updateInternal() internal override(CygnusTerminal) {
        // S*USD LP Balance from the rewarder
        (uint256 stgRewarderBalance, ) = REWARDER.userInfo(STG_POOL_ID, address(this));

        // Convert S*USD LP balance to underlying (doing a full round up)
        uint256 amountUSD = stgRewarderBalance.fullMulDivUp(STG_POOL.totalLiquidity(), STG_POOL.totalSupply());

        // Assign to total balance
        totalBalance = amountUSD;

        /// @custom:event Sync
        emit Sync(totalBalance);
    }

    /**
     *  @notice Deposits underlying in strategy and stakes the LP received
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function afterDepositInternal(uint256 assets) internal override(CygnusTerminal) {
        // 1. Allow Stargate router to use our USDC to deposit
        approveTokenPrivate(underlying, address(STG_ROUTER), assets);
        // Add underlying as stargate liquidity
        STG_ROUTER.addLiquidity(STG_ROUTER_POOL_ID, assets, address(this));

        // The Router gives us S*Underlying
        uint256 stgPoolBalance = contractBalanceOf(address(STG_POOL));

        // 2. Allow Stargate Rewarder to use our S*Underlying to deposit
        approveTokenPrivate(address(STG_POOL), address(REWARDER), stgPoolBalance);
        // Stake S*Underlying
        REWARDER.deposit(STG_POOL_ID, stgPoolBalance);
    }

    /**
     *  @notice Withdraws underlying assets from the strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function beforeWithdrawInternal(uint256 assets) internal override(CygnusTerminal) {
        // Convert Asset to LP (doing a full round up)
        uint256 amountLP = assets.fullMulDivUp(STG_POOL.totalSupply(), STG_POOL.totalLiquidity());

        // Withdraw S*Underlying from Rewarder (round up)
        REWARDER.withdraw(STG_POOL_ID, amountLP);

        // Redeem S*Underlying for underlying
        STG_ROUTER.instantRedeemLocal(uint16(STG_ROUTER_POOL_ID), contractBalanceOf(address(STG_POOL)), address(this));
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security non-reentrant only-eoa
     */
    function getRewards() external override nonReentrant onlyEOA returns (uint256) {
        // Reverts if not EOA
        return getRewardsPrivate();
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security non-reentrant only-eoa
     */
    function reinvestRewards_y7b(bytes memory swapData) external override nonReentrant onlyEOA update accrue {
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
        address daoReserves = ICygnusFactory(hangar18).daoReserves();
        // Transfer the reward to the DAO vault
        REWARDS_TOKEN.safeTransfer(daoReserves, daoReward);

        // ─────────────────────── 3. Convert all rewardsToken to underlying
        // Swap to underlying and return balanceOf
        uint256 rewardReceived = swapTokensPrivate(swapData, contractBalanceOf(REWARDS_TOKEN));

        // ─────────────────────── 4. Add liquidity and receive LP
        // Deposit USDC into Stargate pool
        STG_ROUTER.addLiquidity(STG_ROUTER_POOL_ID, rewardReceived, address(this));

        // ─────────────────────── 5. Stake the LP
        // Stake the LP
        REWARDER.deposit(STG_POOL_ID, contractBalanceOf(address(STG_POOL)));

        // Store last harvest timestamp
        lastReinvest = block.timestamp;

        /// @custom:event RechargeVoid
        emit RechargeVoid(address(this), _msgSender(), currentRewards, eoaReward, daoReward);
    }
}
