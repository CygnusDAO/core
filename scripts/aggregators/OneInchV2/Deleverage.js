/**
 *  @notice Build 1inch swaps using AggregationRouterV5 for deleverage. The router has already received
 *          `deleverageLpAmount` from the collateral contract. We must convert this amount to USDC using
 *          multiple swaps.
 */
module.exports = async function deleverageSwapdata(chainId, lpToken, usdc, router, deleverageLpAmount, difference) {
    // Get tokens and amounts out given an LP token and amount
    const [tokens, amounts] = await router.getAssetsForShares(lpToken.address, deleverageLpAmount, difference);

    /**
     *  @notice 1inch swagger API call
     *  @param {Number} chainId - The id of this chain
     *  @param {String} fromToken - The address of the token we are swapping
     *  @param {String} toToken - The address of the token we are receiving
     *  @param {String} amount - The amount of `fromToken` we are swapping
     *  @param {String} router - The address of the owner of the USDC (router)
     */
    const oneInch = async (chainId, fromToken, toToken, amount, router) => {
        // 1inch Api url
        const apiUrl = `https://api-cygnusdaofinance.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&disableEstimate=true&slippage=0.5`;

        // Swap data
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.tx.data.toString();
    };

    // 1Inch call array to pass to periphery
    let calls = [];

    // We loop through each token and make the api call to sell token `i` to USD
    for (let i = 0; i < tokens.length; i++) {
        // Check if token received is already usdc
        if (tokens[i].toLowerCase() != usdc.toLowerCase()) {
            // Call 1inch api
            const swap = await oneInch(chainId, tokens[i], usdc, amounts[i], router.address);

            // Add to calls array
            calls = [...calls, swap];
        } else {
            // If usdc pass empty bytes
            calls = [...calls, "0x"];
        }
    }

    // Return bytes array to pass to periphery
    return calls;
};
