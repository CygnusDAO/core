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
 *  @title CygnusAlbireo The Borrow Deployer contract which starts the borrow arm of the lending pool
 */
contract CygnusAlbireo is ICygnusAlbireo, Context, ReentrancyGuard {
    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @dev Values get deleted after deploying a new contract so these should always return 0
     *  @custom:struct BorrowParameters Important parameters for the borrow contracts
     *  @custom:member factory The address of the Cygnus factory assigned to `Hangar18`
     *  @custom:member underlying The address of the underlying borrow token (address of DAI, USDc, etc.)
     *  @custom:member cygnusDeneb The address of the Cygnus collateral contract for this borrow token
     &  @custom:member baseRatePerYear The base rate per year for this shuttle
     *  @custom:member farmApy The farm APY for this LP Token
     *  @custom:member kinkUtilizationRate The kink utilization rate for this pool
     */
    struct BorrowParameters {
        address factory;
        address underlying;
        address cygnusDeneb;
        uint256 baseRatePerYear;
        uint256 farmApy;
        uint256 kinkUtilizationRate;
    }

    /**
     *  @inheritdoc ICygnusAlbireo
     */
    BorrowParameters public override borrowParameters;

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAlbireo
     */
    function deployAlbireo(
        address underlying,
        address collateral,
        uint256 baseRatePerYear,
        uint256 farmApy,
        uint256 kinkUtilizationRate
    ) external override nonReentrant returns (address albireo) {
        // Assign important addresses to pass to borrow contracts
        borrowParameters = BorrowParameters({
            factory: _msgSender(),
            underlying: underlying,
            cygnusDeneb: collateral,
            baseRatePerYear: baseRatePerYear,
            farmApy: farmApy,
            kinkUtilizationRate: kinkUtilizationRate
        });

        // Create Borrow contract
        albireo = address(new CygnusBorrow{ salt: keccak256(abi.encode(collateral, _msgSender())) }());

        // Delete and refund some gas
        delete borrowParameters;
    }
}
