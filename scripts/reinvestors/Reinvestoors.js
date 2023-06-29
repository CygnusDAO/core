// JS
const path = require("path");
// Reinvest
const paraswapReinvest = require(path.resolve(__dirname, "./Paraswap/Reinvest.js"));
const oneInchReinvestV1 = require(path.resolve(__dirname, "./OneInchV1/Reinvest.js"));

/// @param chainId The chain ID for the 1inch swap
/// @param terminalToken The collateral or borrowable contract object
/// @param harvester The harvester contract object
async function reinvestCalldata(dexAggregator, chainId, terminalToken, harvester) {
    // Reinvest calldata
    let reinvestCalls;

    switch (dexAggregator) {
        // Paraswap
        case 0:
            reinvestCalls = await paraswapReinvest(chainId, terminalToken, harvester);
            break;
        // 1Inch
        case 1:
            reinvestCalls = await oneInchReinvestV1(chainId, terminalToken, harvester);
            break;
    }

    return reinvestCalls;
}

module.exports = {
    reinvestCalldata,
};
