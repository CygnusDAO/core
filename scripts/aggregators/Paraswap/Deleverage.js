// SDK
const { constructSimpleSDK } = require("@paraswap/sdk");
const axios = require("axios");

// JS
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");
const ethers = hre.ethers;

/// @notice Build 1inch swaps using AggregationRouterV5 for deleverage. The router has already received
///         `deleverageLpAmount` from the collateral contract. We must convert this amount to USDC using
///         multiple swaps.
///
/// @param {Number} chainId - Network ID for the SDK
/// @param {EthersContract} lpToken - The contract object for the LP Token
/// @param {String} usdc - The address of USDC on this chain
/// @param {EthersContract} router - The contract object for the Cygnus Router
/// @param {BigNumber} deleverageLpAmount - The amount of CygLP being deleveraged
module.exports = async function deleverageSwapdata(chainId, lpToken, usdc, router, deleverageLpAmount, difference) {
    // Construct minimal SDK with fetcher only
    const paraSwapMin = constructSimpleSDK({ chainId: chainId, axios });

    // Get tokens and amounts out given an LP token and amount
    const [tokens, amounts] = await router.getAssetsForShares(lpToken.address, deleverageLpAmount, difference);

    /// @notice Paraswap API call
    /// @param {String} fromToken - The address of the token we are swapping
    /// @param {String} toToken - The address of the token we are receiving
    /// @param {String} amount - The amount of `fromToken` we are swapping
    /// @param {String} router - The address of the owner of the USDC (router)
    const paraswap = async (fromToken, toToken, amount, router) => {
        // Get decimals
        const tokenAbi = fs.readFileSync(path.resolve(__dirname, "../../abis/erc20.json")).toString();
        const _srcToken = new ethers.Contract(fromToken, tokenAbi, ethers.provider);
        const _dstToken = new ethers.Contract(toToken, tokenAbi, ethers.provider);
        const _srcDecimals = await _srcToken.decimals();
        const _dstDecimals = await _dstToken.decimals();

        // Get the price route first from /prices/ endpoint (https://apiv5.paraswap.io/prices)
        const priceRoute = await paraSwapMin.swap.getRate({
            srcToken: fromToken,
            destToken: toToken,
            srcDecimals: _srcDecimals,
            destDecimals: _dstDecimals,
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
            srcDecimals: _srcDecimals,
            destDecimals: _dstDecimals,
            srcAmount: amount,
            slippage: "100",
            priceRoute,
            userAddress: router,
            ignoreChecks: "true",
            deadline: Math.floor(Date.now() / 1000) + 900000000000000,
        });

        return swapdata.data;
    };

    // 1Inch call array to pass to periphery
    let calls = [];

    // We loop through each token and make the api call to sell token `i` to USD
    for (let i = 0; i < tokens.length; i++) {
        // Check if token received is already usdc
        if (tokens[i].toLowerCase() != usdc.toLowerCase()) {
            const amount = (BigInt(amounts[i]) * BigInt(0.999999999999e18)) / BigInt(1e18);

            // Call 1inch api
            const swapdata = await paraswap(tokens[i], usdc, amount.toString(), router.address);

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
