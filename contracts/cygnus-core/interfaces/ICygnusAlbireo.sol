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
     *  @return collateral The address of the Cygnus collateral contract for this borrow contract
     *  @return baseRatePerYear The base rate per year for this shuttle
     *  @return multiplier The multiplier per year
     *  @return kinkMultiplier The increase to the multiplier once kink utilization is reached
     */
    function borrowParameters()
        external
        returns (
            address factory,
            address underlying,
            address collateral,
            uint256 baseRatePerYear,
            uint256 multiplier,
            uint256 kinkMultiplier
        );

    /**
     *  @return BORROW_INIT_CODE_HASH The init code hash of the borrow contract for this deployer
     */
    function BORROW_INIT_CODE_HASH() external view returns (bytes32);

    /**
     *  @notice Function to deploy the borrow contract of a lending pool
     *  @param underlying The address of the underlying borrow token (address of DAI, USDc, etc.)
     *  @param collateral The address of the Cygnus collateral contract for this borrow contract
     *  @param baseRatePerYear The base rate per year for this shuttle
     *  @param multiplier The farm APY for this LP Token
     *  @param kinkMultiplier The increase to farmApy once kink utilization is reached
     *  @return cygnusDai The address of the new borrow contract
     */
    function deployAlbireo(
        address underlying,
        address collateral,
        uint256 baseRatePerYear,
        uint256 multiplier,
        uint256 kinkMultiplier
    ) external returns (address cygnusDai);
}
