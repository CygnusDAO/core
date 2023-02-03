// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { CygnusBorrowModel } from "./CygnusBorrowModel.sol";
import { IAlbireoOrbiter } from "./interfaces/IAlbireoOrbiter.sol";
import { IERC20 } from "./interfaces/IERC20.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";
import { CygnusTerminal } from "./CygnusTerminal.sol";

/**
 *  @title  CygnusBorrowVoid The strategy contract for the underlying stablecoin
 *  @author CygnusDAO
 *  @notice Strategy for the underlying stablecoin deposits.
 */
contract CygnusBorrowVoid is CygnusBorrowModel {
    /**
     *  @custom:library PRBMathUD60x18 Library for uint256 fixed point math, also imports the main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /**
     *  @notice Constructs the Borrow Void contract which handles borrowable underlying strategy. The constructor
     *          for all voids should always be the same across all strategies, as such even if the strategy the
     *          constructor must always be left as is and remove all other functions.
     */
    constructor() {
        // Get underlying stablecoin asset for this borrowable contract (ie. USDC, DAI, etc.)
        (, address asset, , , , ) = IAlbireoOrbiter(_msgSender()).borrowParameters();

        // Name of this CygUSD with each token symbols
        symbol = string(abi.encodePacked("CygUSD: ", IERC20(asset).symbol()));

        // Get decimals
        decimals = IERC20(asset).decimals();
    }

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of assets to deposit into the strategy
     */
    function afterDepositInternal(uint256 assets, uint256) internal override(CygnusTerminal) {}

    /**
     *  @notice Cygnus Terminal Override
     *  @inheritdoc CygnusTerminal
     *  @param assets The amount of shares to withdraw from the strategy
     */
    function beforeWithdrawInternal(uint256 assets, uint256) internal override(CygnusTerminal) {}
}
