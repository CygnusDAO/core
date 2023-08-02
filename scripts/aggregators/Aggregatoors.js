// JS
const path = require("path");
// Leverage
const paraswapLeverage = require(path.resolve(__dirname, "./Paraswap/Leverage.js"));
const oneInchLeverage = require(path.resolve(__dirname, "./OneInchV1/Leverage.js"));
const oneInchLeverageV2 = require(path.resolve(__dirname, "./OneInchV2/Leverage.js"));
const oxProjectLeverage = require(path.resolve(__dirname, "./0xProject/Leverage.js"));
const openOceanLeverageV1 = require(path.resolve(__dirname, "./OpenOceanV1/Leverage.js"));
const openOceanLeverageV2 = require(path.resolve(__dirname, "./OpenOceanV2/Leverage.js"));

// Deleverage
const paraswapDeleverage = require(path.resolve(__dirname, "./Paraswap/Deleverage.js"));
const oneInchDeleverage = require(path.resolve(__dirname, "./OneInchV1/Deleverage.js"));
const oneInchDeleverageV2 = require(path.resolve(__dirname, "./OneInchV2/Deleverage.js"));
const oxProjectDeleverage = require(path.resolve(__dirname, "./0xProject/Deleverage.js"));
const openOceanDeleverageV1 = require(path.resolve(__dirname, "./OpenOceanV1/Deleverage.js"));
const openOceanDeleverageV2 = require(path.resolve(__dirname, "./OpenOceanV2/Deleverage.js"));

// enum DexAggregator {
//    PARASWAP,
//    ONE_INCH_LEGACY,
//    ONE_INCH_V@,
//    0xPROJECT
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
        case 2:
            leverageCalls = await oneInchLeverageV2(chainId, lpToken, nativeToken, usdcAddress, router, leverageAmount);
            break;
        case 3:
            leverageCalls = await oxProjectLeverage(chainId, lpToken, nativeToken, usdcAddress, router, leverageAmount);
            break;
        case 4:
            leverageCalls = await openOceanLeverageV1(chainId, lpToken, nativeToken, usdcAddress, router, leverageAmount);
            break;
        case 5:
            leverageCalls = await openOceanLeverageV2(chainId, lpToken, nativeToken, usdcAddress, router, leverageAmount);
            break;
    }

    return leverageCalls;
}

async function deleverageCalldata(dexAggregator, chainId, lpToken, usdcAddress, router, deleverageLPAmount, difference) {
    let deleverageCalldata;

    switch (dexAggregator) {
        // Paraswap
        case 0:
            deleverageCalldata = await paraswapDeleverage(chainId, lpToken, usdcAddress, router, deleverageLPAmount, difference);
            break;
        case 1:
            deleverageCalldata = await oneInchDeleverage(chainId, lpToken, usdcAddress, router, deleverageLPAmount, difference);
            break;
        case 2:
            deleverageCalldata = await oneInchDeleverageV2(chainId, lpToken, usdcAddress, router, deleverageLPAmount, difference);
            break;
        case 3:
            deleverageCalldata = await oxProjectDeleverage(chainId, lpToken, usdcAddress, router, deleverageLPAmount, difference);
            break;
        case 4:
            deleverageCalldata = await openOceanDeleverageV1(chainId, lpToken, usdcAddress, router, deleverageLPAmount, difference);
            break;
        case 5:
            deleverageCalldata = await openOceanDeleverageV2(chainId, lpToken, usdcAddress, router, deleverageLPAmount, difference);
            break;
    }

    return deleverageCalldata;
}

module.exports = {
    leverageCalldata,
    deleverageCalldata,
};
