// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusCollateralControl} from "./interfaces/ICygnusCollateralControl.sol";
import {ICygnusTerminal, CygnusTerminal} from "./CygnusTerminal.sol";

// Libraries
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IOrbiter} from "./interfaces/IOrbiter.sol";
import {IDexPair} from "./interfaces/IDexPair.sol";
import {IHangar18} from "./interfaces/IHangar18.sol";
import {ICygnusNebulaOracle} from "./interfaces/ICygnusNebulaOracle.sol";

/**
 *  @title  CygnusCollateralControl Contract for controlling collateral settings like debt ratios/liq. incentives
 *  @author CygnusDAO
 *  @notice Initializes Collateral Arm. Assigns name, symbol and decimals to CygnusTerminal for the CygLP Token.
 *          This contract should be the only contract the Admin has control of (apart from CygnusCollateralVoid),
 *          specifically to set liquidation fees for the protocol, liquidation incentives for the liquidators
 *          and setting and the debt ratio for this shuttle.
 *
 *          The constructor stores the borrowable address this pool is linked with, and only this address may
 *          borrow stablecoins from the borrowable.
 */
contract CygnusCollateralControl is ICygnusCollateralControl, CygnusTerminal("Cygnus: Collateral", "", 0) {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Fixed point 18 decimal math library, imports main library `PRBMath`
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    // ─────────────────────── Min/Max this pool allows

    /**
     *  @notice Minimum debt ratio at which the collateral becomes liquidatable
     */
    uint256 private constant DEBT_RATIO_MIN = 0.80e18;

    /**
     *  @notice Maximum debt ratio at which the collateral becomes liquidatable
     */
    uint256 private constant DEBT_RATIO_MAX = 1.00e18;

    /**
     *  @notice Minimum liquidation incentive for liquidators that can be set
     */
    uint256 private constant LIQUIDATION_INCENTIVE_MIN = 1.00e18;

    /**
     *  @notice Maximum liquidation incentive for liquidators that can be set
     */
    uint256 private constant LIQUIDATION_INCENTIVE_MAX = 1.10e18;

    /**
     *  @notice Maximum fee the protocol is keeps from each liquidation
     */
    uint256 private constant LIQUIDATION_FEE_MAX = 0.10e18;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // ──────────────────────────── Important Addresses

    /**
     *  @inheritdoc ICygnusCollateralControl
     */
    address public immutable override borrowable;

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

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Collateral arm of the pool and assigns the Borrow contract.
     */
    constructor() {
        // Underlying, Borrowable
        (, address asset, address twinStar, , ) = IOrbiter(_msgSender()).shuttleParameters();

        // Name of this CygLP with token symbol (ie `CygLP: USDC/WETH`)
        symbol = string(abi.encodePacked("CygLP: ", IERC20(asset).symbol()));

        // Same decimals as the underlying
        decimals = IERC20(asset).decimals();

        // Assign the borrowable arm of the lending pool
        borrowable = twinStar;

        // Assurance
        totalSupply = 0;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Checks if new parameter is within range when updating collateral settings
     *  @param min The minimum value allowed for this parameter
     *  @param max The maximum value allowed for this parameter
     *  @param value The value for the parameter that is being updated
     */
    function validRange(uint256 min, uint256 max, uint256 value) internal pure {
        /// @custom:error ParameterNotInRange Avoid outside range
        if (value < min || value > max) {
            revert CygnusCollateralControl__ParameterNotInRange({min: min, max: max, value: value});
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice CygnusTerminl override converting the function to view only
     */
    function exchangeRate() public view virtual override(CygnusTerminal, ICygnusTerminal) returns (uint256) {
        // Gas savings if non-zero
        uint256 _totalSupply = totalSupply;

        // If there is no supply for this token return initial rate
        return _totalSupply == 0 ? 1e18 : totalBalance.divWad(_totalSupply);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusCollateralControl
     *  @custom:security non-reentrant only-admin 👽
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
     *  @inheritdoc ICygnusCollateralControl
     *  @custom:security non-reentrant only-admin 👽
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
     *  @inheritdoc ICygnusCollateralControl
     *  @custom:security non-reentrant only-admin 👽
     */
    function setLiquidationFee(uint256 newLiquidationFee) external override nonReentrant cygnusAdmin {
        // Checks if parameter is within bounds, 0 is allowed since collateral contract checks for 0 fee
        validRange(0, LIQUIDATION_FEE_MAX, newLiquidationFee);

        // Valid, update
        uint256 oldLiquidationFee = liquidationFee;

        // Update liquidation fee
        liquidationFee = newLiquidationFee;

        /// @custom:event newLiquidationFee
        emit NewLiquidationFee(oldLiquidationFee, newLiquidationFee);
    }
}
