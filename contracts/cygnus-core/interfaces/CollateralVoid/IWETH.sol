// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Interface for interfacting with Wrapped Eth
interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function totalSupply() external view returns (uint256);

    function transfer(address dst, uint256 wad) external returns (bool);

    function balanceOf(address owner) external view returns (uint256);

    function approve(address to, uint256 value) external returns (bool);
}
