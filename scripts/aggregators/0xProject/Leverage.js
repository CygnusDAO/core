/// @notice Build swaps using 0xProject's Swap API to leverage.
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount) {
    // Get token0 and token1 for this lp
    const token0 = await lpToken.token0();
    const token1 = await lpToken.token1();

    /// @notice 0xProject swap api call
    /// @param {Number} chainId - The id of this chain
    /// @param {String} fromToken - The address of the token we are swapping
    /// @param {String} toToken - The address of the token we are receiving
    /// @param {String} amount - The amount of `fromToken` we are swapping
    /// @param {String} router - The address of the owner of the USDC (router)
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

        // 0xProject Api call
        const apiUrl = `https://${chain}.api.0x.org/swap/v1/quote?sellToken=${fromToken}&buyToken=${toToken}&sellAmount=${amount}&slippagePercentage=0.0025&skipValidation=true&takerAddress=${router}`;

        const headers = {
            "0x-api-key": "02a575e5-685a-464d-98d4-71431f79489a",
        };

        // Fetch from 0xProject api
        const swapdata = await fetch(apiUrl, { headers }).then((response) => response.json());

        // Return response
        return swapdata.data.toString();
    };

    // 0xproject call array to pass to periphery
    let calls = [];

    // Check if token0 is already usdc
    if (token0.toLowerCase() === usdc.toLowerCase() || token1.toLowerCase() === usdc.toLowerCase()) {
        // If usdc pass empty bytes
        calls = [...calls, "0x"];
    }
    // Not usdc, check for native token (ie WETH) to minimize slippage
    else {
        if (token0.toLowerCase() === nativeToken.toLowerCase() || token1.toLowerCase() === nativeToken.toLowerCase()) {
            // Swap USDC to Native
            const swapdata = await _0xProjectSwap(chainId, usdc, nativeToken, leverageUsdcAmount, router.address);

            // Add to call array
            calls = [...calls, swapdata];
        }
        // Swap to token0
        else {
            // Swap USDC to token0
            const swapdata = await _0xProjectSwap(chainId, usdc, token0, leverageUsdcAmount, router.address);

            // Add to call array
            calls = [...calls, swapdata];
        }
    }

    // Return bytes array to pass to periphery
    return calls;
};
