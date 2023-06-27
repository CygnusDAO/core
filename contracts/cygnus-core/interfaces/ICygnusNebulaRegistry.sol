//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusNebulaOracle.sol
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
pragma solidity ^0.8.17;

// Interfaces
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {ICygnusNebula} from "./ICygnusNebula.sol";
import {IERC20} from "./IERC20.sol";

/**
 *  @title ICygnusNebulaOracle Interface to interact with Cygnus' LP Oracle
 *  @author CygnusDAO
 */
interface ICygnusNebulaRegistry {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when attempting to set admin as the zero address
     *
     *  @custom:error AdminCantBeZero
     */
    error CygnusNebula__AdminCantBeZero();

    /**
     *  @dev Reverts when attempting to set the same pending admin twice
     *
     *  @custom:error PendingAdminAlreadySet
     */
    error CygnusNebula__PendingAdminAlreadySet();

    /**
     *  @dev Reverts when the msg.sender is not the registry's admin
     *
     *  @custom:error SenderNotAdmin
     */
    error CygnusNebula__SenderNotAdmin();

    /**
     *  @dev Reverts when setting a new oracle (ie a new UniV2 oracle)
     *
     *  @custom:error OracleAlreadyAdded
     */
    error CygnusNebula__OracleAlreadyAdded();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when a new pending admin is set, to be accepted by admin
     *
     *  @param oldPendingAdmin The address of the current oracle admin
     *  @param newPendingAdmin The address of the pending oracle admin
     *
     *  @custom:event NewNebulaPendingAdmin
     */
    event NewNebulaPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     *  @dev Logs when the pending admin is confirmed as the new oracle admin
     *
     *  @param oldAdmin The address of the old oracle admin
     *  @param newAdmin The address of the new oracle admin
     *
     *  @custom:event NewNebulaAdmin
     */
    event NewNebulaAdmin(address oldAdmin, address newAdmin);

    /**
     *  @dev Logs when a new nebula oracle is added
     *
     *  @param oracle The address of the new oracle
     *  @param oracleId The ID of the oracle
     *
     *  @custom:event NewNebulaOracle
     */
    event NewNebulaOracle(address oracle, uint256 oracleId);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Struct for each nebula
     *  @custom:member name Friendly name to identify the Nebula
     *  @custom:member nebula The address of the nebula
     *  @custom:member nebulaId The ID of the nebula
     *  @custom:member totalOracles The total amount of initialized oracles
     */
    struct CygnusNebula {
        string name;
        address nebula;
        uint256 nebulaId;
        uint256 totalOracles;
    }

    /**
     *  @return The name for the registry
     */
    function name() external view returns (string memory);

    /**
     *  @return The address of the Cygnus admin
     */
    function admin() external view returns (address);

    /**
     *  @return The address of the new requested admin
     */
    function pendingAdmin() external view returns (address);

    /**
     *  @notice Array of Nebula structs
     *  @param index The index of the nebula struct
     *  @return _name User friendly name of the Nebula (ie 'Constant Product AMMs')
     *  @return _nebula The address of the nebula
     *  @return id The ID of the nebula
     *  @return totalOracles The total amount of initialized oracles in this nebula
     */
    function allNebulas(uint256 index) external view returns (string memory _name, address _nebula, uint256 id, uint256 totalOracles);

    /**
     *  @notice Array of initialized LP Token pairs
     *  @param index THe index of the nebula oracle
     *  @return lpTokenPair The address of the LP Token pair
     */
    function allNebulaOracles(uint256 index) external view returns (address lpTokenPair);

    /**
     *  @notice Length of nebulas added
     */
    function totalNebulas() external view returns (uint256);

    /**
     *  @notice Total LP Token pairs
     */
    function totalNebulaOracles() external view returns (uint256);

    /**
     *  @notice Checks if nebula has already been added to the registry
     *  @param _nebula The address of the nebula
     *  @return Whether the nebula has been added or not
     */
    function isNebula(address _nebula) external view returns (bool);

    /**
     *  @notice Getter for the nebula struct given a nebula address
     *  @param _nebula The address of the nebula
     *  @return Record of the nebula
     */
    function getNebula(address _nebula) external view returns (CygnusNebula memory);

    /**
     *  @notice Getter for the nebula struct given an LP
     *  @param lpTokenPair The address of the LP Token
     *  @return Record of the nebula for this LP
     */
    function getLPTokenNebula(address lpTokenPair) external view returns (CygnusNebula memory);

    /**
     *  @notice Used gas savings during hangar18 shuttle deployments. Given an LP Token pair, we return the nebula address
     *  @param lpTokenPair The address of the LP Token
     *  @return nebula The address of the nebula for `lpTokenPair`
     */
    function getLPTokenNebulaAddress(address lpTokenPair) external view returns (address nebula);

    /**
     *  @notice Initializes an oracle for the LP, mapping it to the nebula
     *  @param nebulaId The ID of the nebula (ie. each nebula depends on the dex and the logic for calculating the LP Price)
     *  @param lpTokenPair The address of the LP Token
     *  @param aggregators Calldata array of Chainlink aggregators
     */
    function initializeOracle(uint256 nebulaId, address lpTokenPair, AggregatorV3Interface[] calldata aggregators) external;

    /**
     *  @notice Get the Oracle for the LP token pair
     *  @param lpTokenPair The address of the LP Token pair
     */
    function getNebulaOracle(address lpTokenPair) external view returns (ICygnusNebula.NebulaOracle memory);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Admin 👽
     *  @notice Adds a new nebula to the registry
     *
     *  @param _nebula Address of the new nebula
     *
     *  @custom:security only-admin
     */
    function addNebula(address _nebula) external;

    /**
     *  @notice Admin 👽
     *  @notice Sets a new pending admin for the Oracle
     *
     *  @param newOraclePendingAdmin Address of the requested Oracle Admin
     *
     *  @custom:security non-reentrant only-admin
     */
    function setRegistryPendingAdmin(address newOraclePendingAdmin) external;

    /**
     *  @notice Admin 👽
     *  @notice Sets a new admin for the Oracle
     *
     *  @custom:security non-reentrant only-admin
     */
    function setRegistryAdmin() external;
}
