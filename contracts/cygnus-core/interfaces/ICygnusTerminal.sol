// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

// Dependencies
import { IErc20Permit } from "./IErc20Permit.sol";

/**
 *  @title The interface for CygnusTerminal which handles pool tokens shared by Collateral and Borrow contracts
 *  @notice The interface for the CygnusTerminal contract allows minting/redeeming Cygnus pool tokens
 */
interface ICygnusTerminal is IErc20Permit {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error CantMintZeroShares Emitted when attempting to mint zero amount of tokens
     */
    error CygnusTerminal__CantMintZeroShares();

    /**
     *  @custom:error CantBurnZeroAssets Emitted when attempting to redeem zero amount of tokens
     */
    error CygnusTerminal__CantRedeemZeroAssets();

    /**
     *  @custom:error RedeemAmountInvalid Emitted when attempting to redeem over amount of tokens
     */
    error CygnusTerminal__RedeemAmountInvalid(uint256 assets, uint256 totalBalance);

    /**
     *  @custom:error MsgSenderNotAdmin Emitted when attempting to call Admin-only functions
     */
    error CygnusTerminal__MsgSenderNotAdmin(address sender, address factoryAdmin);

    /**
     *  @custom:error CantSweepUnderlying Emitted when trying to sweep the underlying from this contract
     */
    error CygnusTerminal__CantSweepUnderlying(address token, address underlying);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Logs when totalBalance is syncd to real balance
     *  @param totalBalance Total balance in terms of the underlying
     *  @custom:event Sync Emitted when `totalBalance` is in sync with balanceOf(address(this)).
     */
    event Sync(uint256 totalBalance);

    /**
     *  @notice Logs when an asset is minted
     *  @param sender The address of `CygnusAltair` or the sender of the function call
     *  @param recipient Address of the minter
     *  @param assets Amount of assets being deposited
     *  @param shares Amount of pool tokens being minted
     *  @custom:event Mint Emitted when CygLP or CygDai pool tokens are minted
     */
    event Deposit(address indexed sender, address indexed recipient, uint256 assets, uint256 shares);

    /**
     *  @notice Logs when an asset is redeemed
     *  @param sender The address of `CygnusAltair` or the sender of the function call
     *  @param recipient The address of the recipient of assets
     *  @param owner The address of the owner of the pool tokens
     *  @param assets The amount of assets to redeem
     *  @param shares The amount of pool tokens burnt
     *  @custom:event Redeem Emitted when CygLP or CygDAI are redeemed
     */
    event Withdraw(
        address indexed sender,
        address indexed recipient,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
           3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return totalBalance Total balance owned by this shuttle pool in terms of its underlying
     */
    function totalBalance() external view returns (uint256);

    /**
     *  @return underlying The address of the underlying (LP Token for collateral contracts, DAI for borrow contracts)
     */
    function underlying() external view returns (address);

    /**
     *  @return hangar18 The address of the Cygnus Factory contract used to deploy this shuttle  🛸
     */
    function hangar18() external view returns (address);

    /**
     *  @return shuttleId The ID of this shuttle (shared by Collateral and Borrow)
     */
    function shuttleId() external view returns (uint256);

    /**
     *  @notice Trick compiler for nonpayable function -> overriden by CygnusBorrow.sol
     *  @return exchangeRate The ratio which 1 pool token can be redeemed for underlying amount
     */
    function exchangeRate() external returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Deposits assets and mints shares to recipient
     *  @param assets The amount of assets to deposit
     *  @param recipient Address of the minter
     *  @return shares Amount of shares minted
     *  @custom:security non-reentrant
     */
    function deposit(uint256 assets, address recipient) external returns (uint256 shares);

    /**
     *  @notice Redeems shares and returns assets to recipient
     *  @param shares The amount of shares to redeem for assets
     *  @param recipient The address of the redeemer
     *  @param owner The address of the account who owns the shares
     *  @return assets Amount of assets redeemed
     *  @custom:security non-reentrant
     */
    function redeem(
        uint256 shares,
        address recipient,
        address owner
    ) external returns (uint256 assets);

    /**
     *  @notice 👽
     *  @notice Recovers any ERC20 token accidentally sent to this contract, sent to msg.sender
     *  @param token The address of the token we are recovering
     *  @custom:security non-reentrant
     */
    function sweepToken(address token) external;
}
