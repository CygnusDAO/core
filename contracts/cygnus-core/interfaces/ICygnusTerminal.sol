// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { IERC20Permit } from "./IERC20Permit.sol";

/**
 *  @title The interface for CygnusTerminal which handles pool tokens shared by Collateral and Borrow contracts
 *  @notice The interface for the CygnusTerminal contract allows minting/redeeming Cygnus pool tokens
 */
interface ICygnusTerminal is IERC20Permit {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error CantMintZeroShares Reverts when attempting to mint zero amount of tokens
     */
    error CygnusTerminal__CantMintZeroShares();

    /**
     *  @custom:error CantBurnZeroAssets Reverts when attempting to redeem zero amount of tokens
     */
    error CygnusTerminal__CantRedeemZeroAssets();

    /**
     *  @custom:error RedeemAmountInvalid Reverts when attempting to redeem over amount of tokens
     */
    error CygnusTerminal__RedeemAmountInvalid(uint256 assets, uint256 totalBalance);

    /**
     *  @custom:error MsgSenderNotAdmin Reverts when attempting to call Admin-only functions
     */
    error CygnusTerminal__MsgSenderNotAdmin(address sender, address factoryAdmin);

    /**
     *  @custom:error CantSweepUnderlying Reverts when trying to sweep the underlying asset from this contract
     */
    error CygnusTerminal__CantSweepUnderlying(address token, address underlying);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @param totalBalance Total balance in terms of the underlying
     *  @custom:event Sync Logs when total balance of assets we hold is in sync with the underlying contract.
     */
    event Sync(uint256 totalBalance);

    /**
     *  @param sender The address of `CygnusAltair` or the sender of the function call
     *  @param recipient Address of the minter
     *  @param assets Amount of assets being deposited
     *  @param shares Amount of pool tokens being minted
     *  @custom:event Mint Logs when CygLP or CygUSD pool tokens are minted
     */
    event Deposit(address indexed sender, address indexed recipient, uint256 assets, uint256 shares);

    /**
     *  @param sender The address of the redeemer of the shares
     *  @param recipient The address of the recipient of assets
     *  @param owner The address of the owner of the pool tokens
     *  @param assets The amount of assets to redeem
     *  @param shares The amount of pool tokens burnt
     *  @custom:event Redeem Logs when CygLP or CygUSD are redeemed
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
     *  @return underlying The address of the underlying (LP Token for collateral contracts, USDC for borrow contracts)
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
     *  @return totalBalance Total balance owned by this shuttle pool in terms of its underlying
     */
    function totalBalance() external view returns (uint256);

    /**
     *  @return exchangeRate The ratio which 1 pool token can be redeemed for underlying amount
     *  @notice There are two exchange rates: 1 for collateral and 1 for borrow contracts. The borrow contract
     *          exchangeRate function is used to mint DAO reserves, as such we keep this as a non-view function,
     *          and instead use the `exchangeRateStored` state variable to keep track of the exchange rate.
     *          For the collateral exchange rate, we override this function in CygnusCollateralControl and mark
     *          it as view.
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
     *  @return assets Amount of assets returned to the user
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
