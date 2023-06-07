// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrowControl} from "./ICygnusBorrowControl.sol";

/**
 *  @title  ICygnusBorrowControl Interface for the CygnusBorrowApprove contract
 */
interface ICygnusBorrowApprove is ICygnusBorrowControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts if the borrow permit is invalid both in terms of the typehash or the recovered address
     *
     *  @custom:error InvalidBorrowPermit
     */
    error InvalidBorrowPermit();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when `owner` approves `spender` to borrow on their behalf/
     *
     *  @param owner The address of the owner of the CygLP
     *  @param spender The address allowed to borrow on `owner`s behalf
     *  @param amount The amount the `owner` is allowing the `spender` to borrow on their behalf
     *
     *  @custom:event BorrowApproval
     */
    event BorrowApproval(address owner, address spender, uint256 amount);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Returns the total amount that `spender` can borrow on behalf of `owner`.
     *
     *  @param owner The address of the owner of the CygLP
     *  @param spender The address allowed to borrow on owner's behalf
     *
     *  @return amount The current allowed amount
     */
    function borrowAllowance(address owner, address spender) external view returns (uint256 amount);

    /**
     *  @notice keccak256("BorrowPermit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
     *
     *  @return BORROW_PERMIT_TYPEHASH The keccak256 of the borrow permit
     */
    function BORROW_PERMIT_TYPEHASH() external view returns (bytes32);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Approves a spender to borrow on their behalf
     *
     *  @param spender The address allowed to borrow on the msg.sender (owner) behalf
     *  @param amount The amount the `owner` is allowing the `spender` to borrow on their behalf
     *
     *  @return Whether or not the approval succeeded
     */
    function borrowApprove(address spender, uint256 amount) external returns (bool);

    /**
     *  @dev Sets `value` as the borrow allowance of `spender` over ``owner``'s collateral, given ``owner``'s signed approval.
     *  @param owner The address of the owner of the CygLP
     *  @param spender The address allowed to borrow on `owner`s behalf
     *  @param value The amount the `owner` is allowing the `spender` to borrow on their behalf
     *  @param deadline The timestamp indicating the deadline by which the permit is valid.
     *  @param v The recovery id of the signature.
     *  @param r The `r` value of the signature.
     *  @param s The `s` value of the signature.
     */
    function borrowPermit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}
