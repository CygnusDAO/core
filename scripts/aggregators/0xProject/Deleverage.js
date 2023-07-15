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
    const _0xProjectSwap = async (chainId, fromToken, toToken, amount, router) => {
        // The API uses chain name instead of chainID so ocnvert
        let chain;

        // update chain
        switch (chainId) {
            case 1:
                chain = "";
                break;
            case 137:
                chain = "polygon";
                break;
            case 10:
                chain = "optimism";
                break;
            case 56:
                chain = "bsc";
                break;
            case 42161:
                chain = "arbitrum";
                break;
        }

        // 1inch Api call
        const apiUrl = `https://${chain}.api.0x.org/swap/v1/quote?sellToken=${fromToken}&buyToken=${toToken}&sellAmount=${amount}&slippagePercentage=0.02&skipValidation=true&takerAddress=${router}`;

        const headers = {
            "0x-api-key": "02a575e5-685a-464d-98d4-71431f79489a",
        };

        // Swap data
        const swapdata = await fetch(apiUrl, { headers }).then((response) => response.json());

        // Return response
        return swapdata.data;
    };

    // 1Inch call array to pass to periphery
    let calls = [];

    // We loop through each token and make the api call to sell token `i` to USD
    for (let i = 0; i < tokens.length; i++) {
        // Check if token received is already usdc
        if (tokens[i].toLowerCase() != usdc.toLowerCase()) {
            // Call 1inch api
            const swap = await _0xProjectSwap(chainId, tokens[i], usdc, amounts[i].toString(), router.address);

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
