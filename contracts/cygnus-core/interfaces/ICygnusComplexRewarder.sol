// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

/**
 *  @notice Interface for function to track user CYG rewards
 */
interface ICygnusComplexRewarder {
    /**
     * @dev Updates the borrowing information for a given borrower in a specific borrowable asset pool.
     *
     * @param shuttleId The ID of the Shuttle associated with the borrowable asset pool.
     * @param borrower The address of the borrower whose information is being updated.
     * @param borrowBalance The new borrow balance for the borrower in the borrowable asset pool.
     * @param borrowIndex The current borrow index for the borrowable asset pool.
     *
     * Requirements:
     * - The caller must be the borrowable contract associated with the given Shuttle.
     */
    function trackBorrower(uint256 shuttleId, address borrower, uint256 borrowBalance, uint256 borrowIndex) external;
}
