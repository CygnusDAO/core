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
     *  @custom:error FactoryAlreadyInitialized Emitted when attempting to set already initialized factory
     */
    error CygnusTerminal__FactoryAlreadyInitialized(address);

    /**
     *  @custom:error CantMintZero Emitted when attempting to mint zero amount of tokens
     */
    error CygnusTerminal__CantMintZero(uint256);

    /**
     *  @custom:error CantBurnZero Emitted when attempting to redeem zero amount of tokens
     */
    error CygnusTerminal__CantBurnZero(uint256);

    /**
     *  @custom:error BurnAmountInvalid Emitted when attempting to redeem over amount of tokens
     */
    error CygnusTerminal__BurnAmountInvalid(uint256);

    /**
     *  @custom:error MsgSenderNotAdmin Emitted when attempting to call Admin-only functions
     */
    error CygnusTerminal__MsgSenderNotAdmin(address);

    /**
     *  @custom:error MsgSenderNotFactory Emitted when attempting to call Factory-only functions
     */
    error CygnusTerminal__MsgSenderNotFactory(address);

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
     *  @param sender The address of `CygnusAltair`
     *  @param minter Address of the minter.
     *  @param mintAmount Amount initial is worth at the current exchange rate.
     *  @param poolTokens Amount of the tokens to be minted.
     *  @custom:event Mint Emitted when tokens are minted
     */
    event Mint(address indexed sender, address indexed minter, uint256 mintAmount, uint256 poolTokens);

    /**
     *  @notice Logs when an asset is redeemed
     *  @param sender The address of `CygnusAltair`
     *  @param redeemer The address of the redeemer
     *  @param redeemAmount The amount to redeem
     *  @param poolTokens The amount of PoolTokens to burn
     *  @custom:event Redeem Emitted when Albireo or Deneb tokens are redeemed
     */
    event Redeem(address indexed sender, address indexed redeemer, uint256 redeemAmount, uint256 poolTokens);

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
     *  @return exchangeRate The ratio at which 1 pool token can be redeemed for underlying amount
     *  @notice Trick compiler nonpayable function
     */
    function exchangeRate() external returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This low level function should only be called from `CygnusAltair` contract only
     *  @param minter Address of the minter
     *  @return poolTokens Amount of pool tokens to mint
     *  @custom:security non-reentrant
     */
    function mint(address minter) external returns (uint256 poolTokens);

    /**
     *  @dev This low level function should only be called from `CygnusAltair` contract only
     *  @param holder Address of the redeemer
     *  @return redeemAmount The holder's shares
     *  @custom:security non-reentrant
     */
    function redeem(address holder) external returns (uint256 redeemAmount);

    /**
     *  @notice Uniswap's skim function
     *  @param recipient Address of user skimming difference between total balance stored and actual balance
     *  @custom:security non-reentrant
     */
    function skim(address recipient) external;

    /**
     *  @notice Uniswap's sync function
     *  @notice Force real balance to match totalBalance
     *  @custom:security non-reentrant
     */
    function sync() external;
}
