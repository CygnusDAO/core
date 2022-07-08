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
        0x6a0e359c4e645cf451f401ce4c2b66f67565877ae474483f64426d4c62840a0b;

    /**
     *  IMPORTANT: UPDATE WITH LATEST CODE HASH
     *
     *  @notice keccak256(creationCode) of CygnusBorrow.sol contract
     *  @notice Used by Router and CygnusFactory to deploy shuttles
     */
    bytes32 internal constant BORROW_INIT_CODE_HASH =
        0x83dfb73801a9e9bfef34c1b7264e7edee2f7eb8c8aea8cf5c2bdf40624444164;

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
