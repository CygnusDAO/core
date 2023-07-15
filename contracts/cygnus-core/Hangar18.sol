//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Hangar18.sol
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

/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  .
    .               .            .               .      🛰️     .           .                 *              .
           █████████           ---======*.                                                 .           ⠀
          ███░░░░░███                                               📡                🌔                       . 
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀           .           .
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .⠀
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████     .----===*  ⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .⠀
                       ███ ░███  ███ ░███                .                 .                 .  ⠀
     🛰️  .             ░░██████  ░░██████                                             .                 .           
                       ░░░░░░    ░░░░░░      -------=========*                      .                     ⠀
           .                            .       .          .            .                          .             .⠀
    
        LENDING POOL FACTORY V1 - `Hangar18`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {IHangar18} from "./interfaces/IHangar18.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries
import {CygnusPoolAddress} from "./libraries/CygnusPoolAddress.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {LibString} from "./libraries/LibString.sol";

// Interfaces
import {ICygnusNebulaRegistry} from "./interfaces/ICygnusNebulaRegistry.sol";
import {IDenebOrbiter} from "./interfaces/IDenebOrbiter.sol";
import {IAlbireoOrbiter} from "./interfaces/IAlbireoOrbiter.sol";
import {ICygnusBorrow} from "./interfaces/ICygnusBorrow.sol";
import {ICygnusCollateral} from "./interfaces/ICygnusCollateral.sol";
import {ICygnusBorrow} from "./interfaces/ICygnusBorrow.sol";

/**
 *  @title  Hangar18
 *  @author CygnusDAO
 *  @notice Factory-like contract for CygnusDAO which deploys all borrow/collateral contracts in this chain. There
 *          is only 1 factory contract per chain along with multiple pairs of `orbiters`.
 *
 *          Orbiters are the collateral and borrow deployers contracts which are not not part of the
 *          core contracts, but instead are in charge of deploying the arms of core contracts with each other's
 *          addresses (borrow orbiter deploys the borrow arm with the collateral address, and vice versa).
 *
 *          Orbiters = Strategies for the underlying assets
 *
 *          Each orbiter has the bytecode of the collateral/borrow contracts being deployed, and they may differ
 *          slighlty due to the strategy deployed (for example each masterchef is different, requiring different
 *          harvest strategy, staking mechanism, etc.). The only contract that may differ between core contracts
 *          is the `CygnusCollateralVoid`, where all functions are private or external, meaning no other contract
 *          relies on it and can be left blank.
 *
 *          Ideally there should only be 1 orbiter per DEX (1 borrow && 1 collateral orbiter) or 1 per strategy.
 *
 *          This factory contract contains the records of all shuttles deployed by Cygnus. Every collateral/borrow
 *          contract reports back here to:
 *              - Check admin address (to increase debt ratios, update interest rate model, set void, etc.)
 *              - Check reserves manager address when minting new DAO reserves (in CygnusBorrow.sol) or to add
 *                DAO liquidation fees if any (in CygnusCollateral.sol)
 */
contract Hangar18 is IHangar18, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers.
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IHangar18
     */
    DenebOrbiter[] public override allDenebOrbiters;

    /**
     *  @inheritdoc IHangar18
     */
    AlbireoOrbiter[] public override allAlbireoOrbiters;

    /**
     *  @inheritdoc IHangar18
     */
    Station[] public override allStations;

    /**
     *  @inheritdoc IHangar18
     */
    Shuttle[] public override allShuttles;

    /**
     *  @inheritdoc IHangar18
     */
    mapping(address => bool) public override isOrbiter;

    /**
     *  @inheritdoc IHangar18
     */
    mapping(LiquidityType => mapping(uint256 => Station)) public getStation; // Type -> Orbiter Id = Station

    /**
     *  @inheritdoc IHangar18
     */
    mapping(address => mapping(uint256 => Shuttle)) public override getShuttles; // LP -> Orbiter Id = Shuttle

    /**
     *  @inheritdoc IHangar18
     */
    string public override name =
        string.concat("Cygnus: Hangar18 - Lending Pool Deployer #", LibString.toString(block.chainid));

    /**
     *  @inheritdoc IHangar18
     */
    string public constant override version = "1.0.0";

    /**
     *  @inheritdoc IHangar18
     */
    address public immutable override usd;

    /**
     *  @inheritdoc IHangar18
     */
    address public immutable override nativeToken;

    /**
     *  @inheritdoc IHangar18
     */
    ICygnusNebulaRegistry public immutable nebulaRegistry;

    /**
     *  @inheritdoc IHangar18
     */
    address public override admin;

    /**
     *  @inheritdoc IHangar18
     */
    address public override pendingAdmin;

    /**
     *  @inheritdoc IHangar18
     */
    address public override daoReserves;

    /**
     *  @inheritdoc IHangar18
     */
    address public override pendingDaoReserves;

    /**
     *  @inheritdoc IHangar18
     */
    address public override cygnusX1Vault;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Sets the important addresses which pools report back here to check for
     *  @param _admin Address of the Cygnus Admin to update important protocol parameters
     *  @param _daoReserves Address of the contract that handles weighted forwarding of Erc20 tokens
     *  @param _usd Address of the borrowable`s underlying (stablecoins USDC, DAI, BUSD, etc.).
     *  @param _nativeToken The address of this chain's native token
     *  @param _registry The Cygnus oracle registry which keeps track of all initialized LP oracles
     */
    constructor(
        address _admin,
        address _daoReserves,
        address _usd,
        address _nativeToken,
        ICygnusNebulaRegistry _registry
    ) {
        // Assign cygnus admin, has access to special functions
        admin = _admin;

        // Assign reserves manager
        daoReserves = _daoReserves;

        // Address of the native token for this chain (ie WETH)
        nativeToken = _nativeToken;

        // Address of DAI on this factory's chain
        usd = _usd;

        // Oracle registry
        nebulaRegistry = _registry;

        /// @custom:event NewCygnusAdmin
        emit NewCygnusAdmin(address(0), _admin);

        /// @custom:event DaoReserves
        emit NewDaoReserves(address(0), _daoReserves);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Modifier for Cygnus Admin only
     */
    modifier cygnusAdmin() {
        isCygnusAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Only Cygnus admins can deploy pools in Cygnus V1
     */
    function isCygnusAdmin() private view {
        /// @custom:error CygnusAdminOnly
        if (msg.sender != admin) {
            revert Hangar18__CygnusAdminOnly({sender: msg.sender, admin: admin});
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IHangar18
     */
    function borrowableTvlUsd(uint256 stationId) public view override returns (uint256 totalUsd) {
        // Get shuttle`
        Station memory station = allStations[stationId];
        // Borrows
        uint256 totalBorrows = ICygnusBorrow(station.borrowable).totalBorrows();
        // Current balance of USD
        uint256 totalBalance = ICygnusCollateral(station.borrowable).totalBalance();
        // Total USD value of pool
        totalUsd = totalBorrows + totalBalance;
    }

    /**
     *  @inheritdoc IHangar18
     */
    function collateralTvlUsd(uint256 shuttleId) public view override returns (uint256 totalUsd) {
        // Array of pools deployed
        Shuttle memory shuttle = allShuttles[shuttleId];
        // LP Price
        uint256 price = ICygnusCollateral(shuttle.collateral).getLPTokenPrice();
        // Total LP assets
        uint256 totalBalance = ICygnusCollateral(shuttle.collateral).totalBalance();
        // TVL = Price of LP * Balance of LP
        totalUsd = totalBalance.mulWad(price); // Denom in USDC
    }

    /**
     *  @notice Duplicated TVL
     *  @inheritdoc IHangar18
     */
    function shuttleTvlUsd(uint256 shuttleId) external view returns (uint256 totalUsd) {
        // Array of pools deployed
        Shuttle memory shuttle = allShuttles[shuttleId];
        // Total pools deployed
        address borrowable = ICygnusCollateral(shuttle.collateral).borrowable();
        // Station id for this collateral`s borrowable
        uint256 stationId = ICygnusBorrow(borrowable).stationId();
        // TVL of a specific lending pool
        return borrowableTvlUsd(stationId) + collateralTvlUsd(shuttleId);
    }

    /**
     *  @inheritdoc IHangar18
     */
    function allBorrowablesTvlUsd() public view override returns (uint256 totalUsd) {
        // Loop through each pool deployed, get borrowable and add to total TVL
        for (uint256 i = 0; i < allStations.length; i++) totalUsd += borrowableTvlUsd(i);
    }

    function allCollateralsTvlUsd() public view returns (uint256 totalUsd) {
        // Add collateral
        for (uint256 i = 0; i < allShuttles.length; i++) totalUsd += collateralTvlUsd(i);
    }

    /**
     *  @notice De-duplicated TVL
     *  @inheritdoc IHangar18
     */
    function cygnusTvlUsd() public view override returns (uint256) {
        // Return the cygnus protocol TVL on this chain
        return allBorrowablesTvlUsd() + allCollateralsTvlUsd();
    }

    /**
     *  @inheritdoc IHangar18
     */
    function daoBorrowableReservesUsd() public view override returns (uint256 reserves) {
        // Array of pools deployed
        Station[] memory stations = allStations;
        // Total pools deployed
        uint256 poolsDeployed = stations.length;
        // Loop through each pool deployed, get borrowable and add to total TVL
        for (uint256 i = 0; i < poolsDeployed; i++) {
            // This pool`s borrowable
            address borrowable = stations[i].borrowable;
            // Total reserves owned by the DAO
            uint256 cygUsdBalance = ICygnusBorrow(borrowable).balanceOf(daoReserves);
            // current exchange rate of CygUSD to USD
            uint256 exchangeRate = ICygnusBorrow(borrowable).exchangeRate();
            // Current reserves in USD
            reserves += cygUsdBalance.mulWad(exchangeRate);
        }
    }

    /**
     *  @inheritdoc IHangar18
     */
    function daoCollateralReservesUsd() public view override returns (uint256 reserves) {
        // Array of pools deployed
        Shuttle[] memory shuttles = allShuttles;
        // Total pools deployed
        uint256 poolsDeployed = allShuttles.length;
        // Loop through each pool deployed, get collateral and query the DAO's positionUsd:
        // positionUsd = (CygLP * Exchange Rate) * LP Price
        for (uint256 i = 0; i < poolsDeployed; i++) {
            // This pool`s collateral
            address collateral = shuttles[i].collateral;
            // Position in USD
            (, , , , , uint256 positionUsd, ) = ICygnusCollateral(collateral).getBorrowerPosition(daoReserves);
            // Add to reserves
            reserves += positionUsd;
        }
    }

    /**
     *  @inheritdoc IHangar18
     */
    function cygnusTotalReservesUsd() public view override returns (uint256) {
        // Total reserves USD
        return daoBorrowableReservesUsd() + daoCollateralReservesUsd();
    }

    /**
     *  @inheritdoc IHangar18
     */
    function cygnusTotalBorrowsUsd() public view override returns (uint256 totalBorrows) {
        // Array of pools deployed
        Station[] memory stations = allStations;
        // Total pools deployed
        uint256 poolsDeployed = stations.length;
        // Loop through each pool deployed, get borrowable and add to total TVL
        for (uint256 i = 0; i < poolsDeployed; i++) {
            // This pool`s borrowable
            address borrowable = stations[i].borrowable;
            // Total stablecoin borrows
            totalBorrows += ICygnusBorrow(borrowable).totalBorrows();
        }
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc IHangar18
     */
    function totalDenebOrbiters() external view override returns (uint256) {
        // Return how many collateral deployers we have
        return allDenebOrbiters.length;
    }

    /**
     *  @inheritdoc IHangar18
     */
    function totalAlbireoOrbiters() external view override returns (uint256) {
        // Return how many borrowable deployers we have
        return allAlbireoOrbiters.length;
    }

    /**
     *  @inheritdoc IHangar18
     */
    function totalShuttles() external view override returns (uint256) {
        // Return how many shuttles this contract has launched
        return allShuttles.length;
    }

    /**
     *  @inheritdoc IHangar18
     */
    function totalStations() external view override returns (uint256) {
        // Return how many borrowable lending pools we have
        return allStations.length;
    }

    /**
     *  @inheritdoc IHangar18
     */
    function totalNebulas() external view override returns (uint256) {
        // Return unique nebulas
        return nebulaRegistry.totalNebulas();
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Creates a record of each shuttle deployed by this contract
     *  @dev Prepares shuttle for deployment and stores the orbiter used for this Shuttle
     *  @param lpTokenPair Address of the LP Token for this shuttle
     *  @param orbiterId The orbiter ID used to deploy this shuttle
     *  @return shuttle Struct of the lending pool being deployed
     */
    function boardShuttlePrivate(address lpTokenPair, uint256 orbiterId) private returns (Shuttle storage) {
        /// @custom:error ShuttleAlreadyDeployed
        if (getShuttles[lpTokenPair][orbiterId].launched) revert Hangar18__ShuttleAlreadyDeployed();

        // Create shuttle
        return
            getShuttles[lpTokenPair][orbiterId] = Shuttle(
                false, // False until `deployShuttle` call succeeds
                uint88(allShuttles.length), // Lending pool ID
                address(0), // Borrowable address
                address(0), // Collateral address
                uint96(orbiterId) // The orbiter ID used to launch this shuttle
            );
    }

    /**
     *  @notice Creates a record of each station deployed by this contract
     *  @dev Prepares Station for deployment and stores the orbiter used for this station
     *  @param liquidityType Enum representing the type of shuttles this station supports
     *  @param orbiterId The orbiter ID used to deploy this station
     *  @return station Struct of the station beign deployed
     */
    function boardStationPrivate(LiquidityType liquidityType, uint256 orbiterId) internal returns (Station storage) {
        /// @custom:error StationAlreadyDeployed Avoid deploying the same station twice
        if (getStation[liquidityType][orbiterId].launched) revert Hangar18__StationAlreadyDeployed();

        // Return station
        return
            getStation[liquidityType][orbiterId] = Station(
                false, // Set to false until call succeeds
                uint88(allStations.length), // Lending pool ID
                address(0), // Zero Address until deployment succeds
                liquidityType, // Liquidity type
                orbiterId
            );
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  Phase 1: Load orbiter
     *  Phase 2: Create shuttle struct, reverts if LP has already been launched with the same orbiter
     *  Phase 3: Check that we have an oracle enabled for the LP
     *  Phase 4: Deploy Collateral
     *  Phase 5: Initialize
     *
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function deployShuttle(
        address lpTokenPair,
        uint256 denebId,
        uint256 stationId
    ) external override cygnusAdmin returns (address collateral) {
        //  ─────────────────────────────── Phase 1 ───────────────────────────────
        // Load orbiter to storage for gas savings (throws if orbiter doesn't exist)
        DenebOrbiter storage orbiter = allDenebOrbiters[denebId];

        //  ─────────────────────────────── Phase 2 ───────────────────────────────
        // Prepare shuttle for deployment, reverts if lpTokenPair already exists
        Shuttle storage shuttle = boardShuttlePrivate(lpTokenPair, denebId);

        //  ─────────────────────────────── Phase 3 ───────────────────────────────
        // Check that oracle has been initialized in the registry and get the nebula address
        address nebula = nebulaRegistry.getLPTokenNebulaAddress(lpTokenPair);

        /// @custom:error LiquidityTokenNotSupported
        if (nebula == address(0)) revert Hangar18__LiquidityTokenNotSupported();

        //  ─────────────────────────────── Phase 4 ───────────────────────────────
        // Get station, throws if it doesnt exist
        address borrowable = allStations[stationId].borrowable;

        // Deploy collateral contract
        collateral = orbiter.denebOrbiter.deployDeneb(lpTokenPair, borrowable, nebula, shuttle.shuttleId);

        //  ─────────────────────────────── Phase 5 ───────────────────────────────
        // Save addresses to storage and mark as launched. This LP Token with orbiter ID cannot be redeployed
        shuttle.launched = true;

        // Add cygnus borrow contract to record
        shuttle.borrowable = borrowable;

        // Add collateral contract to record
        shuttle.collateral = collateral;

        // Push the lending pool struct to the object array
        allShuttles.push(shuttle);

        // Add collateral to the borrowable
        ICygnusBorrow(borrowable).setCollateral(collateral);

        /// @custom:event NewShuttle
        emit NewShuttle(lpTokenPair, denebId, shuttle.shuttleId, borrowable, collateral);
    }

    /**
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function deployStation(
        LiquidityType liquidityType,
        uint256 albireoId
    ) external override cygnusAdmin returns (address borrowable) {
        // Load orbiter to storage for gas savings (throws if orbiter doesn't exist)
        AlbireoOrbiter storage orbiter = allAlbireoOrbiters[albireoId];

        // Prepare station for deployment, reverts if station already exists for this liquidity type
        Station storage station = boardStationPrivate(liquidityType, albireoId);

        // Deploy station with liquidity type and no twin star (collaterals get assigned later)
        borrowable = orbiter.albireoOrbiter.deployAlbireo(usd, address(0), address(nebulaRegistry), station.stationId);

        // Save addresses to storage and mark as launched. This liquidity type with orbiter ID cannot be redeployed
        station.launched = true;

        // Assign borrowable to Station struct
        station.borrowable = borrowable;

        // Push to station array
        allStations.push(station);

        /// @custom:event NewStation
        emit NewStation(liquidityType, albireoId, station.stationId, borrowable);
    }

    /**
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function setDenebOrbiter(string calldata _name, address deneb) external override cygnusAdmin {
        /// @custom:error OrbiterAlreadySet
        if (isOrbiter[deneb]) revert Hangar18__OrbiterAlreadySet();

        // Total collateral orbiters
        uint256 totalOrbiters = allDenebOrbiters.length;

        // Has not been initialized yet, create struct and push to orbiter array
        allDenebOrbiters.push(
            DenebOrbiter({
                status: true, // Cant be set again
                orbiterId: uint88(totalOrbiters), // Collateral Orbiter ID
                denebOrbiter: IDenebOrbiter(deneb), // To deploy contracts
                orbiterName: _name // Friendly name (ie. 'Balancer Weighted Pools')
            })
        );

        // Cant be set again
        isOrbiter[deneb] = true;

        /// @custom:event InitializeOrbiters
        emit NewOrbiter(true, totalOrbiters, deneb, _name);
    }

    /**
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function setAlbireoOrbiter(string calldata _name, address albireo) external override cygnusAdmin {
        /// @custom:error OrbiterAlreadySet
        if (isOrbiter[albireo]) revert Hangar18__OrbiterAlreadySet();

        // Total borrowable orbiters
        uint256 totalOrbiters = allAlbireoOrbiters.length;

        // Has not been initialized yet, create struct and push to albireo orbiter array
        allAlbireoOrbiters.push(
            AlbireoOrbiter({
                status: true,
                orbiterId: uint88(totalOrbiters), // Orbiter ID
                albireoOrbiter: IAlbireoOrbiter(albireo), // Borrowable deployer
                orbiterName: _name // Friendly name (ie STARGATE POOLS, SONNE POOLS, etc)
            })
        );

        // Cant be set again
        isOrbiter[albireo] = true;

        /// @custom:event InitializeOrbiters
        emit NewOrbiter(true, totalOrbiters, albireo, _name);
    }

    /**
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function setPendingAdmin(address newPendingAdmin) external override cygnusAdmin {
        /// @custom:error AdminAlreadySet
        if (newPendingAdmin == admin) revert Hangar18__AdminAlreadySet();

        // Address of the pending admin until this point
        address oldPendingAdmin = pendingAdmin;

        // Assign the new pending admin as the pending admin
        pendingAdmin = newPendingAdmin;

        /// @custom:event NewPendingCygnusAdmin
        emit NewPendingCygnusAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function setNewCygnusAdmin() external override cygnusAdmin {
        /// @custom:error PendingAdminCantBeZero
        if (pendingAdmin == address(0)) revert Hangar18__PendingAdminCantBeZero();

        // Address of the Admin until this point
        address oldAdmin = admin;

        // Assign the pending admin as the new cygnus admin
        admin = pendingAdmin;

        // Gas refund
        delete pendingAdmin;

        // @custom:event NewCygnusAdming
        emit NewCygnusAdmin(oldAdmin, admin);
    }

    /**
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function setPendingDaoReserves(address newPendingDaoReserves) external override cygnusAdmin {
        /// @custom:error DaoReservesAlreadySet
        if (newPendingDaoReserves == daoReserves) revert Hangar18__DaoReservesAlreadySet();

        // Pending dao reserves until this point
        address oldPendingDaoReserves = pendingDaoReserves;

        // Assign the new pending dao reserves
        pendingDaoReserves = newPendingDaoReserves;

        /// @custom:event NewPendingDaoReserves
        emit NewPendingDaoReserves(oldPendingDaoReserves, pendingDaoReserves);
    }

    /**
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function setNewDaoReserves() external override cygnusAdmin {
        /// @custom:error DaoReservesCantBeZero
        if (pendingDaoReserves == address(0)) revert Hangar18__DaoReservesCantBeZero();

        // Address of the reserves admin up until now
        address oldDaoReserves = daoReserves;

        // Assign the pending admin as admin
        daoReserves = pendingDaoReserves;

        // Gas refund
        delete pendingDaoReserves;

        /// @custom:event DaoReserves
        emit NewDaoReserves(oldDaoReserves, daoReserves);
    }

    /**
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function setCygnusX1Vault(address newX1Vault) external override cygnusAdmin {
        /// @custom:error X1VaultCantBeZero
        if (newX1Vault == address(0)) revert Hangar18__X1VaultCantBeZero();

        // Old vault
        address oldVault = cygnusX1Vault;

        // Assign new vault
        cygnusX1Vault = newX1Vault;

        /// @custom:event NewX1Vault
        emit NewX1Vault(oldVault, newX1Vault);
    }
}
