// SPDX-License-Identifier: Unlicensed

/**
 *  @title CygnusPoolAddress
 *  @dev Provides functions for deriving Cygnus collateral and borrow addresses deployed by Factory
 */
pragma solidity >=0.8.4;

library CygnusPoolAddress {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  IMPORTANT: UPDATE WITH LATEST CODE HASH
     *
     *  @notice keccak256(creationCode) of CygnusCollateral.sol contract
     *  @notice Used by Router and CygnusFactory to deploy shuttles
     */
    bytes32 internal constant COLLATERAL_INIT_CODE_HASH =
        0xcbb495345c9123b8945c232d35e48b530ada4f555866211d5eefc8b0c420de2f;

    /**
     *  IMPORTANT: UPDATE WITH LATEST CODE HASH
     *
     *  @notice keccak256(creationCode) of CygnusBorrow.sol contract
     *  @notice Used by Router and CygnusFactory to deploy shuttles
     */
    bytes32 internal constant BORROW_INIT_CODE_HASH =
        0x9bba9cba088e6f28f2118477d1543e873b613284f71292b7e768edb12a367eba;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Used by CygnusAltair.sol and Cygnus Factory
     *  @dev create2_address: keccak256(0xff, senderAddress, salt, keccak256(init_code))[12:]
     *  @param lpTokenPair The address of the LP Token
     *  @param factory The address of the Cygnus Factory used to deploy the shuttle
     *  @return collateral The calculated address of the Cygnus collateral contract given `lpTokenPair`
     *                     and `factory` addresses
     */
    function getCollateralContract(
        address lpTokenPair,
        address factory,
        address collateralDeployer
    ) internal pure returns (address collateral) {
        collateral = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            collateralDeployer,
                            keccak256(abi.encode(lpTokenPair, factory)),
                            COLLATERAL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    /**
     *  @dev Used by CygnusAltair.sol
     *  @dev create2_address: keccak256(0xff, senderAddress, salt, keccak256(init_code))[12:]
     *  @param collateral The address of the LP Token
     *  @param factory The address of the Cygnus Factory used to deploy the shuttle
     *  @param borrowDeployer The address of the CygnusAlbireo contract
     *  @return borrow The calculated address of the Cygnus Borrow contract deployed by factory given
     *          `lpTokenPair` and `factory` addresses along with borrowDeployer contract address
     */
    function getBorrowContract(
        address collateral,
        address factory,
        address borrowDeployer
    ) internal pure returns (address borrow) {
        borrow = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            borrowDeployer,
                            keccak256(abi.encode(collateral, factory)),
                            BORROW_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}
