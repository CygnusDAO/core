// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

interface ICygnusDAOReserves {
    /// @notice Adds a shuttle to the record
    /// @param shuttleId The ID for the shuttle we are adding
    /// @custom:security non-reentrant only-admin
    function addShuttle(uint256 shuttleId, address borrowable, address collateral) external;
}
