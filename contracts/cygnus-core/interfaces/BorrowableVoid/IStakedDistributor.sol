// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

// Staked distributor
interface IStakedDistributor { 
  // Mint staked sonne
  function mint(uint256 amount) external;
  function burn(uint256 amount) external;
  function getClaimable(address, address) external view returns (uint256);
  function claimAll() external returns (uint256[] memory amounts);
  function tokens(uint256) external returns (address);
}
