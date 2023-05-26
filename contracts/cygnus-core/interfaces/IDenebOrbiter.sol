// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

/**
 *  @title ICygnusDeneb The interface for a contract that is capable of deploying Cygnus collateral pools
 *  @notice A contract that constructs a Cygnus collateral pool must implement this to pass arguments to the pool
 */
interface IDenebOrbiter {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Passing the struct parameters to the collateral contract avoids setting constructor
     *
     *  @return factory The address of the Cygnus factory
     *  @return underlying The address of the underlying LP Token
     *  @return borrowable The address of the Cygnus borrow contract for this collateral
     *  @return oracle The address of the oracle for this lending pool
     *  @return shuttleId The ID of the lending pool
     */
    function shuttleParameters()
        external
        returns (
            address factory,
            address underlying,
            address borrowable,
            address oracle,
            uint256 shuttleId
        );

    /**
     *  @return COLLATERAL_INIT_CODE_HASH The init code hash of the collateral contract for this deployer
     */
    function COLLATERAL_INIT_CODE_HASH() external view returns (bytes32);

    /**
     *  @notice Function to deploy the collateral contract of a lending pool
     *
     *  @param underlying The address of the underlying LP Token
     *  @param borrowable The address of the Cygnus borrow contract for this collateral
     *  @param oracle The address of the oracle for this lending pool
     *  @param shuttleId The ID of the lending pool
     *
     *  @return collateral The address of the new deployed Cygnus collateral contract
     */
    function deployDeneb(
        address underlying,
        address borrowable,
        address oracle,
        uint256 shuttleId
    ) external returns (address collateral);
}
