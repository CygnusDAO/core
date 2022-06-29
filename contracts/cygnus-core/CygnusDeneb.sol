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
import { ICygnusDeneb } from "./interfaces/ICygnusDeneb.sol";
import { Context } from "./utils/Context.sol";
import { ReentrancyGuard } from "./utils/ReentrancyGuard.sol";

// Collateral contract
import { CygnusCollateral } from "./CygnusCollateral.sol";

/**
 *  @title  CygnusDeneb
 *  @notice This is the Collateral Deployer for Cygnus which starts the collateral arm of the lending pool
 */
contract CygnusDeneb is ICygnusDeneb, Context, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Passing the struct parameters to the collateral contract avoids setting constructor
     *  @custom:struct CollateralParameters Important parameters for the collateral contracts
     *  @custom:member factory The address of the Cygnus factory
     *  @custom:member underlying The address of the underlying LP Token
     *  @custom:member cygnusAlbireo The address of the first Cygnus borrow token
     */
    struct CollateralParameters {
        address factory;
        address underlying;
        address cygnusAlbireo;
    }

    /**
     *  @inheritdoc ICygnusDeneb
     */
    CollateralParameters public override collateralParameters;

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusDeneb
     */
    function deployDeneb(address underlying, address borrowable)
        external
        override
        nonReentrant
        returns (address deneb)
    {
        // Assign important addresses to pass to collateral contracts
        collateralParameters = CollateralParameters({
            factory: _msgSender(),
            underlying: underlying,
            cygnusAlbireo: borrowable
        });

        // Create Collateral contract
        deneb = address(new CygnusCollateral{ salt: keccak256(abi.encode(underlying, _msgSender())) }());

        // Delete and refund some gas
        delete collateralParameters;
    }
}
