// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

/**
 *  @title ICygnusAlbireo The interface the Cygnus borrow deployer
 *  @notice A contract that constructs a Cygnus borrow pool must implement this to pass arguments to the pool
 */
interface IAlbireoOrbiter {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Passing the struct parameters to the borrow contracts avoids setting constructor parameters
     *
     *  @return factory The address of the Cygnus factory assigned to `Hangar18`
     *  @return underlying The address of the underlying borrow token (address of USDC)
     *  @return collateral The address of the Cygnus collateral contract for this borrow contract
     *  @return oracle The address of the oracle for this lending pool
     *  @return shuttleId The lending pool ID
     */
    function shuttleParameters()
        external
        returns (address factory, address underlying, address collateral, address oracle, uint256 shuttleId);

    /**
     *  @return BORROW_INIT_CODE_HASH The init code hash of the borrow contract for this deployer
     */
    function BORROWABLE_INIT_CODE_HASH() external view returns (bytes32);

    /**
     *  @notice Function to deploy the borrow contract of a lending pool
     *
     *  @param underlying The address of the underlying borrow token (address of USDc)
     *  @param collateral The address of the Cygnus collateral contract for this borrow contract
     *  @param shuttleId The ID of the shuttle we are deploying (shared by borrow and collateral)
     *  @return borrowable The address of the new borrow contract
     */
    function deployAlbireo(
        address underlying,
        address collateral,
        address oracle,
        uint256 shuttleId
    ) external returns (address borrowable);
}
