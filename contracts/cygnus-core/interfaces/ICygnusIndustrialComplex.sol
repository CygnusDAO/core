// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

/**
 *  @notice Interface to interact with CYG rewards
 */
interface ICygnusIndustrialComplex {
    /**
     *  @custom:enum Position Lending or Borrowing shuttle
     *  @custom:member LENDER Pass 0 to claim from lender pools
     *  @custom:memebr BROROWER Pass 1 to claim from borrower pools
     */
    enum Position {
        LENDER,
        BORROWER
    }

    /**
     *  @dev Tracks rewards for lenders and borrowers.
     *
     *  @param account The address of the lender or borrower
     *  @param balance The updated balance of the account
     *  @param adjustmentFactor The updated borrow index of the borrowable asset or 1e18 for lenders
     *  @param position Whether the account has a borrow or lend position
     *
     *  Effects:
     *  - Updates the shares and reward debt of the borrower in the borrowable asset's pool.
     *  - Updates the total shares of the borrowable asset's pool.
     */
    function trackRewards(address account, uint256 balance, uint256 adjustmentFactor, Position position) external;
}
