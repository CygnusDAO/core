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
    
        BORROW DEPLOYER V1 - `Albireo`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */

// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusAlbireo } from "./interfaces/ICygnusAlbireo.sol";
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
contract CygnusAlbireo is ICygnusAlbireo, Context, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct BorrowParameters Important parameters for the borrow contracts
     *  @custom:member factory The address of the Cygnus factory assigned to `Hangar18`
     *  @custom:member underlying The address of the underlying borrow token (address of DAI, USDc, etc.)
     *  @custom:member cygnusDeneb The address of the Cygnus collateral contract for this borrow token
     &  @custom:member baseRatePerYear The base rate per year for this shuttle
     *  @custom:member farmApy The farm APY for this LP Token
     *  @custom:member kinkMultiplier The multiplier applied to the farmApy once kink util is reached
     */
    struct BorrowParameters {
        address factory;
        address underlying;
        address cygnusDeneb;
        uint256 baseRatePerYear;
        uint256 farmApy;
        uint256 kinkMultiplier;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAlbireo
     */
    BorrowParameters public override borrowParameters;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAlbireo
     */
    function deployAlbireo(
        address underlying,
        address collateralContract,
        uint256 baseRatePerYear,
        uint256 farmApy,
        uint256 kinkMultiplier
    ) external override nonReentrant returns (address albireo) {
        // Assign important addresses to pass to borrow contracts
        borrowParameters = BorrowParameters({
            factory: _msgSender(),
            underlying: underlying,
            cygnusDeneb: collateralContract,
            baseRatePerYear: baseRatePerYear,
            farmApy: farmApy,
            kinkMultiplier: kinkMultiplier
        });

        // Create Borrow contract
        albireo = address(new CygnusBorrow{ salt: keccak256(abi.encode(collateralContract, _msgSender())) }());

        // Delete and refund some gas
        delete borrowParameters;
    }
}
