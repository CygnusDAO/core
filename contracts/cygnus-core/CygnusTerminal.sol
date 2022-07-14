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

     Deposit LP Token, borrow DAI 

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

    @dev: Should only be tested with Solidity >=0.8 as some functions don't check for overflow/underflow 
    and all errors are handled with the new `custom errors` feature among other small things...                  */

// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusTerminal } from "./interfaces/ICygnusTerminal.sol";
import { Erc20Permit } from "./Erc20Permit.sol";

// Libraries
import { SafeErc20 } from "./libraries/SafeErc20.sol";
import { PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";
import { IChainlinkNebulaOracle } from "./interfaces/IChainlinkNebulaOracle.sol";
import { IErc20 } from "./interfaces/IErc20.sol";
import { IMiniChef } from "./interfaces/IMiniChef.sol";

/**
 *  @title  CygnusTerminal
 *  @author CygnusDAO
 *  @notice Contract used to mint Collateral and Borrow tokens. Both Collateral/Borrow arms of Cygnus mint here
            to get the vault token (CygDAI or CygLP). Similar to UniswapV2Pair with some small edits, specifically
            the mint/redeem functions are edited with the masterchef for the pools
 */
contract CygnusTerminal is ICygnusTerminal, Erc20Permit {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeErc20 Low level handling of Erc20 tokens (mint, redeem, sync, skim)
     */
    using SafeErc20 for IErc20;

    /**
     *  @custom:library PRBMathUD60x18 Fixed point 18 decimal math library, imports main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice The initial exchange rate between underlying and pool tokens
     */
    uint256 internal constant INITIAL_EXCHANGE_RATE = 1e18;

    /**
     *  @notice The minimum liquidity used by Uniswap
     */
    uint256 internal constant MINIMUM_LIQUIDITY = 10**3;

    /**
     *  @notice Dead address we mint the MINIMUM_LIQUIDITY to
     */
    address internal constant DEAD_ADDRESS = address(0xdead);

    /**
     *  @notice Address of the Masterchef/Rewarder contract
     */
    IMiniChef internal rewarder;

    /**
     *  @notice Pool ID this lpTokenPair corresponds to in `rewarder`
     */
    uint256 internal pid;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     */
    uint256 public override totalBalance;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    address public override underlying;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    address public override hangar18;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    bool public override voidActivated;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs tokens for both Collateral and Borrow arms
     *  @dev We create another borrow permit for Borrow arm in CygnusBorrowApprove contract
     *  @param name_ Erc20 name of the Borrow/Collateral token
     *  @param symbol_ Erc20 symbol of the Borrow/Collateral token
     *  @param decimals_ Decimals of the Borrow/Collateral token (always 18)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) Erc20Permit(name_, symbol_, decimals_) {}

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
            5. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Updates this contract's total balance in terms of its underlying
     */
    function updateInternal() internal virtual {
        // Match totalBalance state to balanceOf this contract
        totalBalance = IErc20(underlying).balanceOf(address(this));

        /// @custom:event Sync
        emit Sync(totalBalance);
    }

    /**
     *  @notice Internal check for admins only, checks factory for admin
     */
    function isCygnusAdmin() internal view {
        // Current admin from the factory
        address admin = ICygnusFactory(hangar18).admin();

        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (_msgSender() != admin) {
            revert CygnusTerminal__MsgSenderNotAdmin({ caller: _msgSender(), factoryAdmin: admin });
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     */
    function exchangeRate() public view virtual override returns (uint256) {
        // Gas savings if non-zero
        uint256 _totalSupply = totalSupply;

        // If there is no supply for this token return initial rate, else (totalBalance * scale) / totalSupply
        return _totalSupply == 0 ? INITIAL_EXCHANGE_RATE : totalBalance.div(_totalSupply);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @dev This low level function should only be called from `Altair` contract only
     *  @inheritdoc ICygnusTerminal
     *  @custom:security non-reentrant
     */
    function mint(address minter) external override nonReentrant update returns (uint256 cygnusMintTokens) {
        // Get current balance
        uint256 balance = IErc20(underlying).balanceOf(address(this));

        // Mint and deposit in masterchef if Void is activated
        if (voidActivated) {
            // Check for pools with deposit fees
            (uint256 totalBalanceBefore, ) = rewarder.userInfo(pid, address(this));

            // Deposit in rewader
            rewarder.deposit(pid, balance);

            // Check balance after deposit
            (uint256 totalBalanceAfter, ) = rewarder.userInfo(pid, address(this));

            // Get mint amount
            balance = totalBalanceAfter - totalBalanceBefore;
        }
        // Else just mint tokens without depositing in masterchef
        else {
            balance = balance - totalBalance;
        }

        // (amount * scale) / exchangeRate
        cygnusMintTokens = balance.div(exchangeRate());

        // Only for the very first deposit
        if (totalSupply == 0) {
            // Substract from mint amount
            cygnusMintTokens -= MINIMUM_LIQUIDITY;

            // Burn to dead address, emit transfer event
            mintInternal(DEAD_ADDRESS, MINIMUM_LIQUIDITY);
        }

        /// custom:error CantMintZero Avoid minting no tokens
        if (cygnusMintTokens <= 0) {
            revert CygnusTerminal__CantMintZero(cygnusMintTokens);
        }

        // Mint tokens and emit Transfer event
        mintInternal(minter, cygnusMintTokens);

        /// @custom:event Mint
        emit Mint(_msgSender(), minter, balance, cygnusMintTokens);
    }

    /**
     *  @dev This low level function should only be called from `Altair` contract only
     *  @inheritdoc ICygnusTerminal
     *  @custom:security non-reentrant
     */
    function redeem(address holder) external override nonReentrant update returns (uint256 redeemAmount) {
        // Get current balance
        uint256 cygnusRedeemTokens = balanceOf(address(this));

        // Get the initial amount * exchange rate / scale
        redeemAmount = cygnusRedeemTokens.mul(exchangeRate());

        /// @custom:error CantBurnZero Avoid redeem unless is positive amount
        if (redeemAmount <= 0) {
            revert CygnusTerminal__CantRedeemZero(redeemAmount);
        }
        /// @custom:error BurnAmountInvalid Avoid redeeming more than shuttle's balance
        else if (redeemAmount > totalBalance) {
            revert CygnusTerminal__RedeemAmountInvalid({ invalidAmount: redeemAmount, contractBalance: totalBalance });
        }

        // Burn initial amount and emit Transfer event
        burnInternal(address(this), cygnusRedeemTokens);

        if (voidActivated) {
            rewarder.withdraw(pid, redeemAmount);
        }

        // Optimistically transfer redeemed tokens
        IErc20(underlying).safeTransfer(holder, redeemAmount);

        /// @custom:event Redeem
        emit Redeem(_msgSender(), holder, redeemAmount, cygnusRedeemTokens);
    }

    /**
     *  @inheritdoc ICygnusTerminal
     *  @custom:security non-reentrant
     */
    function skim(address recipient) external override nonReentrant {
        // Uniswap's function to force real balance to match totalBalance
        IErc20(underlying).safeTransfer(recipient, balanceOf(address(this)) - totalBalance);
    }

    /**
     *  @inheritdoc ICygnusTerminal
     *  @custom:security non-reentrant
     */
    function sync() external virtual override nonReentrant {
        updateInternal();
    }
}
