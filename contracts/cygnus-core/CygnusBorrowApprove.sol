// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusBorrowApprove } from "./interfaces/ICygnusBorrowApprove.sol";
import { CygnusBorrowControl } from "./CygnusBorrowControl.sol";

/**
 *  @title  CygnusBorrowApprove
 *  @notice Contract for approving borrows for the borrow arm of the lending pool and updating borrow allowances.
 *          Before any borrow, the borrower must have positive borrowAllowances set by this contract.
 */
contract CygnusBorrowApprove is ICygnusBorrowApprove, CygnusBorrowControl {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowApprove
     */
    bytes32 public constant override BORROW_PERMIT_TYPEHASH =
        keccak256("BorrowPermit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /**
     *  @inheritdoc ICygnusBorrowApprove
     */
    mapping(address => mapping(address => uint256)) public override borrowAllowances;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Safe private function which updates allowances after doing sufficient checks
     *  @param owner The address of the owner of the tokens
     *  @param spender The address of the account given the allowance
     *  @param amount The max amount of tokens the spender can spend
     */
    function borrowApproveInternal(
        address owner,
        address spender,
        uint256 amount
    ) private {
        // Store approve amount
        borrowAllowances[owner][spender] = amount;

        /// @custom:event BorrowApproved
        emit BorrowApproval(owner, spender, amount);
    }

    /*  ────────────────────────────────────────────── Internal ────────────────────────────────────────────────  */

    /**
     *  @return The uint32 block timestamp
     */
    function getBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp);
    }

    /**
     *  @notice Internal function which does the sufficient checks to approve allowances
     *  @notice If all checks pass, call private approve function. Used by child CygnusBorrow
     *  @param owner The address of the owner of the tokens
     *  @param spender The address of the person given the allowance
     *  @param amount The max amount of tokens the spender can spend
     */
    function borrowApproveUpdate(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        uint256 currentAllowance = borrowAllowances[owner][spender];

        /// @custom:error OwnerIsSpender Avoid approving self
        if (owner == spender) {
            revert CygnusBorrowApprove__OwnerIsSpender({ owner: owner, spender: spender });
        }
        /// @custom:error OwnerZeroAddress Avoid the owner being the zero address
        else if (owner == address(0)) {
            revert CygnusBorrowApprove__OwnerZeroAddress({ owner: owner, spender: spender });
        }
        /// @custom:error SpenderZeroAddress Avoid the spender being the zero address
        else if (spender == address(0)) {
            revert CygnusBorrowApprove__SpenderZeroAddress({ owner: owner, spender: spender });
        }
        /// custom:error BorrowNotAllowed Avoid borrowing more than allowwed
        else if (currentAllowance < amount) {
            revert CygnusBorrowApprove__BorrowNotAllowed({ borrowAllowance: currentAllowance, borrowAmount: amount });
        }

        // Updates the borrow allowance in the next function call
        borrowApproveInternal(owner, spender, currentAllowance - amount);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusBorrowApprove
     */
    function borrowApprove(address spender, uint256 amount) external override returns (bool) {
        // Safe internal Approve
        borrowApproveInternal(_msgSender(), spender, amount);

        return true;
    }

    /**
     *  @inheritdoc ICygnusBorrowApprove
     */
    function borrowPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        // Call permit with the borrow permit typehash
        permit(owner, spender, value, deadline, v, r, s, BORROW_PERMIT_TYPEHASH);

        // If succeeds approve internally
        borrowApproveInternal(owner, spender, value);
    }
}
