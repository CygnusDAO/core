/*
 *
 * Custom revert error messages for all Borrow contracts
 *
 */
const CygnusBorrowErrors = {
    /*
     *  CygnusBorrow.sol
     *
     */
    BORROW_EXCEEDS_BALANCE: 'CygnusBorrow__BorrowExceedsTotalBalance',

    INSUFFICIENT_LIQUIDITY: 'CygnusBorrow__InsufficientLiquidity',

    /*
     *  CygnusBorrowApprove.sol
     *
     */
    INVALID_SIGNATURE: 'CygnusBorrowApprove__InvalidSignature',

    OWNER_ZERO_ADDRESS: 'CygnusBorrowApprove__OwnerZeroAddress',

    PERMIT_EXPIRED: 'CygnusBorrowApprove__PermitExpired',

    RECOVERED_OWNER_ZEROADDRESS: 'CygnusBorrowApprove__RecoveredOwnerZeroAddress',

    SPENDER_ZEROADDRESS: 'CygnusBorrowApprove__SpenderZeroAddress',

    OWNER_IS_SPENDER: 'CygnusBorrowApprove__OwnerIsSpender',

    BORROW_NOT_ALLOWED: 'CygnusBorrowApprove__BorrowNotAllowed',

    /*
     *  CygnusBorrowControl.sol
     *
     */
    PARAMETER_NOT_IN_RANGE: 'CygnusBorrowControl__ParameterNotInRange',

    RESERVES_MANAGER_ZEROADDRESS: 'CygnusBorrowControl__BorrowTrackerCantBeZero',
};

module.exports = {
    CygnusBorrowErrors,
};
