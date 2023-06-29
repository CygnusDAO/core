// Paraswap SDK
const { constructSimpleSDK } = require("@paraswap/sdk");
const axios = require("axios");

// JS
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");
const ethers = hre.ethers;

/// @param chainId The chain ID
/// @param collateral The collateral contract object
/// @param harvester The harvester contract object
module.exports = async function reinvest(chainId, terminalToken, harvester) {
    // Construct minimal SDK with fetcher only
    const paraSwapMin = constructSimpleSDK({ chainId: chainId, axios });

    // 1. Get harvester for this collateral (needed to get the optimal token to swap to).
    const harvesterInfo = await harvester.getHarvester(terminalToken.address);

    // 2. Get the cached optimal token. swapping to anything but this token will cause the transaction to revert
    const wantToken = harvesterInfo.wantToken;

    // 3. do a static call to the cygnuscollateral contract get the tokens and amounts harvested
    const { tokens, amounts } = await terminalToken.callStatic.getRewards();

    /// @notice 1inch swagger API call
    /// @param {String} fromToken - The address of the token we are swapping
    /// @param {String} toToken - The address of the token we are receiving
    /// @param {String} amount - The amount of `fromToken` we are swapping
    /// @param {String} router - The address of the owner of the USDC (router)
    const paraswap = async (fromToken, toToken, amount) => {
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
            userAddress: harvester.address,
            excludeDEXS: "WooFiV2",
            includeContractMethods: "multiSwap",
            side: "SELL",
        });

        // Get the tx data from /transactions/ endpoint (https://apiv5.paraswap.io/transactions/:network)
        // Network is already in route since we constructed sdk with chainId
        const swapdata = await paraSwapMin.swap.buildTx({
            srcToken: fromToken,
            destToken: toToken,
            srcAmount: amount,
            slippage: "50",
            priceRoute,
            userAddress: harvester.address,
            ignoreChecks: "true",
            receiver: harvesterInfo.receiver,
            deadline: Math.floor(Date.now() / 1000) + 4503599627370496,
        });

        return swapdata.data;
    };

    // Call array to pass to harvester
    let calls = [];

    // loop through each reward token and call 1inch
    for (let i = 0; i < tokens.length; i++) {
        // if amount harvester is greater than 0 and token is not wanttoken
        if (amounts[i].gt(0) && tokens[i] !== wantToken) {
            // call 1inch api
            const swapdata = await paraswap(tokens[i], wantToken, amounts[i].toString());

            // push to the `calls` array and remove selector of the 1inch swap function
            calls.push(swapdata);
        }
        // if the amount is 0 or the token is wanttoken we pass empty bytes
        else calls.push("0x"); // empty call
    }

    // return the bytes to pass to the collateral and harvester
    return calls;
};
