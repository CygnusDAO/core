// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

// Interface to interact with harvester if needed
interface ICygnusHarvester {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */
    /**
     *  @dev Reverts if tx.origin is different to msg.sender
     *
     *  @param sender The sender of the transaction
     *  @param origin The origin of the transaction
     *
     *  @custom:error OnlyAccountsAllowed
     */
    error CygnusHarvester__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @dev Reverts if the receiver of the swap is not this contract
     *
     *  @param dstReceiver The expected receiver address of the swap
     *  @param receiver The actual receiver address of the swap
     *
     *  @custom:error DstReceiverNotValid
     */
    error CygnusHarvester__DstReceiverNotValid(address dstReceiver, address receiver);

    /**
     *  @dev Reverts if the token received is not underlying
     *
     *  @param dstToken The expected address of the token received
     *  @param token The actual address of the token received
     *
     *  @custom:error DstTokenNotValid
     */
    error CygnusHarvester__DstTokenNotValid(address dstToken, address token);

    /**
     *  @dev Reverts if the src token we are swapping is not the rewards token
     *
     *  @param srcToken The expected address of the token to be swapped
     *  @param token The actual address of the token to be swapped
     *
     *  @custom:error SrcTokenNotValid
     */
    error CygnusHarvester__SrcTokenNotValid(address srcToken, address token);

    /**
     *  @dev Reverts if the harvester is not initialized
     *
     *  @param harvester The address of the collateral passed
     *
     *  @custom:error HarvesterNotInitialized
     */
    error CygnusHarvester__HarvesterNotInitialized(address harvester);

    /**
     *  @dev Reverts if msg.sender is not harvester admin
     *
     *  @param sender The address of the msg.sender
     *  @param admin The address of the harvester admin
     *
     *  @custom:error MsgSenderNotAdmin
     */
    error CygnusHarvester__MsgSenderNotAdmin(address sender, address admin);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     * @dev Logs when a collateral harvester is initialized for a shuttle.
     *
     * @param shuttleId The ID of the shuttle for which the collateral harvester is being initialized.
     * @param collateral The address of the Cygnus Collateral collateral being harvested.
     * @param underlying The address of the underlying token for the collateral token.
     *
     *  @custom:event InitializeCollateralHarvester
     */
    event InitializeCollateralHarvester(uint256 shuttleId, address collateral, address underlying);

    /**
     *  @notice Harvest and return the pending reward tokens and mounts interally, used by reinvest function.
     *  @param tokens Array of reward token addresses
     *  @param amounts Array of reward token amounts
     *  @param swapData The 1inch data needed for the harvest
     */
    function harvestRewards(address[] memory tokens, uint256[] memory amounts, bytes[] calldata swapData) external returns (uint256);
}
