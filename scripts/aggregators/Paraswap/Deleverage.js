// SDK
const { constructSimpleSDK } = require("@paraswap/sdk");
const axios = require("axios");

/// @notice Build 1inch swaps using AggregationRouterV5 for deleverage. The router has already received
///         `deleverageLpAmount` from the collateral contract. We must convert this amount to USDC using
///         multiple swaps.
///
/// @param {Number} chainId - Network ID for the SDK
/// @param {EthersContract} lpToken - The contract object for the LP Token
/// @param {String} usdc - The address of USDC on this chain
/// @param {EthersContract} router - The contract object for the Cygnus Router
/// @param {BigNumber} deleverageLpAmount - The amount of CygLP being deleveraged
module.exports = async function deleverageSwapdata(chainId, lpToken, usdc, router, deleverageLpAmount) {
    // Construct minimal SDK with fetcher only
    const paraSwapMin = constructSimpleSDK({ chainId: chainId, axios });

    // Get tokens and amounts out given an LP token and amount
    const [tokens, amounts] = await router.getAssetsForShares(lpToken.address, deleverageLpAmount);


    /// @notice Paraswap API call
    /// @param {String} fromToken - The address of the token we are swapping
    /// @param {String} toToken - The address of the token we are receiving
    /// @param {String} amount - The amount of `fromToken` we are swapping
    /// @param {String} router - The address of the owner of the USDC (router)
    const paraswap = async (fromToken, toToken, amount, router) => {
        // Get the price route first from /prices/ endpoint (https://apiv5.paraswap.io/prices)
        const priceRoute = await paraSwapMin.swap.getRate({
            srcToken: fromToken,
            destToken: toToken,
            srcDecimals: 18,
            destDecimals: 6,
            amount: amount,
            userAddress: router,
            excludeDEXS: "WooFiV2",
            side: "SELL",
        });

        // Get the tx data from /transactions/ endpoint (https://apiv5.paraswap.io/transactions/:network)
        // Network is already in route since we constructed sdk with chainId
        const swapdata = await paraSwapMin.swap.buildTx({
            srcToken: fromToken,
            destToken: toToken,
            srcAmount: amount,
            slippage: "60",
            priceRoute,
            userAddress: router,
            ignoreChecks: "true",
            deadline: Math.floor(Date.now() / 1000) + 1000000000,
        });

        return swapdata.data;
    };

    // 1Inch call array to pass to periphery
    let calls = [];

    // We loop through each token and make the api call to sell token `i` to USD
    for (let i = 0; i < tokens.length; i++) {
        // Check if token received is already usdc
        if (tokens[i].toLowerCase() != usdc.toLowerCase()) {
            // Call 1inch api
            const swapdata = await paraswap(tokens[i], usdc, amounts[i].toString(), router.address);

            // Add to calls array
            calls = [...calls, swapdata];
        } else {
            // If usdc pass empty bytes
            calls = [...calls, "0x"];
        }
    }

    // Return bytes array to pass to periphery
    return calls;
};
