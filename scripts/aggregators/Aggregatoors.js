const path = require("path");

const leverageModules = {
    0: require(path.resolve(__dirname, "./Paraswap/Leverage.js")),
    1: require(path.resolve(__dirname, "./OneInchV1/Leverage.js")),
    2: require(path.resolve(__dirname, "./OneInchV2/Leverage.js")),
    3: require(path.resolve(__dirname, "./0xProject/Leverage.js")),
    4: require(path.resolve(__dirname, "./OpenOceanV1/Leverage.js")),
    5: require(path.resolve(__dirname, "./OpenOceanV2/Leverage.js")),
    6: require(path.resolve(__dirname, "./Okx/Leverage.js")),
    7: ["0x", "0x"], // Perform the leverage on-chain using UniswapV3
};

const deleverageModules = {
    0: require(path.resolve(__dirname, "./Paraswap/Deleverage.js")),
    1: require(path.resolve(__dirname, "./OneInchV1/Deleverage.js")),
    2: require(path.resolve(__dirname, "./OneInchV2/Deleverage.js")),
    3: require(path.resolve(__dirname, "./0xProject/Deleverage.js")),
    4: require(path.resolve(__dirname, "./OpenOceanV1/Deleverage.js")),
    5: require(path.resolve(__dirname, "./OpenOceanV2/Deleverage.js")),
    6: require(path.resolve(__dirname, "./Okx/Deleverage.js")),
    7: ["0x", "0x"], // Perform the leverage on-chain using UniswapV3
};

// Returns array of calldata to pass to the aggregator router converting USDC to LP assets
async function leverageCalldata(dexAggregator, chainId, lpToken, nativeToken, usdcAddress, router, leverageAmount, nebula) {
    // Escape in case of Uniswap, no calldata
    if (dexAggregator == 7) return ["0x", "0x"];

    // Get aggregator's logic
    const leverageFunction = leverageModules[dexAggregator];

    // Return calldata using the `dexAggregator`
    return await leverageFunction(chainId, lpToken, nativeToken, usdcAddress, router, leverageAmount, nebula);
}

// Returns array of calldata to pass to the aggregator router converting LP assets to USDC
async function deleverageCalldata(dexAggregator, chainId, lpToken, usdcAddress, router, deleverageLPAmount, difference) {
    // Escape in case of Uniswap, no calldata
    if (dexAggregator == 7) return ["0x", "0x"];

    // Get aggregator's logic
    const deleverageFunction = deleverageModules[dexAggregator];

    // Return calldata using the `dexAggregator`
    return await deleverageFunction(chainId, lpToken, usdcAddress, router, deleverageLPAmount, difference);
}

module.exports = {
    leverageCalldata,
    deleverageCalldata,
};
