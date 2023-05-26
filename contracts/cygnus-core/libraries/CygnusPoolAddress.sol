// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

/**
 *  @title CygnusPoolAddress
 *  @dev Provides functions for deriving Cygnus collateral and borrow addresses deployed by Factory
 */
library CygnusPoolAddress {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Used by CygnusAltair.sol and Cygnus Factory
     *  @dev create2_address: keccak256(0xff, senderAddress, salt, keccak256(init_code))
     *  @param lpTokenPair The address of the LP Token
     *  @param factory The address of the Cygnus Factory used to deploy the shuttle
     *  @param denebOrbiter The address of the collateral deployer
     *  @param initCodeHash The keccak256 hash of the initcode of the Cygnus Collateral contracts
     *  @return collateral The calculated address of the Cygnus collateral contract given the salt (`lpTokenPair` and
     *                     `factory` addresses), the msg.sender (Deneb Orbiter) and the init code hash of the
     *                     CygnusCollateral.
     */
    function getCollateralContract(
        address lpTokenPair,
        address factory,
        address denebOrbiter,
        bytes32 initCodeHash
    ) internal pure returns (address collateral) {
        collateral = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            denebOrbiter,
                            keccak256(abi.encode(lpTokenPair, factory)),
                            initCodeHash
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
        address borrowDeployer,
        bytes32 initCodeHash
    ) internal pure returns (address borrow) {
        borrow = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            borrowDeployer,
                            keccak256(abi.encode(collateral, factory)),
                            initCodeHash
                        )
                    )
                )
            )
        );
    }
}
