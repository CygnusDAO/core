/*
 *  Custom revert error messages for CygnusTerminal, Erc20 and Erc20Permit contracts
 *
 *  These errors apply to both Collateral/Borrow contracts as the contracts
 *  are parent contracts of both
 *
 */
const CygnusTerminalErrors = {
    /*
     *  Erc20.sol
     *
     */
    INSUFFICIENT_ALLOWANCE: 'Erc20__InsufficientAllowance',

    APPROVE_OWNER_ZEROADDRESS: 'Erc20__ApproveOwnerZeroAddress',

    APPROVE_SPENDER_ZEROADDRESS: 'Erc20__ApproveSpenderZeroAddress',

    BURN_ZEROADDRESS: 'Erc20__BurnZeroAddress',

    MINT_ZEROADDRESS: 'Erc20__MintZeroAddress',

    TRANSFER_SENDER_ZEROADDRESS: 'Erc20__TransferSenderZeroAddress',

    TRANSFERRECIPIENT_ZEROADDRESS: 'Erc20__TransferRecipientZeroAddress',

    INSUFFICIENT_BALANCE: 'Erc20__InsufficientBalance',

    /*
     *  Erc20Permit.sol
     *
     */
    INVALID_SIGNATURE: 'Erc20Permit__InvalidSignature',

    /*
     *  CygnusTerminal.sol
     *
     */
    MSG_SENDER_NOT_ADMIN: 'CygnusTerminal__MsgSenderNotAdmin',

    CANT_MINT_ZERO: 'CygnusTerminal__CantMintZero',

    CANT_BURN_ZERO: 'CygnusTerminal__CantBurnZero',

    BURN_AMOUNT_INVALID: 'CygnusTerminal__BurnAmountInvalid',

    /*
     *  CygnusFactory.sol
     *
     */
    MSG_SENDER_NOT_ADMIN_FACTORY: 'CygnusFactory__CygnusAdminOnly',
};

module.exports = {
    CygnusTerminalErrors,
};
