// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrowVoid} from "./interfaces/ICygnusBorrowVoid.sol";
import {CygnusBorrowModel} from "./CygnusBorrowModel.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IHangar18} from "./interfaces/IHangar18.sol";
import {ICygnusHarvester} from "./interfaces/ICygnusHarvester.sol";

// Strategy
import {IStargatePool} from "./interfaces/BorrowableVoid/IStargatePool.sol";
import {IStargateRouter} from "./interfaces/BorrowableVoid/IStargateRouter.sol";
import {IStargateLPStaking} from "./interfaces/BorrowableVoid/IStargateLPStaking.sol";

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
     *  @notice Stargate pool for the underlying 0x1205f31718499dBf1fCa446663B532Ef87481fe1
     */
    IStargatePool private constant STG_POOL = IStargatePool(0xDecC0c09c3B5f6e92EF4184125D5648a66E35298);

    /**
     *  @notice Stargate Router
     */
    IStargateRouter private constant STG_ROUTER = IStargateRouter(0xB0D502E938ed5f4df2E681fE6E419ff29631d62b);

    /**
     *  @notice Stargate LP Staking rewards
     */
    IStargateLPStaking private constant REWARDER = IStargateLPStaking(0x4DeA9e918c6289a52cd469cAC652727B7b412Cd2);

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    ICygnusHarvester public override harvester;

    /**
     *  @inheritdoc ICygnusBorrowVoid
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
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    function rewarder() external pure override returns (address) {
        // Return the contract that rewards us with `rewardsToken`
        return address(REWARDER);
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    function rewardToken() external view override returns (address) {
        // Return the address of the reward tokn
        return REWARDER.eToken();
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
     *  @notice Harvest rewards and return tokens and amounts received
     *  @return tokens Array of reward tokens
     *  @return amounts Array of received amounts of each token
     */
    function getRewardsPrivate() private returns (address[] memory tokens, uint256[] memory amounts) {
        // Get rewards by depositing 0, Goose clone
        REWARDER.deposit(STG_POOL_ID, 0);

        // Single reward token array
        tokens = new address[](1);

        // Single reward amount
        amounts = new uint256[](1);

        // Get reward token
        tokens[0] = REWARDER.eToken();

        // Get reward amount
        amounts[0] = contractBalanceOf(tokens[0]);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Preview total balance from the Stargate strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function previewTotalBalance() internal view override(CygnusTerminal) returns (uint256 balance) {
        // S*USD LP Balance from the rewarder
        (uint256 stgRewarderBalance, ) = REWARDER.userInfo(STG_POOL_ID, address(this));

        // Convert S*USD LP balance to underlying
        balance = stgRewarderBalance.fullMulDiv(STG_POOL.totalLiquidity(), STG_POOL.totalSupply());
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
        REWARDER.deposit(STG_POOL_ID, contractBalanceOf(address(STG_POOL)));
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
     *  @custom:security non-reentrant
     */
    // prettier-ignore
    function getRewards() external override nonReentrant returns (address[] memory tokens, uint256[] memory amounts) {
        // Harvest rewards and return tokens and amounts
        return getRewardsPrivate();
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security non-reentrant
     */
    function reinvestRewards_y7b(uint256 liquidity) external override nonReentrant update accrue {
        /// @custom:error OnlyHarvesterAllowed Avoid call if msg.sender is not the harvester
        if (msg.sender != address(harvester)) revert CygnusBorrowVoid__OnlyHarvesterAllowed();

        // After deposit hook
        afterDepositInternal(liquidity);

        /// @custom:event RechargeVoid
        emit RechargeVoid(msg.sender, liquidity, lastReinvest = block.timestamp);
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security non-reentrant
     */
    function chargeVoid() external override nonReentrant {
        // Allow Stargate router to use our USDC to deposits
        approveTokenPrivate(underlying, address(STG_ROUTER), type(uint256).max);

        // Allow Stargate Rewarder to use our S*Underlying to deposit
        approveTokenPrivate(address(STG_POOL), address(REWARDER), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(underlying, shuttleId, msg.sender);
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
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
