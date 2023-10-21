/// For the API calls
const path = require("path");
require("dotenv").config({ path: path.resolve(__dirname, "../../../.env") });

/// @notice Build swaps using OneInch's Router to convert LP to USDC
/// @notice This is a legacy method which uses `compatibilityMode=true` so we don't have to reduce amounts[i]
module.exports = async function deleverageSwapdata(chainId, lpToken, usdc, router, deleverageLpAmount, difference) {
    // Get tokens and amounts out given an LP token and amount
    const [tokens, amounts] = await router.getAssetsForShares(lpToken.address, deleverageLpAmount, difference);

    /// Perform api call and return the data we need to pass to the CygnusAltair router
    const oneInch = async (chainId, fromToken, toToken, amount, router) => {
        // 1inch Api url
        const apiUrl = `${process.env.INCH_API_URL}/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&disableEstimate=true&compatibilityMode=true&slippage=0.3`;

        // Swap data
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.tx.data.toString().replace("0x12aa3caf", "0x");
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
