const hre = require("hardhat");
const ethers = hre.ethers;

/**
 *  @notice Build 1inch swaps using AggregationRouterV5.
 */
module.exports = async function SwapCallData(chainId, lpToken, nativeToken, lendingToken, router, leverageUsdcAmount) {
  // Get token0 and token1 for this lp
  const token0 = await lpToken.token0();
  const token1 = await lpToken.token1();

  /**
   *  @notice TokenA and TokenB placeholders, and placeholders for the maximum amount of swaps possible (2)
   */
  let firstSwap;

  /**
   *  @notice Byte data array to pass to our periphery contract with the api calls from 1inch to complete the swaps
   */
  let calls = [];

  /**
   *  @notice 1inch swagger API call
   *  @param {Number} chainId - The id of this chain
   *  @param {String} fromToken - The address of the token we are swapping
   *  @param {String} toToken - The address of the token we are receiving
   *  @param {String} amount - The amount of `fromToken` we are swapping
   *  @param {String} router - The address of the router (this is not really needed, but convinient)
   */
  const oneInch = async (chainId, fromToken, toToken, amount, router) => {
    // Fetch 1inch API
    const swapData = await fetch(
      `https://api.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&slippage=0.5&disableEstimate=true&compatibilityMode=true&complexityLevel=3&protocols=POLYGON_QUICKSWAP,POLYGON_CURVE,POLYGON_SUSHISWAP,POLYGON_AAVE_V2,COMETH,POLYGON_MSTABLE,POLYGON_DODO,POLYGON_BALANCER_V2,POLYGON_QUICKSWAP_V3,POLYGON_SWAAP,POLYGON_ELK,POLYGON_QUICKSWAP_V3,POLYGON_UNISWAP_V3,MM_FINANCE,DFYN,POLYDEX_FINANCE,IRONSWAP`,
    ).then(response => response.json());

    return swapData;
  };

  //
  // ─────────────────────── 1. Check if token0 or token1 is already USDC
  //
  if (token0 === lendingToken || token1 === lendingToken) {
    return calls;
  } else {
    //
    // ───────────────────── 2. Check if token0 or token1 is Native token (WETH)
    //
    if (token0 === nativeToken || token1 === nativeToken) {
      // Make first swap from USDC to Native Token
      firstSwap = await oneInch(chainId, lendingToken, nativeToken, leverageUsdcAmount, router);

      // Add to call array
      calls = [...calls, firstSwap.tx.data.toString().replace("0x12aa3caf", "0x")];
    } else {
      //
      // ───────────────────── 3. Neither token are USDC or Native Token, swap all USDC to token0
      //
      // Swap USDC to token0
      firstSwap = await oneInch(chainId, lendingToken, token0, leverageUsdcAmount, router);

      // Add to call array
      calls = [...calls, firstSwap.tx.data.toString().replace("0x12aa3caf", "0x")];
    }
  }

  // ───────────────────────── 4. Calculate optimal deposit of tokenA to tokenB

  // Return LP Tokens minted by borrowing `leverageUsdcAmount` of USDC
  return calls;
};
