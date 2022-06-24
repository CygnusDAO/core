// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

/**
 *  @title ICygnusAlbireo The interface the Cygnus borrow deployer
 *  @notice A contract that constructs a Cygnus borrow pool must implement this to pass arguments to the pool
 */
interface ICygnusAlbireo {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Passing the struct parameters to the borrow contracts avoids setting constructor parameters
     *  @return factory The address of the Cygnus factory assigned to `Hangar18`
     *  @return underlying The address of the underlying borrow token (address of DAI, USDc, etc.)
     *  @return cygnusDeneb The address of the Cygnus collateral contract for this borrow token
     *  @return baseRatePerYear The base rate per year for this shuttle
     *  @return farmApy The farm APY for this LP Token
     *  @return kinkUtilizationRate The kink utilization rate for this pool
     */
    function borrowParameters()
        external
        returns (
            address factory,
            address underlying,
            address cygnusDeneb,
            uint256 baseRatePerYear,
            uint256 farmApy,
            uint256 kinkUtilizationRate
        );

    /**
     *  @notice Function to deploy the borrow contract of a lending pool
     *  @param underlying The address of the underlying borrow token (address of DAI, USDc, etc.)
     *  @param cygnusDeneb The address of the Cygnus collateral contract for this borrow token
     *  @param baseRatePerYear The base rate per year for this shuttle
     *  @param farmApy The farm APY for this LP Token
     *  @param kinkUtilizationRate The kink utilization rate for this pool
     *  @return albireo The address of the new borrow contract
     */
    function deployAlbireo(
        address underlying,
        address cygnusDeneb,
        uint256 baseRatePerYear,
        uint256 farmApy,
        uint256 kinkUtilizationRate
    ) external returns (address albireo);
}
