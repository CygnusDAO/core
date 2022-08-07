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

// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";
import { Context } from "./utils/Context.sol";
import { ReentrancyGuard } from "./utils/ReentrancyGuard.sol";

// Libraries
import { CygnusPoolAddress } from "./libraries/CygnusPoolAddress.sol";
import { PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import { IChainlinkNebulaOracle } from "./interfaces/IChainlinkNebulaOracle.sol";

// Orbiters
import { IDenebOrbiter } from "./interfaces/IDenebOrbiter.sol";
import { IAlbireoOrbiter } from "./interfaces/IAlbireoOrbiter.sol";

/**
 *  @title  CygnusFactory
 *  @author CygnusDAO
 *  @notice Factory contract for CygnusDAO which deploys all borrow/collateral contracts in this chain. There
 *          is only 1 factory contract per chain along with multiple pairs of `orbiters`.
 *
 *          Orbiters are the collateral and borrow deployers contracts which are not not part of the
 *          core contracts, but instead are in charge of deploying the arms of core contracts with each other's
 *          addresses (borrow orbiter deploys the borrow arm with the collateral address, and vice versa).
 *
 *          Each orbiter has the bytecode of the collateral being deployed, and they may differ slighlty due
 *          to the strategy deployed (for example each masterchef is different, requiring different harvest
 *          strategy, staking mechanism, etc.) and each `CygnusCollateralVoid` would be different.
 *          Ideally there should only be 1 orbiter per DEX (1 borrow && 1 collateral orbiter) or 1 per strategy.
 *
 *          This factory contract contains the records of all shuttles deployed by Cygnus. Every collateral/borrow
 *          contract reports back here to:
 *              - Check admin address (to increase debt ratios, update interest rate model, set void, etc.)
 *              - Check reserves manager address when minting new DAO reserves (in CygnusBorrow.sol)
 */
contract CygnusFactory is ICygnusFactory, Context, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusFactory
     */
    mapping(uint256 => Orbiter) public override getOrbiters;

    /**
     *  @inheritdoc ICygnusFactory
     */
    Orbiter[] public override allOrbiters;

    /**
     *  @inheritdoc ICygnusFactory
     */
    mapping(address => mapping(uint256 => Shuttle)) public override getShuttles;

    /**
     *  @inheritdoc ICygnusFactory
     */
    Shuttle[] public override allShuttles;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address public override admin;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address public override pendingAdmin;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address public override daoReserves;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address public override pendingDaoReserves;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address public immutable override dai;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address public immutable override nativeToken;

    /**
     *  @inheritdoc ICygnusFactory
     */
    IChainlinkNebulaOracle public override cygnusNebulaOracle;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Sets the cygnus admin/reservesManager/dai/native token/oracle addresses
     *  @param _admin Address of the Cygnus Admin to update important protocol parameters
     *  @param _daoReserves Address of the contract that handles weighted forwarding of Erc20 tokens
     *  @param _dai Address of the DAI contract on this chain (different for mainnet, c-chain, etc.)
     *  @param _nativeToken The address of this chain's native token
     *  @param _cygnusNebulaOracle Address of the price oracle
     */
    constructor(
        address _admin,
        address _daoReserves,
        address _dai,
        address _nativeToken,
        IChainlinkNebulaOracle _cygnusNebulaOracle
    ) {
        // Assign cygnus admin, has access to special functions
        admin = _admin;

        // Assign reserves manager
        daoReserves = _daoReserves;

        // Address of the native token for this chain (ie WETH)
        nativeToken = _nativeToken;

        // Address of DAI on this factory's chain
        dai = _dai;

        // Assign oracle used by all pools
        cygnusNebulaOracle = _cygnusNebulaOracle;

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
        /// @custom:error CygnusAdminOnly Avoid unless caller is Cygnus admin
        if (_msgSender() != admin) {
            revert CygnusFactory__CygnusAdminOnly({ sender: _msgSender(), admin: admin });
        }
    }

    /**
     *  @notice Checks if the same pair of collateral and borrowable deployers we are setting already exist
     *  @param albireoOrbiter The address of the borrowable deployer
     *  @param denebOrbiter The address of the collateral deployer
     *  @param orbitersLength How many orbiter pairs we have deployed
     */
    function checkOrbitersInternal(
        IAlbireoOrbiter albireoOrbiter,
        IDenebOrbiter denebOrbiter,
        uint256 orbitersLength
    ) private view {
        // Load orbiter to memory
        Orbiter[] memory orbiter = allOrbiters;

        // Check if orbiters already exist
        for (uint256 i = 0; i < orbitersLength; i++) {
            /// @custom:error OrbiterAlreadySet Avoid setting the same orbiters twice
            if (orbiter[i].cygnusDeneb == denebOrbiter && orbiter[i].cygnusAlbireo == albireoOrbiter) {
                revert CygnusFactory__OrbiterAlreadySet({ orbiter: orbiter[i] });
            }
        }
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusFactory
     */
    function orbitersDeployed() external view override returns (uint256) {
        // Return how many borrow/collateral orbiters this contract has
        return allOrbiters.length;
    }

    /**
     *  @inheritdoc ICygnusFactory
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
     *  @dev Prepares shuttle for deployment and stores each Shuttle struct
     *  @param lpTokenPair Address of LP Token for this shuttle
     */
    function boardShuttle(address lpTokenPair, uint256 orbiterId) private {
        // Get the ID for this LP token's shuttle
        uint24 shuttleId = getShuttles[lpTokenPair][orbiterId].shuttleId;

        /// @custom:error ShuttleAlreadyDeployed Avoid initializing two identical shuttles
        if (shuttleId != 0) {
            revert CygnusFactory__ShuttleAlreadyDeployed({ id: shuttleId, lpTokenPair: lpTokenPair });
        }

        // Set all to default before deploying
        getShuttles[lpTokenPair][orbiterId] = Shuttle(
            false, // Initialized, default false until oracle is set
            uint24(allShuttles.length), // Lending pool ID
            address(0), // Borrow contract address
            address(0), // Collateral address
            address(0), // Underlying borrow asset (DAI)
            address(0), // Underlying collateral asset (LP Token)
            Orbiter(false, 0, "", IAlbireoOrbiter(address(0)), IDenebOrbiter(address(0)))
        );
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *    Phase1: Orbiter check
     *              - Orbiters (deployers) are active and usable
     *    Phase2: Board shuttle check
     *              - No shuttle with the same LP Token has been deployed before
     *    Phase3: Deploy Collateral and Borrow contracts
     *              - Calculate address of the collateral and deploy borrow contract with calculated collateral address
     *              - Deploy the collateral contract with the deployed borrow address
     *              - Check that collateral contract address is equal to the calculated collateral address, else revert
     *    Phase4: Price Oracle check:
     *              - Assert price oracle exists for this LP Token pair
     *    Phase5: Initialize shuttle
     *              - Initialize and store record of this shuttle in this contract
     *
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function deployShuttle(
        address lpTokenPair,
        uint256 orbiterId,
        uint256 baseRate,
        uint256 multiplier,
        uint256 kinkMultiplier
    ) external override nonReentrant returns (address cygnusDai, address collateral) {
        //  ─────────────────────────────── Phase 1 ───────────────────────────────

        // Load orbiter to memory
        Orbiter memory orbiter = getOrbiters[orbiterId];

        /// @custom:error OrbitersAreInactive Avoid deploying if orbiters are inactive or are not set
        if (!orbiter.status) {
            revert CygnusFactory__OrbitersAreInactive({ orbiter: orbiter });
        }
        //  ─────────────────────────────── Phase 2 ───────────────────────────────

        Shuttle storage shuttle = getShuttles[lpTokenPair][orbiterId];

        // Prepare shuttle for deployment, reverts if lpTokenPair already exists
        boardShuttle(lpTokenPair, orbiterId);

        //  ─────────────────────────────── Phase 3 ───────────────────────────────

        // Get the pre-determined collateral address for this LP Token (check CygnusPoolAddres library)
        address create2Collateral = CygnusPoolAddress.getCollateralContract(
            lpTokenPair,
            address(this),
            address(orbiter.cygnusDeneb),
            orbiter.cygnusDeneb.COLLATERAL_INIT_CODE_HASH()
        );

        // Deploy borrow
        cygnusDai = orbiter.cygnusAlbireo.deployAlbireo(dai, create2Collateral, baseRate, multiplier, kinkMultiplier);

        // Deploy collateral
        collateral = orbiter.cygnusDeneb.deployDeneb(lpTokenPair, cygnusDai);

        /// @custom:error CollateralAddressMismatch Avoid deploying shuttle if calculated is different than deployed
        if (collateral != create2Collateral) {
            revert CygnusFactory__CollateralAddressMismatch({
                calculatedCollateral: create2Collateral,
                deployedCollateral: collateral
            });
        }

        //  ─────────────────────────────── Phase 4 ───────────────────────────────

        // Oracle should never NOT be initialized for this pair. If not initialized, deployment of collateral auto fails
        (bool nebulaOracleInitialized, , , , ) = cygnusNebulaOracle.getNebula(lpTokenPair);

        /// @custom:error LPTokenPairNotSupported Avoid deploying if the oracle for the LP token is not initalized
        if (!nebulaOracleInitialized) {
            revert CygnusFactory__LPTokenPairNotSupported({ lpTokenPair: lpTokenPair });
        }

        //  ─────────────────────────────── Phase 5 ───────────────────────────────

        // No way back now, store shuttle in factory

        // Add collateral contract to record
        shuttle.collateral = collateral;

        // Add cygnus borrow contract to record
        shuttle.cygnusDai = cygnusDai;

        // Add the address of the underlying albireo contract
        shuttle.lpTokenPair = lpTokenPair;

        // Add the address of the underlying albireo contract
        shuttle.borrowToken = dai;

        // Store orbiters struct in the shuttle struct
        shuttle.orbiter = orbiter;

        // This specific lending pool is initialized can't be deployed again
        shuttle.launched = true;

        // Push to struct of all shuttles deployed
        allShuttles.push(shuttle);

        // Link to mapping
        // getShuttles[lpTokenPair][orbiterId] = shuttle;

        /// @custom:event NewShuttleLaunched
        emit NewShuttleLaunched(shuttle.shuttleId, cygnusDai, collateral, dai, lpTokenPair);
    }

    /**
     *  @notice Anyone may create their own strategy to deploy their own lending pool but admin reserves the right
     *          to switch status, reverting future deployments
     *  @inheritdoc ICygnusFactory
     */
    function initializeOrbiter(
        string memory orbiterName,
        IAlbireoOrbiter cygnusAlbireo,
        IDenebOrbiter cygnusDeneb
    ) external override {
        // Total orbiters
        uint256 totalOrbiters = allOrbiters.length;

        // Check if collateral orbiter already exists, reverts if it does
        checkOrbitersInternal(cygnusAlbireo, cygnusDeneb, totalOrbiters);

        // Orbiters, ID starts from 0 so length is alwyas 1 ahead from record
        Orbiter storage orbiter = getOrbiters[totalOrbiters];

        // ID for this group of collateral and borrow orbiters
        orbiter.orbiterId = uint24(totalOrbiters);

        // Name of the exchange these orbiters are for
        orbiter.orbiterName = orbiterName;

        // Borrow orbiter address
        orbiter.cygnusAlbireo = cygnusAlbireo;

        // Collateral orbiter address
        orbiter.cygnusDeneb = cygnusDeneb;

        // ID for this group of collateral/borrow orbiters
        orbiter.status = true;

        // Push struct to array
        allOrbiters.push(orbiter);

        /// @custom:event InitializeOrbiters
        emit InitializeOrbiters(true, totalOrbiters, orbiterName, cygnusDeneb, cygnusAlbireo);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     */
    function switchOrbiterStatus(uint256 orbiterId) external override cygnusAdmin {
        // Get the orbiter by the ID
        ICygnusFactory.Orbiter storage orbiter = getOrbiters[orbiterId];

        /// @custom:error OrbiterNotSet Avoid switching on/off if orbiters are not set
        if ((address(orbiter.cygnusDeneb) == address(0)) || address(orbiter.cygnusAlbireo) == address(0)) {
            revert CygnusFactory__OrbitersNotSet({ orbiterId: orbiterId });
        }

        // Switch orbiter status. If currently active then future deployments with this orbiter will revert
        orbiter.status = !orbiter.status;

        /// @custom:event SwitchOrbiterStatus
        emit SwitchOrbiterStatus(
            orbiter.status,
            orbiter.orbiterId,
            orbiter.orbiterName,
            orbiter.cygnusAlbireo,
            orbiter.cygnusDeneb
        );
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     */
    function setNewNebulaOracle(address newPriceOracle) external override cygnusAdmin {
        /// @custom:error CygnusNebulaCantBeZero Avoid zero address oracle
        if (newPriceOracle == address(0)) {
            revert CygnusFactory__CygnusNebulaCantBeZero();
        }
        /// @custom:error CygnusNebulaAlreadySet Avoid setting the same address twice
        else if (newPriceOracle == address(cygnusNebulaOracle)) {
            revert CygnusFactory__CygnusNebulaAlreadySet({
                priceOracle: address(cygnusNebulaOracle),
                newPriceOracle: newPriceOracle
            });
        }

        // Assign old oracle address for event
        IChainlinkNebulaOracle oldOracle = cygnusNebulaOracle;

        // Address of the requested account to be Cygnus admin
        cygnusNebulaOracle = IChainlinkNebulaOracle(newPriceOracle);

        /// @custom:event NewCygnusNebulaOracle
        emit NewCygnusNebulaOracle(oldOracle, cygnusNebulaOracle);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     */
    function setPendingAdmin(address newPendingAdmin) external override cygnusAdmin {
        /// @custom:error CygnusAdminAlreadySet Avoid setting the pending admin as the current admin
        if (newPendingAdmin == admin) {
            revert CygnusFactory__AdminAlreadySet({ newPendingAdmin: newPendingAdmin, admin: admin });
        }
        /// @custom:error PendingAdminAlreadySet Avoid setting the same pending admin twice
        else if (newPendingAdmin == pendingAdmin) {
            revert CygnusFactory__PendingAdminAlreadySet({
                newPendingAdmin: newPendingAdmin,
                pendingAdmin: pendingAdmin
            });
        }

        // Address of the pending admin until this point
        address oldPendingAdmin = pendingAdmin;

        // Assign the new pending admin as the pending admin
        pendingAdmin = newPendingAdmin;

        /// @custom:event PendingCygnusAdmin
        emit PendingCygnusAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     */
    function setNewCygnusAdmin() external override cygnusAdmin {
        /// @custom:error PendingAdminCantBeZero Avoid setting cygnus admin as address(0)
        if (pendingAdmin == address(0)) {
            revert CygnusFactory__PendingAdminCantBeZero();
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
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     */
    function setPendingDaoReserves(address newPendingDaoReserves) external override cygnusAdmin {
        /// @custom:error DaoReservesAlreadySet Avoid setting the pending dao reserves as the current dao reserves
        if (newPendingDaoReserves == daoReserves) {
            revert CygnusFactory__DaoReservesAlreadySet({
                newPendingDaoReserves: newPendingDaoReserves,
                daoReserves: daoReserves
            });
        }
        /// @custom:error PendingDaoReservesAlreadySet Avoid setting the same pending dao reserves address twice
        else if (newPendingDaoReserves == pendingDaoReserves) {
            revert CygnusFactory__PendingDaoReservesAlreadySet({
                newPendingDaoReserves: newPendingDaoReserves,
                pendingDaoReserves: pendingDaoReserves
            });
        }

        // Pending dao reserves until this point
        address oldPendingDaoReserves = pendingDaoReserves;

        // Assign the new pending dao reserves
        pendingDaoReserves = newPendingDaoReserves;

        /// @custom:event PendingDaoReserves
        emit PendingDaoReserves(oldPendingDaoReserves, pendingDaoReserves);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     */
    function setNewDaoReserves() external override cygnusAdmin {
        /// @custom:error DaoReservesCantBeZero Avoid setting the dao reserves as the zero address
        if (pendingDaoReserves == address(0)) {
            revert CygnusFactory__DaoReservesCantBeZero();
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
}
