/*
 * Custom revert error messages for all Collateral contracts
 *
 */
const CygnusCollateralErrors = {
    /*
     *  CygnusCollateral.sol
     *
     */
    VALUE_EXCEEDS_BALANCE: 'CygnusCollateral__ValueExceedsBalance',

    INSUFFICIENT_LIQUIDITY: 'CygnusCollateral__InsufficientLiquidity',

    INVALID_BORROWABLE_CONTRACT: 'CygnusCollateral__BorrowableInvalid',

    MSG_SENDER_NOT_BORROWABLE: 'CygnusCollateral__NotBorrowable',

    NOT_LIQUIDATABLE: 'CygnusCollateral__NotLiquidatable',

    CANT_LIQUIDATE_SELF: 'CygnusCollateral__LiquidatingSelf',

    INSUFFICIENT_REDEEM_AMOUNT: 'CygnusCollateral__InsufficientRedeemAmount',

    /*
     *  CygnusChef.sol
     *
     */
    INSUFFICIENT_RESERVES: 'CygnusCollateralChef__InsufficientReserves',

    MSG_SENDER_NOT_ADMIN: 'CygnusCollateralChef__MsgSenderNotOrigin',

    /*
     *  CygnusCollateralControl.sol
     *
     */
    PARAMETER_NOT_IN_RANGE: 'CygnusCollateralControl__ParameterNotInRange',

    ORACLE_CANT_BE_ZEROADDRESS: 'CygnusCollateralControl__OracleCantBeZeroAddress',

    ORACLE_ALREADY_SET: 'CygnusCollateralControl__CygnusNebulaDuplicate',

    /*
     *  CygnusCollateralModel.sol
     *
     */
    BORROWER_CANT_BE_ZEROADDRESS: 'CygnusCollateralModel__BorrowerCantBeAddressZero' 
};

module.exports = {
    CygnusCollateralErrors,
};
