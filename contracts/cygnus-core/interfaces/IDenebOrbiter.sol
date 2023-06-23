//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  IDenebOrbiter.sol
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
        returns (address factory, address underlying, address borrowable, address oracle, uint256 shuttleId);

    /**
     *  @return collateralInitCodeHash The init code hash of the collateral contract for this deployer
     */
    function collateralInitCodeHash() external view returns (bytes32);

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
