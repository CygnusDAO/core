const fs = require("fs");
const path = require("path");
const hre = require("hardhat");
const ethers = hre.ethers;

/**
 *  @notice Build 1inch swaps using AggregationRouterV5 for deleverage. The router has already received
 *          `deleverageLpAmount` from the collateral contract. We must convert this amount to USDC using
 *          multiple swaps.
 */
module.exports = async function deleverageSwapdata(chainId, lpToken, usdc, router, deleverageLpAmount, difference) {
    // Get tokens and amounts out given an LP token and amount
    const [tokens, amounts] = await router.getAssetsForShares(lpToken.address, deleverageLpAmount, difference);

    /// @notice OpenOcean swagger API call
    /// @param {String} fromToken - The address of the token we are swapping
    /// @param {String} toToken - The address of the token we are receiving
    /// @param {String} amount - The amount of `fromToken` we are swapping
    /// @param {String} router - The address of the owner of the USDC (router)
    const openOcean = async (fromToken, toToken, amount, router) => {
        const tokenAbi = fs.readFileSync(path.resolve(__dirname, "../../abis/erc20.json")).toString();
        const _srcToken = new ethers.Contract(fromToken, tokenAbi, ethers.provider);
        const _decimals = await _srcToken.decimals();
        const _scalar = 10 ** +_decimals;
        // const gasPrice = (await ethers.provider.getFeeData()).gasPrice;
        // const _gasPrice = ethers.utils.formatUnits(gasPrice, "gwei");

        amount = (Number(amount) - 1) / +_scalar;

        // Api URL
        const apiUrl = `https://open-api.openocean.finance/v3/${chainId}/swap_quote?inTokenAddress=${fromToken}&outTokenAddress=${toToken}&amount=${amount}&slippage=0.5&gasPrice=${5}&account=${router}`;

        // Fetch from 1inch api
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.data.data;
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
            const swap = await openOcean(tokens[i], usdc, amount, router.address);

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
