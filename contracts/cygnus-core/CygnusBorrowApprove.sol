// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrowApprove} from "./interfaces/ICygnusBorrowApprove.sol";
import {CygnusBorrowControl} from "./CygnusBorrowControl.sol";

// Libraries
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

/**
 *  @title  CygnusBorrowApprove Enables selective borrowing using borrower's collateral (CygLP)
 *  @notice The main purpose of this contract is to check that msg.sender is allowed to borrow. Since the borrow function requires
 *          a router contract for leverage functionality, simply using msg.sender as the owner of the CygLP and thus the one with collateral
 *          is not enough. Therefore before borrowing, if the msg.sender is different than the borrower, we first check for borrow allowance.
 *  @notice The original author of this is Solady (https://github.com/Vectorized/solady/blob/main/src/tokens/ERC20.sol). We simply
 *          adjusted some of the functions to reflect a new allowance given only for borrows.
 */
contract CygnusBorrowApprove is ICygnusBorrowApprove, CygnusBorrowControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /// @dev `keccak256(bytes("BorrowApproval(address,address,uint256)"))`.
    uint256 private constant _BORROW_APPROVAL_EVENT_SIGNATURE = 0xc3c1215b41d54142382d54a05fb991007165ae91bcb1879bac8b290d9111aaf4;

    /// @dev The allowance slot of (`owner`, `spender`) is given by:
    /// ```
    ///     mstore(0x20, spender)
    ///     mstore(0x0c, _BORROW_ALLOWANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let allowanceSlot := keccak256(0x0c, 0x34)
    /// ```
    uint256 private constant _BORROW_ALLOWANCE_SLOT_SEED = 0x73b812c2;

    /*  ────────────────────────────────────────────── Public ─────────────────────────────────────────────────  */

    /**
     *  @notice keccak256("BorrowPermit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
     *  @inheritdoc ICygnusBorrowApprove
     */
    bytes32 public constant override BORROW_PERMIT_TYPEHASH = 0xf6d86ed606f871fa1a557ac0ba607adce07767acf53f492fb215a1a4db4aea6f;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
         5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @inheritdoc ICygnusBorrowApprove
     */
    function borrowAllowance(address owner, address spender) external view override returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x20, spender)
            mstore(0x0c, _BORROW_ALLOWANCE_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x34))
        }
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
         6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @dev Updates the borrow allowance of `owner` for `spender` based on `borrowAmount` (similar to spendAllowance)
     *  @param owner The address of the owner of the CygLP
     *  @param spender The address allowed to borrow on `owner`s behalf
     *  @param amount The amount the `owner` is allowing the `spender` to borrow on their behalf
     */
    function _borrowAllowance(address owner, address spender, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the borrow allowance slot and load its value.
            mstore(0x20, spender)
            mstore(0x0c, _BORROW_ALLOWANCE_SLOT_SEED)
            mstore(0x00, owner)
            let borrowAllowanceSlot := keccak256(0x0c, 0x34)
            let allowance_ := sload(borrowAllowanceSlot)
            // If the allowance is not the maximum uint256 value.
            if iszero(eq(allowance_, not(0))) {
                // Revert if the amount to be borrowed exceeds the borrow allowance.
                if gt(amount, allowance_) {
                    mstore(0x00, 0x991282cd) // `InsufficientBorrowAllowance()`.
                    revert(0x1c, 0x04)
                }
                // Subtract and store the updated allowance.
                sstore(borrowAllowanceSlot, sub(allowance_, amount))
            }
        }
    }

    /**
     *  @dev Sets `amount` as the borrow allowance of `spender`
     *  @param owner The address of the owner of the CygLP
     *  @param spender The address allowed to borrow on `owner`s behalf
     *  @param amount The amount the `owner` is allowing the `spender` to borrow on their behalf
     */
    function _borrowApprove(address owner, address spender, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let owner_ := shl(96, owner)
            // Compute the allowance slot and store the amount.
            mstore(0x20, spender)
            mstore(0x0c, or(owner_, _BORROW_ALLOWANCE_SLOT_SEED))
            sstore(keccak256(0x0c, 0x34), amount)
            // Emit the {Approval} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _BORROW_APPROVAL_EVENT_SIGNATURE, shr(96, owner_), shr(96, mload(0x2c)))
        }
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowApprove
     */
    function borrowApprove(address spender, uint256 borrowAmount) external override returns (bool) {
        // Approve borrow internally
        _borrowApprove(msg.sender, spender, borrowAmount);
        return true;
    }

    /**
     *  @inheritdoc ICygnusBorrowApprove
     */
    function borrowPermit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external override {
        bytes32 domainSeparator = DOMAIN_SEPARATOR();
        /// @solidity memory-safe-assembly
        assembly {
            // Grab the free memory pointer.
            let m := mload(0x40)
            // Revert if the block timestamp greater than `deadline`.
            if gt(timestamp(), deadline) {
                mstore(0x00, 0x1a15a3cc) // `PermitExpired()`.
                revert(0x1c, 0x04)
            }
            // Clean the upper 96 bits.
            owner := shr(96, shl(96, owner))
            spender := shr(96, shl(96, spender))
            // Compute the nonce slot and load its value.
            mstore(0x0c, _NONCES_SLOT_SEED)
            mstore(0x00, owner)
            let nonceSlot := keccak256(0x0c, 0x20)
            let nonceValue := sload(nonceSlot)
            // Increment and store the updated nonce.
            sstore(nonceSlot, add(nonceValue, 1))
            // Prepare the inner hash.
            // `keccak256("BorrowPermit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")`.
            // forgefmt: disable-next-item
            mstore(m, BORROW_PERMIT_TYPEHASH)
            mstore(add(m, 0x20), owner)
            mstore(add(m, 0x40), spender)
            mstore(add(m, 0x60), value)
            mstore(add(m, 0x80), nonceValue)
            mstore(add(m, 0xa0), deadline)
            // Prepare the outer hash.
            mstore(0, 0x1901)
            mstore(0x20, domainSeparator)
            mstore(0x40, keccak256(m, 0xc0))
            // Prepare the ecrecover calldata.
            mstore(0, keccak256(0x1e, 0x42))
            mstore(0x20, and(0xff, v))
            mstore(0x40, r)
            mstore(0x60, s)
            pop(staticcall(gas(), 1, 0, 0x80, 0x20, 0x20))
            // If the ecrecover fails, the returndatasize will be 0x00,
            // `owner` will be be checked if it equals the hash at 0x00,
            // which evaluates to false (i.e. 0), and we will revert.
            // If the ecrecover succeeds, the returndatasize will be 0x20,
            // `owner` will be compared against the returned address at 0x20.
            if iszero(eq(mload(returndatasize()), owner)) {
                mstore(0x00, 0x35016152) // `InvalidBorrowPermit()`.
                revert(0x1c, 0x04)
            }
            // Compute the allowance slot and store the value.
            // The `owner` is already at slot 0x20.
            mstore(0x40, or(shl(160, _BORROW_ALLOWANCE_SLOT_SEED), spender))
            sstore(keccak256(0x2c, 0x34), value)
            // Emit the {Approval} event.
            log3(add(m, 0x60), 0x20, _BORROW_APPROVAL_EVENT_SIGNATURE, owner, spender)
            mstore(0x40, m) // Restore the free memory pointer.
            mstore(0x60, 0) // Restore the zero pointer.
        }
    }
}
