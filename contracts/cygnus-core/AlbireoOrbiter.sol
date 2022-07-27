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

// Borrow contract
import { CygnusBorrow } from "./CygnusBorrow.sol";

/**
 *  @title  CygnusAlbireo Contract that deploys the Cygnus Borrow arm of the lending pool
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
     *  @custom:struct BorrowParameters Important parameters for the borrow contracts
     *  @custom:member factory The address of the Cygnus factory assigned to `Hangar18`
     *  @custom:member underlying The address of the underlying borrow token (address of DAI, USDc, etc.)
     *  @custom:member collateral The address of the Cygnus collateral contract for this borrow token
     &  @custom:member baseRatePerYear The base rate per year for this shuttle
     *  @custom:member farmApy The farm APY for this LP Token
     *  @custom:member kinkUtilizationRate The kink utilization rate for this pool
     */
    struct BorrowParameters {
        address factory;
        address underlying;
        address collateral;
        uint256 baseRatePerYear;
        uint256 multiplier;
        uint256 kinkMultiplier;
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
        uint256 baseRatePerYear,
        uint256 multiplier,
        uint256 kinkMultiplier
    ) external override nonReentrant returns (address cygnusDai) {
        // Assign important addresses to pass to borrow contracts
        borrowParameters = BorrowParameters({
            factory: _msgSender(),
            underlying: underlying,
            collateral: collateral,
            baseRatePerYear: baseRatePerYear,
            multiplier: multiplier,
            kinkMultiplier: kinkMultiplier
        });

        // Create Borrow contract
        cygnusDai = address(new CygnusBorrow{ salt: keccak256(abi.encode(collateral, _msgSender())) }());

        // Delete and refund some gas
        delete borrowParameters;
    }
}
