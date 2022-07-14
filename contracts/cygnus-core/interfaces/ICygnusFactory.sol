// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Deployers
import { ICygnusDeneb } from "./ICygnusDeneb.sol";
import { ICygnusAlbireo } from "./ICygnusAlbireo.sol";

// Oracles
import { IChainlinkNebulaOracle } from "./IChainlinkNebulaOracle.sol";

/**
 *  @title The interface for the Cygnus Factory
 *  @notice The Cygnus factory facilitates creation of collateral and borrow pools
 */
interface ICygnusFactory {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error ShuttleAlreadyDeployed Emitted when trying to deploy a shuttle that already exists
     */
    error CygnusFactory__ShuttleAlreadyDeployed(address);

    /**
     *  @custom:error CollateralAlreadyExists Emitted when trying to deploy an already initialized collateral arm
     */
    error CygnusFactory__CollateralAlreadyExists(address);

    /**
     *  @custom:error CollateralAddressMismatch Emitted when predicted collateral address doesn't match with deployed
     */
    error CygnusFactory__CollateralAddressMismatch(address calculatedCollateral, address deployedCollateral);

    /**
     *  @custom:error CygnusAdminOnly Emitted when caller is not Admin
     */
    error CygnusFactory__CygnusAdminOnly(address);

    /**
     *  @custom:error LPTokenPairNotSupported Emitted when trying to deploy a shuttle with an unsupported LP Pair
     */
    error CygnusFactory__LPTokenPairNotSupported(address);

    /**
     *  @custom:error PendingReservesCantBeZero Emitted when pending reserves contract address is the zero address
     */
    error CygnusFactory__PendingVegaCantBeZero(address);

    /**
     *  @custom:error PendingCygnusAdmin Emitted when pending Cygnus admin is the zero address
     */
    error CygnusFactory__PendingAdminCantBeZero(address);

    /**
     *  @custom:error CygnusNebulaCantBeZero Emitted when the new oracle is the zero address
     */
    error CygnusFactory__CygnusNebulaCantBeZero(address);

    /**
     *  @custom:error CygnusVegaAlreadySet Emitted when the vega token manager is the same as the one we are assigning
     */
    error CygnusFactory__CygnusVegaAlreadySet(address);

    /**
     *  @custom:error CygnusAdminAlreadySet Emitted when the admin is the same as the new one we are assigning
     */
    error CygnusFactory__CygnusAdminAlreadySet(address);

    /**
     *  @custom:error CygnusNebulaAlreadySet Emitted when the oracle set is the same as the new one we are assigning
     */
    error CygnusFactory__CygnusNebulaAlreadySet(address);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Logs when a new Cygnus oracle is set
     *  @param oldCygnusNebula Address of the old price oracle
     *  @param newCygnusNebula Address of the new confirmed price oracle
     *  @custom:event Emitted when a new price oracle is set
     */
    event NewCygnusNebulaOracle(IChainlinkNebulaOracle oldCygnusNebula, IChainlinkNebulaOracle newCygnusNebula);

    /**
     *  @notice Logs when a new shuttle is launched
     *  @param lpTokenPair The address of the underlying LP Token
     *  @param shuttleID The ID of this lending pool
     *  @param cygnusDeneb The address of the Cygnus collateral contract
     *  @param cygnusAlbireo The address of the Cygnus borrow contract
     *  @param cygnusDAI The address of underlying borrow token (DAI)
     *  @custom:event Emitted when a new lending pool is launched
     */
    event NewShuttleLaunched(
        address indexed lpTokenPair,
        uint256 shuttleID,
        address cygnusDeneb,
        address cygnusAlbireo,
        address cygnusDAI
    );

    /**
     *  @notice Logs when a new pending admin is set
     *  @param pendingAdmin Address of the requested admin
     *  @param _admin Address of the present admin
     *  @custom:event Emitted when a new Cygnus admin is requested
     */
    event PendingCygnusAdmin(address pendingAdmin, address _admin);

    /**
     *  @notice Logs when a new cygnus admin is set
     *  @param oldAdmin Address of the old admin
     *  @param newAdmin Address of the new confirmed admin
     *  @custom:event Emitted when a new Cygnus admin is confirmed
     */
    event NewCygnusAdmin(address oldAdmin, address newAdmin);

    /**
     *  @notice Logs when a new pending reserve manager contract is set
     *  @param oldPendingVegaContract Address of the current `Vega` contract
     *  @param newPendingVegaContract Address of the requested new `Vega` contract
     *  @custom:event Emitted when a new implementation contract is requested
     */
    event PendingVegaTokenManager(address oldPendingVegaContract, address newPendingVegaContract);

    /**
     *  @notice Logs when a new reserve manager contract is set for Cygnus
     *  @param oldVegaTokenManager Address of old `Vega` contract
     *  @param vegaTokenManager Address of the new confirmed `Vega` contract
     *  @custom:event Emitted when a new implementation contract is confirmed
     */
    event NewVegaTokenManager(address oldVegaTokenManager, address vegaTokenManager);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return admin The address of the Cygnus Admin which grants special permissions in collateral/borrow contracts
     */
    function admin() external view returns (address);

    /**
     *  @notice pendingAdmin The address of the requested account to be the new Cygnus Admin
     */
    function pendingNewAdmin() external view returns (address);

    /**
     *  @return vegaTokenManager The address that handles Cygnus reserves from all pools
     */
    function vegaTokenManager() external view returns (address);

    /**
     *  @return pendingVegaTokenManager The address of the requested contract to be the new Cygnus reserves manager
     */
    function pendingVegaTokenManager() external view returns (address);

    /**
     * @return collateralDeployer The address of the Collateral deployer
     */
    function collateralDeployer() external view returns (ICygnusDeneb);

    /**
     * @return borrowDeployer The address of the Borrow deployer
     */
    function borrowDeployer() external view returns (ICygnusAlbireo);

    /**
     * @return cygnusNebulaOracle The address of the Cygnus price oracle
     */
    function cygnusNebulaOracle() external view returns (IChainlinkNebulaOracle);

    /**
     *  @notice Official record for all the pairs deployed
     *  @param lpTokenPair The address of the LP Token
     *  @return isInitialized Whether this pair exists or not
     *  @return shuttleID The ID of this shuttle
     *  @return cygnusDeneb The address of the collateral contract
     *  @return cygnusAlbireo The address of the borrow contract
     *  @return borrowToken The address of the underlying albireo contract (DAI)
     */
    function getShuttles(address lpTokenPair)
        external
        view
        returns (
            bool isInitialized,
            uint24 shuttleID,
            address cygnusDeneb,
            address cygnusAlbireo,
            address borrowToken
        );

    /**
     *  @return allShuttles Addresses of all shuttles that have been launched consisting of LP Token addresses
     */
    function allShuttles(uint256) external view returns (address);

    /**
     *  @return shuttlesLength The total number of shuttles deployed
     */
    function shuttlesLength() external view returns (uint256);

    /**
     *  @return dai The address of DAI
     */
    function dai() external view returns (address);

    /**
     * @return nativeToken The address of the chain's native token
     */
    function nativeToken() external view returns (address);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Initializes both Borrow arms and the collateral arm
     *  @param lpTokenPair The address of the underlying LP Token this pool is for
     *  @param baseRate The interest rate model's base rate this shuttle uses
     *  @param farmApy The multiplier this shuttle uses for calculating the interest rate
     *  @param kinkMultiplier The increase to farmApy once kink utilization is reached
     *  @return cygnusAlbireo The address of the Cygnus borrow contract for this pool
     *  @return cygnusDeneb The address of the Cygnus collateral contract for both borrow tokens
     *  @custom:error non-reentrant
     */
    function deployShuttle(
        address lpTokenPair,
        uint256 baseRate,
        uint256 farmApy,
        uint256 kinkMultiplier
    ) external returns (address cygnusAlbireo, address cygnusDeneb);

    /**
     *  @notice sets a new price oracle 👽
     *  @param newpriceoracle address of the new price oracle
     */
    function setNewNebulaOracle(address newpriceoracle) external;

    /**
     *  @notice Sets a new pending admin for Cygnus 👽
     *  @param newCygnusAdmin Address of the requested Cygnus admin
     */
    function setPendingAdmin(address newCygnusAdmin) external;

    /**
     *  @notice Approves the pending admin and is the new Cygnus admin 👽
     */
    function setNewCygnusAdmin() external;

    /**
     *  @notice Request a new implementation contract for Cygnus
     *  @param newVegaTokenManager The address of the requested contract to be the new Vega Token Manager
     */
    function setPendingVegaTokenManager(address newVegaTokenManager) external;

    /**
     *  @notice Accepts the new implementation contract
     */
    function setNewVegaTokenManager() external;
}
