// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusCollateralVoid} from "./interfaces/ICygnusCollateralVoid.sol";
import {CygnusCollateralModel} from "./CygnusCollateralModel.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IWETH} from "./interfaces/IWETH.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IDexPair} from "./interfaces/IDexPair.sol";
import {IDexRouter02} from "./interfaces/IDexRouter.sol";
import {ICygnusFactory} from "./interfaces/ICygnusFactory.sol";
import {IRewarder, IMiniChef} from "./interfaces/IMiniChef.sol";

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
 *          are indifferent to this. Do not modify constructor.
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
     *  @notice Whether strategy is initialized or not
     */
    bool private initialized;

    /**
     *  @notice Pool ID this lpTokenPair corresponds to in `rewarder`
     */
    uint256 private sushiPoolId;

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

    /*  ─────────────────────────────────────────────── Public ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public constant override REINVEST_REWARD = 0.02e18;

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    uint256 public constant override DAO_REWARD = 0.01e18;

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

    /**
     *  @notice Accepts native deposits and immediately wraps in native contract
     */
    receive() external payable {
        // Deposit in nativeToken (WETH) contract
        IWETH(nativeToken).deposit{value: msg.value}();
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

    /**
     *  @dev Compute swap amount of tokenA to swap to tokenB to mint Liquidity
     *  @notice Dex swap fee of 997 (This dex' swap fee of 0.3%)
     *  @param amountA amount of token A desired to deposit
     *  @param reservesA Reserves of token A from the DEX
     */
    function optimalDepositA(uint256 amountA, uint256 reservesA) private pure returns (uint256) {
        uint256 a = uint256(1997) * reservesA;
        uint256 b = amountA * 1000 * reservesA * 3988;
        uint256 c = (a * a + b).sqrt();
        return (c - a) / 1994;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     */
    function getCygnusVoid() external view override returns (IMiniChef, IDexRouter02, address, uint256) {
        // Return all the private storage variables from this contract
        return (REWARDER, DEX_ROUTER, REWARDS_TOKEN, sushiPoolId);
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
                if (rewardAmounts[i] > 0) {
                    swapTokensPrivate(rewardTokens[i], REWARDS_TOKEN, contractBalanceOf(rewardTokens[i]));
                }
            }
        } else {
            // Not active, harvest Sushi
            REWARDER.harvest(sushiPoolId, address(this));
        }

        // Return balance harvested
        return contractBalanceOf(REWARDS_TOKEN);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Syncs total balance of this contract with LP token deposits from the rewarder
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function updateInternal() internal override(CygnusTerminal) {
        // Get this contracts deposited LP amount
        (uint256 amountLP, ) = REWARDER.userInfo(sushiPoolId, address(this));

        // Assign to totalBalance
        totalBalance = amountLP;

        /// @custom:event Sync
        emit Sync(totalBalance);
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of shares to withdraw from the strategy
     */
    function beforeWithdrawInternal(uint256 assets) internal override(CygnusTerminal) {
        // Withdraw assets from the strategy
        REWARDER.withdraw(sushiPoolId, assets, address(this));
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of shares to withdraw from the strategy
     */
    function afterDepositInternal(uint256 assets) internal override(CygnusTerminal) {
        // Check allowance and approve if necessary
        approveTokenPrivate(underlying, address(REWARDER), assets);

        // Deposit assets into the strategy
        REWARDER.deposit(sushiPoolId, assets, address(this));
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant only-admin 👽
     */
    function chargeVoid(uint256 _sushiPoolId) external override nonReentrant cygnusAdmin {
        /// @custom:error VoidAlreadyInitialized Avoid initializing twice
        if (initialized) {
            revert CygnusCollateralVoid__VoidAlreadyInitialized({ poolId: _sushiPoolId });
        }

        // Store pool ID from rewarder contract
        sushiPoolId = _sushiPoolId;

        // Set initialized, can't be set again
        initialized = true;

        /// @custom:event ChargeVoid
        emit ChargeVoid(block.timestamp, shuttleId, underlying, _sushiPoolId);
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
        address daoReserves = ICygnusFactory(hangar18).daoReserves();
        // Transfer the reward to the DAO vault
        REWARDS_TOKEN.safeTransfer(daoReserves, daoReward);

        // ─────────────────────── 3. Convert all rewardsToken to token0 or token1
        // Placeholders to sort tokens
        address tokenA;
        address tokenB;

        // Check if rewards token is already token0 or token1 from LP
        if (token0 == REWARDS_TOKEN || token1 == REWARDS_TOKEN) {
            // Check which token is rewardsToken
            (tokenA, tokenB) = token0 == REWARDS_TOKEN ? (token0, token1) : (token1, token0);
        } else {
            // Swap token reward token to native token
            swapTokensPrivate(REWARDS_TOKEN, nativeToken, contractBalanceOf(REWARDS_TOKEN));

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
        REWARDER.deposit(sushiPoolId, liquidity, address(this));

        // Store last harvest timestamp
        lastReinvest = block.timestamp;

        /// @custom:event RechargeVoid
        emit RechargeVoid(address(this), _msgSender(), currentRewards, eoaReward, daoReward);
    }

    /**
     *  @inheritdoc ICygnusCollateralVoid
     *  @custom:security non-reentrant only-eoa
     */
    function smokeDust() external override nonReentrant onlyEOA returns (uint256 amountTokenA, uint256 amountTokenB){
        // Get dust amount of token0
        amountTokenA = contractBalanceOf(token0);

        // Swap to rewards token
        if (amountTokenA > 0) {
            swapTokensPrivate(token0, REWARDS_TOKEN, amountTokenA);
        }

        // Get dust amount of token1
        amountTokenB = contractBalanceOf(token1);

        // Swap to rewards token
        if (amountTokenB > 0) {
            swapTokensPrivate(token1, REWARDS_TOKEN, amountTokenB);
        }
    }
}
