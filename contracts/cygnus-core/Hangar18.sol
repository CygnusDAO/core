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
    
        CYGNUS FACTORY V1 - `Hangar18`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */

// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {IHangar18} from "./interfaces/IHangar18.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries
import {CygnusPoolAddress} from "./libraries/CygnusPoolAddress.sol";

// Interfaces
import {ICygnusNebulaOracle} from "./interfaces/ICygnusNebulaOracle.sol";
import {IAggregationRouterV5, IAggregationExecutor} from "./interfaces/IAggregationRouterV5.sol";

// Orbiters
import {IDenebOrbiter} from "./interfaces/IDenebOrbiter.sol";
import {IAlbireoOrbiter} from "./interfaces/IAlbireoOrbiter.sol";

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
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IHangar18
     */
    IAggregationRouterV5 public constant override AGGREGATION_ROUTER_V5 = IAggregationRouterV5(0x1111111254EEB25477B68fb85Ed929f73A960582);

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
    mapping(uint256 => Orbiter) public override getOrbiters;

    /**
     *  @inheritdoc IHangar18
     */
    mapping(address => mapping(uint256 => Shuttle)) public override getShuttles;

    /**
     *  @inheritdoc IHangar18
     */
    ICygnusNebulaOracle[] public override allNebulas;

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
    address public immutable override usd;

    /**
     *  @inheritdoc IHangar18
     */
    address public immutable override nativeToken;

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
     */
    constructor(address _admin, address _daoReserves, address _usd, address _nativeToken) {
        // Assign cygnus admin, has access to special functions
        admin = _admin;

        // Assign reserves manager
        daoReserves = _daoReserves;

        // Address of the native token for this chain (ie WETH)
        nativeToken = _nativeToken;

        // Address of DAI on this factory's chain
        usd = _usd;

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
    function checkOrbitersInternal(bytes32 uniqueHash, uint256 orbitersLength) private view {
        // Load orbiter to memory
        Orbiter[] memory orbiter = allOrbiters;

        // Loop through all orbiters
        for (uint256 i = 0; i < orbitersLength; i++) {
            // Check unique hash
            if (uniqueHash == orbiter[i].uniqueHash) {
                /// @custom:error OrbiterAlreadySet
                revert Hangar18__OrbiterAlreadySet({orbiter: orbiter[i]});
            }
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

    /**
     *  @inheritdoc IHangar18
     */
    function nebulasDeployed() external view override returns (uint256) {
        // Return how many oracles we deployed
        return allNebulas.length;
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
    function boardShuttle(address lpTokenPair, uint256 orbiterId) private returns (Shuttle storage) {
        // Get the ID for this LP token's shuttle
        bool deployed = getShuttles[lpTokenPair][orbiterId].launched;

        /// @custom:error ShuttleAlreadyDeployed
        if (deployed == true) {
            revert Hangar18__ShuttleAlreadyDeployed({lpTokenPair: lpTokenPair, orbiterId: orbiterId});
        }

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
     *  @notice Checks if the oracle has been added to our list
     *  @param nebulaOracle The address of the oracle
     */
    function checkOracleInternal(ICygnusNebulaOracle nebulaOracle) internal {
        // All oracles we have
        ICygnusNebulaOracle[] memory oracles = allNebulas;

        // Loop through the array to see if we have added the oracle
        for (uint256 i = 0; i < oracles.length; i++) {
            // Escape
            if (oracles[i] == nebulaOracle) return;
        }

        // If not added add to array of oracles
        allNebulas.push(nebulaOracle);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  Phase1: Orbiter check
     *            - Orbiters (deployers) are active and usable
     *  Phase2: Board shuttle check
     *            - No shuttle with the same LP Token AND Orbiter has been deployed before
     *  Phase3: Deploy Collateral and Borrow contracts
     *            - Calculate address of the collateral and deploy borrow contract with calculated collateral address
     *            - Deploy the collateral contract with the deployed borrow address
     *            - Check that collateral contract address is equal to the calculated collateral address, else revert
     *  Phase4: Price Oracle check:
     *            - Assert price oracle exists for this LP Token pair
     *  Phase5: Initialize shuttle
     *            - Initialize and store record of this shuttle in this contract
     *
     *  @inheritdoc IHangar18
     *  @custom:security non-reentrant only-admin 👽
     */
    function deployShuttle(
        address lpTokenPair,
        uint256 orbiterId
    ) external override nonReentrant cygnusAdmin returns (address borrowable, address collateral) {
        //  ─────────────────────────────── Phase 1 ───────────────────────────────
        // Load orbiter to memory
        Orbiter memory orbiter = getOrbiters[orbiterId];

        /// @custom:error OrbitersAreInactive
        if (!orbiter.status) {
            revert Hangar18__OrbitersAreInactive({orbiter: orbiter});
        }

        //  ─────────────────────────────── Phase 2 ───────────────────────────────
        // Prepare shuttle for deployment, reverts if lpTokenPair already exists
        // Load shuttle to storage
        Shuttle storage shuttle = boardShuttle(lpTokenPair, orbiter.orbiterId);

        //  ─────────────────────────────── Phase 3 ───────────────────────────────
        // Get the pre-determined collateral address for this LP Token (check CygnusPoolAddres library)
        address create2Collateral = CygnusPoolAddress.getCollateralContract(
            lpTokenPair,
            address(this),
            address(orbiter.denebOrbiter),
            orbiter.collateralInitCodeHash
        );

        // Deploy borrow contract
        borrowable = orbiter.albireoOrbiter.deployAlbireo(usd, create2Collateral, address(orbiter.nebulaOracle), shuttle.shuttleId);

        // Deploy collateral contract
        collateral = orbiter.denebOrbiter.deployDeneb(lpTokenPair, borrowable, address(orbiter.nebulaOracle), shuttle.shuttleId);

        /// @custom:error CollateralAddressMismatch
        if (collateral != create2Collateral) {
            revert Hangar18__CollateralAddressMismatch({create2Collateral: create2Collateral, collateral: collateral});
        }

        //  ─────────────────────────────── Phase 4 ───────────────────────────────
        // Oracle should never NOT be initialized for this pair. If not initialized, deployment of collateral auto fails
        bool oracleInitialized = orbiter.nebulaOracle.getNebula(lpTokenPair).initialized;

        /// @custom:error LPTokenPairNotSupported
        if (!oracleInitialized) {
            revert Hangar18__LPTokenPairNotSupported({lpTokenPair: lpTokenPair});
        }

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
    function initializeOrbiter(
        string memory orbiterName,
        IAlbireoOrbiter albireoOrbiter,
        IDenebOrbiter denebOrbiter,
        ICygnusNebulaOracle nebulaOracle
    ) external override nonReentrant cygnusAdmin {
        // Total orbiters
        uint256 totalOrbiters = allOrbiters.length;

        // Collateral init code hash
        bytes32 collateralInitCodeHash = denebOrbiter.collateralInitCodeHash();

        // Borrowable init code hash
        bytes32 borrowableInitCodeHash = albireoOrbiter.borrowableInitCodeHash();

        // Unique hash of both orbiters and oracle
        bytes32 uniqueHash = keccak256(abi.encode(collateralInitCodeHash, borrowableInitCodeHash, nebulaOracle));

        // Check if we already initialized these orbiter pair, reverts if we have
        checkOrbitersInternal(uniqueHash, totalOrbiters);

        // Create storage for orbiters with this ID
        Orbiter storage orbiter = getOrbiters[totalOrbiters];

        // ID for this group of collateral and borrow orbiters
        orbiter.orbiterId = uint88(totalOrbiters);

        // Name of the dex/strategy these orbiters are for or human readable identifier
        orbiter.orbiterName = orbiterName;

        // Collateral orbiter address
        orbiter.denebOrbiter = denebOrbiter;

        // Borrow orbiter address
        orbiter.albireoOrbiter = albireoOrbiter;

        // Assign oracle
        orbiter.nebulaOracle = nebulaOracle;

        // Collateral init code hash
        orbiter.collateralInitCodeHash = collateralInitCodeHash;

        // Borrowable init code hash
        orbiter.borrowableInitCodeHash = borrowableInitCodeHash;

        // Unique hash
        orbiter.uniqueHash = uniqueHash;

        // ID for this group of collateral/borrow orbiters
        orbiter.status = true;

        // Push struct to array
        allOrbiters.push(orbiter);

        // Add oracle to array
        checkOracleInternal(nebulaOracle);

        /// @custom:event InitializeOrbiters
        emit InitializeOrbiters(true, totalOrbiters, albireoOrbiter, denebOrbiter, nebulaOracle, uniqueHash, orbiterName);
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
