//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  IHangar18.sol
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

// Orbiters
import {IDenebOrbiter} from "./IDenebOrbiter.sol";
import {IAlbireoOrbiter} from "./IAlbireoOrbiter.sol";
import {ICygnusNebulaRegistry} from "./ICygnusNebulaRegistry.sol";

// Oracles

/**
 *  @title The interface for the Cygnus Factory
 *  @notice The Cygnus factory facilitates creation of collateral and borrow pools
 */
interface IHangar18 {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when caller is not Admin
     *
     *  @param sender The address of the account that invoked the function and caused the error
     *  @param admin The address of the Admin that is allowed to perform the function
     *
     *  @custom:error CygnusAdminOnly
     */
    error Hangar18__CygnusAdminOnly(address sender, address admin);

    /**
     *  @dev Reverts when the borrow orbiter already exists
     *
     *  @custom:error OrbiterAlreadySet
     */
    error Hangar18__OrbiterAlreadySet();

    /**
     *  @dev Reverts when trying to deploy a shuttle that already exists
     *
     *  @custom:error ShuttleAlreadyDeployed
     */
    error Hangar18__ShuttleAlreadyDeployed();

    /**
     *  @dev Reverts when deploying a shuttle with orbiters that are inactive or dont exist
     *
     *  @custom:error OrbitersAreInactive
     */
    error Hangar18__OrbitersAreInactive();

    /**
     *  @dev Reverts when predicted collateral address doesn't match with deployed
     *
     *  @custom:error CollateralAddressMismatch
     */
    error Hangar18__CollateralAddressMismatch();

    /**
     *  @dev Reverts when trying to deploy a shuttle with an unsupported LP Pair
     *
     *  @custom:error LiquidityTokenNotSupported
     */
    error Hangar18__LiquidityTokenNotSupported();

    /**
     *  @dev Reverts when the CYG rewarder contract is zero
     *
     *  @custom:error PillarsCantBeZero
     */
    error Hangar18__PillarsCantBeZero();

    /**
     *  @dev Reverts when the CYG rewarder contract is zero
     *
     *  @custom:error PillarsCantBeZero
     */
    error Hangar18__AltairCantBeZero();

    /**
     *  @dev Reverts when the oracle set is the same as the new one we are assigning
     *
     *  @param priceOracle The address of the existing price oracle
     *  @param newPriceOracle The address of the new price oracle that was attempted to be set
     *
     *  @custom:error CygnusNebulaAlreadySet
     */
    error Hangar18__CygnusNebulaAlreadySet(address priceOracle, address newPriceOracle);

    /**
     *  @dev Reverts when the admin is the same as the new one we are assigning
     *
     *  @custom:error AdminAlreadySet
     */
    error Hangar18__AdminAlreadySet();

    /**
     *  @dev Reverts when the pending admin is the same as the new one we are assigning
     *
     *  @param newPendingAdmin The address of the new pending admin
     *  @param pendingAdmin The address of the existing pending admin
     *
     *  @custom:error PendingAdminAlreadySet
     */
    error Hangar18__PendingAdminAlreadySet(address newPendingAdmin, address pendingAdmin);

    /**
     *  @dev Reverts when the pending dao reserves is already the dao reserves
     *
     *  @custom:error DaoReservesAlreadySet
     */
    error Hangar18__DaoReservesAlreadySet();

    /**
     *  @dev Reverts when the pending address is the same as the new pending
     *
     *  @custom:error PendingDaoReservesAlreadySet
     */
    error Hangar18__PendingDaoReservesAlreadySet();

    /**
     *  @dev Reverts when pending Cygnus admin is the zero address
     *
     *  @custom:error PendingCygnusAdmin
     */
    error Hangar18__PendingAdminCantBeZero();

    /**
     *  @dev Reverts when pending reserves contract address is the zero address
     *
     *  @custom:error DaoReservesCantBeZero
     */
    error Hangar18__DaoReservesCantBeZero();

    /**
     *  @dev Reverts when setting a new vault as the 0 address
     *
     *  @custom:error X1VaultCantBeZero
     */
    error Hangar18__X1VaultCantBeZero();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when a new lending pool is launched
     *
     *  @param lpTokenPair The address of the LP Token pair
     *  @param orbiterId The ID of the orbiter used to deploy this lending pool
     *  @param borrowable The address of the Cygnus borrow contract
     *  @param collateral The address of the Cygnus collateral contract
     *  @param shuttleId The ID of the lending pool
     *
     *  @custom:event NewShuttle
     */
    event NewShuttle(address indexed lpTokenPair, uint256 indexed shuttleId, uint256 orbiterId, address borrowable, address collateral);

    /**
     *  @dev Logs when a new Cygnus admin is requested
     *
     *  @param pendingAdmin Address of the requested admin
     *  @param _admin Address of the present admin
     *
     *  @custom:event NewPendingCygnusAdmin
     */
    event NewPendingCygnusAdmin(address pendingAdmin, address _admin);

    /**
     *  @dev Logs when a new Cygnus admin is confirmed
     *
     *  @param oldAdmin Address of the old admin
     *  @param newAdmin Address of the new confirmed admin
     *
     *  @custom:event NewCygnusAdmin
     */
    event NewCygnusAdmin(address oldAdmin, address newAdmin);

    /**
     *  @dev Logs when a new implementation contract is requested
     *
     *  @param oldPendingdaoReservesContract Address of the current `daoReserves` contract
     *  @param newPendingdaoReservesContract Address of the requested new `daoReserves` contract
     *
     *  @custom:event NewPendingDaoReserves
     */
    event NewPendingDaoReserves(address oldPendingdaoReservesContract, address newPendingdaoReservesContract);

    /**
     *  @dev Logs when a new implementation contract is confirmed
     *
     *  @param oldDaoReserves Address of old `daoReserves` contract
     *  @param daoReserves Address of the new confirmed `daoReserves` contract
     *
     *  @custom:event NewDaoReserves
     */
    event NewDaoReserves(address oldDaoReserves, address daoReserves);

    /**
     *  @dev Logs when a new pillars is confirmed
     *
     *  @param oldPillars Address of old `pillars` contract
     *  @param newPillars Address of the new pillars contract
     *
     *  @custom:event NewPillarsOfCreation
     */
    event NewPillarsOfCreation(address oldPillars, address newPillars);

    /**
     *  @dev Logs when a new router is confirmed
     *
     *  @param oldRouter Address of the old base router contract
     *  @param newRouter Address of the new router contract
     *
     *  @custom:event NewAltairRouter
     */
    event NewAltairRouter(address oldRouter, address newRouter);


    /**
     *  @dev Logs when orbiters are initialized in the factory
     *
     *  @param status Whether or not these orbiters are active and usable
     *  @param orbitersLength How many orbiter pairs we have (equals the amount of Dexes cygnus is using)
     *  @param borrowOrbiter The address of the borrow orbiter for this dex
     *  @param denebOrbiter The address of the collateral orbiter for this dex
     *  @param orbitersName The name of the dex for these orbiters
     *  @param uniqueHash The keccack256 hash of the collateral init code hash and borrowable init code hash
     *
     *  @custom:event InitializeOrbiters
     */
    event InitializeOrbiters(
        bool status,
        uint256 orbitersLength,
        IAlbireoOrbiter borrowOrbiter,
        IDenebOrbiter denebOrbiter,
        bytes32 uniqueHash,
        string orbitersName
    );

    /**
     *  @dev Logs when admins switch orbiters off for future deployments
     *
     *  @param status Bool representing whether or not these orbiters are usable
     *  @param orbiterId The ID of the collateral & borrow orbiters
     *  @param albireoOrbiter The address of the deleted borrow orbiter
     *  @param denebOrbiter The address of the deleted collateral orbiter
     *  @param orbiterName The name of the dex these orbiters were for
     *
     *  @custom:event SwitchOrbiterStatus
     */
    event SwitchOrbiterStatus(
        bool status,
        uint256 orbiterId,
        IAlbireoOrbiter albireoOrbiter,
        IDenebOrbiter denebOrbiter,
        string orbiterName
    );

    /**
     *  @dev Logs when a new vault is set which accumulates rewards from lending pools
     *
     *  @param oldVault The address of the old vault
     *  @param newVault The address of the new vault
     *
     *  @custom:event NewX1Vault
     */
    event NewX1Vault(address oldVault, address newVault);

    /**
     *  @dev Logs when an owner allows or disallows spender to borrow on their behalf
     *
     *  @param owner The address of msg.sender (owner of the CygLP)
     *  @param spender The address of the user the owner is allowing/disallowing
     *  @param status Whether or not the spender can borrow after this transaction
     *
     *  @custom:event NewMasterBorrowApproval
     */
    event NewMasterBorrowApproval(address owner, address spender, bool status);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     * @custom:struct Official record of all collateral and borrow deployer contracts, unique per dex
     * @custom:member status Whether or not these orbiters are active and usable
     * @custom:member orbiterId The ID for this pair of orbiters
     * @custom:member albireoOrbiter The address of the borrow deployer contract
     * @custom:member denebOrbiter The address of the collateral deployer contract
     * @custom:member borrowableInitCodeHash The hash of the borrowable contract's initialization code
     * @custom:member collateralInitCodeHash The hash of the collateral contract's initialization code
     * @custom:member uniqueHash The unique hash of the orbiter
     * @custom:member orbiterName Huamn friendly name for the orbiters
     */
    struct Orbiter {
        bool status;
        uint88 orbiterId;
        IAlbireoOrbiter albireoOrbiter;
        IDenebOrbiter denebOrbiter;
        bytes32 borrowableInitCodeHash;
        bytes32 collateralInitCodeHash;
        bytes32 uniqueHash;
        string orbiterName;
    }

    /**
     *  @custom:struct Shuttle Official record of pools deployed by this factory
     *  @custom:member launched Whether or not the lending pool is initialized
     *  @custom:member shuttleId The ID of the lending pool
     *  @custom:member borrowable The address of the borrowing contract
     *  @custom:member collateral The address of the Cygnus collateral
     *  @custom:member orbiterId The ID of the orbiters used to deploy lending pool
     */
    struct Shuttle {
        bool launched;
        uint88 shuttleId;
        address borrowable;
        address collateral;
        uint96 orbiterId;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Array of structs containing all orbiters deployed
     *  @param _orbiterId The ID of the orbiter pair
     *  @return status Whether or not these orbiters are active and usable
     *  @return orbiterId The ID for these orbiters (ideally should be 1 per dex)
     *  @return albireoOrbiter The address of the borrow deployer contract
     *  @return denebOrbiter The address of the collateral deployer contract
     *  @return borrowableInitCodeHash The init code hash of the borrowable
     *  @return collateralInitCodeHash The init code hash of the collateral
     *  @return uniqueHash The keccak256 hash of collateralInitCodeHash and borrowableInitCodeHash
     *  @return orbiterName The name of the dex
     */
    function allOrbiters(
        uint256 _orbiterId
    )
        external
        view
        returns (
            bool status,
            uint88 orbiterId,
            IAlbireoOrbiter albireoOrbiter,
            IDenebOrbiter denebOrbiter,
            bytes32 borrowableInitCodeHash,
            bytes32 collateralInitCodeHash,
            bytes32 uniqueHash,
            string memory orbiterName
        );

    /**
     *  @notice Array of LP Token pairs deployed
     *  @param _shuttleId The ID of the shuttle deployed
     *  @return launched Whether this pair exists or not
     *  @return shuttleId The ID of this shuttle
     *  @return borrowable The address of the borrow contract
     *  @return collateral The address of the collateral contract
     *  @return orbiterId The ID of the orbiters used to deploy this lending pool
     */
    function allShuttles(
        uint256 _shuttleId
    ) external view returns (bool launched, uint88 shuttleId, address borrowable, address collateral, uint96 orbiterId);

    /**
     *  @notice Official record of all lending pools deployed
     *  @param _lpTokenPair The address of the LP Token
     *  @param _orbiterId The ID of the orbiter for this LP Token
     *  @return launched Whether this pair exists or not
     *  @return shuttleId The ID of this shuttle
     *  @return borrowable The address of the borrow contract
     *  @return collateral The address of the collateral contract
     *  @return orbiterId The ID of the orbiters used to deploy this lending pool
     */
    function getShuttles(
        address _lpTokenPair,
        uint256 _orbiterId
    ) external view returns (bool launched, uint88 shuttleId, address borrowable, address collateral, uint96 orbiterId);

    /**
     *  @return Human friendly name for this contract
     */
    function name() external view returns (string memory);

    /**
     *  @return The version of this contract
     */
    function version() external view returns (string memory);

    /**
     *  @return usd The address of the borrowable token (stablecoin)
     */
    function usd() external view returns (address);

    /**
     *  @return nativeToken The address of the chain's native token
     */
    function nativeToken() external view returns (address);

    /**
     *  @notice The address of the nebula registry on this chain
     */
    function nebulaRegistry() external view returns (ICygnusNebulaRegistry);

    /**
     *  @return admin The address of the Cygnus Admin which grants special permissions in collateral/borrow contracts
     */
    function admin() external view returns (address);

    /**
     *  @return pendingAdmin The address of the requested account to be the new Cygnus Admin
     */
    function pendingAdmin() external view returns (address);

    /**
     *  @return daoReserves The address that handles Cygnus reserves from all pools
     */
    function daoReserves() external view returns (address);

    /**
     *  @dev Returns the address of the contract to be the new DAO reserves.
     *  @return pendingDaoReserves The address of the requested contract to be the new DAO reserves.
     */
    function pendingDaoReserves() external view returns (address);

    /**
     *  @dev Returns the address of the CygnusDAO revenue vault.
     *  @return cygnusX1Vault The address of the CygnusDAO revenue vault.
     */
    function cygnusX1Vault() external view returns (address);

    /**
     *  @dev Returns the address of the CygnusDAO base router.
     *  @return cygnusAltair Latest address of the base router on this chain.
     */
    function cygnusAltair() external view returns (address);

    /**
     *  @dev Returns the address of the CYG rewarder
     *  @return cygnusPillars The address of the CYG rewarder on this chain
     */
    function cygnusPillars() external view returns (address);

    /**
     * @dev Returns the total number of orbiter pairs deployed (1 collateral + 1 borrow = 1 orbiter).
     * @return orbitersDeployed The total number of orbiter pairs deployed.
     */
    function orbitersDeployed() external view returns (uint256);

    /**
     *  @dev Returns the total number of shuttles deployed.
     *  @return shuttlesDeployed The total number of shuttles deployed.
     */
    function shuttlesDeployed() external view returns (uint256);

    /**
     *  @dev Returns the chain ID
     */
    function chainId() external view returns (uint256);

    /**
     *  @dev Returns the borrowable TVL (Total Value Locked) in USD for a specific shuttle.
     *  @param shuttleId The ID of the shuttle for which the borrowable TVL is requested.
     *  @return The borrowable TVL in USD for the specified shuttle.
     */
    function borrowableTvlUsd(uint256 shuttleId) external view returns (uint256);

    /**
     *  @dev Returns the collateral TVL (Total Value Locked) in USD for a specific shuttle.
     *  @param shuttleId The ID of the shuttle for which the collateral TVL is requested.
     *  @return The collateral TVL in USD for the specified shuttle.
     */
    function collateralTvlUsd(uint256 shuttleId) external view returns (uint256);

    /**
     *  @dev Returns the total TVL (Total Value Locked) in USD for a specific shuttle.
     *  @param shuttleId The ID of the shuttle for which the total TVL is requested.
     *  @return The total TVL in USD for the specified shuttle.
     */
    function shuttleTvlUsd(uint256 shuttleId) external view returns (uint256);

    /**
     *  @dev Returns the USD value of the DAO Cyg LP reserves.
     *  @return The USD value of the DAO Cyg LP reserves.
     */
    function daoCygLPReservesUsd() external view returns (uint256);

    /**
     *  @dev Returns the USD value of the DAO Cyg USD reserves.
     *  @return The USD value of the DAO Cyg USD reserves.
     */
    function daoCygUsdReservesUsd() external view returns (uint256);

    /**
     *  @dev Returns the total USD value of CygnusDAO reserves.
     *  @return The total USD value of CygnusDAO reserves.
     */
    function cygnusTotalReservesUsd() external view returns (uint256);

    /**
     *  @dev Returns the total amount borrowed in USD.
     *  @return The total amount borrowed in USD.
     */
    function totalBorrowsUsd() external view returns (uint256);

    /**
     *  @dev Returns the total borrowable TVL (Total Value Locked) in USD for all shuttles.
     *  @return The total borrowable TVL in USD.
     */
    function allBorrowablesTvlUsd() external view returns (uint256);

    /**
     *  @dev Returns the total collateral TVL (Total Value Locked) in USD for all shuttles.
     *  @return The total collateral TVL in USD.
     */
    function allCollateralsTvlUsd() external view returns (uint256);

    /**
     *  @dev Returns the total TVL (Total Value Locked) in USD for CygnusDAO.
     *  @return The total TVL in USD for CygnusDAO.
     */
    function cygnusTvlUsd() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Admin 👽
     *  @notice Turns off orbiters making them not able for deployment of pools
     *
     *  @param orbiterId The ID of the orbiter pairs we want to switch the status of
     *
     *  @custom:security only-admin
     */
    function switchOrbiterStatus(uint256 orbiterId) external;

    /**
     *  @notice Admin 👽
     *  @notice Initializes both Borrow arms and the collateral arm
     *
     *  @param lpTokenPair The address of the underlying LP Token this pool is for
     *  @param orbiterId The ID of the orbiters we want to deploy to (= dex Id)
     *  @return borrowable The address of the Cygnus borrow contract for this pool
     *  @return collateral The address of the Cygnus collateral contract for both borrow tokens
     *
     *  @custom:security non-reentrant only-admin 👽
     */
    function deployShuttle(address lpTokenPair, uint256 orbiterId) external returns (address borrowable, address collateral);

    /**
     *  @notice Admin 👽
     *  @notice Sets the new orbiters to deploy collateral and borrow contracts and stores orbiters in storage
     *
     *  @param name The name of the strategy OR the dex these orbiters are for
     *  @param albireoOrbiter the address of this orbiter's borrow deployer
     *  @param denebOrbiter The address of this orbiter's collateral deployer
     *
     *  @custom:security non-reentrant only-admin
     */
    function initializeOrbiter(string memory name, IAlbireoOrbiter albireoOrbiter, IDenebOrbiter denebOrbiter) external;

    /**
     *  @notice Admin 👽
     *  @notice Sets a new pending admin for Cygnus
     *
     *  @param newCygnusAdmin Address of the requested Cygnus admin
     *
     *  @custom:security only-admin
     */
    function setPendingAdmin(address newCygnusAdmin) external;

    /**
     *  @notice Admin 👽
     *  @notice Approves the pending admin and is the new Cygnus admin
     *
     *  @custom:security only-admin
     */
    function setNewCygnusAdmin() external;

    /**
     *  @notice Admin 👽
     *  @notice Sets the address for the future reserves manger if accepted
     *  @param newDaoReserves The address of the requested contract to be the new daoReserves
     *  @custom:security only-admin
     */
    function setPendingDaoReserves(address newDaoReserves) external;

    /**
     *  @notice Admin 👽
     *  @notice Accepts the new implementation contract
     *
     *  @custom:security only-admin
     */
    function setNewDaoReserves() external;

    /**
     *  @notice Admin 👽
     *  @notice Sets the address of the new x1 vault which accumulates rewards over time
     *
     *  @custom:security only-admin
     */
    function setCygnusX1Vault(address newX1Vault) external;

    /**
     *  @notice Admin 👽
     *  @notice Sets the address of the new pillars of creation
     *
     *  @custom:security only-admin
     */
    function setCygnusPillars(address newPillars) external;

    /**
     *  @notice Admin 👽
     *  @notice Sets the address of the new base router
     *
     *  @custom:security only-admin
     */
    function setCygnusAltair(address newAltair) external;
}
