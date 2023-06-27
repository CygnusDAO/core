//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  IOrbiter.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.8.17;

import {IHangar18} from "./IHangar18.sol";
import {ICygnusNebula} from "./ICygnusNebula.sol";

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
     *  @return twinstar   The opposite contract to the one being deployed. IE. If collateral is being deployed,
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
            address twinstar,
            ICygnusNebula oracle,
            uint256 shuttleId
        );
}
