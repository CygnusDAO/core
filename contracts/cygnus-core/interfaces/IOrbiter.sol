// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

import {IHangar18} from "./IHangar18.sol";
import {ICygnusNebulaOracle} from "./ICygnusNebulaOracle.sol";

/**
 *  @notice Interface used by core contracts to read variables from the deployers (AlbireoOrbiter.sol and
 *          DenebOrbiter.sol)
 */
interface IOrbiter {
    /**
     *  @notice Simple interface of both borrow/collateral orbiters that gets read during deployment of pools
     *          in the constructor of CygnusTerminal.sol
     *  @return factory    The address of the Cygnus factory-like contract, assigned to `hangar18`
     *  @return underlying The address of the underlying borrow token (stablecoin) or collateral token (LP Token)
     *  @return twinStar   The opposite contract to the one being deployed. IE. If collateral is being deployed,
     *                     then it is the address of the borrowable. If borrowable is being deployed, it is the
     *                     address of the collateral.
     *  @return oracle     The address of the oracle
     *  @return shuttleId  The lending pool ID, shared by both borrowable and collateral
     */
    function shuttleParameters()
        external
        returns (
            IHangar18 factory,
            address underlying,
            address twinStar,
            ICygnusNebulaOracle oracle,
            uint256 shuttleId
        );
}
