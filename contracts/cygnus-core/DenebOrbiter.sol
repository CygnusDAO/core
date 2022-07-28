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

// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { IDenebOrbiter } from "./interfaces/IDenebOrbiter.sol";
import { Context } from "./utils/Context.sol";
import { ReentrancyGuard } from "./utils/ReentrancyGuard.sol";

// Collateral contract
import { CygnusCollateral } from "./CygnusCollateral.sol";

/**
 *  @title  CygnusDeneb Contract that deploys the Cygnus Collateral arm of the lending pool
 *  @author CygnusDAO
 *  @notice The Collateral Deployer which starts the collateral arm of the lending pool. It deploys the collateral
 *          contract with the corresponding Cygnus borrow contract address, the factory and the underlying LP Token.
 *          We pass structs to avoid having to set constructors in the core contracts, being able to calculate
 *          addresses of lending pools with CREATE2
 */
contract DenebOrbiter is IDenebOrbiter, Context, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct CollateralParameters Important parameters for the collateral contracts
     *  @custom:member factory The address of the Cygnus factory
     *  @custom:member underlying The address of the underlying LP Token
     *  @custom:member cygnusDai The address of the Cygnus borrow contract for this collateral
     */
    struct CollateralParameters {
        address factory;
        address underlying;
        address cygnusDai;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IDenebOrbiter
     */
    CollateralParameters public override collateralParameters;

    /**
     *  @inheritdoc IDenebOrbiter
     */
    bytes32 public constant override COLLATERAL_INIT_CODE_HASH = keccak256(type(CygnusCollateral).creationCode);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc IDenebOrbiter
     */
    function deployDeneb(address underlying, address cygnusDai)
        external
        override
        nonReentrant
        returns (address collateral)
    {
        // Assign important addresses to pass to collateral contracts
        collateralParameters = CollateralParameters({
            factory: _msgSender(),
            underlying: underlying,
            cygnusDai: cygnusDai
        });

        // Create Collateral contract
        collateral = address(new CygnusCollateral{ salt: keccak256(abi.encode(underlying, _msgSender())) }());

        // Delete and refund some gas
        delete collateralParameters;
    }
}
