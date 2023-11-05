//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  AlbireoOrbiter.sol
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
    .               .            .               .      🛰️     .           .                .           .
           █████████           ---======*.                                                 .           ⠀
          ███░░░░░███                                               📡                🌔                         . 
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀           .          
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .⠀
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████     .----===*  ⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .⠀
                       ███ ░███  ███ ░███                .                 .                 .  ⠀
     🛰️  .             ░░██████  ░░██████                                             .                 .           
                       ░░░░░░    ░░░░░░      -------=========*                      .                     ⠀
           .                            .       .          .            .                          .             .⠀
    
        BORROW DEPLOYER V1 - `Albireo`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {IAlbireoOrbiter} from "./interfaces/IAlbireoOrbiter.sol";

// Bytecode
import {CygnusBorrow} from "./CygnusBorrow.sol";

/**
 *  @title  AlbireoOrbiter Contract that deploys the Cygnus Borrow arm of the lending pool
 *  @author CygnusDAO
 *  @notice The Borrowable Deployer which deploys the borrowable arm of the lending pool. It deploys the borrowable
 *          contract with the factory, underlying stablecoin, corresponding Cygnus Collateral contract address, the
 *          oracle for this lending pool and the unique shuttle ID.
 *          We pass structs to avoid having to set constructors in the core contracts, being able to calculate
 *          addresses of lending pools with CREATE2
 */
contract AlbireoOrbiter is IAlbireoOrbiter {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct BorrowParameters Important parameters for the borrow contracts and interest rate model
     *  @custom:member factory The address of the Cygnus factory assigned to `Hangar18`
     *  @custom:member underlying The address of the underlying borrow token (address of USDC)
     *  @custom:member collateral The address of the Cygnus collateral contract for this borrowable
     *  @custom:member oracle The address of the oracle for this lending pool
     *  @custom:member shuttleId The ID for the shuttle we are deployin (shared by collateral)
     */
    struct BorrowParameters {
        address factory;
        address underlying;
        address collateral;
        address oracle;
        uint256 shuttleId;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IAlbireoOrbiter
     */
    BorrowParameters public override shuttleParameters;

    /**
     *  @inheritdoc IAlbireoOrbiter
     */
    bytes32 public immutable override borrowableInitCodeHash = keccak256(type(CygnusBorrow).creationCode);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc IAlbireoOrbiter
     */
    function deployAlbireo(
        address underlying,
        address collateral,
        address oracle,
        uint256 shuttleId
    ) external override returns (address borrowable) {
        // Assign important addresses to pass to borrow contracts
        shuttleParameters = BorrowParameters({
            factory: msg.sender,
            underlying: underlying,
            collateral: collateral,
            oracle: oracle,
            shuttleId: shuttleId
        });

        // Create Borrow contract
        borrowable = address(new CygnusBorrow{salt: keccak256(abi.encode(collateral, msg.sender))}());

        // Delete and refund some gas
        delete shuttleParameters;
    }
}
