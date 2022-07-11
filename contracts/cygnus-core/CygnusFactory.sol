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
import { ICygnusDeneb } from "./interfaces/ICygnusDeneb.sol";
import { ICygnusAlbireo } from "./interfaces/ICygnusAlbireo.sol";
import { IChainlinkNebulaOracle } from "./interfaces/IChainlinkNebulaOracle.sol";

/**
 *  @title  CygnusCollateralControl
 *  @author CygnusDAO
 *  @notice Factory contract for Cygnus Collateral and Borrow contracts
 */
contract CygnusFactory is ICygnusFactory, Context, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 for uint256 fixed point math, also imports the main library `PRBMath`.
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Official record of all shuttles deployed
     *  @custom:struct Official record of pools deployed by this factory
     *  @custom:member isInitialized Whether or not the lending pool is initialized
     *  @custom:member shuttleID The ID of the lending pool
     *  @custom:member cygnusDeneb The address of the Cygnus collateral
     *  @custom:member cygnusAlbireo The address of the borrowing contract
     *  @custom:member borrowToken The address of the underlying albireo contract (DAI)
     */
    struct Shuttle {
        bool isInitialized;
        uint24 shuttleID;
        address cygnusDeneb;
        address cygnusAlbireo;
        address borrowToken;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusFactory
     */
    mapping(address => Shuttle) public override getShuttles;

    /**
     *  @inheritdoc ICygnusFactory
     */
    address[] public override allShuttles;

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
    ICygnusDeneb public immutable override collateralDeployer;

    /**
     *  @inheritdoc ICygnusFactory
     */
    ICygnusAlbireo public immutable override borrowDeployer;

    /**
     *  @inheritdoc ICygnusFactory
     */
    IChainlinkNebulaOracle public override cygnusNebulaOracle; // Price oracle

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Sets the cygnus admin/reservesManager/deployers/oracle and the borrow token (DAI)
     *  @param _cygnusAdmin Address of the Cygnus Admin to update important protocol parameters
     *  @param _vegaTokenManager Address of the contract that handles weighted forwarding of Erc20 tokens
     *  @param _dai Address of the DAI contract on this chain (different for mainnet, c-chain, etc.)
     *  @param _collateralDeployer Address of the collateral deployer (Deneb)
     *  @param _borrowDeployer Address of the borrow deployer (Albireo)
     *  @param _cygnusNebulaOracle Address of the price oracle
     */
    constructor(
        address _cygnusAdmin,
        address _vegaTokenManager,
        address _dai,
        address _nativeToken,
        ICygnusDeneb _collateralDeployer,
        ICygnusAlbireo _borrowDeployer,
        IChainlinkNebulaOracle _cygnusNebulaOracle
    ) {
        // Assign admin, has access to updatable parameters
        admin = _cygnusAdmin;

        // Cygnus reserves
        vegaTokenManager = _vegaTokenManager;

        // Address of DAI on this factory's chain
        dai = _dai;

        // Native token for this chain
        nativeToken = _nativeToken;

        // Assign collateral deployer for checking collateral addresses deployed from the contract
        collateralDeployer = _collateralDeployer;

        // Assign borrow deployer for checking borrow addresses deployed from the contract
        borrowDeployer = _borrowDeployer;

        // Assign oracle used by all pools
        cygnusNebulaOracle = _cygnusNebulaOracle;

        /// @custom:event NewCygnusAdmin
        emit NewCygnusAdmin(address(0), _cygnusAdmin);

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
        if (_msgSender() != admin) {
            revert CygnusFactory__CygnusAdminOnly(_msgSender());
        }
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusFactory
     */
    function shuttlesLength() external view override returns (uint256) {
        return allShuttles.length;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Creates a record of each shuttle deployed by this contract
     *  @dev Prepares shuttle for deployment and stores each Shuttle struct
     *  @param lpTokenPair Address of the DEX' LP Token for this shuttle
     */
    function boardShuttle(address lpTokenPair) private {
        /// @custom:error ShuttleAlreadyDeployed Avoid initializing two identical shuttles
        if (getShuttles[lpTokenPair].shuttleID != 0) {
            revert CygnusFactory__ShuttleAlreadyDeployed(lpTokenPair);
        }

        // Push to lending pool
        allShuttles.push(lpTokenPair);

        // Create the struct for this pair
        getShuttles[lpTokenPair] = Shuttle(
            false, // Initialized, default false until oracle is set
            uint24(allShuttles.length), // Lending pool ID
            address(0), // Collateral address
            address(0), // Borrow contract address
            address(0) // DAI
        );
    }

    /*  ────────────────────────────────────────────── external ───────────────────────────────────────────────  */

    /**
     *  3 Phases:
     *    i. Calculate Cygnus collateral address internally
     *    ii.a. Deploy Borrow contract with calculated Collateral Address
     *       b. Deploy collateral with deployed Borrow contract address.
     *       c. Check if collateral address == calculated address, revert if error
     *    iii. assert oracle exists for this pair and initialize lending pool
     *
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function deployShuttle(
        address lpTokenPair,
        uint256 baseRate,
        uint256 farmApy,
        uint256 kinkUtilizationRate
    ) external override nonReentrant cygnusAdmin returns (address _cygnusAlbireo, address _cygnusDeneb) {
        //  ─────────────────────────────── Phase 1 ───────────────────────────────

        // Check if exists, if not, add this shuttle ID (address[].length)
        boardShuttle(lpTokenPair);

        // Get the pre-determined collateral address for this LP Token (check CygnusPoolAddres library)
        address _collateral = CygnusPoolAddress.getCollateralContract(
            lpTokenPair,
            address(this),
            address(collateralDeployer)
        );

        /// @custom:error CollateralAlreadyExists Avoid deploying same collateral twice
        if (getShuttles[lpTokenPair].cygnusDeneb != address(0)) {
            revert CygnusFactory__CollateralAlreadyExists(lpTokenPair);
        }

        //  ─────────────────────────────── Phase 2 ───────────────────────────────

        // Deploy first borrow token
        _cygnusAlbireo = borrowDeployer.deployAlbireo(dai, _collateral, baseRate, farmApy, kinkUtilizationRate);

        // Deploy collateral
        _cygnusDeneb = collateralDeployer.deployDeneb(lpTokenPair, _cygnusAlbireo);

        /// @custom:error CollateralAddressMismatch Avoid deploying shuttle if calculated is different than deployed
        if (_cygnusDeneb != _collateral) {
            revert CygnusFactory__CollateralAddressMismatch(_cygnusDeneb);
        }

        //  ─────────────────────────────── Phase 3 ───────────────────────────────

        // No way back now, initialize pool

        // Add collateral contract to record
        getShuttles[lpTokenPair].cygnusDeneb = _cygnusDeneb;

        // Add cygnus borrow contract to record
        getShuttles[lpTokenPair].cygnusAlbireo = _cygnusAlbireo;

        // Add the address of the underlying albireo contract
        getShuttles[lpTokenPair].borrowToken = dai;

        // Oracle status for this pair
        (bool nebulaOracleInitialized, , , , ) = cygnusNebulaOracle.getNebula(lpTokenPair);

        // Oracle should never not be initialized for this pair
        if (!nebulaOracleInitialized) {
            revert CygnusFactory__LPTokenPairNotSupported(lpTokenPair);
        }

        // This specific lending pool is initialized can't be deployed again
        getShuttles[lpTokenPair].isInitialized = true;

        /// @custom:event NewShuttleLaunched
        emit NewShuttleLaunched(lpTokenPair, allShuttles.length, _cygnusDeneb, _cygnusAlbireo, dai);
    }

    /**
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function setNewNebulaOracle(address newPriceOracle) external override cygnusAdmin nonReentrant {
        /// @custom:error CygnusNebulaCantBeZero Avoid zero address oracle
        if (newPriceOracle == address(0)) {
            revert CygnusFactory__CygnusNebulaCantBeZero(newPriceOracle);
        }
        /// @custom:error CygnusNebulaAlreadySet Avoid setting the same address twice
        else if (newPriceOracle == address(cygnusNebulaOracle)) {
            revert CygnusFactory__CygnusNebulaAlreadySet(newPriceOracle);
        }

        // Assign old oracle address for event
        IChainlinkNebulaOracle oldOracle = cygnusNebulaOracle;

        // Address of the requested account to be Cygnus admin
        cygnusNebulaOracle = IChainlinkNebulaOracle(newPriceOracle);

        /// @custom:event NewCygnusNebulaOracle
        emit NewCygnusNebulaOracle(oldOracle, cygnusNebulaOracle);
    }

    /**
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function setPendingAdmin(address newCygnusAdmin) external override cygnusAdmin nonReentrant {
        /// @custom:error CygnusAdminAlreadySet Avoid setting the same admin twice
        if (newCygnusAdmin == admin) {
            revert CygnusFactory__CygnusAdminAlreadySet(newCygnusAdmin);
        }

        // Address of the requested account to be Cygnus admin
        pendingNewAdmin = newCygnusAdmin;

        /// @custom:event PendingCygnusAdmin
        emit PendingCygnusAdmin(admin, newCygnusAdmin);
    }

    /**
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function setNewCygnusAdmin() external override cygnusAdmin nonReentrant {
        /// @custom:error PendingAdminCantBeZero Avoid setting cygnus admin as address(0)
        if (pendingNewAdmin == address(0)) {
            revert CygnusFactory__PendingAdminCantBeZero(pendingNewAdmin);
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
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function setPendingVegaTokenManager(address newVegaTokenManager) external override cygnusAdmin nonReentrant {
        /// @custom:error CygnusVegaAlreadySet Avoid setting the same reserves admin twice
        if (newVegaTokenManager == vegaTokenManager) {
            revert CygnusFactory__CygnusVegaAlreadySet(newVegaTokenManager);
        }

        // Address of the Vega contract up until now
        pendingVegaTokenManager = newVegaTokenManager;

        /// @custom:event PendingVegaTokenManager
        emit PendingVegaTokenManager(vegaTokenManager, newVegaTokenManager);
    }

    /**
     *  @inheritdoc ICygnusFactory
     *  @custom:security non-reentrant
     */
    function setNewVegaTokenManager() external override cygnusAdmin nonReentrant {
        /// @custom:error PendingVegaCantBeZero Avoid setting the reserves manager as the zero address
        if (pendingVegaTokenManager == address(0)) {
            revert CygnusFactory__PendingVegaCantBeZero(pendingVegaTokenManager);
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
