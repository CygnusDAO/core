// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusCollateralControl } from "./interfaces/ICygnusCollateralControl.sol";
import { CygnusTerminal } from "./CygnusTerminal.sol";

// Interfaces
import { IChainlinkNebulaOracle } from "./interfaces/IChainlinkNebulaOracle.sol";
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";
import { ICygnusDeneb } from "./interfaces/ICygnusDeneb.sol";

/**
 *  @title  CygnusCollateralControl Contract for controlling collateral settings like debt ratios/liq. incentives
 *  @author CygnusDAO
 *  @notice Initializes Collateral Arm. Passes name, symbol and decimals to CygnusTerminal for the CygLP Token
 */
contract CygnusCollateralControl is ICygnusCollateralControl, CygnusTerminal("Cygnus: Collateral", "CygnusLP", 18) {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // ───────────────────── Important Addresses  ──────────────────────

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    address public immutable override cygnusDai;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    IChainlinkNebulaOracle public override cygnusNebulaOracle;

    // ────────────────────── Current pool rates  ───────────────────────

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public override debtRatio = 0.80e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public override liquidationIncentive = 1.05e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public override liquidationFee;

    // ──────────────────── Min/Max this pool allows  ────────────────────

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public constant override DEBT_RATIO_MIN = 0.50e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public constant override DEBT_RATIO_MAX = 0.875e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public constant override LIQUIDATION_INCENTIVE_MIN = 1.00e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public constant override LIQUIDATION_INCENTIVE_MAX = 1.20e18;

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    uint256 public constant override LIQUIDATION_FEE_MAX = 0.20e18;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Collateral arm of the pool and assigns important addresses
     *  @custom:security non-reentrant
     */
    constructor() nonReentrant {
        // Get important addresses from collateral deployer
        (hangar18, underlying, cygnusDai) = ICygnusDeneb(_msgSender()).collateralParameters();

        // Assign price oracle from factory
        cygnusNebulaOracle = ICygnusFactory(hangar18).cygnusNebulaOracle();

        // Go long and prosper =)
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
            revert CygnusCollateralControl__ParameterNotInRange(parameter);
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
    function setNebulaOracle() external override cygnusAdmin nonReentrant {
        // Assign oracle with factory's latest oracle, factory does zero address check
        IChainlinkNebulaOracle newPriceOracle = ICygnusFactory(hangar18).cygnusNebulaOracle();

        /// @custom:error CygnusNebulaDuplicate Avoid new oracle being the same as the old oracle
        if (address(newPriceOracle) == address(cygnusNebulaOracle)) {
            revert CygnusCollateralControl__CygnusNebulaDuplicate(address(newPriceOracle));
        }

        // Assign oracle for event
        IChainlinkNebulaOracle _cygnusNebulaOracle = cygnusNebulaOracle;

        // Update price oracle
        cygnusNebulaOracle = newPriceOracle;

        /// @custom:event NewPriceOracle
        emit NewPriceOracle(_cygnusNebulaOracle, newPriceOracle);
    }

    /**
     *  @notice 👽
     *  @inheritdoc ICygnusCollateralControl
     *  @custom:security non-reentrant
     */
    function setDebtRatio(uint256 newDebtRatio) external override cygnusAdmin nonReentrant {
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
    function setLiquidationIncentive(uint256 newLiquidationIncentive) external override cygnusAdmin nonReentrant {
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
    function setLiquidationFee(uint256 newLiquidationFee) external override cygnusAdmin nonReentrant {
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
