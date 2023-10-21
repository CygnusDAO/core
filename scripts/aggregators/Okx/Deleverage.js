const path = require("path");
const CryptoJS = require("crypto-js");
require("dotenv").config({ path: path.resolve(__dirname, "../../../.env") });

/**
 *  @notice Build OKX swaps using AggregationRouterV5 for deleverage. The router has already received
 *          `deleverageLpAmount` from the collateral contract. We must convert this amount to USDC using
 *          multiple swaps.
 */
module.exports = async function deleverageSwapdata(chainId, lpToken, usdc, router, deleverageLpAmount, difference) {
    // Get tokens and amounts out given an LP token and amount
    const [tokens, amounts] = await router.getAssetsForShares(lpToken.address, deleverageLpAmount, difference);

    // Build calldata
    const okXSwap = async (chainId, fromToken, toToken, amount, router) => {
        // Generate the signature (https://www.okx.com/web3/build/docs/home/rest-authentication)
        const requestPath = `/api/v5/dex/aggregator/swap?chainId=${chainId}&fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&slippage=0.005&userWalletAddress=${router}`;
        const timestamp = new Date().toISOString();
        const SecretKey = process.env.OKX_SECRET_KEY;
        const signature = CryptoJS.enc.Base64.stringify(CryptoJS.HmacSHA256(timestamp + "GET" + requestPath, SecretKey));

        // This is necessary for OKX request
        const headers = {
            "OK-ACCESS-KEY": process.env.OKX_KEY,
            "OK-ACCESS-SIGN": signature,
            "OK-ACCESS-TIMESTAMP": timestamp,
            "OK-ACCESS-PASSPHRASE": process.env.OKX_PASSPHRASE,
        };

        // OKX API URL (https://www.okx.com/web3/build/docs/api/dex-swap)
        const apiUrl = `https://www.okx.com${requestPath}`;

        // Fetch from OKX api
        const swapdata = await fetch(apiUrl, { method: "GET", headers }).then((response) => response.json());

        // Return response data to pass to the router
        return swapdata.data[0].tx.data.toString();
    };

    // 1Inch call array to pass to periphery
    let calls = [];

    // We loop through each token and make the api call to sell token `i` to USD
    for (let i = 0; i < tokens.length; i++) {
        // Check if token received is already usdc
        if (tokens[i].toLowerCase() != usdc.toLowerCase()) {
            /// Make sure we swap less than we have in contract
            const amount = (BigInt(amounts[i]) * BigInt(0.999999999999e18)) / BigInt(1e18);

            // Call 1inch api
            const swap = await okXSwap(chainId, tokens[i], usdc, amount.toString(), router.address);

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
