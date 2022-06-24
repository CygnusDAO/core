// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusTerminal } from "./ICygnusTerminal.sol";

// Interfaces
import { IChainlinkNebulaOracle } from "./IChainlinkNebulaOracle.sol";

/**
 *  @title ICygnusCollateralControl Interface for the admin control of collateral contracts (incentives, debt ratios)
 */
interface ICygnusCollateralControl is ICygnusTerminal {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error ParameterNotInRange Emitted when updating a collateral parameter outside of the range allowed
     */
    error CygnusCollateralControl__ParameterNotInRange(uint256 parameter);

    /**
     *  @custom:error OracleCantBeZeroAddress Emitted when oracle address is invalid
     */
    error CygnusCollateralControl__OracleCantBeZeroAddress(IChainlinkNebulaOracle newPriceOracle);

    /**
     *  @custom:error CygnusNebulaDuplicate Emitted when the new oracle address is the same as the current oracle
     */
    error CygnusCollateralControl__CygnusNebulaDuplicate(address);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════  
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Updated directly from the factory -> First update factory oracle then update shuttle
     *  @notice Logs when the oracle is updated by admins
     *  @param oldPriceOracle The address of the previous price oracle
     *  @param newPriceOracle The address of the new price oracle for this shuttle
     *  @custom:event Emitted when a new price oracle is set
     */
    event NewPriceOracle(IChainlinkNebulaOracle oldPriceOracle, IChainlinkNebulaOracle newPriceOracle);

    /**
     *  @notice Logs when the liquidation incentive is updated by admins
     *  @param oldLiquidationIncentive The old incentive for liquidators taken from the collateral
     *  @param newLiquidationIncentive The new liquidation incentive for this shuttle
     *  @custom:event NewLiquidationIncentive Emitted when a new liquidation incentive is set
     */
    event NewLiquidationIncentive(uint256 oldLiquidationIncentive, uint256 newLiquidationIncentive);

    /**
     *  @notice Logs when the debt ratio is updated by admins
     *  @param oldDebtRatio The old debt ratio at which the collateral was liquidatable in this shuttle
     *  @param newDebtRatio The new debt ratio for this shuttle
     *  @custom:event NewDebtRatio Emitted when a new debt ratio is set
     */
    event NewDebtRatio(uint256 oldDebtRatio, uint256 newDebtRatio);

    /**
     *  @notice Logs when the liquidation fee is updated by admins
     *  @param oldLiquidationFee The previous fee the protocol kept as reserves from each liquidation
     *  @param newLiquidationFee The new liquidation fee for this shuttle
     *  @custom:event NewLiquidationFee Emitted when a new liquidation fee is set
     */
    event NewLiquidationFee(uint256 oldLiquidationFee, uint256 newLiquidationFee);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // ────────────── Important Addresses ─────────────

    /**
     *  @return The address of AlbireoTokenB (if available).
     */
    function cygnusDai() external view returns (address);

    /**
     *  @notice Not immutable in case we need to update oracle from factory
     *  @return The address of the Cygnus Price Oracle
     */
    function cygnusNebulaOracle() external view returns (IChainlinkNebulaOracle);

    // ────────────── Current Pool Rates ──────────────

    /**
     *  @return The current debt ratio for this shuttle, default at 80% (x5 leverage).
     */
    function debtRatio() external view returns (uint256);

    /**
     *  @return The current liquidation incentive for this shuttle, default at 5%.
     */
    function liquidationIncentive() external view returns (uint256);

    /**
     *  @return The current liquidation fee the protocol keeps from each liquidation, default at 0%.
     */
    function liquidationFee() external view returns (uint256);

    // ──────────── Min/Max rates allowed ─────────────

    /**
     *  @notice Set a minimum for borrow protection
     *  @return Minimum debt ratio at which the collateral becomes liquidatable, equivalent to 50% (x2 leverage)
     */
    function DEBT_RATIO_MIN() external pure returns (uint256);

    /**
     *  @return Maximum debt ratio at which the collateral becomes liquidatable, equivalent to 87.5% (x8 leverage)
     */
    function DEBT_RATIO_MAX() external pure returns (uint256);

    /**
     *  @notice Set a minimum to for lender protection
     *  @return The minimum liquidation incentive for liquidators, equivalent to 2% of collateral
     */
    function LIQUIDATION_INCENTIVE_MIN() external pure returns (uint256);

    /**
     *  @return The maximum liquidation incentive for liquidators, equivalent to 20% of collateral
     */
    function LIQUIDATION_INCENTIVE_MAX() external pure returns (uint256);

    /**
     *  @notice No minimum as the default is 0
     *  @return Maximum fee the protocol is allowed to keep from each liquidation, equivalent to 20%
     */
    function LIQUIDATION_FEE_MAX() external pure returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice 👽
     *  @notice Updates price oracle with the factory's latest oracle if necessary
     *  @dev Factory must be updated with the new oracle first
     *  @custom:security non-reentrant
     */
    function setNebulaOracle() external;

    /**
     *  @notice 👽
     *  @notice Updates the debt ratio for the shuttle
     *  @param  newDebtRatio The new requested point at which a loan is liquidatable
     *  @custom:security non-reentrant
     */
    function setDebtRatio(uint256 newDebtRatio) external;

    /**
     *  @notice 👽
     *  @notice Updates the liquidation incentive for the shuttle
     *  @param  newLiquidationIncentive The new requested profit liquidators keep from the collateral
     *  @custom:security non-reentrant
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentive) external;

    /**
     *  @notice 👽
     *  @notice Updates the fee the protocol keeps for every liquidation
     *  @param newLiquidationFee The new requested fee taken from the liquidation incentive
     *  @custom:security non-reentrant
     */
    function setLiquidationFee(uint256 newLiquidationFee) external;
}
