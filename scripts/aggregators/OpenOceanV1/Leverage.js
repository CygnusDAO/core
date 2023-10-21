const fs = require("fs");
const path = require("path");
// JS
const hre = require("hardhat");
const ethers = hre.ethers;

/// @notice Build swaps using OpenOcean's Router to convert USDC to LP
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount, nebula) {
    // Get LP info
    const { tokens, reservesUsd } = await nebula.lpTokenInfo(lpToken.address);

    // TVL
    const tvl = reservesUsd[0].add(reservesUsd[1]);

    // Weight of each token
    const token0Weight = reservesUsd[0].mul(BigInt(1e18)).div(tvl);
    const token1Weight = BigInt(1e18) - BigInt(token0Weight);

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

        amount = +amount / +_scalar - 1;

        // Api URL
        const apiUrl = `https://open-api.openocean.finance/v3/${chainId}/swap_quote?inTokenAddress=${fromToken}&outTokenAddress=${toToken}&amount=${amount}&slippage=0.3&gasPrice=${5}&account=${router}&disabledDexIds=33`;

        // Fetch from 1inch api
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.data.data.toString().replace("0x90411a32", "0x");
    };

    // 0xproject call array to pass to periphery
    let calls = [];

    // Check if token0 is already usdc
    if (tokens[0].toLowerCase() != usdc.toLowerCase()) {
        // weight of token0 in the pool
        const adjustedAmount0 = (BigInt(leverageUsdcAmount) * BigInt(token0Weight)) / BigInt(1e18);

        // Swap USDC to Native
        const swapdata = await openOcean(usdc, tokens[0], adjustedAmount0.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Check if token1 is already usdc
    if (tokens[1].toLowerCase() != usdc.toLowerCase()) {
        // Weight of toekn1 in the pool
        const adjustedAmount1 = (BigInt(leverageUsdcAmount) * BigInt(token1Weight)) / BigInt(1e18);

        // Swap USDC to Native
        const swapdata = await openOcean(usdc, tokens[1], adjustedAmount1.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Return bytes array to pass to periphery
    return calls;
};
