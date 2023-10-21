const fs = require("fs");
const path = require("path");
const hre = require("hardhat");
const ethers = hre.ethers;

/// TODO: Dex ID by chain
/// @notice Build swaps using OpenOcean's Router to convert LP to USDC
/// @notice This is a legacy method which disables dex id so we don't have to reduce amounts[i]
module.exports = async function deleverageSwapdata(chainId, lpToken, usdc, router, deleverageLpAmount, difference) {
    // Get tokens and amounts out given an LP token and amount
    const [tokens, amounts] = await router.getAssetsForShares(lpToken.address, deleverageLpAmount, difference);

    const openOcean = async (fromToken, toToken, amount, router) => {
        const tokenAbi = fs.readFileSync(path.resolve(__dirname, "../../abis/erc20.json")).toString();
        const _srcToken = new ethers.Contract(fromToken, tokenAbi, ethers.provider);
        const _decimals = await _srcToken.decimals();
        const _scalar = 10 ** +_decimals;
        // const gasPrice = (await ethers.provider.getFeeData()).gasPrice;
        // const _gasPrice = ethers.utils.formatUnits(gasPrice, "gwei");

        amount = +amount / +_scalar - 1;

        // Api URL
        const apiUrl = `https://open-api.openocean.finance/v3/${chainId}/swap_quote?inTokenAddress=${fromToken}&outTokenAddress=${toToken}&amount=${amount}&slippage=5&gasPrice=${5}&account=${router}&disabledDexIds=33`;

        // Fetch from 1inch api
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.data.data.toString().replace("0x90411a32", "0x");
    };

    // 1Inch call array to pass to periphery
    let calls = [];

    // We loop through each token and make the api call to sell token `i` to USD
    for (let i = 0; i < tokens.length; i++) {
        // Check if token received is already usdc
        if (tokens[i].toLowerCase() != usdc.toLowerCase()) {
            // Call 1inch api
            const swap = await openOcean(tokens[i], usdc, amounts[i], router.address);

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
