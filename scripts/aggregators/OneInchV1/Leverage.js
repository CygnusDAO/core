/// For the API calls
const path = require("path");
require("dotenv").config({ path: path.resolve(__dirname, "../../../.env") });

/// @notice Build swaps using OneInch's Router to convert USDC to LP
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount, nebula) {
    // Get LP info
    const { tokens, reservesUsd } = await nebula.lpTokenInfo(lpToken.address);

    // Weight of each token
    const tvl = reservesUsd[0].add(reservesUsd[1]);
    const token0Weight = reservesUsd[0].mul(BigInt(1e18)).div(tvl);
    const token1Weight = BigInt(1e18) - BigInt(token0Weight);

    // Perform api call and return the data we need to pass to the CygnusAltair router
    const oneInch = async (chainId, fromToken, toToken, amount, router) => {
        // 1inch Api call
        const apiUrl = `${process.env.INCH_API_URL}/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&disableEstimate=true&compatibilityMode=true&slippage=0.3`;

        // Fetch from 1inch api
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.tx.data.toString().replace("0x12aa3caf", "0x");
    };

    /// Initialize calldata array
    let calls = [];

    // Check if token0 is already usdc
    if (tokens[0].toLowerCase() != usdc.toLowerCase()) {
        // Swap USDC to token0 according to token0 weight
        const adjustedAmount0 = (BigInt(leverageUsdcAmount) * BigInt(token0Weight)) / BigInt(1e18);

        const swapdata = await oneInch(chainId, usdc, tokens[0], adjustedAmount0.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Check if token1 is already usdc
    if (tokens[1].toLowerCase() != usdc.toLowerCase()) {
        // Swap USDC to token1 according to token1 weight
        const adjustedAmount1 = (BigInt(leverageUsdcAmount) * BigInt(token1Weight)) / BigInt(1e18);

        const swapdata = await oneInch(chainId, usdc, tokens[1], adjustedAmount1.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    return calls;
};
