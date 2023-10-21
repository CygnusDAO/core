/// For the API calls
const path = require("path");
require("dotenv").config({ path: path.resolve(__dirname, "../../../.env") });

/// @notice Build swaps using 0xProject's Swap API to leverage.
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount, nebula) {
    // Get LP info
    const { tokens, reservesUsd } = await nebula.lpTokenInfo(lpToken.address);

    // TVL
    let tvl = reservesUsd[0].add(reservesUsd[1]);

    // Weight of each token
    let token0Weight = reservesUsd[0].mul(BigInt(1e18)).div(tvl);
    let token1Weight = BigInt(1e18) - BigInt(token0Weight);

    // Perform api call and return the data we need to pass to the CygnusAltair router
    const zeroExProjectSwap = async (chainId, fromToken, toToken, amount) => {
        // The API uses chain name instead of chainID so convert
        let chain;

        switch (chainId) {
            case 1:
                chain = "";
                break;
            case 137:
                chain = "polygon.";
                break;
            case 10:
                chain = "optimism.";
                break;
            case 56:
                chain = "bsc.";
                break;
            case 42161:
                chain = "arbitrum.";
                break;
        }

        // 0xProject API call (exclude woofi we cannot replicate call in test environment, remove in prod)
        const apiUrl = `https://${chain}api.0x.org/swap/v1/quote?sellToken=${fromToken}&buyToken=${toToken}&sellAmount=${amount}&slippagePercentage=0.01&skipValidation=true&excludedSources=WOOFi`;

        // https://0x.org/docs/0x-swap-api/introduction
        const headers = { "0x-api-key": process.env.ZERO_EX_API_KEY };

        // Fetch from 0xProject api
        const swapdata = await fetch(apiUrl, { headers }).then((response) => response.json());

        // Return response
        return swapdata.data.toString();
    };

    // 0xproject call array to pass to periphery
    let calls = [];

    // Check if token0 is already usdc
    if (tokens[0].toLowerCase() != usdc.toLowerCase()) {
        // weight of token0 in the pool
        const adjustedAmount0 = (BigInt(leverageUsdcAmount) * BigInt(token0Weight)) / BigInt(1e18);

        // Swap USDC to Native
        const swapdata = await zeroExProjectSwap(chainId, usdc, tokens[0], adjustedAmount0.toString());

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Check if token1 is already usdc
    if (tokens[1].toLowerCase() != usdc.toLowerCase()) {
        // Weight of toekn1 in the pool
        const adjustedAmount1 = (BigInt(leverageUsdcAmount) * BigInt(token1Weight)) / BigInt(1e18);

        // Swap USDC to Native
        const swapdata = await zeroExProjectSwap(chainId, usdc, tokens[1], adjustedAmount1.toString());

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Return bytes array to pass to periphery
    return calls;
};
