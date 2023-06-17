// JS
const path = require("path");
// Leverage
const paraswapLeverage = require(path.resolve(__dirname, "./Paraswap/Leverage.js"));
const oneInchLeverage = require(path.resolve(__dirname, "./OneInch/Leverage.js"));
// Deleverage
const paraswapDeleverage = require(path.resolve(__dirname, "./Paraswap/Deleverage.js"));
const oneInchDeleverage = require(path.resolve(__dirname, "./OneInch/Deleverage.js"));

// enum DexAggregator {
//    PARASWAP,
//    ONE_INCH
// }
async function leverageCalldata(dexAggregator, chainId, lpToken, nativeToken, usdcAddress, router, leverageAmount) {
    let leverageCalls;

    switch (dexAggregator) {
        // Paraswap
        case 0:
            leverageCalls = await paraswapLeverage(chainId, lpToken, nativeToken, usdcAddress, router, leverageAmount);
            break;
        case 1:
            leverageCalls = await oneInchLeverage(chainId, lpToken, nativeToken, usdcAddress, router, leverageAmount);
            break;
    }

    return leverageCalls;
}

async function deleverageCalldata(dexAggregator, chainId, lpToken, usdcAddress, router, deleverageLPAmount) {
    let deleverageCalldata;

    switch (dexAggregator) {
        // Paraswap
        case 0:
            deleverageCalldata = await paraswapDeleverage(chainId, lpToken, usdcAddress, router, deleverageLPAmount);
            break;
        case 1:
            deleverageCalldata = await oneInchDeleverage(chainId, lpToken, usdcAddress, router, deleverageLPAmount);
            break;
    }

    return deleverageCalldata;
}

module.exports = {
    leverageCalldata,
    deleverageCalldata,
};
