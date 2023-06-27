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
     *
     *  @custom:error CantMintZeroShares
     */
    error CygnusTerminal__CantMintZeroShares();

    /**
     *  @dev Reverts when attempting to redeem zero assets
     *
     *  @custom:error CantBurnZeroAssets
     */
    error CygnusTerminal__CantRedeemZeroAssets();

    /**
     *  @dev Reverts when attempting to call Admin-only functions
     *
     *  @custom:error MsgSenderNotAdmin
     */
    error CygnusTerminal__MsgSenderNotAdmin();

    /**
     *  @dev Reverts when trying to sweep the underlying asset from this contract
     *
     *  @custom:error CantSweepUnderlying
     */
    error CygnusTerminal__CantSweepUnderlying();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when totalBalance syncs with the underlying contract's balanceOf.
     *
     *  @param totalBalance Total balance in terms of the underlying
     *
     *  @custom:event Sync
     */
    event Sync(uint160 totalBalance);

    /**
     *  @dev Logs when CygLP or CygUSD pool tokens are minted
     *
     *  @param sender The address of `CygnusAltair` or the sender of the function call
     *  @param recipient Address of the minter
     *  @param assets Amount of assets being deposited
     *  @param shares Amount of pool tokens being minted
     *
     *  @custom:event Mint
     */
    event Deposit(address indexed sender, address indexed recipient, uint256 assets, uint256 shares);

    /**
     *  @dev Logs when CygLP or CygUSD are redeemed
     *
     *  @param sender The address of the redeemer of the shares
     *  @param recipient The address of the recipient of assets
     *  @param owner The address of the owner of the pool tokens
     *  @param assets The amount of assets to redeem
     *  @param shares The amount of pool tokens burnt
     *
     *  @custom:event Redeem
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
     *  @return PERMIT2 Uniswap's Permit2 router. We use the AllowanceTransfer as opposed to SignatureTransfer
     *                  to allow router deposits.
     */
    function PERMIT2() external view returns (IAllowanceTransfer);

    /**
     *  @return hangar18 The address of the Cygnus Factory contract used to deploy this shuttle
     */
    function hangar18() external view returns (IHangar18);

    /**
     *  @return underlying The address of the underlying (LP Token for collateral contracts, USDC for borrow contracts)
     */
    function underlying() external view returns (address);

    /**
     *  @return cygnusNebulaOracle The address of the oracle for this lending pool
     */
    function cygnusNebulaOracle() external view returns (ICygnusNebula);

    /**
     *  @return shuttleId The ID of this shuttle (shared by Collateral and Borrow)
     */
    function shuttleId() external view returns (uint256);

    /**
     *  @return totalBalance Total balance owned by this shuttle pool in terms of its underlying
     */
    function totalBalance() external view returns (uint160);

    /**
     *  @return exchangeRate The ratio which 1 pool token can be redeemed for underlying amount.
     */
    function exchangeRate() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice This function must be called with the `approve` method of the underlying asset token contract for
     *          the `assets` amount on behalf of the sender before calling this function.
     *  @notice Implements the deposit of the underlying asset into the Cygnus Vault pool. This function transfers
     *          the underlying assets from the sender to this contract and mints a corresponding amount of Cygnus
     *          Vault shares to the recipient. A deposit fee may be charged by the strategy, which is deducted from
     *          the deposited assets.
     *
     *  @dev If the deposit amount is less than or equal to 0, this function will revert.
     *
     *  @param assets Amount of the underlying asset to deposit.
     *  @param recipient Address that will receive the corresponding amount of shares.
     *  @param _permit Data signed over by the owner specifying the terms of approval
     *  @param _signature The owner's signature over the permit data
     *  @return shares Amount of Cygnus Vault shares minted and transferred to the `recipient`.
     */
    function deposit(
        uint256 assets,
        address recipient,
        IAllowanceTransfer.PermitSingle calldata _permit,
        bytes calldata _signature
    ) external returns (uint256 shares);

    /**
     *  @notice Redeems the specified amount of `shares` for the underlying asset and transfers it to `recipient`.
     *
     *  @dev shares must be greater than 0.
     *  @dev If the function is called by someone other than `owner`, then the function will reduce the allowance
     *       granted to the caller by `shares`.
     *
     *  @param shares The number of shares to redeem for the underlying asset.
     *  @param recipient The address that will receive the underlying asset.
     *  @param owner The address that owns the shares.
     *
     *  @return assets The amount of underlying assets received by the `recipient`.
     */
    function redeem(uint256 shares, address recipient, address owner) external returns (uint256 assets);
}
