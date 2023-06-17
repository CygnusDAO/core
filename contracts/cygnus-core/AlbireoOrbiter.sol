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

// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {IAlbireoOrbiter} from "./interfaces/IAlbireoOrbiter.sol";

// CygnusBorrow.sol
import {CygnusBorrow} from "./CygnusBorrow.sol";

/**
 *  @title  AlbireoOrbiter Contract that deploys the Cygnus Borrow arm of the lending pool
 *  @author CygnusDAO
 *  @notice The Borrow Deployer contract which starts the borrow arm of the lending pool. It deploys the borrow
 *          contract with the corresponding Cygnus collateral contract address. We pass structs to avoid having
 *          to set constructors in the core contracts, being able to calculate addresses of lending pools with
 *          CREATE2
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
     *  @custom:member shuttleId The ID for the shuttle we are deploying (shared by collateral/borrow)
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
