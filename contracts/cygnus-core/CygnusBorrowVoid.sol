// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusBorrowVoid} from "./interfaces/ICygnusBorrowVoid.sol";
import {CygnusBorrowModel} from "./CygnusBorrowModel.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IHangar18} from "./interfaces/IHangar18.sol";
import {IStargatePool} from "./interfaces/BorrowableVoid/IStargatePool.sol";
import {IStargateRouter} from "./interfaces/BorrowableVoid/IStargateRouter.sol";
import {IStargateLPStaking} from "./interfaces/BorrowableVoid/IStargateLPStaking.sol";
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
    uint256 private stgPoolId = type(uint256).max;

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
    uint256 public constant override REINVEST_REWARD = 0.04e18;

    /**
     *  @notice DAO rewards 2%
     */
    uint256 public constant override DAO_REWARD = 0.02e18;

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
        view
        override
        returns (uint256, uint256, IStargatePool, IStargateRouter, IStargateLPStaking, address, IAggregationRouterV5)
    {
        return (stgPoolId, STG_ROUTER_POOL_ID, STG_POOL, STG_ROUTER, REWARDER, REWARDS_TOKEN, AGGREGATION_ROUTER_V5);
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
        (address caller, IAggregationRouterV5.SwapDescription memory desc /* permit */, , bytes memory data) = abi
            .decode(swapData, (address, IAggregationRouterV5.SwapDescription, bytes, bytes));

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != updatedAmount) desc.amount = updatedAmount;

        /// @custom:error SrcTokenNotValid Avoid swapping anything but rewards token
        if (address(desc.srcToken) != REWARDS_TOKEN) {
            revert CygnusBorrowVoid__SrcTokenNotValid({srcToken: address(desc.srcToken), token: REWARDS_TOKEN});
        }

        /// @custom:error DstTokenNotValid Avoid swapping to anything but underlying
        if (address(desc.dstToken) != underlying) {  
            revert CygnusBorrowVoid__DstTokenNotValid({dstToken: address(desc.dstToken), token: underlying});
        }

        /// @custom:error DstReceiverNotValid Avoid swapping to another address
        if (desc.dstReceiver != address(this)) {
            revert CygnusBorrowVoid__DstReceiverNotValid({dstReceiver: desc.dstReceiver, receiver: address(this)});
        }

        // Allow 1inch router to access our `srcToken` (REWARDS_TOKEN)
        approveTokenPrivate(address(desc.srcToken), address(AGGREGATION_ROUTER_V5), desc.amount);

        // Swap `srcToken` to `dstToken` with no permit
        (amountOut, ) = AGGREGATION_ROUTER_V5.swap(IAggregationExecutor(caller), desc, new bytes(0), data);
    }

    /**
     *  @notice Gets the rewards from the stgRewarder contract
     */
    function getRewardsPrivate() private returns (uint256) {
        // Get rewards by depositing 0, Goose clone
        REWARDER.deposit(stgPoolId, 0);

        // Return balance
        return contractBalanceOf(REWARDS_TOKEN);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Preview total balance from the Stargate strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function previewTotalBalance() internal view override(CygnusTerminal) returns (uint256 balance) {
        // S*USD LP Balance from the rewarder
        (uint256 stgRewarderBalance, ) = REWARDER.userInfo(stgPoolId, address(this));

        // Convert S*USD LP balance to underlying
        balance = stgRewarderBalance.fullMulDiv(STG_POOL.totalLiquidity(), STG_POOL.totalSupply());
    }

    /**
     *  @notice Syncs total balance of this contract with USD deposits from the rewarder
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function updateInternal() internal override(CygnusTerminal) {
        // Convert S*USD LP balance to underlying (doing a full round up)
        uint256 amountUSD = previewTotalBalance();

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
        // Add underlying as stargate liquidity
        STG_ROUTER.addLiquidity(STG_ROUTER_POOL_ID, assets, address(this));

        // Stake S*Underlying
        REWARDER.deposit(stgPoolId, contractBalanceOf(address(STG_POOL)));
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
        REWARDER.withdraw(stgPoolId, amountLP);

        // Redeem S*Underlying for underlying
        STG_ROUTER.instantRedeemLocal(uint16(STG_ROUTER_POOL_ID), contractBalanceOf(address(STG_POOL)), address(this));
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security non-reentrant only-admin 👽
     */
    function chargeVoid(uint256 _stgPoolId) external override nonReentrant cygnusAdmin {
        // Avoid initializing pool twice
        if (stgPoolId == type(uint256).max) {
            // Assign pool id for rewarder underlying
            stgPoolId = _stgPoolId;
        }

        // Allow Stargate router to use our USDC to deposits
        approveTokenPrivate(underlying, address(STG_ROUTER), type(uint256).max);

        // Allow Stargate Rewarder to use our S*Underlying to deposit
        approveTokenPrivate(address(STG_POOL), address(REWARDER), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(underlying, shuttleId, _msgSender());
    }

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
    function reinvestRewards_y7b(bytes calldata swapData) external override nonReentrant onlyEOA update accrue {
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

        // ─────────────────────── 3. Convert all rewardsToken to underlying
        // Swap to underlying and return balanceOf
        uint256 underlyingReceived = swapTokensPrivate(swapData, currentRewards - eoaReward - daoReward);

        // ─────────────────────── 4. Add liquidity and receive LP
        // Deposit USDC into Stargate pool to receive LP
        STG_ROUTER.addLiquidity(STG_ROUTER_POOL_ID, underlyingReceived, address(this));

        // ─────────────────────── 5. Stake the LP
        // Stake the LP
        REWARDER.deposit(stgPoolId, contractBalanceOf(address(STG_POOL)));

        // Store last harvest timestamp
        lastReinvest = block.timestamp;

        /// @custom:event RechargeVoid
        emit RechargeVoid(_msgSender(), currentRewards, eoaReward, daoReward, underlyingReceived);
    }
}
