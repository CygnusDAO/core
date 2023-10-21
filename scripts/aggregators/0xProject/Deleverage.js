/// For the API calls
const path = require("path");
require("dotenv").config({ path: path.resolve(__dirname, "../../../.env") });

/// @notice Build swaps using 0xProject's Swap API to deleverage
module.exports = async function deleverageSwapdata(chainId, lpToken, usdc, router, deleverageLpAmount, difference) {
    // Get tokens and amounts out given an LP token and amount
    const [tokens, amounts] = await router.getAssetsForShares(lpToken.address, deleverageLpAmount, difference);

    // Perform api call and return the data we need to pass to the CygnusAltair router
    const zeroExProjectSwap = async (chainId, fromToken, toToken, amount, router) => {
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
        const apiUrl = `https://${chain}api.0x.org/swap/v1/quote?sellToken=${fromToken}&buyToken=${toToken}&sellAmount=${amount}&skipValidation=true&takerAddress=${router}&slippagePercentage=0.01&excludedSources=WOOFi`;

        // https://0x.org/docs/0x-swap-api/introduction
        const headers = { "0x-api-key": process.env.ZERO_EX_API_KEY };

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
            /// Make sure we swap less than we have in contract to never revert, cleans dust at the end
            const amount = (BigInt(amounts[i]) * BigInt(0.999999999999e18)) / BigInt(1e18);

            // Call 1inch api
            const swap = await zeroExProjectSwap(chainId, tokens[i], usdc, amount.toString(), router.address);

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
