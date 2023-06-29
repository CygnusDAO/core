/// @notice Build swaps using OneInch's Router to leverage. The router has already received
///         `deleverageLpAmount` from the collateral contract. We must convert this amount to USDC to get the best
///         amount possible.
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount) {
    // Get token0 and token1 for this lp
    const token0 = await lpToken.token0();
    const token1 = await lpToken.token1();

    // remove OPTIMISM_WOOFI_V2
    const protocols =
        "OPTIMISM_UNISWAP_V3,OPTIMISM_SYNTHETIX,OPTIMISM_SYNTHETIX_WRAPPER,OPTIMISM_ONE_INCH_LIMIT_ORDER,OPTIMISM_ONE_INCH_LIMIT_ORDER_V2,OPTIMISM_ONE_INCH_LIMIT_ORDER_V3,OPTIMISM_CURVE,OPTIMISM_BALANCER_V2,OPTIMISM_VELODROME,OPTIMISM_KYBERSWAP_ELASTIC,OPTIMISM_CLIPPER_COVES,OPTIMISM_KYBER_DMM_STATIC,OPTIMISM_AAVE_V3,OPTIMISM_ELK,OPTIMISM_TRIDENT,OPTIMISM_MUMMY_FINANCE,OPTIMISM_NOMISWAPEPCS";

    /// @notice 1inch swagger API call
    /// @param {Number} chainId - The id of this chain
    /// @param {String} fromToken - The address of the token we are swapping
    /// @param {String} toToken - The address of the token we are receiving
    /// @param {String} amount - The amount of `fromToken` we are swapping
    /// @param {String} router - The address of the owner of the USDC (router)
    const oneInch = async (chainId, fromToken, toToken, amount, router) => {
        // 1inch Api call
        const apiUrl = `https://api-cygnusdaofinance.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&disableEstimate=true&compatibilityMode=true&slippage=0.25&protocols=${protocols}`;

        // Fetch from 1inch api
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.tx.data.toString().replace("0x12aa3caf", "0x");
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
            calls = [...calls, swapdata];
        }
        // Swap to token0
        else {
            // Swap USDC to token0
            const swapdata = await oneInch(chainId, usdc, token0, leverageUsdcAmount, router.address);

            // Add to call array
            calls = [...calls, swapdata];
        }
    }

    // Return bytes array to pass to periphery
    return calls;
};
