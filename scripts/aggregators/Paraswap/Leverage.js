const { constructSimpleSDK } = require("@paraswap/sdk");
const axios = require("axios");

// JS
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");
const ethers = hre.ethers;

/// @notice Build swaps using Paraswap's Augustus Swapper to leverage. The router has already received
///         `deleverageLpAmount` from the collateral contract. We must convert this amount to USDC to get the best
///         amount possible.
module.exports = async function paraswapLeverage(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount) {
    // Construct minimal SDK with fetcher only
    const paraSwapMin = constructSimpleSDK({ chainId: chainId, axios });

    // Get token0 and token1 for this lp
    const token0 = await lpToken.token0();
    const token1 = await lpToken.token1();

    /// @notice 1inch swagger API call
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
            srcDecimals: _srcDecimals,
            destDecimals: _dstDecimals,
            destToken: toToken,
            srcAmount: amount,
            slippage: "30",
            priceRoute,
            userAddress: router,
            ignoreChecks: "true",
            receiver: router,
            deadline: Math.floor(Date.now() / 1000) + 4503599627370496,
        });

        return swapdata.data;
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
            const swapdata = await paraswap(usdc, nativeToken, leverageUsdcAmount.toString(), router.address);

            // Add to call array
            calls = [...calls, swapdata];
        }
        // Swap to token0
        else {
            // Swap USDC to token0
            const swapdata = await paraswap(usdc, token0, leverageUsdcAmount.toString(), router.address);

            // Add to call array
            calls = [...calls, swapdata];
        }
    }

    // Return bytes array to pass to periphery
    return calls;
};
