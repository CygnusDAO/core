// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

interface IVeloVoter {
    function gauges(address) external view returns (address);
}
