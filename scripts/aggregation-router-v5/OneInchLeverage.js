const hre = require("hardhat");
const ethers = hre.ethers;

/**
 *  @notice Build 1inch swaps using AggregationRouterV4. Inspired by https://github.com/smye/1inch-swap/
 *
 *          The reason we can calculate what each proceeding swap will be is by decoding the data from the previous
 *          swap for `toTokenAmount`. We then in our periphery contract override the `amount` variable to check for
 *          small differences and pass this to the 1Inch Aggregator.
 */
module.exports = async function SwapCallData(chainId, lpToken, nativeToken, lendingToken, router, leverageUsdcAmount) {
  // Get token0 and token1 for this lp
  const token0 = await lpToken.token0();
  const token1 = await lpToken.token1();

  /**
   *  @notice TokenA and TokenB placeholders, and placeholders for the maximum amount of swaps possible (2)
   */
  let tokenA, tokenB, firstSwap;

  /**
   *  @notice Byte data array to pass to our periphery contract with the api calls from 1inch to complete the swaps
   */
  let calls = [];

  /**
   *  @notice Calculates the optimal swap amount of the tokens to then mint 1 lp token
   *  @notice Single liquidity calculation for UniswapV2 type pools. For UniV3 type pools use the UniV3 SDK.
   *  @param amountA The amount of the token to deposit
   *  @param reservesA The reserves amount of the token in the pool
   *  @param _dexSwapFee The swap fee charged by the dex / 10000 (ie. Uniswap charges 0.3% thus swapFee = 997)
   *  @return The optimal swap amount of tokenA to tokenB to the mint 1 lp token
   */
  const optimalDeposit = (amountA, reservesA, _dexSwapFee) => {
    const a = (1000 + _dexSwapFee) * reservesA;
    const b = amountA * 1000 * reservesA * 4 * _dexSwapFee;
    const c = Math.sqrt(a * a + b);
    const d = 2 * _dexSwapFee;
    const res = (c - a) / d;
    return res;
  };

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
      `https://api.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&slippage=5&disableEstimate=true&compatibilityMode=true&complexityLevel=2&protocols=POLYGON_QUICKSWAP,POLYGON_CURVE,POLYGON_SUSHISWAP,POLYGON_AAVE_V2,COMETH,POLYGON_MSTABLE,POLYGON_DODO,POLYGON_BALANCER_V2,POLYGON_QUICKSWAP_V3,POLYGON_SWAAP,POLYGON_ELK,POLYGON_QUICKSWAP_V3,POLYGON_UNISWAP_V3,MM_FINANCE,DFYN,POLYDEX_FINANCE,IRONSWAP`,
    ).then(response => response.json());

    return swapData;
  };

  //
  // ─────────────────────── 1. Check if token0 or token1 is already USDC
  //
  if (token0 === lendingToken || token1 === lendingToken) {
    // Assign tokenA to USDC and make the swap at the end
    [tokenA, tokenB] = token0 === lendingToken ? [token0, token1] : [token1, token0];
  } else {
    //
    // ───────────────────── 2. Check if token0 or token1 is Native token (WETH)
    //
    if (token0 === nativeToken || token1 === nativeToken) {
      // Make first swap from USDC to Native Token
      firstSwap = await oneInch(chainId, lendingToken, nativeToken, leverageUsdcAmount, router);

      // Add to call array
      calls = [...calls, firstSwap.tx.data.toString().replace("0x12aa3caf", "0x")];

      // Assign tokenA to Native
      [tokenA, tokenB] = token0 === nativeToken ? [token0, token1] : [token1, token0];
    } else {
      //
      // ───────────────────── 3. Neither token are USDC or Native Token, swap all USDC to token0
      //
      // Swap USDC to token0
      firstSwap = await oneInch(chainId, lendingToken, token0, leverageUsdcAmount, router);

      // Add to call array
      calls = [...calls, firstSwap.tx.data.toString().replace("0x12aa3caf", "0x")];

      // Assign tokenA to token0
      [tokenA, tokenB] = [token0, token1];
    }
  }

  // ───────────────────────── 4. Calculate optimal deposit of tokenA to tokenB

  // Get reserves
  const { _reserve0, _reserve1 } = await lpToken.getReserves();
  const reservesA = tokenA === token0 ? _reserve0 : _reserve1;
  const optimalTokenA = optimalDeposit(firstSwap.toTokenAmount, ethers.utils.formatUnits(reservesA, 0), 997);

  // Do the second swap
  const secondSwap = await oneInch(
    chainId,
    tokenA,
    tokenB,
    optimalTokenA.toLocaleString("fullwide", { useGrouping: false }),
    router,
  );

  calls = [...calls, secondSwap.tx.data.toString().replace("0x12aa3caf", "0x")];

  // Return LP Tokens minted by borrowing `leverageUsdcAmount` of USDC
  return calls;
};
