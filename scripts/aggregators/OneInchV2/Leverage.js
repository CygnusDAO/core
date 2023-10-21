/// For the API calls
const path = require("path");
require("dotenv").config({ path: path.resolve(__dirname, "../../../.env") });

/// @notice Build swaps using OneInch's Router to convert USDC to LP
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount, nebula) {
    // Get LP info
    const { tokens, reservesUsd } = await nebula.lpTokenInfo(lpToken.address);

    // Weight of each token
    const tvl = reservesUsd[0].add(reservesUsd[1]);
    const token0Weight = reservesUsd[0].mul(BigInt(1e18)).div(tvl);
    const token1Weight = BigInt(1e18) - BigInt(token0Weight);

    // TODO: Remove this
    const protocols =
        "POLYGON_QUICKSWAP,POLYGON_CURVE,POLYGON_SUSHISWAP,POLYGON_AAVE_V2,COMETH,DFYN,POLYGON_MSTABLE,FIREBIRD_FINANCE,ONESWAP,POLYDEX_FINANCE,POLYGON_WAULTSWAP,POLYGON_BALANCER_V2,POLYGON_DODO,POLYGON_DODO_V2,POLYGON_JETSWAP,IRONSWAP,POLYGON_UNIFI,POLYGON_DFX_FINANCE,POLYGON_APESWAP,POLYGON_SAFE_SWAP,POLYCAT_FINANCE,POLYGON_CURVE_V2,POLYGON_UNISWAP_V3,POLYGON_ELK,POLYGON_SYNAPSE,POLYGON_PMM5,POLYGON_PMM6,POLYGON_GRAVITY,POLYGON_PMMX,POLYGON_NERVE,POLYGON_DYSTOPIA,POLYGON_RADIOSHACK,POLYGON_PMM7,POLYGON_MESHSWAP,POLYGON_MAVERICK,POLYGON_PMM4,POLYGON_CLIPPER_COVES,POLYGON_SWAAP,MM_FINANCE,POLYGON_AAVE_V3,POLYGON_QUICKSWAP_V3,POLYGON_ZK_BOB,POLYGON_TRIDENT,POLYGON_DFX_FINANCE_V2,POLYGON_SATIN,POLYGON_SATIN_4POOL,POLYGON_METAVAULT_TRADE,POLYGON_NOMISWAPEPCS,POLYGON_PEARL,POLYGON_SUSHISWAP_V3";


    // Perform api call and return the data we need to pass to the CygnusAltair router
    const oneInch = async (chainId, fromToken, toToken, amount, router) => {
        // 1inch Api call
        const apiUrl = `${process.env.INCH_API_URL}/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&disableEstimate=true&slippage=0.25&complexityLevel=3&protocols=${protocols}`;

        // Fetch from 1inch api
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response
        return swapdata.tx.data.toString();
    };

    /// Initialize calldata array
    let calls = [];

    // Check if token0 is already usdc
    if (tokens[0].toLowerCase() != usdc.toLowerCase()) {
        // Swap USDC to token0 according to token0 weight
        const adjustedAmount0 = (BigInt(leverageUsdcAmount) * BigInt(token0Weight)) / BigInt(1e18);

        const swapdata = await oneInch(chainId, usdc, tokens[0], adjustedAmount0.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    // Check if token1 is already usdc
    if (tokens[1].toLowerCase() != usdc.toLowerCase()) {
        // Swap USDC to token1 according to token1 weight
        const adjustedAmount1 = (BigInt(leverageUsdcAmount) * BigInt(token1Weight)) / BigInt(1e18);

        const swapdata = await oneInch(chainId, usdc, tokens[1], adjustedAmount1.toString(), router.address);

        // Add to call array
        calls = [...calls, swapdata];
    }
    // Add empty call array
    else calls = [...calls, "0x"];

    return calls;
};

/// const protocols = "POLYGON_QUICKSWAP,POLYGON_CURVE,POLYGON_SUSHISWAP,POLYGON_AAVE_V2,COMETH,DFYN,POLYGON_MSTABLE,FIREBIRD_FINANCE,ONESWAP,POLYDEX_FINANCE,POLYGON_WAULTSWAP,POLYGON_BALANCER_V2,POLYGON_DODO,POLYGON_DODO_V2,POLYGON_JETSWAP,IRONSWAP,POLYGON_UNIFI,POLYGON_DFX_FINANCE,POLYGON_APESWAP,POLYGON_SAFE_SWAP,POLYCAT_FINANCE,POLYGON_CURVE_V2,POLYGON_UNISWAP_V3,POLYGON_ELK,POLYGON_SYNAPSE,POLYGON_PMM5,POLYGON_PMM6,POLYGON_GRAVITY,POLYGON_PMMX,POLYGON_NERVE,POLYGON_DYSTOPIA,POLYGON_RADIOSHACK,POLYGON_PMM7,POLYGON_MESHSWAP,POLYGON_MAVERICK,POLYGON_PMM4,POLYGON_CLIPPER_COVES,POLYGON_SWAAP,MM_FINANCE,POLYGON_AAVE_V3,POLYGON_QUICKSWAP_V3,POLYGON_ZK_BOB,POLYGON_TRIDENT,POLYGON_DFX_FINANCE_V2,POLYGON_SATIN,POLYGON_SATIN_4POOL,POLYGON_METAVAULT_TRADE,POLYGON_NOMISWAPEPCS,POLYGON_PEARL,POLYGON_SUSHISWAP_V3";
