const hre = require("hardhat");
const ethers = hre.ethers;

/// @notice Build swaps using OneInch's Router to leverage. The router has already received
///         `deleverageLpAmount` from the collateral contract. We must convert this amount to USDC to get the best
///         amount possible.
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount) {
    const ext = await router.getAltairExtension(lpToken.address);
    const _router = await ethers.getContractAt("CygnusAltairX", ext);

    // Get tokens and weights
    const { token0, token1, token0Weight, token1Weight } = await _router.getTokenWeights(lpToken.address);

    /// @notice 1inch swagger API call
    /// @param {Number} chainId - The id of this chain
    /// @param {String} fromToken - The address of the token we are swapping
    /// @param {String} toToken - The address of the token we are receiving
    /// @param {String} amount - The amount of `fromToken` we are swapping
    /// @param {String} router - The address of the owner of the USDC (router)
    const oneInch = async (chainId, fromToken, toToken, amount, router) => {
        // 1inch Api call
        const apiUrl = `https://api-cygnusdaofinance.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&toAddress=${router}&disableEstimate=true&compatibilityMode=true&slippage=0.025`;

        // Fetch from 1inch api
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.tx.data.toString().replace("0x12aa3caf", "0x");
    };

    // 0xproject call array to pass to periphery
    let calls = [];

    // Check if token0 is already usdc
    if (token0.toLowerCase() != usdc.toLowerCase()) {
        // weight of token0 in the pool
        const adjustedAmount0 = (BigInt(leverageUsdcAmount) * BigInt(token0Weight)) / BigInt(1e18);

        // Swap USDC to Native
        const swapdata = await oneInch(chainId, usdc, token0, adjustedAmount0.toString(), router.address);

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
        const swapdata = await oneInch(chainId, usdc, token1, adjustedAmount1.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Return bytes array to pass to periphery
    return calls;
};
