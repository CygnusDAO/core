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
     *  @custom:error OrbiterAlreadySet Emitted when the borrow orbiter already exists
     */
    error CygnusFactory__OrbiterAlreadySet(Orbiter orbiter);

    /**
     *  @custom:error ShuttleAlreadyDeployed Emitted when trying to deploy a shuttle that already exists
     */
    error CygnusFactory__ShuttleAlreadyDeployed(uint24 id, address lpTokenPair);

    /**
     *  @custom:error OrbitersAreInactive Emitted when deploying a shuttle with orbiters that are inactive or dont exist
     */
    error CygnusFactory__OrbitersAreInactive(Orbiter orbiter);

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
    error CygnusFactory__CygnusNebulaCantBeZero();

    /**
     *  @custom:error CygnusNebulaAlreadySet Emitted when the oracle set is the same as the new one we are assigning
     */
    error CygnusFactory__CygnusNebulaAlreadySet(address priceOracle, address newPriceOracle);

    /**
     *  @custom:error AdminAlreadySet Emitted when the admin is the same as the new one we are assigning
     */
    error CygnusFactory__AdminAlreadySet(address newPendingAdmin, address admin);

    /**
     *  @custom:error PendingAdminAlreadySet Emitted when the pending admin is the same as the new one we are assigning
     */
    error CygnusFactory__PendingAdminAlreadySet(address newPendingAdmin, address pendingAdmin);

    /**
     *  @custom:error DaoReservesAlreadySet Emitted when the pending dao reserves is already the dao reserves
     */
    error CygnusFactory__DaoReservesAlreadySet(address newPendingDaoReserves, address daoReserves);

    /**
     *  @custom:error PendingCygnusAdmin Emitted when pending Cygnus admin is the zero address
     */
    error CygnusFactory__PendingAdminCantBeZero();

    /**
     *  @custom:error DaoReservesCantBeZero Emitted when pending reserves contract address is the zero address
     */
    error CygnusFactory__DaoReservesCantBeZero();

    /**
     *  @custom:error PendingDaoReservesAlreadySet Emitted when the pending address is the same as the new pending
     */
    error CygnusFactory__PendingDaoReservesAlreadySet(address newPendingDaoReserves, address pendingDaoReserves);

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
     *  @notice Logs when a new pending dao reserves contract is set
     *  @param oldPendingdaoReservesContract Address of the current `daoReserves` contract
     *  @param newPendingdaoReservesContract Address of the requested new `daoReserves` contract
     *  @custom:event Emitted when a new implementation contract is requested
     */
    event PendingDaoReserves(address oldPendingdaoReservesContract, address newPendingdaoReservesContract);

    /**
     *  @notice Logs when a new dao reserves contract is set for Cygnus
     *  @param oldDaoReserves Address of old `daoReserves` contract
     *  @param daoReserves Address of the new confirmed `daoReserves` contract
     *  @custom:event Emitted when a new implementation contract is confirmed
     */
    event NewDaoReserves(address oldDaoReserves, address daoReserves);

    /**
     *  @notice Logs when new orbiters are added to the factory.
     *  @param status Whether or not these orbiters are active and usable
     *  @param orbitersLength How many orbiter pairs we have (equals the amount of Dexes cygnus is using)
     *  @param orbitersName The name of the dex for these orbiters
     *  @param collateralOrbiter The address of the collateral orbiter for this dex
     *  @param borrowOrbiter The address of the borrow orbiter for this dex
     *
     */
    event InitializeOrbiters(
        bool status,
        uint256 orbitersLength,
        string orbitersName,
        IDenebOrbiter collateralOrbiter,
        IAlbireoOrbiter borrowOrbiter
    );

    /**
     *  @notice Logs when orbiters get deleted from storage
     *  @param status Bool representing whether or not these orbiters are usable
     *  @param orbiterId The ID of the collateral & borrow orbiters
     *  @param orbiterName The name of the dex these orbiters were for
     *  @param cygnusDeneb The address of the deleted collateral orbiter
     *  @param cygnusAlbireo The address of the deleted borrow orbiter
     */
    event SwitchOrbiterStatus(
        bool status,
        uint256 orbiterId,
        string orbiterName,
        IAlbireoOrbiter cygnusAlbireo,
        IDenebOrbiter cygnusDeneb
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice We write it to interface due to getShuttles return value
     *  @custom:struct Official record of all collateral and borrow deployer contracts, unique per dex
     *  @custom:member status Whether or not these orbiters are active and usable
     *  @custom:member orbiterId The ID for this pair of orbiters
     *  @custom:member orbiterName The name of the dex
     *  @custom:member cygnusDeneb The address of the collateral deployer contract
     *  @custom:member cygnusAlbireo The address of the borrow deployer contract
     */
    struct Orbiter {
        bool status;
        uint24 orbiterId;
        string orbiterName;
        IAlbireoOrbiter cygnusAlbireo;
        IDenebOrbiter cygnusDeneb;
    }

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
        Orbiter orbiter;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Official record of all obiters deployed
     *  @param _orbiterId The ID of the orbiter deployed
     *  @return status Whether or not these orbiters are active and usable
     *  @return orbiterId The ID for these orbiters (ideally should be 1 per dex)
     *  @return orbiterName The name of the dex
     *  @return cygnusAlbireo The address of the borrow deployer contract
     *  @return cygnusDeneb The address of the collateral deployer contract
     */
    function getOrbiters(uint256 _orbiterId)
        external
        view
        returns (
            bool status,
            uint24 orbiterId,
            string memory orbiterName,
            IAlbireoOrbiter cygnusAlbireo,
            IDenebOrbiter cygnusDeneb
        );

    /**
     *  @notice Array of structs containing all orbiters deployed
     *  @param _orbiterId The ID of the orbiter pair
     */
    function allOrbiters(uint256 _orbiterId)
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
     *  @notice Official record of all lending pools deployed
     *  @param _lpTokenPair The address of the LP Token
     *  @param _orbiterId The ID of the orbiter for this LP Token
     *  @return launched Whether this pair exists or not
     *  @return shuttleId The ID of this shuttle
     *  @return cygnusDai The address of the borrow contract
     *  @return collateral The address of the collateral contract
     *  @return borrowToken The address of the underlying borrow contract
     *  @return lpTokenPair The address of the collaterla's
     *  @return orbiter The struct containing the address of the collateral/borrow orbiters for each dex
     */
    function getShuttles(address _lpTokenPair, uint256 _orbiterId)
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
     *  @notice Array of structs containing all shuttles deployed along with their orbiters
     *  @param _shuttleId The ID of the shuttle deployed
     */
    function allShuttles(uint256 _shuttleId)
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
     *  @return pendingDaoReserves The address of the requested contract to be the new dao reserves
     */
    function pendingDaoReserves() external view returns (address);

    /**
     * @return cygnusNebulaOracle The address of the Cygnus price oracle
     */
    function cygnusNebulaOracle() external view returns (IChainlinkNebulaOracle);

    /**
     *  @return orbitersDeployed The total number of orbiter pairs deployed (1 collateral + 1 borrow = 1 orbiter)
     */
    function orbitersDeployed() external view returns (uint256);

    /**
     *  @return shuttlesDeployed The total number of shuttles deployed
     */
    function shuttlesDeployed() external view returns (uint256);

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

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Turns off orbiters making them not able for deployment of pools
     *  @param orbiterId The ID of the orbiter pairs we want to switch the status of
     *  @custom:security non-reentrant
     */
    function switchOrbiterStatus(uint256 orbiterId) external;

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
     *  @notice Sets the new orbiters to deploy collateral and borrow contracts and stores orbiters in storage
     *  @param name The name of the strategy OR the dex these orbiters are for
     *  @param cygnusAlbireo the address of this orbiter's borrow deployer
     *  @param cygnusDeneb The address of this orbiter's collateral deployer
     *  @custom:security non-reentrant
     */
    function initializeOrbiter(
        string memory name,
        IAlbireoOrbiter cygnusAlbireo,
        IDenebOrbiter cygnusDeneb
    ) external;

    /**
     *  @notice 👽
     *  @notice Sets a new price oracle
     *  @param newpriceoracle address of the new price oracle
     */
    function setNewNebulaOracle(address newpriceoracle) external;

    /**
     *  @notice 👽
     *  @notice Sets a new pending admin for Cygnus
     *  @param newCygnusAdmin Address of the requested Cygnus admin
     */
    function setPendingAdmin(address newCygnusAdmin) external;

    /**
     *  @notice 👽
     *  @notice Approves the pending admin and is the new Cygnus admin
     */
    function setNewCygnusAdmin() external;

    /**
     *  @notice 👽
     *  @notice Sets the address for the future reserves manger if accepted
     *  @param newDaoReserves The address of the requested contract to be the new daoReserves
     */
    function setPendingDaoReserves(address newDaoReserves) external;

    /**
     *  @notice 👽
     *  @notice Accepts the new implementation contract
     */
    function setNewDaoReserves() external;
}
