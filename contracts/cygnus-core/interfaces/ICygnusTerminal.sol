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
    event Mint(address indexed sender, address indexed recipient, uint256 assets, uint256 shares);

    /**
     *  @notice Logs when an asset is redeemed
     *  @param sender The address of `CygnusAltair` or the sender of the function call
     *  @param recipient The address of the redeemer
     *  @param assets The amount to redeem
     *  @param shares The amount of PoolTokens burnt
     *  @custom:event Redeem Emitted when CygLP or CygDAI are redeemed
     */
    event Redeem(address indexed sender, address indexed recipient, uint256 assets, uint256 shares);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
           3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return totalBalance Total balance of this shuttle in terms of the underlying
     */
    function totalBalance() external returns (uint256);

    /**
     *  @return underlying The address of the underlying (LP Token for collateral contracts, DAI for borrow contracts)
     */
    function underlying() external returns (address);

    /**
     *  @return hangar18 The address of the Cygnus Factory V1 contract 🛸
     */
    function hangar18() external returns (address);

    /**
     *  @notice Trick compiler for nonpayable function
     *  @return exchangeRate The ratio at which 1 pool token can be redeemed for underlying amount
     */
    function exchangeRate() external returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This low level function should only be called from `CygnusAltair` contract only
     *  @param recipient Address of the minter
     *  @return mintTokens Amount of pool tokens to mint
     *  @custom:security non-reentrant
     */
    function mint(address recipient) external returns (uint256 mintTokens);

    /**
     *  @dev This low level function should only be called from `CygnusAltair` contract only
     *  @param recipient Address of the redeemer
     *  @return redeemAmount The holder's shares
     *  @custom:security non-reentrant
     */
    function redeem(address recipient) external returns (uint256 redeemAmount);
}
