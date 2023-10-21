const path = require("path");
const CryptoJS = require("crypto-js");
require("dotenv").config({ path: path.resolve(__dirname, "../../../.env") });

// Uses OKX aggregation router to convert USDC to LP Token assets in the correct weight to mint LP
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount, nebula) {
    // Weight of each token in the LP
    const { tokens, reservesUsd } = await nebula.lpTokenInfo(lpToken.address);
    const tvl = reservesUsd[0].add(reservesUsd[1]);
    const token0Weight = reservesUsd[0].mul(BigInt(1e18)).div(tvl);
    const token1Weight = BigInt(1e18) - BigInt(token0Weight);

    // Get the data from OKX api of swapping `fromToken` to `toToken`
    const okXSwap = async (chainId, fromToken, toToken, amount, router) => {
        // Generate the signature. Follow steps from:
        // (https://www.okx.com/web3/build/docs/home/rest-authentication)
        const requestPath = `/api/v5/dex/aggregator/swap?chainId=${chainId}&fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&slippage=0.005&userWalletAddress=${router}`;
        const timestamp = new Date().toISOString();
        const secretKey = process.env.OKX_SECRET_KEY;
        const signature = CryptoJS.enc.Base64.stringify(CryptoJS.HmacSHA256(timestamp + "GET" + requestPath, secretKey));

        // These are all necessary for OKX request
        const headers = {
            "OK-ACCESS-KEY": process.env.OKX_KEY,
            "OK-ACCESS-SIGN": signature,
            "OK-ACCESS-TIMESTAMP": timestamp,
            "OK-ACCESS-PASSPHRASE": process.env.OKX_PASSPHRASE,
        };

        // Build the OKX API URL with the request path (https://www.okx.com/web3/build/docs/api/dex-swap)
        const apiUrl = `https://www.okx.com${requestPath}`;

        // Fetch from OKX api
        const swapdata = await fetch(apiUrl, { method: "GET", headers }).then((response) => response.json());

        // Return response data to pass to the router
        return swapdata.data[0].tx.data.toString();
    };

    // Initialize empty array
    let calls = [];

    // Check if token0 is already usdc
    if (tokens[0].toLowerCase() != usdc.toLowerCase()) {
        // weight of token0 in the pool
        const adjustedAmount0 = (BigInt(leverageUsdcAmount) * BigInt(token0Weight)) / BigInt(1e18);

        // Swap USDC to token0 from the LP
        const swapdata = await okXSwap(chainId, usdc, tokens[0], adjustedAmount0.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Check if token1 is already usdc
    if (tokens[1].toLowerCase() != usdc.toLowerCase()) {
        // Weight of toekn1 in the pool
        const adjustedAmount1 = (BigInt(leverageUsdcAmount) * BigInt(token1Weight)) / BigInt(1e18);

        // Swap USDC to token1 from the LP
        const swapdata = await okXSwap(chainId, usdc, tokens[1], adjustedAmount1.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Return bytes array to pass to periphery
    return calls;
};
