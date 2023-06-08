// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrowVoid} from "./interfaces/ICygnusBorrowVoid.sol";
import {CygnusBorrowModel} from "./CygnusBorrowModel.sol";
import {CygnusBorrowApprove} from "./CygnusBorrowApprove.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {ICygnusHarvester} from "./interfaces/ICygnusHarvester.sol";

// Strategy
import {ISonnePool} from "./interfaces/BorrowableVoid/ISonnePool.sol";
import {IUniTroller} from "./interfaces/BorrowableVoid/IUniTroller.sol";
import {IStakedDistributor} from "./interfaces/BorrowableVoid/IStakedDistributor.sol";

// Overrides
import {CygnusTerminal} from "./CygnusTerminal.sol";

/**
 *  @title  CygnusBorrowVoid The strategy contract for the underlying stablecoin
 *  @author CygnusDAO
 *  @notice Strategy for the underlying stablecoin deposits.
 */
contract CygnusBorrowVoid is ICygnusBorrowVoid, CygnusBorrowModel, CygnusBorrowApprove {
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

    /*  ─────────── Strategy */

    /**
     *  @notice Sonne USDC Pool
     */
    ISonnePool private constant SONNE_USDC = ISonnePool(0xEC8FEa79026FfEd168cCf5C627c7f486D77b765F);

    /**
     *  @notice Comptroller implementation
     */
    IUniTroller private constant REWARDER = IUniTroller(0x60CF091cD3f50420d50fD7f707414d0DF4751C58);

    /**
     *  @notice Distributor for bonus rewards
     */
    IStakedDistributor private constant DISTRIBUTOR = IStakedDistributor(0xDC05d85069Dc4ABa65954008ff99f2D73FF12618);

    /**
     *  @notice Sonne Token
     */
    address private constant SONNE = 0x1DB2466d9F5e10D7090E7152B68d62703a2245F0;

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
         4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Overrides the previous modifier from CygnusTerminal to update before interactions too
     *  @notice CygnusTerminal override
     *  @custom:modifier update Updates the total balance var in terms of its underlying
     */
    modifier update() override(CygnusTerminal) {
        // Update before deposit to prevent deposit spam for yield bearing tokens
        _update();
        _;
        // Update after deposit
        _update();
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

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
    function rewardToken() external pure override returns (address) {
        // Return the address of the main reward tokn
        return SONNE;
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
     *  @notice Gets the rewards from the stgRewarder contract
     */
    function getRewardsPrivate() private returns (address[] memory tokens, uint256[] memory amounts) {
        // Make the markets array to claim from the Comptroller
        address[] memory markets = new address[](1);

        // Assign cToken
        markets[0] = address(SONNE_USDC);

        // 1. Claim Sonne from Comptroller
        REWARDER.claimComp(address(this), markets);

        // 2. Claim Sonne from Distributor
        uint256[] memory _amounts = DISTRIBUTOR.claimAll();

        // 3. Re-stake all Sonne
        uint256 sonneRewards = contractBalanceOf(SONNE);

        // Check non-zero
        if (sonneRewards > 0) DISTRIBUTOR.mint(sonneRewards);

        // 4. Get bonus rewards from Distributor (remove address 0 and index 0)
        uint256 numTokens = _amounts.length - 1;

        // Tokens harvested from the distributor
        tokens = new address[](numTokens);

        // Amounts harvested from the distributor
        amounts = new uint256[](numTokens);

        // Loop through each reward token
        for (uint256 i = 1; i <= numTokens; i++) {
            // Token
            tokens[i - 1] = DISTRIBUTOR.tokens(i);

            // Amounts
            amounts[i - 1] = contractBalanceOf(tokens[i - 1]);
        }
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Preview total balance from the Stargate strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function _previewTotalBalance() internal override(CygnusTerminal) returns (uint256 balance) {
        // Accrue interest and return total balance
        balance = SONNE_USDC.balanceOfUnderlying(address(this));
    }

    /**
     *  @notice Deposits underlying assets in the strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function _afterDeposit(uint256 assets) internal override(CygnusTerminal) {
        // Mint sonneUsdc
        uint256 errorcode = SONNE_USDC.mint(assets);

        /// @custom:error CTokenError Avoid cToken mint error (NO_ERROR == 0)
        if (errorcode != 0) revert CygnusBorrowVoid__CTokenError();
    }

    /**
     *  @notice Withdraws underlying assets from the strategy
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     */
    function _beforeWithdraw(uint256 assets) internal override(CygnusTerminal) {
        // Redeem for underlying
        uint256 errorcode = SONNE_USDC.redeemUnderlying(assets);

        /// @custom:error CTokenError Avoid cToken redeem error (NO_ERROR == 0)
        if (errorcode != 0) revert CygnusBorrowVoid__CTokenError();
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    function chargeVoid() external override {
        // Allow cToken to access our underlying
        approveTokenPrivate(underlying, address(SONNE_USDC), type(uint256).max);

        // Allow cToken to access our underlying
        approveTokenPrivate(SONNE, address(DISTRIBUTOR), type(uint256).max);

        /// @custom:event ChargeVoid
        emit ChargeVoid(underlying, shuttleId, msg.sender);
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
     *  @custom:security non-reentrant
     */
    function getRewards() external override nonReentrant returns (address[] memory tokens, uint256[] memory amounts) {
        // Harvest rewards and return tokens and amounts
        return getRewardsPrivate();
    }

    /**
     *  @inheritdoc ICygnusBorrowVoid
     */
    function reinvestRewards_y7b(uint256 liquidity) external override update accrue {
        /// @custom:error OnlyHarvesterAllowed Avoid call if msg.sender is not the harvester
        if (msg.sender != address(harvester)) revert CygnusBorrowVoid__OnlyHarvesterAllowed();

        // After deposit hook
        _afterDeposit(liquidity);

        /// @custom:event RechargeVoid
        emit RechargeVoid(msg.sender, liquidity, lastReinvest = block.timestamp);
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
        // NOTE: This is safe because approved token is never underlying
        (address[] memory tokens, ) = getRewardsPrivate();

        // Loop through each token
        for (uint256 i = 0; i < tokens.length; i++) {
            // Approve harvester in token `i`
            if (tokens[i] != underlying) {
                // Remove allowance for old harvester
                approveTokenPrivate(tokens[i], address(harvester), 0);

                // Approve new harvester
                approveTokenPrivate(tokens[i], address(_harvester), type(uint256).max);
            }
        }

        /// @custom:event NewHarvester
        emit NewHarvester(oldHarvester, _harvester);
    }
}
