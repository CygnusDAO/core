/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════

       █████████           ---======*.                                       🛸          .                    .⠀
      ███░░░░░███                                              📡                                         🌔   
     ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
    ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀        🛰️   .               
    ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
    ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .              .⠀
     ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████       -----========*⠀
      ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .⠀
                   ███ ░███  ███ ░███                .                 .         🛸           ⠀               
     .      *     ░░██████  ░░██████   .                         🛰️                 .          .                
                   ░░░░░░    ░░░░░░                                                 ⠀
       .                            .       .         ------======*             .                          .      ⠀

     https://cygnusdao.finance                                                          .                     .

    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════

     Smart contracts to `go long` on your liquidity.

     Deposit liquidity, borrow USD.

     Structure of all Cygnus Contracts:

     Contract                        ⠀Interface                                             
        ├ 1. Libraries                   ├ 1. Custom Errors                                               
        ├ 2. Storage                     ├ 2. Custom Events
        │     ├ Private             ⠀    ├ 3. Constant Functions                          ⠀        
        │     ├ Internal                 │     ├ Public                            ⠀       
        │     └ Public                   │     └ External                        ⠀⠀⠀              
        ├ 3. Constructor                 └ 4. Non-Constant Functions  
        ├ 4. Modifiers              ⠀          ├ Public
        ├ 5. Constant Functions     ⠀          └ External
        │     ├ Private             ⠀                      
        │     ├ Internal            
        │     ├ Public              
        │     └ External            
        └ 6. Non-Constant Functions 
              ├ Private             
              ├ Internal            
              ├ Public              
              └ External            

    @dev: Inspired by Impermax, follows similar architecture and code but with significant edits. It should 
          only be tested with Solidity >=0.8 as some functions don't check for overflow/underflow and all errors
          are handled with the new `custom errors` feature among other small things...                           */

// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusTerminal} from "./interfaces/ICygnusTerminal.sol";
import {ERC20} from "./ERC20.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {SafeCastLib} from "./libraries/SafeCastLib.sol";

// Interfaces
import {IOrbiter} from "./interfaces/IOrbiter.sol";
import {IHangar18} from "./interfaces/IHangar18.sol";
import {ICygnusNebulaOracle} from "./interfaces/ICygnusNebulaOracle.sol";
import {IAllowanceTransfer} from "./interfaces/IAllowanceTransfer.sol";

/**
 *  @title  CygnusTerminal
 *  @author CygnusDAO
 *  @notice Contract used to mint Collateral and Borrow tokens. Both Collateral/Borrow arms of Cygnus mint here
 *          to get the vault token (CygUSD for stablecoin deposits and CygLP for Liquidity deposits).
 */
abstract contract CygnusTerminal is ICygnusTerminal, ERC20, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
     */
    using SafeTransferLib for address;

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers.
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     */
    IAllowanceTransfer public constant override PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /**
     *  @inheritdoc ICygnusTerminal
     */
    IHangar18 public immutable override hangar18;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    ICygnusNebulaOracle public immutable override cygnusNebulaOracle;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    address public immutable override underlying;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    uint256 public immutable override shuttleId;

    /**
     *  @notice The contract's totalBalance is stored as a uint160 which is the max asset allowance the Permit2 router allows.
     *  @inheritdoc ICygnusTerminal
     */
    uint160 public override totalBalance;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs tokens for both Collateral and Borrow arms
     */
    constructor() {
        // Get immutables from deployer contract who is msg.sender of deployments
        // Factory, asset, borrow/collateral, oracle, lending pool ID
        (hangar18, underlying, , cygnusNebulaOracle, shuttleId) = IOrbiter(msg.sender).shuttleParameters();
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Controls important parameters in both Collateral and Borrow contracts 👽
     */
    modifier cygnusAdmin() {
        _checkAdmin();
        _;
    }

    /**
     *  @notice We mark as virtual in case need we need to also update before interaction (ie yield bearing tokens)
     *  @custom:modifier update Updates the total balance var in terms of its underlying
     */
    modifier update() virtual {
        _;
        // Update `totalBalance` after interaction
        _update();
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ─────────────────────────────────────────────── ─ */

    /**
     *  @notice Internal check for msg.sender admin, checks factory's current admin 👽
     */
    function _checkAdmin() private view {
        // Current admin from the factory
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (msg.sender != admin) revert CygnusTerminal__MsgSenderNotAdmin();
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return amount This contract's `token` balance
     */
    function _checkBalance(address token) internal view returns (uint256) {
        // Our balance of `token`
        return token.balanceOf(address(this));
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     */
    function exchangeRate() public virtual override returns (uint256) {
        // Gas savings if non-zero
        uint256 _totalSupply = totalSupply();

        // Compute the exchange rate as the total balance of the underlying asset divided by the total supply of
        // the vault token. If there is no supply for this token, return the initial exchange rate of 1:1.
        return _totalSupply == 0 ? 1e18 : uint256(totalBalance).divWad(_totalSupply);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Updates this contract's total balance in terms of its underlying
     */
    function _update() internal {
        // Get current balanceOf this contract
        uint256 balance = _previewTotalBalance();

        /// @custom:event Sync
        emit Sync(totalBalance = SafeCastLib.toUint160(balance));
    }

    /**
     *  @notice Preview the total balance of the underlying we own from the strategy (if any)
     *  @return balance This contract's balance of the underlying asset
     */
    function _previewTotalBalance() internal virtual returns (uint256 balance) {
        // Get current balanceOf this contract
        balance = _checkBalance(underlying);
    }

    /**
     *  @notice Internal hook for deposits into strategies
     *  @param assets The amount of assets to deposit in the strategy
     */
    function _afterDeposit(uint256 assets) internal virtual {}

    /**
     *  @notice Internal hook for withdrawals from strategies
     *  @param assets The amount of assets to withdraw from the strategy
     */
    function _beforeWithdraw(uint256 assets) internal virtual {}

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     */
    function deposit(
        uint256 assets,
        address recipient,
        IAllowanceTransfer.PermitSingle calldata _permit,
        bytes calldata signature
    ) external override update returns (uint256 shares) {
        // Get balance before depositing in case of deposit fees
        uint256 balanceBefore = _previewTotalBalance();

        // Check for permit (users can just approve permit2 and skip this by passing an empty
        // `_permit` and an empty `signature`)
        if (signature.length > 0) {
            // Set allowance using permit
            PERMIT2.permit(
                // The owner of the tokens being approved.
                // We only allow the owner of the tokens to be the depositor, but
                // recipient can be set to another address
                msg.sender,
                // Data signed over by the owner specifying the terms of approval
                _permit,
                // The owner's signature over the permit data that was the result
                // of signing the EIP712 hash of `_permit`
                signature
            );
        }

        // Transfer underlying to vault
        PERMIT2.transferFrom(msg.sender, address(this), SafeCastLib.toUint160(assets), underlying);

        // Deposit in strategy
        _afterDeposit(assets);

        // Balance after (does not update totalBalance)
        uint256 balanceAfter = _previewTotalBalance();

        // Check for deposit fee
        shares = (balanceAfter - balanceBefore).divWad(exchangeRate());

        /// @custom:error CantMintZeroShares Avoid minting no shares
        if (shares == 0) revert CygnusTerminal__CantMintZeroShares();

        // Avoid first depositor front-running & update shares - only for the first pool depositor
        if (totalSupply() == 0) {
            // Update shares for first depositor
            shares -= 1000;

            // Lock initial tokens
            _mint(address(0xdEaD), 1000);
        }

        // Mint shares and emit Transfer event
        _mint(recipient, shares);

        /// @custom:event Deposit
        emit Deposit(msg.sender, recipient, assets, shares);
    }

    /**
     *  @inheritdoc ICygnusTerminal
     */
    function redeem(uint256 shares, address recipient, address owner) external override update returns (uint256 assets) {
        // Withdraw flow
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

        // Check current exchange rate
        assets = shares.mulWad(exchangeRate());

        /// @custom:error CantRedeemZeroAssets Avoid redeeming no assets
        if (assets <= 0) revert CygnusTerminal__CantRedeemZeroAssets();

        // Withdraw assets from the strategy (if any)
        _beforeWithdraw(assets);

        // Burn shares
        _burn(owner, shares);

        // Transfer assets to recipient
        underlying.safeTransfer(recipient, assets);

        /// @custom:event Withdraw
        emit Withdraw(msg.sender, recipient, owner, assets, shares);
    }

    /**
     *  @inheritdoc ICygnusTerminal
     *  @custom:security non-reentrant only-admin 👽
     */
    function sweepToken(address token) external override nonReentrant cygnusAdmin {
        /// @custom:error CantSweepUnderlying Avoid sweeping underlying
        if (token == underlying) revert CygnusTerminal__CantSweepUnderlying();

        // Balance this contract has of the erc20 token we are recovering
        uint256 balance = _checkBalance(token);

        // Transfer token
        token.safeTransfer(msg.sender, balance);

        /// @custom:event SweepToken
        emit SweepToken(msg.sender, token, balance);
    }
}
