// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Orbiters
import { IDenebOrbiter } from "./IDenebOrbiter.sol";
import { IAlbireoOrbiter } from "./IAlbireoOrbiter.sol";

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
     *  @custom:error CygnusAdminOnly Emitted when caller is not Admin
     */
    error CygnusFactory__CygnusAdminOnly(address sender, address admin);

    /**
     *  @custom:error BorrowOrbiterAlreadySet Emitted when the borrow orbiter already exists
     */
    error CygnusFactory__BorrowOrbiterAlreadySet(IAlbireoOrbiter cygnusAlbireo, IAlbireoOrbiter newCygnusAlbireo);

    /**
     *  @custom:error CollateralOrbiterAlreadySet Emitted when the borrow orbiter already exists
     */
    error CygnusFactory__CollateralOrbiterAlreadySet(IDenebOrbiter cygnusDeneb, IDenebOrbiter newCygnusDeneb);

    /**
     *  @custom:error ShuttleAlreadyDeployed Emitted when trying to deploy a shuttle that already exists
     */
    error CygnusFactory__ShuttleAlreadyDeployed(uint24 id, address lpTokenPair);

    /**
     *  @custom:error OrbitersAreInactive Emitted when deploying a shuttle with orbiters that are inactive
     */
    error CygnusFactory__OrbitersAreInactive(uint24 id, IDenebOrbiter cygnusDeneb, IAlbireoOrbiter cygnusAlbireo);

    /**
     *  @custom:error CollateralAddressMismatch Emitted when predicted collateral address doesn't match with deployed
     */
    error CygnusFactory__CollateralAddressMismatch(address calculatedCollateral, address deployedCollateral);

    /**
     *  @custom:error LPTokenPairNotSupported Emitted when trying to deploy a shuttle with an unsupported LP Pair
     */
    error CygnusFactory__LPTokenPairNotSupported(address lpTokenPair);

    /**
     *  @custom:error OrbitersNotSet Emitted when attempting to switch off orbiters that don't exist
     */
    error CygnusFactory__OrbitersNotSet(uint256 orbiterId);

    /**
     *  @custom:error CygnusNebulaCantBeZero Emitted when the new oracle is the zero address
     */
    error CygnusFactory__CygnusNebulaCantBeZero(address priceOracle);

    /**
     *  @custom:error CygnusNebulaAlreadySet Emitted when the oracle set is the same as the new one we are assigning
     */
    error CygnusFactory__CygnusNebulaAlreadySet(address priceOracle, address newPriceOracle);

    /**
     *  @custom:error CygnusAdminAlreadySet Emitted when the admin is the same as the new one we are assigning
     */
    error CygnusFactory__CygnusAdminAlreadySet(address currentAdmin, address newPendingAdmin);

    /**
     *  @custom:error PendingCygnusAdmin Emitted when pending Cygnus admin is the zero address
     */
    error CygnusFactory__PendingAdminCantBeZero(address pending, address sender);

    /**
     *  @custom:error CygnusVegaAlreadySet Emitted when the vega token manager is the same as the one we are assigning
     */
    error CygnusFactory__CygnusVegaAlreadySet(address currentVegaTokenManager, address newVegaTokenManager);

    /**
     *  @custom:error PendingReservesCantBeZero Emitted when pending reserves contract address is the zero address
     */
    error CygnusFactory__PendingVegaCantBeZero(address pending, address sender);

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
     *  @param shuttleId The ID of this lending pool
     *  @param cygnusDai The address of the Cygnus borrow contract
     *  @param collateral The address of the Cygnus collateral contract
     *  @param dai The address of underlying borrow token (DAI)
     *  @param lpTokenPair The address of the underlying LP Token
     *  @custom:event Emitted when a new lending pool is launched
     */
    event NewShuttleLaunched(
        uint256 indexed shuttleId,
        address cygnusDai,
        address collateral,
        address dai,
        address lpTokenPair
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

    /**
     *  @notice Logs when new orbiters are added to the factory.
     *  @param active Whether or not these orbiters are active and usable
     *  @param orbitersLength How many orbiter pairs we have (equals the amount of Dexes cygnus is using)
     *  @param orbitersName The name of the dex for these orbiters
     *  @param collateralOrbiter The address of the collateral orbiter for this dex
     *  @param borrowOrbiter The address of the borrow orbiter for this dex
     *
     */
    event InitializeOrbiters(
        bool active,
        uint256 orbitersLength,
        string orbitersName,
        IDenebOrbiter collateralOrbiter,
        IAlbireoOrbiter borrowOrbiter
    );

    /**
     *  @notice Logs when orbiters get deleted from storage
     *  @param active Bool representing whether or not these orbiters are usable
     *  @param orbiterId The ID of the collateral & borrow orbiters
     *  @param orbiterName The name of the dex these orbiters were for
     *  @param cygnusDeneb The address of the deleted collateral orbiter
     *  @param cygnusAlbireo The address of the deleted borrow orbiter
     */
    event SwitchOrbiterStatus(
        bool active,
        uint256 orbiterId,
        string orbiterName,
        IDenebOrbiter cygnusDeneb,
        IAlbireoOrbiter cygnusAlbireo
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice We write it to interface due to getShuttles return value
     *  @custom:struct Official record of all collateral and borrow deployer contracts, unique per dex
     *  @custom:member active Whether or not these orbiters are active and usable
     *  @custom:member orbiterId The ID for this pair of orbiters
     *  @custom:member orbiterName The name of the dex
     *  @custom:member cygnusDeneb The address of the collateral deployer contract
     *  @custom:member cygnusAlbireo The address of the borrow deployer contract
     */
    struct Orbiter {
        bool active;
        uint24 orbiterId;
        string orbiterName;
        IAlbireoOrbiter cygnusAlbireo;
        IDenebOrbiter cygnusDeneb;
    }

    /**
     *  @return admin The address of the Cygnus Admin which grants special permissions in collateral/borrow contracts
     */
    function admin() external view returns (address);

    /**
     *  @return pendingAdmin The address of the requested account to be the new Cygnus Admin
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
     * @return cygnusNebulaOracle The address of the Cygnus price oracle
     */
    function cygnusNebulaOracle() external view returns (IChainlinkNebulaOracle);

    /**
     *  @notice Official record for all the pairs deployed
     *  @param _lpTokenPair The address of the LP Token
     *  @return launched Whether this pair exists or not
     *  @return shuttleId The ID of this shuttle
     *  @return cygnusDai The address of the borrow contract
     *  @return collateral The address of the collateral contract
     *  @return borrowToken The address of the underlying borrow contract
     *  @return lpTokenPair The address of the collaterla's
     *  @return orbiter The struct containing the address of the collateral/borrow orbiters for each dex
     */
    function getShuttles(address _lpTokenPair)
        external
        view
        returns (
            bool launched,
            uint24 shuttleId,
            address cygnusDai,
            address collateral,
            address borrowToken,
            address lpTokenPair,
            Orbiter memory orbiter
        );

    /**
     *  @notice Getter for the Orbiter struct
     *  @return active Whether or not these orbiters are active and usable
     *  @return orbiterId The ID for these orbiters (ideally should be 1 per dex)
     *  @return orbiterName The name of the dex
     *  @return cygnusAlbireo The address of the borrow deployer contract
     *  @return cygnusDeneb The address of the collateral deployer contract
     */
    function getOrbiters(uint256 orbitersId_)
        external
        view
        returns (
            bool active,
            uint24 orbiterId,
            string memory orbiterName,
            IAlbireoOrbiter cygnusAlbireo,
            IDenebOrbiter cygnusDeneb
        );

    /**
     *  @return allShuttles Addresses of all shuttles that have been launched consisting of LP Token addresses
     */
    function allShuttles(uint256) external view returns (address);

    /**
     *  @notice Array of Structs containing info of each orbiter deployed
     *  @param orbiterId_ The ID of the orbiter pair we want to get the info of
     *  @return active Whether or not these orbiters are active and usable
     *  @return orbiterId The ID for these orbiters (ideally should be 1 per dex)
     *  @return orbiterName The name of the dex
     *  @return cygnusAlbireo The address of the borrow deployer contract
     *  @return cygnusDeneb The address of the collateral deployer contract
     */
    function allOrbiters(uint256 orbiterId_)
        external
        view
        returns (
            bool active,
            uint24 orbiterId,
            string memory orbiterName,
            IAlbireoOrbiter cygnusAlbireo,
            IDenebOrbiter cygnusDeneb
        );

    /**
     *  @return shuttlesDeployed The total number of shuttles deployed
     */
    function shuttlesDeployed() external view returns (uint256);

    /**
     *  @return orbitersDeployed The total number of orbiter pairs deployed (1 collateral + 1 borrow = 1 orbiter)
     */
    function orbitersDeployed() external view returns (uint256);

    /**
     *  @return dai The address of DAI
     */
    function dai() external view returns (address);

    /**
     *  @return nativeToken The address of the chain's native token
     */
    function nativeToken() external view returns (address);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Turns off orbiters making them not able for deployment of pools
     *  @param orbiterId The ID of the orbiter pairs we want to switch the status of
     *  @custom:security non-reentrant
     */
    function switchOrbiterStatus(uint256 orbiterId) external;

    /**
     *  @notice Sets the new orbiters to deploy collateral and borrow contracts and stores orbiters in storage
     *  @param name The name of the DEX these orbiters are for
     *  @param cygnusDeneb The address of this orbiter's collateral deployer
     *  @param cygnusAlbireo the address of this orbiter's borrow deployer
     *  @custom:security non-reentrant
     */
    function setNewOrbiter(
        string memory name,
        IDenebOrbiter cygnusDeneb,
        IAlbireoOrbiter cygnusAlbireo
    ) external;

    /**
     *  @notice Initializes both Borrow arms and the collateral arm
     *  @param lpTokenPair The address of the underlying LP Token this pool is for
     *  @param orbiterId The ID of the orbiters we want to deploy to (= dex Id)
     *  @param baseRate The interest rate model's base rate this shuttle uses
     *  @param multiplier The multiplier this shuttle uses for calculating the interest rate
     *  @param kinkMultiplier The increase to farmApy once kink utilization is reached
     *  @return cygnusDai The address of the Cygnus borrow contract for this pool
     *  @return collateral The address of the Cygnus collateral contract for both borrow tokens
     *  @custom:security non-reentrant
     */
    function deployShuttle(
        address lpTokenPair,
        uint256 orbiterId,
        uint256 baseRate,
        uint256 multiplier,
        uint256 kinkMultiplier
    ) external returns (address cygnusDai, address collateral);

    /**
     *  @notice 👽
     *  @notice Sets a new price oracle
     *  @param newpriceoracle address of the new price oracle
     *  @custom:security non-reentrant
     */
    function setNewNebulaOracle(address newpriceoracle) external;

    /**
     *  @notice 👽
     *  @notice Sets a new pending admin for Cygnus
     *  @param newCygnusAdmin Address of the requested Cygnus admin
     *  @custom:security non-reentrant
     */
    function setPendingAdmin(address newCygnusAdmin) external;

    /**
     *  @notice 👽
     *  @notice Approves the pending admin and is the new Cygnus admin
     *  @custom:security non-reentrant
     */
    function setNewCygnusAdmin() external;

    /**
     *  @notice 👽
     *  @notice Sets the address for the future reserves manger if accepted
     *  @param newVegaTokenManager The address of the requested contract to be the new Vega Token Manager
     *  @custom:security non-reentrant
     */
    function setPendingVegaTokenManager(address newVegaTokenManager) external;

    /**
     *  @notice 👽
     *  @notice Accepts the new implementation contract
     *  @custom:security non-reentrant
     */
    function setNewVegaTokenManager() external;
}
