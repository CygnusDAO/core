// Simple reinvest for borrowable
module.exports = async function ReinvestBorrowable(chainId, fromToken, toToken, amount, borrowable) {
    /**
     *  @notice 1inch swagger API call
     *  @param {Number} chainId - The id of this chain
     *  @param {String} fromToken - The address of the token we are swapping
     *  @param {String} toToken - The address of the token we are receiving
     *  @param {String} amount - The amount of `fromToken` we are swapping
     *  @param {String} router - The address of the router (this is not really needed, but convinient)
     */
    const oneInch = async (chainId, fromToken, toToken, amount, borrowable) => {
        // Fetch 1inch API
        const swapData = await fetch(
            `https://api.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${borrowable}&slippage=0.5&disableEstimate=true&compatibilityMode=true&complexityLevel=3&protocols=POLYGON_QUICKSWAP,POLYGON_CURVE,POLYGON_SUSHISWAP,POLYGON_AAVE_V2,COMETH,POLYGON_MSTABLE,POLYGON_DODO,POLYGON_BALANCER_V2,POLYGON_QUICKSWAP_V3,POLYGON_SWAAP,POLYGON_ELK,POLYGON_QUICKSWAP_V3,POLYGON_UNISWAP_V3,MM_FINANCE,DFYN,POLYDEX_FINANCE,IRONSWAP`
        ).then((response) => response.json())

        return swapData
    }

    // One 1inch api call
    const swapData = await oneInch(chainId, fromToken, toToken, amount, borrowable)

    // Clean data to pass to borrowable
    // bytes4(keccak256("swap(address,(address,address,address,address,uint256,uint256,uint256),bytes,bytes)"));
    const call = swapData.tx.data.toString().replace("0x12aa3caf", "0x")

    return call
}
