// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

/**
 *  @title ICygnusDeneb The interface for a contract that is capable of deploying Cygnus collateral pools
 *  @notice A contract that constructs a Cygnus collateral pool must implement this to pass arguments to the pool
 */
interface ICygnusDeneb {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Passing the struct parameters to the collateral contract avoids setting constructor
     *  @return factory The address of the Cygnus factory
     *  @return underlying The address of the underlying LP Token
     *  @return cygnusAlbireo The address of the first Cygnus borrow token
     */
    function collateralParameters()
        external
        returns (
            address factory,
            address underlying,
            address cygnusAlbireo
        );

    /**
     *  @notice Function to deploy the collateral contract of a lending pool
     *  @param underlying The address of the underlying LP Token
     *  @param cygnusAlbireo The address of the Cygnus borrow token
     *  @return deneb The address of the new deployed Cygnus collateral contract
     */
    function deployDeneb(address underlying, address cygnusAlbireo) external returns (address deneb);
}
