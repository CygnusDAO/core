const hre = require("hardhat")
const ethers = hre.ethers

const fs = require("fs")
const path = require("path")

/**
 *  @notice Build 1inch swaps using AggregationRouterV4. Inspired by https://github.com/smye/1inch-swap/
 *
 *          The reason we can calculate what each proceeding swap will be is by decoding the data from the previous
 *          swap for `toTokenAmount`. We then in our periphery contract override the `amount` variable to check for
 *          small differences and pass this to the 1Inch Aggregator.
 *
 */
module.exports = async function SwapCallData(
    chainId,
    lpToken,
    nativeToken,
    usdc,
    router,
    deleverageLpAmount,
    borrower
) {
    // Create contracts for token0 and token1
    const token0 = new ethers.Contract(
        await lpToken.token0(),
        fs.readFileSync(path.resolve(__dirname, "../abis/dai.json")).toString(),
        ethers.provider
    )
    const token1 = new ethers.Contract(
        await lpToken.token1(),
        fs.readFileSync(path.resolve(__dirname, "../abis/dai.json")).toString(),
        ethers.provider
    )

    const one = ethers.utils.parseUnits("1", 18)

    /**
     * @notice Calculates the amount of Token0 and Token1 we get after burning, used to build the 1Inch call
     */
    async function burnAmounts() {
        // Get total Supply of the liquidity tokens
        const totalSupply = await lpToken.totalSupply()

        // Get the pool's balance of token0 and token1
        const balanceToken0 = await token0.balanceOf(lpToken.address)
        const balanceToken1 = await token1.balanceOf(lpToken.address)

        const amount = ethers.utils.parseUnits(deleverageLpAmount.toString(), 18)

        // Calculate the amount we would get of each token respectively
        const amountA = amount.mul(balanceToken0).div(one).div(totalSupply)
        const amountB = amount.mul(balanceToken1).div(one).div(totalSupply)

        // Return amounts
        return [amountA, amountB]
    }

    // Get burn amounts if we deleverage `deleverageLpAmount`
    const [burnAmountToken0, burnAmountToken1] = await burnAmounts()

    // First and last swap calls
    let firstSwap, lastSwap

    // Calls array that we pass to the smart contract
    let calls = []

    /**
     *  @notice 1inch swagger API call
     *  @param {Number} chainId - The id of this chain
     *  @param {String} fromToken - The address of the token we are swapping
     *  @param {String} toToken - The address of the token we are receiving
     *  @param {String} amount - The amount of `fromToken` we are swapping
     *  @param {String} router - The address of the router (this is not really needed, but convinient)
     */
    const oneInch = async (chainId, fromToken, toToken, amount, router) => {
        const swapData = await fetch(
            `https://api.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&slippage=0.5&disableEstimate=true&compatibilityMode=true&complexityLevel=3&protocols=POLYGON_QUICKSWAP,POLYGON_CURVE,POLYGON_SUSHISWAP,POLYGON_AAVE_V2,COMETH,POLYGON_MSTABLE,POLYGON_DODO,POLYGON_BALANCER_V2,POLYGON_QUICKSWAP_V3,POLYGON_SWAAP,POLYGON_ELK,POLYGON_QUICKSWAP_V3,POLYGON_UNISWAP_V3,MM_FINANCE,DFYN,POLYDEX_FINANCE,IRONSWAP`
        ).then((response) => response.json())

        return swapData
    }

    // Simulate the operations the smart contract performs

    //
    // ─────────────────────── 1. Check if token0 or token1 is already USDC
    //
    if (token0.address === usdc || token1.address === usdc) {
        if (token0.address === usdc) {
            // Swap token1 to usdc
            firstSwap = await oneInch(chainId, token1.address, usdc, burnAmountToken1, router)

            // Calls with second empty
            calls = [...calls, firstSwap.tx.data.toString().replace("0x12aa3caf", "0x"), "0x"]
        } else {
            // Swap token0 to usdc
            firstSwap = await oneInch(chainId, token0.address, usdc, burnAmountToken0, router)

            // Calls with second empty
            calls = [...calls, firstSwap.tx.data.toString().replace("0x12aa3caf", "0x"), "0x"]
        }
    } else {
        //
        // ─────────────────────── 2. Swap both to USDC
        //
        // Swap token0 to USDC
        firstSwap = await oneInch(chainId, token0.address, usdc, burnAmountToken0, router)

        // Swap token1 to USDC
        lastSwap = await oneInch(chainId, token1.address, usdc, burnAmountToken1, router)
        // Build call array replacing the swap tx data
        calls = [
            ...calls,
            firstSwap.tx.data.toString().replace("0x12aa3caf", "0x"),
            lastSwap.tx.data.toString().replace("0x12aa3caf", "0x"),
        ]
    }

    return calls
}
