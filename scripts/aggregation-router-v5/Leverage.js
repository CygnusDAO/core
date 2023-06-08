/**
 *  @notice Build 1inch swaps using AggregationRouterV5 for leverage. The router has already received
 *          `leverageUsdcAmount` from the borrowable contract. We must convert this USDC amount to token0
 *          or token1 of the LP. After this swap, we do the other swap on chain.
 *  @notice Only 1 swap is needed.
 */
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount) {
    // Get token0 and token1 for this lp
    const token0 = await lpToken.token0();
    const token1 = await lpToken.token1();

    const protocols =
        "OPTIMISM_UNISWAP_V3,OPTIMISM_SYNTHETIX,OPTIMISM_SYNTHETIX_WRAPPER,OPTIMISM_CURVE,OPTIMISM_BALANCER_V2,OPTIMISM_VELODROME,OPTIMISM_CLIPPER_COVES,OPTIMISM_AAVE_V3,OPTIMISM_ELK,OPTIMISM_TRIDENT,OPTIMISM_MUMMY_FINANCE,OPTIMISM_NOMISWAPEPCS";

    /**
     *  @notice 1inch swagger API call
     *  @param {Number} chainId - The id of this chain
     *  @param {String} fromToken - The address of the token we are swapping
     *  @param {String} toToken - The address of the token we are receiving
     *  @param {String} amount - The amount of `fromToken` we are swapping
     *  @param {String} router - The address of the owner of the USDC (router)
     */
    const oneInch = async (chainId, fromToken, toToken, amount, router) => {
        // 1inch Api call
        const apiUrl = `https://api.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&disableEstimate=true&compatibilityMode=true&slippage=1&protocols=${protocols}`;

        // Fetch from 1inch api
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata;
    };

    // 1Inch call array to pass to periphery
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
            const swapdata = await oneInch(chainId, usdc, nativeToken, leverageUsdcAmount, router.address);

            // Add to call array
            calls = [...calls, swapdata.tx.data.toString().replace("0x12aa3caf", "0x")];
        }
        // Swap to token0
        else {
            // Swap USDC to token0
            const swapdata = await oneInch(chainId, usdc, token0, leverageUsdcAmount, router.address);

            // Add to call array
            calls = [...calls, swapdata.tx.data.toString().replace("0x12aa3caf", "0x")];
        }
    }

    // Return bytes array to pass to periphery
    return calls;
};
