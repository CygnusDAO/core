// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

import { ICygnusBorrowControl } from "./ICygnusBorrowControl.sol";

/**
 *  @title CygnusBorrowApprove Interface for the approval of borrows before taking out a loan
 */
interface ICygnusBorrowApprove is ICygnusBorrowControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error OwnerIsSpender Emitted when the owner is the spender
     */
    error CygnusBorrowApprove__OwnerIsSpender(address owner, address spender);

    /**
     *  @custom:error OwnerZeroAddress Emitted when the owner is the zero address
     */
    error CygnusBorrowApprove__OwnerZeroAddress(address owner, address spender);

    /**
     *  @custom:error SpenderZeroAddress Emitted when the spender is the zero address
     */
    error CygnusBorrowApprove__SpenderZeroAddress(address owner, address spender);

    /**
     *  @custom:error BorrowNotAllowed Emitted when borrowing above max allowance set
     */
    error CygnusBorrowApprove__BorrowNotAllowed(uint256 borrowAllowance, uint256 borrowAmount);

    /**
     *  @custom:error PermitExpired Emitted when the transaction permit is expired
     */
    error CygnusBorrowApprove__PermitExpired(uint256 transactDeadline, uint256 currentTimestamp);

    /**
     *  @custom:error RecoveredOwnerZeroAddress Emitted when the recovered owner is the zero address
     */
    error CygnusBorrowApprove__RecoveredOwnerZeroAddress(address recoveredOwner);

    /**
     *  @custom:error InvalidSignature Emitted when the recovered owner does not match the actual owner
     */
    error CygnusBorrowApprove__InvalidSignature(uint8 v, bytes32 r, bytes32 s);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Logs borrow allowance for a spender is updated
     *  @param owner Indexed address of the owner of the tokens
     *  @param spender The address of the user being allowed to spend the tokens
     *  @param amount The maximum amount of tokens the spender may spend
     *  @custom:event BorrowApproval Emitted when borrow allowance is updated
     */
    event BorrowApproval(address indexed owner, address spender, uint256 amount);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice IERC721 permit typehash for signature based borrow approvals
     *  @return BORROW_PERMIT_TYPEHASH The keccak256 of the owner, spender, value, nonce and deadline
     */
    function BORROW_PERMIT_TYPEHASH() external view returns (bytes32);

    /**
     *  @notice Mapping of spending allowances from one address to another address
     *  @param owner The address of the token owner
     *  @param spender The address of the token spender
     *  @return The maximum amount the spender can spend
     */
    function borrowAllowances(address owner, address spender) external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @param owner The address owner of the tokens
     *  @param spender The user allowed to spend the tokens
     *  @param value The maximum amount of tokens the spender may spend
     *  @param deadline A future time...
     *  @param v Must be a valid secp256k1 signature from the owner along with r and s
     *  @param r Must be a valid secp256k1 signature from the owner along with v and s
     *  @param s Must be a valid secp256k1 signature from the owner along with r and v
     */
    function borrowPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     *  @param spender The user allowed to spend the tokens
     *  @param value The amount of tokens approved to spend
     *  @return Whether or not the borrow was approved
     */
    function borrowApprove(address spender, uint256 value) external returns (bool);
}
