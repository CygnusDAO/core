//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusTerminal.sol
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
pragma solidity >=0.8.17;

// Dependencies
import {IERC20Permit} from "./IERC20Permit.sol";

// Interfaces
import {IHangar18} from "./IHangar18.sol";
import {IAllowanceTransfer} from "./IAllowanceTransfer.sol";
import {ICygnusNebula} from "./ICygnusNebula.sol";

/**
 *  @title ICygnusTerminal
 *  @notice The interface to mint/redeem pool tokens (CygLP and CygUSD)
 */
interface ICygnusTerminal is IERC20Permit {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when attempting to mint zero shares
     *  @custom:error CantMintZeroShares
     */
    error CygnusTerminal__CantMintZeroShares();

    /**
     *  @dev Reverts when attempting to redeem zero assets
     *  @custom:error CantBurnZeroAssets
     */
    error CygnusTerminal__CantRedeemZeroAssets();

    /**
     *  @dev Reverts when attempting to call Admin-only functions
     *  @custom:error MsgSenderNotAdmin
     */
    error CygnusTerminal__MsgSenderNotAdmin();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when totalBalance syncs with the underlying contract's balanceOf.
     *  @param totalBalance Total balance in terms of the underlying
     *  @custom:event Sync
     */
    event Sync(uint160 totalBalance);

    /**
     *  @dev Logs when CygLP or CygUSD pool tokens are minted
     *  @param sender The address of `CygnusAltair` or the sender of the function call
     *  @param recipient Address of the minter
     *  @param assets Amount of assets being deposited
     *  @param shares Amount of pool tokens being minted
     *  @custom:event Mint
     */
    event Deposit(address indexed sender, address indexed recipient, uint256 assets, uint256 shares);

    /**
     *  @dev Logs when CygLP or CygUSD are redeemed
     *  @param sender The address of the redeemer of the shares
     *  @param recipient The address of the recipient of assets
     *  @param owner The address of the owner of the pool tokens
     *  @param assets The amount of assets to redeem
     *  @param shares The amount of pool tokens burnt
     *  @custom:event Redeem
     */
    event Withdraw(address indexed sender, address indexed recipient, address indexed owner, uint256 assets, uint256 shares);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
           3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return Address of the Permit2 router on this chain. We use the AllowanceTransfer instead of SignatureTransfer 
     *          to allow deposits from other smart contracts.
     *        
     */
    function PERMIT2() external view returns (IAllowanceTransfer);

    /**
     *  @return The address of the Cygnus Factory contract used to deploy this shuttle
     */
    function hangar18() external view returns (IHangar18);

    /**
     *  @return The address of the underlying asset (stablecoin for Borrowable, LP Token for collateral)
     */
    function underlying() external view returns (address);

    /**
     *  @return The address of the oracle for this lending pool
     */
    function nebula() external view returns (ICygnusNebula);

    /**
     *  @return The unique ID of the lending pool, shared by Borrowable and Collateral
     */
    function shuttleId() external view returns (uint256);

    /**
     *  @return Total available cash deposited in the strategy (stablecoin for Borrowable, LP Token for collateral)
     */
    function totalBalance() external view returns (uint160);

    /**
     *  @return The total assets owned by the vault. Same as total balance, but includes total borrows for Borrowable.
     */
    function totalAssets() external view returns (uint256);

    /**
     *  @return The exchange rate between 1 vault share (CygUSD/CygLP) and the underlying asset
     */
    function exchangeRate() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Deposits the underlying asset into the vault (stablecoins for borrowable, LP tokens for collateral).
     *          Users must approve the Permit2 router in the underlying before depositing. Users can bypass
     *          the permit and signature arguments by also approving the vault contract in the Permit2 router
     *          and pass an empty permit and signature.
     *  @param assets Amount of the underlying asset to deposit.
     *  @param recipient Address that will receive the corresponding amount of shares.
     *  @param _permit Data signed over by the owner specifying the terms of approval
     *  @param _signature The owner's signature over the permit data
     *  @return shares Amount of Cygnus Vault shares minted and transferred to the `recipient`.
     *  @custom:security non-reentrant
     */
    function deposit(
        uint256 assets,
        address recipient,
        IAllowanceTransfer.PermitSingle calldata _permit,
        bytes calldata _signature
    ) external returns (uint256 shares);

    /**
     *  @notice Redeems vault shares and transfers out assets (stablecoins for borrowable, LP tokens for collateral).
     *  @param shares The number of shares to redeem for the underlying asset.
     *  @param recipient The address that will receive the underlying asset.
     *  @param owner The address that owns the shares.
     *  @return assets The amount of underlying assets received by the `recipient`.
     *  @custom:security non-reentrant
     */
    function redeem(uint256 shares, address recipient, address owner) external returns (uint256 assets);

    /**
     *  @notice Syncs `totalBalance` in terms of its underlying
     *  @custom:security non-reentrant
     */
    function sync() external;
}
