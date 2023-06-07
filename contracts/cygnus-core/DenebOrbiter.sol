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
    
        COLLATERAL ORBITER V1 - `Deneb`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */

// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {IDenebOrbiter} from "./interfaces/IDenebOrbiter.sol";

// Contracts
import {CygnusCollateral} from "./CygnusCollateral.sol";

/**
 *  @title  DenebOrbiter Contract that deploys the Cygnus Collateral arm of the lending pool
 *  @author CygnusDAO
 *  @notice The Collateral Deployer which starts the collateral arm of the lending pool. It deploys the collateral
 *          contract with the corresponding Cygnus borrow contract address, the factory and the underlying LP Token.
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
