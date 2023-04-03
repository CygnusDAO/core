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
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusTerminal} from "./interfaces/ICygnusTerminal.sol";
import {ERC20Permit} from "./ERC20Permit.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IHangar18} from "./interfaces/IHangar18.sol";
import {IDenebOrbiter} from "./interfaces/IDenebOrbiter.sol";
import {IAlbireoOrbiter} from "./interfaces/IAlbireoOrbiter.sol";

/**
 *  @title  CygnusTerminal
 *  @author CygnusDAO
 *  @notice Contract used to mint Collateral and Borrow tokens. Both Collateral/Borrow arms of Cygnus mint here
 *          to get the vault token (CygUSD for stablecoin deposits and CygLP for Liquidity deposits).
 */
contract CygnusTerminal is ICygnusTerminal, ERC20Permit {
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

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     */
    address public immutable override hangar18;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    uint256 public immutable override shuttleId;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    address public immutable override underlying;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    uint256 public override totalBalance;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs tokens for both Collateral and Borrow arms
     *  @notice We have to do a try/catch if we want to store underlying as immutables. This is because both borrowable and
     *          collateral contracts call different deployer contracts which have their unique params.
     *  @param _name ERC20 name of the Borrow/Collateral token
     *  @param _symbol ERC20 symbol of the Borrow/Collateral token
     *  @param _decimals Decimals of the Borrow/Collateral token
     */
    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20Permit(_name, _symbol, _decimals) {
        // Set placeholders for try/catch
        // Factory
        address _hangar18;

        // Asset
        address _underlying;

        // Lending Pool ID (shared by both borrowable and collateral)
        uint256 _shuttleId;

        // Try Collateral parameters: factory, underlying, borrowable (assigned on child contract), shuttleId
        try IDenebOrbiter(_msgSender()).collateralParameters() returns (
            address _factory,
            address _asset,
            address,
            uint256 _poolId
        ) {
            // Try collateral: factory, LP Token, pool Id
            (_hangar18, _underlying, _shuttleId) = (_factory, _asset, _poolId);
        } catch {
            // Catch borrowable: factory, stablecoin, pool Id
            (_hangar18, _underlying, , _shuttleId, , ) = IAlbireoOrbiter(_msgSender()).borrowParameters();
        }

        // Assign placeholders to immutables
        (hangar18, underlying, shuttleId) = (_hangar18, _underlying, _shuttleId);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier update Updates the total balance var in terms of its underlying
     */
    modifier update() {
        _;
        updateInternal();
    }

    /**
     *  @custom:modifier cygnusAdmin Controls important parameters in both Collateral and Borrow contracts 👽
     */
    modifier cygnusAdmin() {
        checkAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal check for msg.sender admin, checks factory's current admin 👽
     */
    function checkAdmin() internal view {
        // Current admin from the factory
        address admin = IHangar18(hangar18).admin();

        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (_msgSender() != admin) {
            revert CygnusTerminal__MsgSenderNotAdmin({sender: _msgSender(), admin: admin});
        }
    }

    /**
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return This contract's `token` balance
     */
    function contractBalanceOf(address token) internal view returns (uint256) {
        // Solady's `balanceOf`
        return token.balanceOf(address(this));
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     */
    function exchangeRate() public virtual override returns (uint256) {
        // Gas savings if non-zero
        uint256 _totalSupply = totalSupply;

        // If there is no supply for this token return initial rate
        return _totalSupply == 0 ? 1e18 : totalBalance.divWad(_totalSupply);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Updates this contract's total balance in terms of its underlying
     */
    function updateInternal() internal virtual {
        // Get current balanceOf this contract
        uint256 balance = contractBalanceOf(underlying);

        // Assign to totalBalance
        totalBalance = balance;

        /// @custom:event Sync
        emit Sync(totalBalance);
    }

    /**
     *  @notice Internal hook for deposits into strategies
     *  @param assets The amount of assets to deposit in the strategy
     */
    function afterDepositInternal(uint256 assets) internal virtual {}

    /**
     *  @notice Internal hook for withdrawals from strategies
     *  @param assets The amount of assets to withdraw from the strategy
     */
    function beforeWithdrawInternal(uint256 assets) internal virtual {}

    /**
     *  @notice Preview the total balance of the underlying we own from the strategy (if any)
     */
    function previewTotalBalance() internal virtual returns (uint256) {}

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     *  @custom:security non-reentrant
     */
    function deposit(uint256 assets, address recipient) external override nonReentrant update returns (uint256 shares) {
        // Transfer underlying from sender to this contract
        underlying.safeTransferFrom(_msgSender(), address(this), assets);

        // Check for deposit fee
        uint256 balanceBefore = previewTotalBalance();
        // Deposit in strategy
        afterDepositInternal(assets);
        // Balance after
        uint256 balanceAfter = previewTotalBalance();

        // Get the shares amount 
        shares = (balanceAfter - balanceBefore).divWad(exchangeRate());

        /// @custom:error CantMintZeroShares Avoid minting no shares
        if (shares <= 0) {
            revert CygnusTerminal__CantMintZeroShares();
        }

        // Avoid first depositor front-running & update shares - only for the first pool depositor
        if (totalSupply == 0) {
            // Lock initial tokens
            mintInternal(address(0xdEaD), 1000);

            // Update shares for first depositor
            shares -= 1000;
        }

        // Mint shares and emit Transfer event
        mintInternal(recipient, shares);

        /// @custom:event Deposit
        emit Deposit(_msgSender(), recipient, assets, shares);
    }

    /**
     *  @inheritdoc ICygnusTerminal
     *  @custom:security non-reentrant
     */
    function redeem(
        uint256 shares,
        address recipient,
        address owner
    ) external override nonReentrant update returns (uint256 assets) {
        // Withdraw flow
        if (_msgSender() != owner) {
            // Check msg.sender's allowance
            uint256 allowed = allowances[owner][_msgSender()]; // Saves gas for limited approvals.

            // Reverts on underflow
            if (allowed != type(uint256).max) allowances[owner][_msgSender()] = allowed - shares;
        }

        // Check current exchange rate
        assets = shares.mulWad(exchangeRate());

        /// @custom:error CantRedeemZeroAssets Avoid redeeming no assets
        if (assets <= 0) {
            revert CygnusTerminal__CantRedeemZeroAssets();
        }

        // Withdraw assets from the strategy (if any)
        beforeWithdrawInternal(assets);

        // Burn shares
        burnInternal(owner, shares);

        // Transfer assets to recipient
        underlying.safeTransfer(recipient, assets);

        /// @custom:event Withdraw
        emit Withdraw(_msgSender(), recipient, owner, assets, shares);
    }

    /**
     *  @inheritdoc ICygnusTerminal
     *  @custom:security non-reentrant only-admin 👽
     */
    function sweepToken(address token) external override nonReentrant cygnusAdmin {
        /// @custom:error CantSweepUnderlying Avoid sweeping underlying
        if (token == underlying) {
            revert CygnusTerminal__CantSweepUnderlying({token: token, underlying: underlying});
        }

        // Balance this contract has of the erc20 token we are recovering
        uint256 balance = contractBalanceOf(token);

        // Transfer token
        token.safeTransfer(_msgSender(), balance);
    }
}
