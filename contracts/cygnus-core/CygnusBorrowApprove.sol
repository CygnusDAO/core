// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusBorrowApprove } from "./interfaces/ICygnusBorrowApprove.sol";
import { CygnusBorrowControl } from "./CygnusBorrowControl.sol";

/**
 *  @title  CygnusBorrowApprove
 *  @notice Contract for approving borrows for the borrow arm of the lending pool and updating borrow allowances.
 *          Before any borrow the borrower must have positive borrowAllowances set by this contract.
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
     *  @param spender The address of the person given the allowance
     *  @param amount The max amount of tokens the spender can spend
     */
    function borrowApproveInternal(
        address owner,
        address spender,
        uint256 amount
    ) private {
        borrowAllowances[owner][spender] = amount;

        /// @custom:event BorrowApproved
        emit BorrowApproval(owner, spender, amount);
    }

    /*  ────────────────────────────────────────────── Internal ────────────────────────────────────────────────  */

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

        /// custom:error Avoid self
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
    function borrowApprove(address spender, uint256 value) external override returns (bool) {
        // Safe internal Approve
        borrowApproveInternal(_msgSender(), spender, value);

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
        /// @custom:error OwnerZeroAddress Avoid owner being the zero address
        if (owner == address(0)) {
            revert CygnusBorrowApprove__OwnerZeroAddress({ owner: owner, spender: spender });
        }
        /// @custom:error SpenderZeroAddress Avoid spender being the zero address
        else if (spender == address(0)) {
            revert CygnusBorrowApprove__SpenderZeroAddress({ owner: owner, spender: spender });
        }
        /// @custom:error PermitExpired Avoid transacting past deadline
        else if (deadline < getBlockTimestamp()) {
            revert CygnusBorrowApprove__PermitExpired({
                transactDeadline: deadline,
                currentTimestamp: getBlockTimestamp()
            });
        }

        // It's safe to use unchecked here because the nonce cannot realistically overflow, ever.
        bytes32 hashStruct;

        unchecked {
            hashStruct = keccak256(
                abi.encode(BORROW_PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline)
            );
        }

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashStruct));

        address recoveredOwner = ecrecover(digest, v, r, s);

        /// @custom:error RecoveredOwnerZeroAddress Avoid the zero address being the recovered owner
        if (recoveredOwner == address(0)) {
            revert CygnusBorrowApprove__RecoveredOwnerZeroAddress(recoveredOwner);
        }
        /// @custom:error InvalidSignature Avoid invalid signature
        else if (recoveredOwner != owner) {
            revert CygnusBorrowApprove__InvalidSignature({ v: v, r: r, s: s });
        }

        // Finally approve internally
        borrowApproveInternal(owner, spender, value);
    }
}
