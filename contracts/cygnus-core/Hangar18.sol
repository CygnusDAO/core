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

// Interfaces
import {ICygnusNebulaRegistry} from "./interfaces/ICygnusNebulaRegistry.sol";
import {IDenebOrbiter} from "./interfaces/IDenebOrbiter.sol";
import {IAlbireoOrbiter} from "./interfaces/IAlbireoOrbiter.sol";
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
    Orbiter[] public override allOrbiters;

    /**
     *  @inheritdoc IHangar18
     */
    Shuttle[] public override allShuttles;

    /**
     *  @inheritdoc IHangar18
     */
    mapping(address => mapping(uint256 => Shuttle)) public override getShuttles; // LP Address => Orbiter ID = Lending Pool

    /**
     *  @inheritdoc IHangar18
     */
    string public override name = string(abi.encodePacked("Hangar18: Lending Pool Deployer #", block.chainid));

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
    constructor(address _admin, address _daoReserves, address _usd, address _nativeToken, ICygnusNebulaRegistry _registry) {
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

    /**
     *  @notice Checks if the same pair of collateral & borrowable deployers and oracle we are setting already exist
     *  @param uniqueHash The keccak256 hash of the borrowableInitCodeHash, collateralInitCodeHash and oracle address
     *  @param orbitersLength How many orbiter pairs we have deployed
     */
    function checkOrbitersPrivate(bytes32 uniqueHash, uint256 orbitersLength) private view {
        // Load orbiter to memory
        Orbiter[] memory orbiter = allOrbiters;

        // Loop through all orbiters
        for (uint256 i = 0; i < orbitersLength; i++) {
            /// @custom:error OrbiterAlreadySet
            if (uniqueHash == orbiter[i].uniqueHash) revert Hangar18__OrbiterAlreadySet();
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IHangar18
     */
    function collateralTvlUsd() public view override returns (uint256 totalUsd) {
        // Array of pools deployed
        Shuttle[] memory shuttles = allShuttles;

        // Total pools deployed
        uint256 poolsDeployed = allShuttles.length;

        // Loop through each pool deployed, get collateral and add to total TVL
        for (uint256 i = 0; i < poolsDeployed; i++) {
            // This pool`s collateral
            address collateral = shuttles[i].collateral;

            // LP Price
            uint256 price = ICygnusCollateral(collateral).getLPTokenPrice();

            // Total LP assets
            uint256 totalBalance = ICygnusCollateral(collateral).totalBalance();

            // TVL = Price of LP * Balance of LP
            totalUsd += totalBalance.mulWad(price); // Denom in USDC
        }
    }

    /**
     *  @inheritdoc IHangar18
     */
    function borrowableTvlUsd() public view override returns (uint256 totalUsd) {
        // Array of pools deployed
        Shuttle[] memory shuttles = allShuttles;

        // Total pools deployed
        uint256 poolsDeployed = allShuttles.length;

        // Loop through each pool deployed, get borrowable and add to total TVL
        for (uint256 i = 0; i < poolsDeployed; i++) {
            // This pool`s borrowable
            address borrowable = shuttles[i].borrowable;

            // Total stablecoin assets in pool
            uint256 totalBalance = ICygnusBorrow(borrowable).totalBalance();

            // Total stablecoin borrows
            uint256 totalBorrows = ICygnusBorrow(borrowable).totalBorrows();

            // TVL = total borrows + total balance (they are both USDC)
            totalUsd += totalBalance + totalBorrows;
        }
    }

    /**
     *  @inheritdoc IHangar18
     */
    function cygnusTotalBorrowsUsd() public view override returns (uint256 totalBorrows) {
        // Array of pools deployed
        Shuttle[] memory shuttles = allShuttles;

        // Total pools deployed
        uint256 poolsDeployed = allShuttles.length;

        // Loop through each pool deployed, get borrowable and add to total TVL
        for (uint256 i = 0; i < poolsDeployed; i++) {
            // This pool`s borrowable
            address borrowable = shuttles[i].borrowable;

            // Total stablecoin borrows
            totalBorrows += ICygnusBorrow(borrowable).totalBorrows();
        }
    }

    /**
     *  @inheritdoc IHangar18
     */
    function cygnusTvlUsd() public view override returns (uint256) {
        // Return the total cygnus protocol TVL on this chain
        return borrowableTvlUsd() + collateralTvlUsd();
    }

    /**
     *  @inheritdoc IHangar18
     */
    function cygnusDAOReservesUsd() public view override returns (uint256 reserves) {
        // Array of pools deployed
        Shuttle[] memory shuttles = allShuttles;

        // Total pools deployed
        uint256 poolsDeployed = allShuttles.length;

        // Loop through each pool deployed, get borrowable and add to total TVL
        for (uint256 i = 0; i < poolsDeployed; i++) {
            // This pool`s borrowable
            address borrowable = shuttles[i].borrowable;

            // Total reserves owned by the DAO
            uint256 cygUsdBalance = ICygnusBorrow(borrowable).balanceOf(daoReserves);

            // current exchange rate of CygUSD to USD
            uint256 exchangeRate = ICygnusBorrow(borrowable).exchangeRate();

            // Current reserves in USD
            reserves += cygUsdBalance.mulWad(exchangeRate);
        }
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc IHangar18
     */
    function orbitersDeployed() external view override returns (uint256) {
        // Return how many borrow/collateral orbiters this contract has
        return allOrbiters.length;
    }

    /**
     *  @inheritdoc IHangar18
     */
    function shuttlesDeployed() external view override returns (uint256) {
        // Return how many shuttles this contract has launched
        return allShuttles.length;
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
        // Get the ID for this LP token's shuttle
        bool deployed = getShuttles[lpTokenPair][orbiterId].launched;

        /// @custom:error ShuttleAlreadyDeployed
        if (deployed == true) revert Hangar18__ShuttleAlreadyDeployed();

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

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  Phase1: Orbiter check
     *            - Orbiters (deployers) are active and usable
     *  Phase2: Board shuttle check
     *            - No shuttle with the same LP Token AND Orbiter has been deployed before
     *  Phase4: Price Oracle check:
     *            - Assert price oracle exists for this LP Token pair
     *  Phase3: Deploy Collateral and Borrow contracts
     *            - Calculate address of the collateral and deploy borrow contract with calculated collateral address
     *            - Deploy the collateral contract with the deployed borrow address
     *            - Check that collateral contract address is equal to the calculated collateral address, else revert
     *  Phase5: Initialize shuttle
     *            - Initialize and store record of this shuttle in this contract
     *
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function deployShuttle(
        address lpTokenPair,
        uint256 orbiterId
    ) external override cygnusAdmin returns (address borrowable, address collateral) {
        //  ─────────────────────────────── Phase 1 ───────────────────────────────
        // Load orbiter to storage for gas savings (orbiter should already set and we are not overwriting)
        Orbiter storage orbiter = allOrbiters[orbiterId];

        /// @custom:error OrbitersAreInactive
        if (!orbiter.status) revert Hangar18__OrbitersAreInactive();

        //  ─────────────────────────────── Phase 2 ───────────────────────────────
        // Prepare shuttle for deployment, reverts if lpTokenPair already exists
        // Load shuttle to storage to store if the call succeeds
        Shuttle storage shuttle = boardShuttlePrivate(lpTokenPair, orbiterId);

        //  ─────────────────────────────── Phase 3 ───────────────────────────────
        // Check that oracle has been initialized in the registry and get the nebula address
        address nebula = nebulaRegistry.getLPTokenNebulaAddress(lpTokenPair);

        /// @custom:error LiquidityTokenNotSupported
        if (nebula == address(0)) revert Hangar18__LiquidityTokenNotSupported();

        //  ─────────────────────────────── Phase 4 ───────────────────────────────
        // Get the pre-determined collateral address for this LP Token (check CygnusPoolAddres library)
        address create2Collateral = CygnusPoolAddress.getCollateralContract(
            lpTokenPair,
            address(this),
            address(orbiter.denebOrbiter),
            orbiter.collateralInitCodeHash
        );

        // Deploy borrow contract
        borrowable = orbiter.albireoOrbiter.deployAlbireo(usd, create2Collateral, nebula, shuttle.shuttleId);

        // Deploy collateral contract
        collateral = orbiter.denebOrbiter.deployDeneb(lpTokenPair, borrowable, nebula, shuttle.shuttleId);

        /// @custom:error CollateralAddressMismatch
        if (collateral != create2Collateral) revert Hangar18__CollateralAddressMismatch();

        //  ─────────────────────────────── Phase 5 ───────────────────────────────
        // Save addresses to storage and mark as launched. This LP Token with orbiter ID cannot be redeployed
        shuttle.launched = true;

        // Add cygnus borrow contract to record
        shuttle.borrowable = borrowable;

        // Add collateral contract to record
        shuttle.collateral = collateral;

        // Push the lending pool struct to the object array
        allShuttles.push(shuttle);

        /// @custom:event NewShuttleLaunched
        emit NewShuttle(lpTokenPair, orbiterId, shuttle.shuttleId, shuttle.borrowable, shuttle.collateral);
    }

    /**
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function initializeOrbiter(string memory _name, IAlbireoOrbiter albireo, IDenebOrbiter deneb) external override cygnusAdmin {
        // Total orbiters
        uint256 totalOrbiters = allOrbiters.length;

        // Borrowable init code hash
        bytes32 borrowableInitCodeHash = albireo.borrowableInitCodeHash();

        // Collateral init code hash
        bytes32 collateralInitCodeHash = deneb.collateralInitCodeHash();

        // Unique hash of both orbiters by hashing their respective init code hash
        bytes32 uniqueHash = keccak256(abi.encode(borrowableInitCodeHash, collateralInitCodeHash));

        // Check if we already initialized these orbiter pair, reverts if we have
        checkOrbitersPrivate(uniqueHash, totalOrbiters);

        // Has not been initialized yet, create struct and push to orbiter array
        allOrbiters.push(
            Orbiter({
                orbiterId: uint88(totalOrbiters), // Orbiter ID
                orbiterName: _name, // Friendly name
                albireoOrbiter: albireo, // Borrowable deployer
                denebOrbiter: deneb, // Collateral deployer
                borrowableInitCodeHash: borrowableInitCodeHash, // Borrowable code hash
                collateralInitCodeHash: collateralInitCodeHash, // Collateral code hash
                uniqueHash: uniqueHash, // Unique bytes32 orbiter id
                status: true // Mark as true
            })
        );

        /// @custom:event InitializeOrbiters
        emit InitializeOrbiters(true, totalOrbiters, albireo, deneb, uniqueHash, _name);
    }

    /**
     *  @notice Reverts future deployments with disabled orbiter
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function switchOrbiterStatus(uint256 orbiterId) external override cygnusAdmin {
        // Get the orbiter by the ID
        IHangar18.Orbiter storage orbiter = allOrbiters[orbiterId];

        /// @custom:error OrbiterNotSet
        if (orbiter.uniqueHash == bytes32(0)) {
            revert Hangar18__OrbitersNotSet({orbiterId: orbiterId});
        }

        // Switch orbiter status. If currently active then future deployments with this orbiter will revert
        orbiter.status = !orbiter.status;

        /// @custom:event SwitchOrbiterStatus
        emit SwitchOrbiterStatus(orbiter.status, orbiter.orbiterId, orbiter.albireoOrbiter, orbiter.denebOrbiter, orbiter.orbiterName);
    }

    /**
     *  @inheritdoc IHangar18
     *  @custom:security only-admin 👽
     */
    function setPendingAdmin(address newPendingAdmin) external override cygnusAdmin {
        /// @custom:error AdminAlreadySet
        if (newPendingAdmin == admin) {
            revert Hangar18__AdminAlreadySet({newPendingAdmin: newPendingAdmin, admin: admin});
        }

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
        if (pendingAdmin == address(0)) {
            revert Hangar18__PendingAdminCantBeZero();
        }

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
        if (newPendingDaoReserves == daoReserves) {
            revert Hangar18__DaoReservesAlreadySet({newPendingDaoReserves: newPendingDaoReserves, daoReserves: daoReserves});
        }

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
        if (pendingDaoReserves == address(0)) {
            revert Hangar18__DaoReservesCantBeZero();
        }

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
        if (newX1Vault == address(0)) {
            revert Hangar18__X1VaultCantBeZero();
        }

        // Old vault
        address oldVault = cygnusX1Vault;

        // Assign new vault
        cygnusX1Vault = newX1Vault;

        /// @custom:event NewX1Vault
        emit NewX1Vault(oldVault, newX1Vault);
    }
}
