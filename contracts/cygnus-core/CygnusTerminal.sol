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

     Smart contracts to `go long` on your LP Token.

     Deposit LP Token, borrow USDC

     Structure of all Cygnus Contracts

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

    @dev: This is a fork of Impermax with some small edits. It should only be tested with Solidity >=0.8 as some 
          functions don't check for overflow/underflow and all errors are handled with the new `custom errors`
          feature among other small things...                                                                    */

// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusTerminal } from "./interfaces/ICygnusTerminal.sol";
import { ERC20Permit } from "./ERC20Permit.sol";

// Libraries
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";
import { IChainlinkNebulaOracle } from "./interfaces/IChainlinkNebulaOracle.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IMiniChef } from "./interfaces/IMiniChef.sol";

import { IDenebOrbiter } from "./interfaces/IDenebOrbiter.sol";
import { IAlbireoOrbiter } from "./interfaces/IAlbireoOrbiter.sol";

/**
 *  @title  CygnusTerminal
 *  @author CygnusDAO
 *  @notice Contract used to mint Collateral and Borrow tokens. Both Collateral/Borrow arms of Cygnus mint here
 *          to get the vault token (CygUSD for USDC deposits or CygLP for LP Token deposits).
 *          It follows similar functionality to UniswapV2Pair with some small differences.
 *          We added only the `deposit` and `redeem` functions from the erc-4626 standard to save on byte size.
 */
contract CygnusTerminal is ICygnusTerminal, ERC20Permit {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Fixed point 18 decimal math library, imports main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /**
     *  @custom:library SafeTransferLib Solady`s library for low level handling of ERC20 tokens
     */
    using SafeTransferLib for address;

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
     *  @notice We have to do a try/catch if we want to store the underlying as immutable as both borrowable
     *          and collateral call the same contract
     *  @param name_ ERC20 name of the Borrow/Collateral token
     *  @param symbol_ ERC20 symbol of the Borrow/Collateral token
     *  @param decimals_ Decimals of the Borrow/Collateral token (always 18)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20Permit(name_, symbol_, decimals_) {
        // Placeholders

        // Factory
        address factory;

        // underlying
        address asset;

        // Immutable pool id
        uint256 poolId;

        // Try collateral parameters: factory, underlying, borrowable, shuttleId
        try IDenebOrbiter(_msgSender()).collateralParameters() returns (address a, address b, address, uint256 d) {
            // placeholder factory
            factory = a;
            // placeholder underlying
            asset = b;
            // placeholder shuttleId
            poolId = d;
        } catch {
            // Catch borrowable parameters: factory, underlying, collateral, shuttleId, baseRate, multiplier
            (factory, asset, , poolId, , ) = IAlbireoOrbiter(_msgSender()).borrowParameters();
        }
        // Assign immutables to success call

        // Cygnus Factory
        hangar18 = factory;
        // Underlying
        underlying = asset;
        // Lending pool ID (shared by both borrowable and collateral)
        shuttleId = poolId;
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
        isCygnusAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal check for admins only, checks factory for admin
     */
    function isCygnusAdmin() internal view {
        // Current admin from the factory
        address admin = ICygnusFactory(hangar18).admin();

        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (_msgSender() != admin) {
            revert CygnusTerminal__MsgSenderNotAdmin({ sender: _msgSender(), factoryAdmin: admin });
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     */
    function exchangeRate() public virtual override returns (uint256) {
        // Gas savings if non-zero
        uint256 _totalSupply = totalSupply;

        // If there is no supply for this token return initial rate
        return _totalSupply == 0 ? 1e18 : totalBalance.div(_totalSupply);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal hook for deposits into strategies
     *  @param assets The amount of assets deposited
     *  @param shares The amount of shares minted
     */
    function afterDepositInternal(uint256 assets, uint256 shares) internal virtual {}

    /**
     *  @notice Internal hook for withdrawals from strategies
     *  @param assets The amount of assets being withdrawn
     *  @param shares The amount of shares burnt
     */
    function beforeWithdrawInternal(uint256 assets, uint256 shares) internal virtual {}

    /**
     *  @notice Updates this contract's total balance in terms of its underlying
     */
    function updateInternal() internal virtual {
        // Match totalBalance state to balanceOf this contract
        totalBalance = IERC20(underlying).balanceOf(address(this));

        /// @custom:event Sync
        emit Sync(totalBalance);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     *  @custom:security non-reentrant
     */
    function deposit(uint256 assets, address recipient) external override nonReentrant update returns (uint256 shares) {
        // Get the amount of shares to mint
        shares = assets.div(exchangeRate());

        /// custom:error CantMintZeroShares Avoid minting no tokens
        if (shares <= 0) {
            revert CygnusTerminal__CantMintZeroShares();
        }

        // Transfer underlying from sender to this contract
        underlying.safeTransferFrom(_msgSender(), address(this), assets);

        // Mint tokens and emit Transfer event
        mintInternal(recipient, shares);

        // Deposit assets into the strategy (if any)
        afterDepositInternal(assets, shares);

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

        // Get the amount of assets to redeem
        assets = shares.mul(exchangeRate());

        /// @custom:error CantRedeemZeroAssets Avoid redeeming 0 assets
        if (assets <= 0) {
            revert CygnusTerminal__CantRedeemZeroAssets();
        }
        /// @custom:error RedeemAmountInvalid Avoid redeeming if theres insufficient cash
        else if (assets > totalBalance) {
            revert CygnusTerminal__RedeemAmountInvalid({ assets: assets, totalBalance: totalBalance });
        }

        // Withdraw assets from the strategy (if any)
        beforeWithdrawInternal(assets, shares);

        // Burn shares
        burnInternal(owner, shares);

        // Transfer assets to recipient
        underlying.safeTransfer(recipient, assets);

        /// @custom:event Withdraw
        emit Withdraw(_msgSender(), recipient, owner, assets, shares);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusTerminal
     *  @custom:security non-reentrant
     */
    function sweepToken(address token) external override nonReentrant cygnusAdmin update {
        /// @custom:error CantSweepUnderlying Avoid sweeping underlying
        if (token == underlying) {
            revert CygnusTerminal__CantSweepUnderlying({ token: token, underlying: underlying });
        }

        // Balance this contract has of the erc20 token we are recovering
        uint256 balance = IERC20(token).balanceOf(address(this));

        // Transfer token
        token.safeTransfer(_msgSender(), balance);
    }
}
