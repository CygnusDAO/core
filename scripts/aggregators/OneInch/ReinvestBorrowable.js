/**
 *  @notice Simple reinvest for collateral
 *  @param chainId The chain ID for the 1inch swap
 *  @param borrowable The Borrowable contract object
 *  @param harvester The harvester contract object
 */
module.exports = async function reinvestBorrowable(chainId, borrowable, harvester) {
    // 1. Get harvester for this borrowable (needed to get the optimal token to swap to).
    const harvesterInfo = await harvester.getHarvester(borrowable.address);

    // 2. Get the cached optimal token. swapping to anything but this token will cause the transaction to revert
    const wantToken = harvesterInfo.wantToken;

    // 3. Do a static call to the CygnusBorrow contract get the tokens and amounts harvested
    const { tokens, amounts } = await borrowable.callStatic.getRewards();

    // Note: Collateral strategies do not have this step as the reward is removed just before adding liquidity
    // 4. Get the CygnusX1Vault reward to remove from swap amount
    const vaultReward = await harvester.x1VaultReward();

    /**
     *  @notice Make a 1inch API call
     *  @param {string} fromToken - The address of the token being swapped
     *  @param {string} toToken - The address of the token being received
     *  @param {string} amount - The amount of fromToken being swapped
     *  @returns {object} swapData - Data from the 1inch swap
     */
    const oneInchSwap = async (fromToken, toToken, amount) => {
        // Api call
        const apiUrl = `https://api.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${harvester.address}&destReceiver=${borrowable.address}&slippage=1&disableEstimate=true&compatibilityMode=true`;

        // Fetch data
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return 1inch bytes
        return swapdata;
    };

    // Calls
    let calls = [];

    // Loop through each reward token and call 1inch
    for (let i = 0; i < tokens.length; i++) {
        // Amount to swap = amount we have minus the vault reward
        const amountToSwap = amounts[i].mul(BigInt(1e18).sub(vaultReward)).div(BigInt(1e18));

        // if amount harvested is greater than 0 and token is not wanttoken
        if (amountToSwap.gt(0) && tokens[i] !== wantToken) {
            // Call 1inch api
            const swapdata = await oneInchSwap(tokens[i], wantToken, amountToSwap);

            // push to the `calls` array and remove selector of the 1inch swap function
            calls.push(swapdata.tx.data.toString().replace("0x12aa3caf", "0x"));
        }
        // if the amount is 0 or the token is wantToken we pass empty bytes
        else calls.push("0x"); // empty call
    }

    return calls;
};
