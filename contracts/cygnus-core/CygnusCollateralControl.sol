// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralControl } from "./interfaces/ICygnusCollateralControl.sol";
import { CygnusTerminal } from "./CygnusTerminal.sol";

// Libraries
import { Strings } from "./libraries/Strings.sol";

// Interfaces
import { IChainlinkNebulaOracle } from "./interfaces/IChainlinkNebulaOracle.sol";
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";
import { IDenebOrbiter } from "./interfaces/IDenebOrbiter.sol";

/**
 *  @title  CygnusCollateralControl Contract for controlling collateral settings like debt ratios/liq. incentives
 *  @author CygnusDAO
 *  @notice Initializes Collateral Arm. Assigns name, symbol and decimals to CygnusTerminal for the CygLP Token.
 *          This contract should be the only contract the Admin has control of (apart from CygnusCollateralVoid),
 *          specifically to set liquidation fees for the protocol, liquidation incentives for the liquidators
 *          and setting and the debt ratio for this shuttle.
 *
 *          The constructor stores the borrowable address this pool is linked with, and only this address may
 *          borrow the underlying.
 */
contract CygnusCollateralControl is ICygnusCollateralControl, CygnusTerminal("Cygnus: Collateral", "CygLP", 18) {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library Strings Library used to append the names of token0 and token1 to the CygLP token
     */
    using Strings for string;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // ──────────────────────────── Important Addresses

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    address public immutable override cygnusDai;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    IChainlinkNebulaOracle public immutable override cygnusNebulaOracle;

    // ───────────────────────────── Current pool rates

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public override debtRatio = 0.95e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public override liquidationIncentive = 1.025e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public override liquidationFee;

    // ─────────────────────── Min/Max this pool allows

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public constant override DEBT_RATIO_MIN = 0.8e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public constant override DEBT_RATIO_MAX = 1e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public constant override LIQUIDATION_INCENTIVE_MIN = 1.00e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public constant override LIQUIDATION_INCENTIVE_MAX = 1.10e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public constant override LIQUIDATION_FEE_MAX = 0.10e18;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Collateral arm of the pool. It assigns the Factory, the underlying LP Token and the
     *          borrow contract for this collateral. It also assigns the Oracle to be used for the collateral model
     *          contract, which is taken from the most current one in the factory.
     */
    constructor() {
        // Get important addresses from collateral deployer
        (hangar18, underlying, cygnusDai) = IDenebOrbiter(_msgSender()).collateralParameters();

        // Assign price oracle from factory
        cygnusNebulaOracle = ICygnusFactory(hangar18).cygnusNebulaOracle();

        // Set the symbol for this LP Token (`CygLP token0/token1`)
        symbol = Strings.appendDeneb(underlying);

        // Assurance
        totalSupply = 0;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Checks if new parameter is within range when updating collateral settings
     *  @param min The minimum value allowed for this parameter
     *  @param max The maximum value allowed for this parameter
     *  @param parameter The value for the parameter that is being updated
     */
    function validRange(
        uint256 min,
        uint256 max,
        uint256 parameter
    ) internal pure {
        /// @custom:error ParameterNotInRange Avoid outside range
        if (parameter < min || parameter > max) {
            revert CygnusCollateralControl__ParameterNotInRange({ minRange: min, maxRange: max, value: parameter });
        }
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusCollateralControl
     *  @custom:security non-reentrant
     */
    function setDebtRatio(uint256 newDebtRatio) external override nonReentrant cygnusAdmin {
        // Checks if new value is within ranges allowed. If false, reverts with custom error
        validRange(DEBT_RATIO_MIN, DEBT_RATIO_MAX, newDebtRatio);

        // Valid, update
        uint256 oldDebtRatio = debtRatio;

        // Update debt ratio
        debtRatio = newDebtRatio;

        /// @custom:event newDebtRatio
        emit NewDebtRatio(oldDebtRatio, newDebtRatio);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusCollateralControl
     *  @custom:security non-reentrant
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentive) external override nonReentrant cygnusAdmin {
        // Checks if parameter is within bounds
        validRange(LIQUIDATION_INCENTIVE_MIN, LIQUIDATION_INCENTIVE_MAX, newLiquidationIncentive);

        // Valid, update
        uint256 oldLiquidationIncentive = liquidationIncentive;

        // Update liquidation incentive
        liquidationIncentive = newLiquidationIncentive;

        /// @custom:event NewLiquidationIncentive
        emit NewLiquidationIncentive(oldLiquidationIncentive, newLiquidationIncentive);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusCollateralControl
     *  @custom:security non-reentrant
     */
    function setLiquidationFee(uint256 newLiquidationFee) external override nonReentrant cygnusAdmin {
        // Checks if parameter is within bounds
        validRange(0, LIQUIDATION_FEE_MAX, newLiquidationFee);

        // Valid, update
        uint256 oldLiquidationFee = liquidationFee;

        // Update liquidation fee
        liquidationFee = newLiquidationFee;

        /// @custom:event newLiquidationFee
        emit NewLiquidationFee(oldLiquidationFee, newLiquidationFee);
    }
}
