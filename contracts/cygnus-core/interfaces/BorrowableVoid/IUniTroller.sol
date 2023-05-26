// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

interface IUniTroller {
    /// @notice The COMP accrued but not yet transferred to each user
    function compAccrued(address) external view returns (uint256);

    /**
     * @notice Claim all the comp accrued by holder in all markets
     * @param holder The address to claim COMP for
     */
    function claimComp(address holder) external;

    function getCompAddress() external view returns (address);
}
