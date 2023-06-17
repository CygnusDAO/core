// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrowControl} from "./interfaces/ICygnusBorrowControl.sol";
import {CygnusTerminal} from "./CygnusTerminal.sol";

// Libraries
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IOrbiter} from "./interfaces/IOrbiter.sol";

// Overrides
import {ERC20} from "./ERC20.sol";

/**
 *  @title  CygnusBorrowControl Contract for controlling borrow settings
 *  @author CygnusDAO
 *  @notice Initializes Borrow Arm. Assigns name, symbol and decimals to CygnusTerminal for the CygUSD Token.
 *          This contract should be the only contract the Cygnus admin has control of, specifically to set the
 *          borrow tracker which tracks individual borrows to reward users in any token (if there is any),
 *          the reserve factor and the kink utilization rate.
 *
 *          The constructor stores the collateral address this pool is linked with, and only this address can
 *          be used as collateral to borrow this contract`s underlying.
 */
contract CygnusBorrowControl is ICygnusBorrowControl, CygnusTerminal {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    // ────────────────────── Min/Max this pool allows

    /**
     *  @notice Maximum base interest rate allowed (10%)
     */
    uint256 private constant BASE_RATE_MAX = 0.10e18;

    /**
     *  @notice Maximum reserve factor that the protocol can keep as reserves (20%)
     */
    uint256 private constant RESERVE_FACTOR_MAX = 0.20e18;

    /**
     *  @notice Minimum kink utilization point allowed (50%)
     */
    uint256 private constant KINK_UTILIZATION_RATE_MIN = 0.50e18;

    /**
     *  @notice Maximum Kink point allowed (95%)
     */
    uint256 private constant KINK_UTILIZATION_RATE_MAX = 0.95e18;

    /**
     *  @notice Maximum Kink multiplier
     */
    uint256 private constant KINK_MULTIPLIER_MAX = 10;

    /**
     *  @notice Used to calculate the per second interest rates
     */
    uint256 private constant SECONDS_PER_YEAR = 31536000;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    // ──────────────────────────── Important Addresses

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    address public override collateral;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    address public override cygnusBorrowRewarder;

    // ───────────────────────────── Current pool rates

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override baseRatePerSecond;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override multiplierPerSecond;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override jumpMultiplierPerSecond;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override kinkUtilizationRate = 0.85e18;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override kinkMultiplier = 2;

    /**
     *  @inheritdoc ICygnusBorrowControl
     */
    uint256 public override reserveFactor = 0.1e18;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Borrowable arm of the pool and assigns the Collateral contract.
     */
    constructor() {
        // Get underlying and collateral from deployer contract to get collateral contract
        (, , address _collateral, , ) = IOrbiter(msg.sender).shuttleParameters();

        // Assign the collateral arm of the lending pool
        collateral = _collateral;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Checks if new parameter is within range when updating borrowable settings
     *  @param min The minimum value allowed for the parameter that is being updated
     *  @param max The maximum value allowed for the parameter that is being updated
     *  @param value The value of the parameter that is being updated
     */
    function _validRange(uint256 min, uint256 max, uint256 value) private pure {
        /// @custom:error ParameterNotInRange Avoid setting important variables outside range
        if (value < min || value > max) revert CygnusBorrowControl__ParameterNotInRange();
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Overrides the name function from the ERC20
     *  @inheritdoc ERC20
     */
    function name() public pure override(ERC20, IERC20) returns (string memory) {
        return "Cygnus: Borrowable";
    }

    /**
     *  @notice Overrides the symbol function to represent the underlying stablecoin (ie 'CygUSD: USDC')
     *  @inheritdoc ERC20
     */
    function symbol() public view override(ERC20, IERC20) returns (string memory) {
        return string(abi.encodePacked("CygUSD: ", IERC20(underlying).symbol()));
    }

    /**
     *  @notice Overrides the decimal function to use the same decimals as underlying
     *  @inheritdoc ERC20
     */
    function decimals() public view override(ERC20, IERC20) returns (uint8) {
        return IERC20(underlying).decimals();
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Updates the parameters of the interest rate model and writes to storage
     *  @dev Does necessary checks internally. Reverts in case of failing checks
     *  @param baseRatePerYear_ The approximate target base APR, as a mantissa (scaled by 1e18)
     *  @param multiplierPerYear_ The rate of increase in interest rate wrt utilization (scaled by 1e18)
     *  @param kinkMultiplier_ The increase to farmApy once kink utilization is reached
     *  @param kinkUtilizationRate_ The point at which the jump multiplier takes effect
     */
    function _interestRateModel(
        uint256 baseRatePerYear_,
        uint256 multiplierPerYear_,
        uint256 kinkMultiplier_,
        uint256 kinkUtilizationRate_
    ) private {
        // Internal parameter check for base rate
        _validRange(0, BASE_RATE_MAX, baseRatePerYear_);

        // Internal parameter check for kink rate
        _validRange(KINK_UTILIZATION_RATE_MIN, KINK_UTILIZATION_RATE_MAX, kinkUtilizationRate_);

        // Internal parameter check for kink multiplier
        _validRange(1, KINK_MULTIPLIER_MAX, kinkMultiplier_);

        // Calculate the Base Rate per second and update to storage
        baseRatePerSecond = baseRatePerYear_ / SECONDS_PER_YEAR;

        // Calculate the Farm Multiplier per second and update to storage
        multiplierPerSecond = multiplierPerYear_.divWad(SECONDS_PER_YEAR * kinkUtilizationRate_);

        // Update kink multiplier
        kinkMultiplier = kinkMultiplier_;

        // update kink utilization rate
        kinkUtilizationRate = kinkUtilizationRate_;

        // Calculate the Jump Multiplier per second and update to storage
        jumpMultiplierPerSecond = multiplierPerYear_.fullMulDiv(kinkMultiplier_, SECONDS_PER_YEAR).divWad(kinkUtilizationRate_);

        /// @custom:event NewInterestParameter
        emit NewInterestRateParameters(baseRatePerYear_, multiplierPerYear_, kinkMultiplier_, kinkUtilizationRate_);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security only-admin 👽
     */
    function setInterestRateModel(
        uint256 baseRatePerYear_,
        uint256 multiplierPerYear_,
        uint256 kinkMultiplier_,
        uint256 kinkUtilizationRate_
    ) external override cygnusAdmin {
        // Update interest rate model with per second rates
        _interestRateModel(baseRatePerYear_, multiplierPerYear_, kinkMultiplier_, kinkUtilizationRate_);
    }

    /**
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security only-admin 👽
     */
    function setReserveFactor(uint256 newReserveFactor) external override cygnusAdmin {
        // Check if parameter is within range allowed
        _validRange(0, RESERVE_FACTOR_MAX, newReserveFactor);

        // Old reserve factor
        uint256 oldReserveFactor = reserveFactor;

        // Update reserve factor
        reserveFactor = newReserveFactor;

        /// @custom:event NewReserveFactor
        emit NewReserveFactor(oldReserveFactor, newReserveFactor);
    }

    /**
     *  @inheritdoc ICygnusBorrowControl
     *  @custom:security only-admin 👽
     */
    function setCygnusBorrowRewarder(address newBorrowRewarder) external override cygnusAdmin {
        // Need the option of setting to address(0) as child contract checks for 0 address in case it's inactive
        // Old borrow tracker
        address oldBorrowRewarder = cygnusBorrowRewarder;

        // Checks admin before, assign borrow tracker
        cygnusBorrowRewarder = newBorrowRewarder;

        /// @custom:event NewCygnusBorrowRewarder
        emit NewCygnusBorrowRewarder(oldBorrowRewarder, newBorrowRewarder);
    }
}
