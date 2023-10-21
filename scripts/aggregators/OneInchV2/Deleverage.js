/// For the API calls
const path = require("path");
require("dotenv").config({ path: path.resolve(__dirname, "../../../.env") });

/// @notice Build swaps using OneInch's Router to deleverage
module.exports = async function deleverageSwapdata(chainId, lpToken, usdc, router, deleverageLpAmount, difference) {
    // Get tokens and amounts out given an LP token and amount
    const [tokens, amounts] = await router.getAssetsForShares(lpToken.address, deleverageLpAmount, difference);

    // TODO: Remove this
    const protocols =
        "POLYGON_QUICKSWAP,POLYGON_CURVE,POLYGON_SUSHISWAP,POLYGON_AAVE_V2,COMETH,DFYN,POLYGON_MSTABLE,FIREBIRD_FINANCE,ONESWAP,POLYDEX_FINANCE,POLYGON_WAULTSWAP,POLYGON_BALANCER_V2,POLYGON_DODO,POLYGON_DODO_V2,POLYGON_JETSWAP,IRONSWAP,POLYGON_UNIFI,POLYGON_DFX_FINANCE,POLYGON_APESWAP,POLYGON_SAFE_SWAP,POLYCAT_FINANCE,POLYGON_CURVE_V2,POLYGON_UNISWAP_V3,POLYGON_ELK,POLYGON_SYNAPSE,POLYGON_PMM5,POLYGON_PMM6,POLYGON_GRAVITY,POLYGON_PMMX,POLYGON_NERVE,POLYGON_DYSTOPIA,POLYGON_RADIOSHACK,POLYGON_PMM7,POLYGON_MESHSWAP,POLYGON_MAVERICK,POLYGON_PMM4,POLYGON_CLIPPER_COVES,POLYGON_SWAAP,MM_FINANCE,POLYGON_AAVE_V3,POLYGON_QUICKSWAP_V3,POLYGON_ZK_BOB,POLYGON_TRIDENT,POLYGON_DFX_FINANCE_V2,POLYGON_SATIN,POLYGON_SATIN_4POOL,POLYGON_METAVAULT_TRADE,POLYGON_NOMISWAPEPCS,POLYGON_PEARL,POLYGON_SUSHISWAP_V3";

    /// Perform api call and return the data we need to pass to the CygnusAltair router
    const oneInch = async (chainId, fromToken, toToken, amount, router) => {
        // 1inch Api url
        const apiUrl = `${process.env.INCH_API_URL}/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&disableEstimate=true&slippage=0.25&protocols=${protocols}&complexityLevel=3`;

        // Swap data
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.tx.data.toString();
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
            const swap = await oneInch(chainId, tokens[i], usdc, amount, router.address);

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
