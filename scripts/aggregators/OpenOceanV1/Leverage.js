const fs = require("fs");
const path = require("path");
// JS
const hre = require("hardhat");
const ethers = hre.ethers;

/// @notice Build swaps using OpenOceans's Exchange router. The router has already received
///         `deleverageLpAmount` from the collateral contract. We must convert this amount to USDC to get the best
///         amount possible.
module.exports = async function openOceanLeverage(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount) {
    const ext = await router.getAltairExtension(lpToken.address);
    const _router = await ethers.getContractAt("CygnusAltairX", ext);

    // Get tokens and weights
    const { token0, token1, token0Weight, token1Weight } = await _router.getTokenWeights(lpToken.address);

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
        //const gasPrice = (await ethers.provider.getFeeData()).gasPrice;
        //const _gasPrice = ethers.utils.formatUnits(gasPrice, "gwei");

        amount = +amount / +_scalar;

        // Api URL
        const apiUrl = `https://open-api.openocean.finance/v3/${chainId}/swap_quote?inTokenAddress=${fromToken}&outTokenAddress=${toToken}&amount=${amount}&slippage=0.1&gasPrice=${5}&account=${router}&disabledDexIds=33`;

        // Fetch from 1inch api
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.data.data.toString().replace("0x90411a32", "0x");
    };

    // 0xproject call array to pass to periphery
    let calls = [];

    // Check if token0 is already usdc
    if (token0.toLowerCase() != usdc.toLowerCase()) {
        // weight of token0 in the pool
        const adjustedAmount0 = (BigInt(leverageUsdcAmount) * BigInt(token0Weight)) / BigInt(1e18);

        // Swap USDC to Native
        const swapdata = await openOcean(usdc, token0, adjustedAmount0.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Check if token1 is already usdc
    if (token1.toLowerCase() != usdc.toLowerCase()) {
        // Weight of toekn1 in the pool
        const adjustedAmount1 = (BigInt(leverageUsdcAmount) * BigInt(token1Weight)) / BigInt(1e18);

        // Swap USDC to Native
        const swapdata = await openOcean(usdc, token1, adjustedAmount1.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Return bytes array to pass to periphery
    return calls;
};
