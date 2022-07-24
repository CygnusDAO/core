// SPDX-License-Identifier: Unlicensed

import { IErc20 } from "./IErc20.sol";
import { IDexPair } from "./IDexPair.sol";

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
    function appendDeneb(address underlying) internal view returns (string memory) {
        // Get name of token0 from LP token
        string memory token0 = IErc20(IDexPair(underlying).token0()).symbol();

        // Get name of token1 from LP token
        string memory token1 = IErc20(IDexPair(underlying).token1()).symbol();

        // Return string
        return string(abi.encodePacked("CygLP ", token0, "/", token1));
    }
}
