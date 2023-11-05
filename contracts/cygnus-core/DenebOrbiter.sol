//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  DenebOrbiter.sol
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

/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  .
    .               .            .               .      🛰️     .           .                 *              .
           █████████           ---======*.                                                 .           ⠀
          ███░░░░░███                                               📡                🌔                       . 
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀           .           .
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .⠀
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████     .----===*  ⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .⠀
                       ███ ░███  ███ ░███                .                 .                 .  ⠀
     🛰️  .             ░░██████  ░░██████                                             .                 .           
                       ░░░░░░    ░░░░░░      -------=========*                      .                     ⠀
           .                            .       .          .            .                          .             .⠀
    
        COLLATERAL DEPLOYER V1 - `Deneb`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {IDenebOrbiter} from "./interfaces/IDenebOrbiter.sol";

// Bytecode
import {CygnusCollateral} from "./CygnusCollateral.sol";

/**
 *  @title  DenebOrbiter Contract that deploys the Cygnus Collateral arm of the lending pool
 *  @author CygnusDAO
 *  @notice The Collateral Deployer which deploys the collateral arm of the lending pool. It deploys the collateral
 *          contract with the factory, underlying LP token, corresponding Cygnus Borrow contract address, the 
 *          oracle for this lending pool and the unique shuttle ID.
 *          We pass structs to avoid having to set constructors in the core contracts, being able to calculate
 *          addresses of lending pools with CREATE2
 */
contract DenebOrbiter is IDenebOrbiter {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct CollateralParameters Important parameters for the collateral contracts
     *  @custom:member factory The address of the Cygnus factory
     *  @custom:member underlying The address of the underlying LP Token
     *  @custom:member borrowable The address of the Cygnus borrow contract for this collateral
     *  @custom:member oracle The address of the oracle for this lending pool
     *  @custom:member shuttleId The unique id of this lending pool (shared by borrowable)
     */
    struct CollateralParameters {
        address factory;
        address underlying;
        address borrowable;
        address oracle;
        uint256 shuttleId;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IDenebOrbiter
     */
    CollateralParameters public override shuttleParameters;

    /**
     *  @inheritdoc IDenebOrbiter
     */
    bytes32 public immutable override collateralInitCodeHash = keccak256(type(CygnusCollateral).creationCode);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc IDenebOrbiter
     */
    function deployDeneb(
        address underlying,
        address borrowable,
        address oracle,
        uint256 shuttleId
    ) external override returns (address collateral) {
        // Assign important addresses to pass to collateral contracts
        shuttleParameters = CollateralParameters({
            factory: msg.sender,
            underlying: underlying,
            borrowable: borrowable,
            oracle: oracle,
            shuttleId: shuttleId
        });

        // Create Collateral contract
        collateral = address(new CygnusCollateral{salt: keccak256(abi.encode(underlying, msg.sender))}());

        // Delete and refund some gas
        delete shuttleParameters;
    }
}
