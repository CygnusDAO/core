// SPDX-License-Identifier: Unlicensed

import { IERC20 } from "../interfaces/IERC20.sol";
import { IDexPair } from "../interfaces/IDexPair.sol";

/**
 *  @title Strings
 *  @notice Used for collateral/borrow control contracts
 */
pragma solidity ^0.8.4;

library Strings {
    /**
     *  @notice Concats two strings
     *  @param underlying Address of the underlying LP Token
     *  @return The concat of token0 + '/' + token1
     */
    function tokenSymbols(address underlying) internal view returns (string memory) {
        // Get name of token0 from LP token
        string memory token0 = IERC20(IDexPair(underlying).token0()).symbol();

        // Get name of token1 from LP token
        string memory token1 = IERC20(IDexPair(underlying).token1()).symbol();

        // Return string
        return string(abi.encodePacked("CygLP ", token0, "/", token1));
    }
}
