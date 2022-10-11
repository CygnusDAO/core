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
    address public immutable override usdc;

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
     *  @notice Sets the important addresses which pools report back here to check for
     *  @param _admin Address of the Cygnus Admin to update important protocol parameters
     *  @param _daoReserves Address of the contract that handles weighted forwarding of Erc20 tokens
     *  @param _usdc Address of the USDC contract on this chain (different for mainnet, c-chain, etc.)
     *  @param _nativeToken The address of this chain's native token
     *  @param _cygnusNebulaOracle Address of the price oracle
     */
    constructor(
        address _admin,
        address _daoReserves,
        address _usdc,
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
        usdc = _usdc;

        // Assign oracle used by all pools
        cygnusNebulaOracle = _cygnusNebulaOracle;

        /// @custom:event NewCygnusAdmin
        emit NewCygnusAdmin(address(0), _admin);

        /// @custom:event DaoReserves
        emit NewDaoReserves(address(0), _daoReserves);

        /// @custom:event NewCygnusNebulaOracle
        emit NewCygnusNebulaOracle(IChainlinkNebulaOracle(address(0)), _cygnusNebulaOracle);
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
            if (orbiter[i].denebOrbiter == denebOrbiter && orbiter[i].albireoOrbiter == albireoOrbiter) {
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
     *  @dev Prepares shuttle for deployment and stores the orbiter used for this Shuttle
     *  @param lpTokenPair Address of the LP Token for this shuttle
     *  @param orbiter The orbiter used to deploy this shuttle
     */
    function boardShuttle(address lpTokenPair, Orbiter memory orbiter) private returns (Shuttle storage) {
        // Get the ID for this LP token's shuttle
        uint256 shuttleId = getShuttles[lpTokenPair][orbiter.orbiterId].shuttleId;

        /// @custom:error ShuttleAlreadyDeployed Avoid initializing two identical shuttles with the same orbiter ID
        if (shuttleId != 0) {
            // If we try to re-deploy the lending pool which actually has the ID of 0, the EVM will handle the revert
            revert CygnusFactory__ShuttleAlreadyDeployed({ id: shuttleId, lpTokenPair: lpTokenPair });
        }

        // Assign shuttle/orbiter ids
        return
            getShuttles[lpTokenPair][orbiter.orbiterId] = Shuttle(
                false, // Initialized, default false until oracle is set
                uint88(allShuttles.length), // Lending pool ID
                address(0), // Borrowable address
                address(0), // Collateral address
                uint96(orbiter.orbiterId) // The orbiter ID used to launch this shuttle
            );
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *    Phase1: Orbiter check
     *              - Orbiters (deployers) are active and usable
     *    Phase2: Board shuttle check
     *              - No shuttle with the same LP Token AND Orbiter has been deployed before
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
        uint256 multiplier
    ) external override nonReentrant returns (address borrowable, address collateral) {
        //  ─────────────────────────────── Phase 1 ───────────────────────────────

        // Load orbiter to memory
        Orbiter memory orbiter = getOrbiters[orbiterId];

        /// @custom:error OrbitersAreInactive Avoid deploying if orbiters are inactive or are not set
        if (!orbiter.status) {
            revert CygnusFactory__OrbitersAreInactive({ orbiter: orbiter });
        }
        //  ─────────────────────────────── Phase 2 ───────────────────────────────

        // Prepare shuttle for deployment, reverts if lpTokenPair already exists
        // Load shuttle to storage
        Shuttle storage shuttle = boardShuttle(lpTokenPair, orbiter);

        //  ─────────────────────────────── Phase 3 ───────────────────────────────

        // Get the pre-determined collateral address for this LP Token (check CygnusPoolAddres library)
        address create2Collateral = CygnusPoolAddress.getCollateralContract(
            lpTokenPair,
            address(this),
            address(orbiter.denebOrbiter),
            orbiter.denebOrbiter.COLLATERAL_INIT_CODE_HASH()
        );

        // Deploy borrow contract
        borrowable = orbiter.albireoOrbiter.deployAlbireo(
            usdc,
            create2Collateral,
            shuttle.shuttleId,
            baseRate,
            multiplier
        );

        // Deploy collateral contract
        collateral = orbiter.denebOrbiter.deployDeneb(lpTokenPair, borrowable, shuttle.shuttleId);

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

        // Save addresses to storage and mark as launched. This LP Token with orbiter ID cannot be redeployed

        // This specific lending pool is initialized can't be deployed again
        shuttle.launched = true;

        // Add cygnus borrow contract to record
        shuttle.borrowable = borrowable;

        // Add collateral contract to record
        shuttle.collateral = collateral;

        // Push the lending pool struct to the object array
        allShuttles.push(shuttle);

        /// @custom:event NewShuttleLaunched
        emit NewShuttleLaunched(lpTokenPair, orbiterId, shuttle.borrowable, shuttle.collateral, shuttle.shuttleId);
    }

    /**
     *  @notice Anyone may create their own strategy to deploy their own lending pool but admin reserves the right
     *          to switch status, reverting only future deployments (deployed pools remain active)
     *  @inheritdoc ICygnusFactory
     */
    function initializeOrbiter(
        string memory orbiterName,
        IAlbireoOrbiter albireoOrbiter,
        IDenebOrbiter denebOrbiter
    ) external override {
        // Total orbiters
        uint256 totalOrbiters = allOrbiters.length;

        // Check if collateral orbiter already exists, reverts if it does
        checkOrbitersInternal(albireoOrbiter, denebOrbiter, totalOrbiters);

        // Orbiters, ID starts from 0 so length is alwyas 1 ahead from record
        Orbiter storage orbiter = getOrbiters[totalOrbiters];

        // ID for this group of collateral and borrow orbiters
        orbiter.orbiterId = uint24(totalOrbiters);

        // Name of the exchange these orbiters are for
        orbiter.orbiterName = orbiterName;

        // Borrow orbiter address
        orbiter.albireoOrbiter = albireoOrbiter;

        // Collateral orbiter address
        orbiter.denebOrbiter = denebOrbiter;

        // ID for this group of collateral/borrow orbiters
        orbiter.status = true;

        // Push struct to array
        allOrbiters.push(orbiter);

        /// @custom:event InitializeOrbiters
        emit InitializeOrbiters(true, totalOrbiters, orbiterName, denebOrbiter, albireoOrbiter);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusFactory
     */
    function switchOrbiterStatus(uint256 orbiterId) external override cygnusAdmin {
        // Get the orbiter by the ID
        ICygnusFactory.Orbiter storage orbiter = getOrbiters[orbiterId];

        /// @custom:error OrbiterNotSet Avoid switching on/off if orbiters are not set
        if ((address(orbiter.denebOrbiter) == address(0)) || address(orbiter.albireoOrbiter) == address(0)) {
            revert CygnusFactory__OrbitersNotSet({ orbiterId: orbiterId });
        }

        // Switch orbiter status. If currently active then future deployments with this orbiter will revert
        orbiter.status = !orbiter.status;

        /// @custom:event SwitchOrbiterStatus
        emit SwitchOrbiterStatus(
            orbiter.status,
            orbiter.orbiterId,
            orbiter.orbiterName,
            orbiter.albireoOrbiter,
            orbiter.denebOrbiter
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

        /// @custom:event NewPendingCygnusAdmin
        emit NewPendingCygnusAdmin(oldPendingAdmin, newPendingAdmin);
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

        /// @custom:event NewPendingDaoReserves
        emit NewPendingDaoReserves(oldPendingDaoReserves, pendingDaoReserves);
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
