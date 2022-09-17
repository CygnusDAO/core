/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  
    .               .            .               .      🛰️     .           .                .           .
           █████████           ---======*.                                                 .           ⠀
          ███░░░░░███                                               📡                🌔                         . 
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
    
        BORROW ORBITER V1 - `Albireo`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */

// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { IAlbireoOrbiter } from "./interfaces/IAlbireoOrbiter.sol";
import { Context } from "./utils/Context.sol";
import { ReentrancyGuard } from "./utils/ReentrancyGuard.sol";

// Contracts
import { CygnusBorrow } from "./CygnusBorrow.sol";

/**
 *  @title  AlbireoOrbiter Contract that deploys the Cygnus Borrow arm of the lending pool
 *  @author CygnusDAO
 *  @notice The Borrow Deployer contract which starts the borrow arm of the lending pool. It deploys
 *          the borrow contract with the corresponding Cygnus collateral contract address. We pass
 *          structs to avoid having to set constructors in the core contracts, being able to calculate
 *          addresses of lending pools with CREATE2
 */
contract AlbireoOrbiter is IAlbireoOrbiter, Context, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct BorrowParameters Important parameters for the borrow contracts and interest rate model
     *  @custom:member factory The address of the Cygnus factory assigned to `Hangar18`
     *  @custom:member underlying The address of the underlying borrow token (address of USDC)
     *  @custom:member collateral The address of the Cygnus collateral contract for this borrow token
     *  @custom:member shuttleId The ID for the shuttle we are deploying (shared by collateral/borrow)
     *  @custom:member baseRatePerYear The base rate per year
     *  @custom:member multiplier The slope of the interest rate
     */
    struct BorrowParameters {
        address factory;
        address underlying;
        address collateral;
        uint256 shuttleId;
        uint256 baseRatePerYear;
        uint256 multiplier;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IAlbireoOrbiter
     */
    BorrowParameters public override borrowParameters;

    /**
     *  @inheritdoc IAlbireoOrbiter
     */
    bytes32 public constant override BORROW_INIT_CODE_HASH = keccak256(type(CygnusBorrow).creationCode);

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
        uint256 shuttleId,
        uint256 baseRatePerYear,
        uint256 multiplier
    ) external override nonReentrant returns (address borrowable) {
        // Assign important addresses to pass to borrow contracts
        borrowParameters = BorrowParameters({
            factory: _msgSender(),
            underlying: underlying,
            collateral: collateral,
            shuttleId: shuttleId,
            baseRatePerYear: baseRatePerYear,
            multiplier: multiplier
        });

        // Create Borrow contract
        borrowable = address(new CygnusBorrow{ salt: keccak256(abi.encode(collateral, _msgSender())) }());

        // Delete and refund some gas
        delete borrowParameters;
    }
}
