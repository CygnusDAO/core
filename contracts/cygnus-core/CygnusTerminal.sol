//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusTerminal.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.

/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
    
           █████████                🛸         🛸                              🛸          .                    
     🛸   ███░░░░░███                                              📡                                     🌔   
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀        🛰️   .             
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .           
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████       -----========*⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .
                       ███ ░███  ███ ░███                .                 .         🛸           ⠀             
         .    🛸*     ░░██████  ░░██████   .    🛸                     🛰️            -----=========*                 
                       ░░░░░░    ░░░░░░                                               🛸  ⠀
           .                            .       .             🛰️         .                          
    
        POOL TOKEN (CygUSD/CygLP) - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════ */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusTerminal} from "./interfaces/ICygnusTerminal.sol";
import {ERC20} from "./ERC20.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries
import {SafeCastLib} from "./libraries/SafeCastLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IOrbiter} from "./interfaces/IOrbiter.sol";
import {IHangar18} from "./interfaces/IHangar18.sol";
import {ICygnusNebula} from "./interfaces/ICygnusNebula.sol";
import {IAllowanceTransfer} from "./interfaces/IAllowanceTransfer.sol";

/**
 *  @title  CygnusTerminal
 *  @author CygnusDAO
 *  @notice Contract used to mint Collateral and Borrow tokens. Both Collateral/Borrow arms of Cygnus mint here
 *          to get the vault token (CygUSD for stablecoin deposits and CygLP for Liquidity deposits).
 *  @notice As the borrowable arm is a stablecoin vault which has assets deposited in strategies, the exchange
 *          rate for CygUSD should be the cash deposited in the strategy + current borrows. Therefore we use an 
 *          internal `_totalAssets(bool)` to take into account latest borrows. The bool dictates whether we should 
 *          simulate accruals or not, helpful for the contract to always display data in real time.
 *
 *  @notice Functions overridden in Strategy contracts (CygnusBorrowVoid.sol & CygnusCollateralVoid.sol):
 *            _afterDeposit        - borrowable/collateral - Deposits underlying into a strategy
 *            _beforeWithdraw      - borrowable/collateral - Withdraws underlying from a strategy
 *            _previewTotalBalance - borrowable/collateral - Previews available cash (USDC or LP) without updating storage
 *
 *          Functions overriden in the Borrow Model contract (CygnusBorrowModel.sol)
 *            _totalAssets         - borrowable            - Includes borrows in the total assets calculation (cash + borrows)
 *            update (modifier)    - borrowable            - Includes accruals before any payable actions
 *
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

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Total balance of the underlying (USDC for borrowable, LP's for collateral) updated after
     *          every state changing action
     */
    uint160 internal _totalBalance;

    /**
     *  @notice The address of this contract`s opposite arm. For collateral pools, this is the borrowable address.
     *          For borrowable pools, this is the collateral address. Getters in child contract.
     */
    address internal immutable twinstar;

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
    address public immutable override underlying;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    ICygnusNebula public immutable override nebula;

    /**
     *  @inheritdoc ICygnusTerminal
     */
    uint256 public immutable override shuttleId;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs tokens for both Collateral and Borrow arms
     */
    constructor() {
        // Get immutables from deployer contract who is msg.sender of deployments
        // Factory, asset, borrow/collateral, oracle, lending pool ID
        (hangar18, underlying, twinstar, nebula, shuttleId) = IOrbiter(msg.sender).shuttleParameters();
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
     *  @notice We override in borrowable arm to accrue interest before any state changing action.
     *  @custom:modifier update Updates `_totalBalance` in terms of its underlying
     *  @custom:override CygnusBorrowModel
     */
    modifier update() virtual {
        _;
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
     *  @notice Converts assets to shares
     *  @notice We always pass false to `_totalAssets()` to not get borrow indices as stored variables are in sync.
     *          This is because this function is only called during deposits/redeems/accruals which accrue interest
     *          beforehand with the `update` modifier.
     */
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        // Gas savings if non-zero
        uint256 _totalSupply = totalSupply();

        // Compute shares given an amount of stablecoin of LP token assets
        return _totalSupply == 0 ? assets : assets.fullMulDiv(_totalSupply, _totalAssets(false));
    }

    /**
     *  @notice Convert shares to assets. Same as above, pass false to `_totalAssets()` as we have already accrued
     */
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        // Gas savings if non-zero
        uint256 _totalSupply = totalSupply();

        // Compute assets given an amount of CygUSD or CygLP shares
        return _totalSupply == 0 ? shares : shares.fullMulDiv(_totalAssets(false), _totalSupply);
    }

    /**
     *  @notice Previews our balance of the underlying asset
     *  @custom:override CygnusBorrowVoid
     *  @custom:override CygnusCollateralVoid
     */
    function _previewTotalBalance() internal view virtual returns (uint256) {}

    /**
     *  @notice Previews the total assets owned by the vault. Overridden by the borrowable arm.
     *          For collateral = LPs in the strategy.
     *          For borrowable = USDC in the strategy + Borrows.
     *  @notice The bool argument is to check if we should simulate interest accrual or not.
     *  @custom:override CygnusBorrowModel
     */
    function _totalAssets(bool) internal view virtual returns (uint256) {
        // The bool is only necessary in Borrowable which is overridden
        return _totalBalance;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice This is overriden by borrowable arm to include total borrows in the shares calculation
     *  @inheritdoc ICygnusTerminal
     */
    function totalAssets() public view override returns (uint256) {
        // Internal _totalAssets dictates whether we should simulate interest accruals or not in borrowable.
        // For collateral this has no effect.
        return _totalAssets(true);
    }

    /**
     *  @notice Computes the exchange rate between 1 unit of the vault token and the underlying asset
     *  @inheritdoc ICygnusTerminal
     */
    function exchangeRate() public view override returns (uint256) {
        // Gas savings if non-zero
        uint256 _totalSupply = totalSupply();

        // Borrowable uses internal `_totalAssets` to get the borrow indices which takes into account latest borrows
        return _totalSupply == 0 ? 1e18 : totalAssets().divWad(_totalSupply);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTerminal
     */
    function totalBalance() external view override returns (uint256) {
        // For collateral it's the same as totalAssets()
        // For borrowable it's the USDC balance deposited in the strategy
        return _previewTotalBalance();
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Updates this contract's total balance in terms of its underlying. This is triggered after any
     *          state-changing function is called.
     */
    function _update() internal {
        // Preview the total assets of stablecoin or LP we own
        uint256 balance = _previewTotalBalance();

        /// @custom:event Sync
        emit Sync(_totalBalance = SafeCastLib.toUint160(balance));
    }

    /**
     *  @notice Internal hook for deposits into strategies
     *  @param assets The amount of assets to deposit in the strategy
     *  @custom:override CygnusBorrowVoid
     *  @custom:override CygnusCollateralVoid
     */
    function _afterDeposit(uint256 assets) internal virtual {}

    /**
     *  @notice Internal hook for withdrawals from strategies
     *  @param assets The amount of assets to withdraw from the strategy
     *  @custom:override CygnusBorrowVoid
     *  @custom:override CygnusCollateralVoid
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
    ) external override nonReentrant update returns (uint256 shares) {
        // Convert assets deposited to shares
        shares = _convertToShares(assets);

        /// @custom:error CantMintZeroShares Avoid minting no shares
        if (shares == 0) revert CygnusTerminal__CantMintZeroShares();

        // Check for permit to approve and deposit in 1 tx. Users can just approve this contract in
        // permit2 and skip this by passing an empty signature).
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

        // Avoid inflation attack on the vault - This is only for the first pool depositor as after there will always
        // be 1000 shares locked in zero address
        if (totalSupply() == 0) {
            // Update shares for first depositor
            shares -= 1000;

            // Lock initial tokens
            _mint(address(0), 1000);
        }

        // Mint shares and emit Transfer event
        _mint(recipient, shares);

        // Deposit in strategy
        _afterDeposit(assets);

        /// @custom:event Deposit
        emit Deposit(msg.sender, recipient, assets, shares);
    }

    /**
     *  @inheritdoc ICygnusTerminal
     */
    function redeem(uint256 shares, address recipient, address owner) external override nonReentrant update returns (uint256 assets) {
        // Withdraw flow
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

        // Check current exchange rate
        assets = _convertToAssets(shares);

        /// @custom:error CantRedeemZeroAssets Avoid redeeming no assets
        if (assets == 0) revert CygnusTerminal__CantRedeemZeroAssets();

        // Withdraw assets from the strategy (if any)
        _beforeWithdraw(assets);

        // Burn shares
        _burn(owner, shares);

        // Transfer assets to recipient
        underlying.safeTransfer(recipient, assets);

        /// @custom:event Withdraw
        emit Withdraw(msg.sender, recipient, owner, assets, shares);
    }
}
