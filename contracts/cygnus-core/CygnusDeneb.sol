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
 *  @title CygnusDeneb The Collateral Deployer which starts the collateral arm of the lending pool. It deploys
 *                     the collateral contract with the corresponding Cygnus borrow contract address. We pass
 *                     structs to avoid having to set constructors in the core contracts, being able to calculate
 *                     addresses of lending pools with CREATE2
 *  @author CygnusDAO
 *  @notice Collateral Deployer V1
 */
contract CygnusDeneb is ICygnusDeneb, Context, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
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

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusDeneb
     */
    CollateralParameters public override collateralParameters;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusDeneb
     */
    function deployDeneb(address underlying, address borrowContract)
        external
        override
        nonReentrant
        returns (address deneb)
    {
        // Assign important addresses to pass to collateral contracts
        collateralParameters = CollateralParameters({
            factory: _msgSender(),
            underlying: underlying,
            cygnusAlbireo: borrowContract
        });

        // Create Collateral contract
        deneb = address(new CygnusCollateral{ salt: keccak256(abi.encode(underlying, _msgSender())) }());

        // Delete and refund some gas
        delete collateralParameters;
    }
}
