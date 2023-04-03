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
            `https://api.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${borrowable}&slippage=0.5&disableEstimate=true&compatibilityMode=true&complexityLevel=3&protocols=ARBITRUM_DODO,ARBITRUM_DODO_V2,ARBITRUM_SUSHISWAP,ARBITRUM_DXSWAP,ARBITRUM_UNISWAP_V3,ARBITRUM_CURVE,ARBITRUM_CURVE_V2,ARBITRUM_GMX,ARBITRUM_SYNAPSE,ARBITRUM_SADDLE,ARBITRUM_AAVE_V3,ARBITRUM_ELK,ARBITRUM_CAMELOT,ARBITRUM_TRADERJOE,ARBITRUM_TRADERJOE_V2,ARBITRUM_SWAPFISH,ARBITRUM_ZYBER,ARBITRUM_ZYBER_STABLE,ARBITRUM_SOLIDLIZARD,ARBITRUM_ZYBER_V3,ARBITRUM_MYCELIUM,ARBITRUM_TRIDENT,ARBITRUM_SHELL_OCEAN`
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
