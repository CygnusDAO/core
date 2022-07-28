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
 *  @title  CygnusCollateralControl
 *  @author CygnusDAO
 *  @notice Factory contract for CygnusDAO which deploys all borrow/collateral contracts in this chain. There
 *          is only 1 factory contract per chain along with multiple pairs of `orbiters`.
 *
 *          Orbiters are the deployers contracts (AlbireoOrbiter and DenebOrbiter) which are not not part of the core
 *          contracts, but instead are in charge of deploying the arms of core contracts with each other's addresses 
 *          (borrow orbiter deploys the borrow arm with the collateral address, and vice versa).

 *          Each orbiter has the bytecode of the collateral being deployed, and they may differ slighlty due
 *          to the strategy deployed (for example each masterchef is different, requiring different harvest strategy,
 *          staking mechanism, etc.) and each `CygnusCollateralVoid` would be different. 
 *          Ideally there should only be 1 orbiter per DEX (1 borrow && 1 collateral orbiter).
 *
 *          This factory contract contains the records of all shuttles deployed by Cygnus. Every collateral/borrow
 *          contract reports back here to:
 *
 *          - Check admin address (to increase debt ratios, update interest rate model, set void, etc.)
 *          - Check reserves manager address when minting new DAO reserves (in CygnusBorrow.sol)
 */
contract CygnusFactory is ICygnusFactory, Context, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct Shuttle Official record of pools deployed by this factory
     *  @custom:member launched Whether or not the lending pool is initialized
     *  @custom:member shuttleId The ID of the lending pool
     *  @custom:member collateral The address of the Cygnus collateral
     *  @custom:member cygnusDai The address of the borrowing contract
     *  @custom:member underlyingCollateral The address of the underlying collateral (LP Token)
     *  @custom:member dai The address of the underlying albireo contract (DAI)
     */
    struct Shuttle {
        bool launched;
        uint24 shuttleId;
        address cygnusDai;
        address collateral;
        address borrowToken;
        address lpTokenPair;
        ICygnusFactory.Orbiter orbiter;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     */
    mapping(address => Shuttle) public override getShuttles;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address[] public override allShuttles;

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
    address public override admin;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address public override pendingNewAdmin;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address public override vegaTokenManager;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address public override pendingVegaTokenManager;

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
    IChainlinkNebulaOracle public override cygnusNebulaOracle; // Price oracle

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Sets the cygnus admin/reservesManager/dai/native token/oracle addresses
     *  @param _admin Address of the Cygnus Admin to update important protocol parameters
     *  @param _vegaTokenManager Address of the contract that handles weighted forwarding of Erc20 tokens
     *  @param _dai Address of the DAI contract on this chain (different for mainnet, c-chain, etc.)
     *  @param _nativeToken The address of this chain's native token
     *  @param _cygnusNebulaOracle Address of the price oracle
     */
    constructor(
        address _admin,
        address _vegaTokenManager,
        address _dai,
        address _nativeToken,
        IChainlinkNebulaOracle _cygnusNebulaOracle
    ) {
        // Assign cygnus admin, has access to special functions
        admin = _admin;

        // Assign reserves manager
        vegaTokenManager = _vegaTokenManager;

        // Address of the native token for this chain (ie WETH)
        nativeToken = _nativeToken;

        // Address of DAI on this factory's chain
        dai = _dai;

        // Assign oracle used by all pools
        cygnusNebulaOracle = _cygnusNebulaOracle;

        /// @custom:event NewCygnusAdmin
        emit NewCygnusAdmin(address(0), _admin);

        /// @custom:event NewVegaTokenManager
        emit NewVegaTokenManager(address(0), _vegaTokenManager);
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
     *  @notice Checks if the new orbiter we are setting already exists. This is just a safety and to make sure
     *          each pair of deployers are in sync with each other
     *  @param newDenebOrbiter The address of the collateral deployer
     *  @param orbitersLength How many orbiter pairs we have deployed
     */
    function checkOrbitersInternal(IDenebOrbiter newDenebOrbiter, uint256 orbitersLength) private view {
        // Check if orbiters already exist
        for (uint256 i = 0; i < orbitersLength; i++) {
            /// @custom:error CollateralOrbiterAlreadySet Avoid duplicate collateral orbiter
            if (getOrbiters[i].cygnusDeneb == newDenebOrbiter) {
                revert CygnusFactory__CollateralOrbiterAlreadySet({
                    cygnusDeneb: getOrbiters[i].cygnusDeneb,
                    newCygnusDeneb: newDenebOrbiter
                });
            }
        }
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusFactory
     */
    function shuttlesDeployed() external view override returns (uint256) {
        // Return how many shuttles this contract has launched
        return allShuttles.length;
    }

    /**
     *  @inheritdoc ICygnusFactory
     */
    function orbitersDeployed() external view override returns (uint256) {
        // Return how many borrow/collateral orbiters this contract has
        return allOrbiters.length;
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
    function boardShuttle(address lpTokenPair) private {
        // Get the ID for this LP token's shuttle
        uint24 shuttleId = getShuttles[lpTokenPair].shuttleId;

        /// @custom:error ShuttleAlreadyDeployed Avoid initializing two identical shuttles
        if (shuttleId != 0) {
            revert CygnusFactory__ShuttleAlreadyDeployed({ id: shuttleId, lpTokenPair: lpTokenPair });
        }

        // Set all to default before deploying
        getShuttles[lpTokenPair] = Shuttle(
            false, // Initialized, default false until oracle is set
            uint24(allShuttles.length), // Lending pool ID
            address(0), // Collateral address
            address(0), // Borrow contract address
            address(0), // Underlying collateral asset (LP Token)
            address(0), // Underlying borrow asset (DAI)
            Orbiter(false, 0, "", IAlbireoOrbiter(address(0)), IDenebOrbiter(address(0)))
        );

        // Push to lending pool
        allShuttles.push(lpTokenPair);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *    Phase 1: Board shuttle check
     *              -> No shuttle with the same LP Token has been deployed before
     *
     *    Phase 2: Orbiter check
     *              -> Orbiters (deployers) are active and usable
     *
     *    Phase 3: Deploy Collateral and Borrow contracts
     *              -> Calculate address of the collateral and deploy borrow contract with calculated collateral address
     *              -> Deploy the collateral contract with the deployed borrow address
     *              -> Check that collateral contract address is equal to the calculated collateral address, else revert
     *
     *    Phase 4: Price Oracle check:
     *              -> Assert price oracle exists for this LP Token pair
     *
     *    Phase 5: Initialize shuttle
     *              -> Initialize and store record of this shuttle in this contract
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

        // Prepare shuttle for deployment, reverts if lpTokenPair already exists
        boardShuttle(lpTokenPair);

        //  ─────────────────────────────── Phase 2 ───────────────────────────────

        // Load orbiters to memory
        Orbiter memory orbiter = getOrbiters[orbiterId];

        /// @custom:error OrbitersAreInactive Avoid deploying if orbiters are inactive or are not set
        if (!orbiter.active) {
            revert CygnusFactory__OrbitersAreInactive({
                id: orbiter.orbiterId,
                cygnusDeneb: orbiter.cygnusDeneb,
                cygnusAlbireo: orbiter.cygnusAlbireo
            });
        }

        //  ─────────────────────────────── Phase 3 ───────────────────────────────

        // Get the pre-determined collateral address for this LP Token (check CygnusPoolAddres library)
        address predictedC = CygnusPoolAddress.getCollateralContract(
            lpTokenPair,
            address(this),
            address(orbiter.cygnusDeneb),
            orbiter.cygnusDeneb.COLLATERAL_INIT_CODE_HASH()
        );

        // Deploy borrow
        cygnusDai = orbiter.cygnusAlbireo.deployAlbireo(dai, predictedC, baseRate, multiplier, kinkMultiplier);

        // Deploy collateral
        collateral = orbiter.cygnusDeneb.deployDeneb(lpTokenPair, cygnusDai);

        /// @custom:error CollateralAddressMismatch Avoid deploying shuttle if calculated is different than deployed
        if (collateral != predictedC) {
            revert CygnusFactory__CollateralAddressMismatch({
                calculatedCollateral: predictedC,
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
        getShuttles[lpTokenPair].collateral = collateral;

        // Add cygnus borrow contract to record
        getShuttles[lpTokenPair].cygnusDai = cygnusDai;

        // Add the address of the underlying albireo contract
        getShuttles[lpTokenPair].lpTokenPair = lpTokenPair;

        // Add the address of the underlying albireo contract
        getShuttles[lpTokenPair].borrowToken = dai;

        // Store orbiters struct in the shuttle struct
        getShuttles[lpTokenPair].orbiter = orbiter;

        // This specific lending pool is initialized can't be deployed again
        getShuttles[lpTokenPair].launched = true;

        /// @custom:event NewShuttleLaunched
        emit NewShuttleLaunched(getShuttles[lpTokenPair].shuttleId, cygnusDai, collateral, dai, lpTokenPair);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function switchOrbiterStatus(uint256 orbiterId) external override nonReentrant cygnusAdmin {
        // Get the orbiter by the ID
        ICygnusFactory.Orbiter storage orbiter = getOrbiters[orbiterId];

        /// @custom:error OrbiterNotSet Avoid switching on/off if orbiters are not set
        if ((address(orbiter.cygnusDeneb) == address(0)) || address(orbiter.cygnusAlbireo) == address(0)) {
            revert CygnusFactory__OrbitersNotSet({ orbiterId: orbiterId });
        }

        // Switch orbiter status
        orbiter.active = !orbiter.active;

        /// @custom:event SwitchOrbiterStatus
        emit SwitchOrbiterStatus(
            orbiter.active,
            orbiter.orbiterId,
            orbiter.orbiterName,
            orbiter.cygnusDeneb,
            orbiter.cygnusAlbireo
        );
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function setNewOrbiter(
        string memory orbiterName,
        IDenebOrbiter _cygnusDeneb,
        IAlbireoOrbiter _cygnusAlbireo
    ) external override nonReentrant cygnusAdmin {
        // Total orbiters
        uint256 totalOrbiters = allOrbiters.length;

        // Check if collateral orbiter already exists, reverts if it does
        checkOrbitersInternal(_cygnusDeneb, totalOrbiters);

        // Orbiters, ID starts from 0 so length is alwyas 1 ahead from record
        Orbiter storage orbiter = getOrbiters[totalOrbiters];

        // ID for this group of collateral and borrow orbiters
        orbiter.orbiterId = uint24(totalOrbiters);

        // Name of the exchange these orbiters are for
        orbiter.orbiterName = orbiterName;

        // Collateral orbiter address
        orbiter.cygnusDeneb = _cygnusDeneb;

        // Borrow orbiter address
        orbiter.cygnusAlbireo = _cygnusAlbireo;

        // ID for this group of collateral/borrow orbiters
        orbiter.active = true;

        // Push struct to array
        allOrbiters.push(orbiter);

        /// @custom:event InitializeOrbiters
        emit InitializeOrbiters(true, totalOrbiters, orbiterName, _cygnusDeneb, _cygnusAlbireo);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function setNewNebulaOracle(address newPriceOracle) external override nonReentrant cygnusAdmin {
        /// @custom:error CygnusNebulaCantBeZero Avoid zero address oracle
        if (newPriceOracle == address(0)) {
            revert CygnusFactory__CygnusNebulaCantBeZero({ priceOracle: newPriceOracle });
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
     *  @custom:security non-reentrant
     */
    function setPendingAdmin(address newCygnusAdmin) external override nonReentrant cygnusAdmin {
        /// @custom:error CygnusAdminAlreadySet Avoid setting the same admin twice
        if (newCygnusAdmin == admin) {
            revert CygnusFactory__CygnusAdminAlreadySet({ currentAdmin: admin, newPendingAdmin: newCygnusAdmin });
        }

        // Address of the requested account to be Cygnus admin
        pendingNewAdmin = newCygnusAdmin;

        /// @custom:event PendingCygnusAdmin
        emit PendingCygnusAdmin(admin, newCygnusAdmin);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function setNewCygnusAdmin() external override nonReentrant cygnusAdmin {
        /// @custom:error PendingAdminCantBeZero Avoid setting cygnus admin as address(0)
        if (pendingNewAdmin == address(0)) {
            revert CygnusFactory__PendingAdminCantBeZero({ pending: pendingNewAdmin, sender: _msgSender() });
        }

        // Address of the Admin up until now
        address oldAdmin = admin;

        // Address of the new Cygnus Admin after this transaction
        admin = pendingNewAdmin;

        // Gas refund
        delete pendingNewAdmin;

        // @custom:event NewCygnusAdming
        emit NewCygnusAdmin(oldAdmin, admin);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function setPendingVegaTokenManager(address newVegaTokenManager) external override nonReentrant cygnusAdmin {
        /// @custom:error CygnusVegaAlreadySet Avoid setting the same reserves admin twice
        if (newVegaTokenManager == vegaTokenManager) {
            revert CygnusFactory__CygnusVegaAlreadySet({
                currentVegaTokenManager: vegaTokenManager,
                newVegaTokenManager: newVegaTokenManager
            });
        }

        // Address of the Vega contract up until now
        pendingVegaTokenManager = newVegaTokenManager;

        /// @custom:event PendingVegaTokenManager
        emit PendingVegaTokenManager(vegaTokenManager, newVegaTokenManager);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function setNewVegaTokenManager() external override nonReentrant cygnusAdmin {
        /// @custom:error PendingVegaCantBeZero Avoid setting the reserves manager as the zero address
        if (pendingVegaTokenManager == address(0)) {
            revert CygnusFactory__PendingVegaCantBeZero({ pending: pendingVegaTokenManager, sender: _msgSender() });
        }

        // Address of the reserves admin up until now
        address oldVegaTokenManager = vegaTokenManager;

        // Assign the pending admin as admin
        vegaTokenManager = pendingVegaTokenManager;

        // Gas refund
        delete pendingVegaTokenManager;

        /// @custom:event NewVegaTokenManager
        emit NewVegaTokenManager(oldVegaTokenManager, vegaTokenManager);
    }
}
