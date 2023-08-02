const hre = require("hardhat");
const ethers = hre.ethers;

/// @notice Build swaps using 0xProject's Swap API to leverage.
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount) {
    const ext = await router.getAltairExtension(lpToken.address);
    const _router = await ethers.getContractAt("CygnusAltairX", ext);

    // Get tokens and weights
    const { token0, token1, token0Weight, token1Weight } = await _router.getTokenWeights(lpToken.address);

    /// @notice 0xProject swap api call
    /// @param {Number} chainId - The id of this chain
    /// @param {String} fromToken - The address of the token we are swapping
    /// @param {String} toToken - The address of the token we are receiving
    /// @param {String} amount - The amount of `fromToken` we are swapping
    /// @param {String} router - The address of the owner of the USDC (router)
    const _0xProjectSwap = async (chainId, fromToken, toToken, amount, router) => {
        // The API uses chain name instead of chainID so ocnvert
        let chain;

        // update chain
        switch (chainId) {
            case 1:
                chain = "";
                break;
            case 137:
                chain = "polygon";
                break;
            case 10:
                chain = "optimism";
                break;
            case 56:
                chain = "bsc";
                break;
            case 42161:
                chain = "arbitrum";
                break;
        }

        // 0xProject Api call
        const apiUrl = `https://${chain}.api.0x.org/swap/v1/quote?sellToken=${fromToken}&buyToken=${toToken}&sellAmount=${amount}&slippagePercentage=0.01&skipValidation=true&takerAddress=${router}`;

        console.log(apiUrl);

        const headers = {
            "0x-api-key": "02a575e5-685a-464d-98d4-71431f79489a",
        };

        // Fetch from 0xProject api
        const swapdata = await fetch(apiUrl, { headers }).then((response) => response.json());

        // Return response
        return swapdata.data.toString();
    };

    // 0xproject call array to pass to periphery
    let calls = [];

    // Check if token0 is already usdc
    if (token0.toLowerCase() != usdc.toLowerCase()) {
        // weight of token0 in the pool
        const adjustedAmount0 = (BigInt(leverageUsdcAmount) * BigInt(token0Weight)) / BigInt(1e18);

        // Swap USDC to Native
        const swapdata = await _0xProjectSwap(chainId, usdc, token0, adjustedAmount0.toString(), router.address);

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
        const swapdata = await _0xProjectSwap(chainId, usdc, token1, adjustedAmount1.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Return bytes array to pass to periphery
    return calls;
};
