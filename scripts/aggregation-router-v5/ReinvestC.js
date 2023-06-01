/**
 *  @notice Simple reinvest for collateral
 *  @param chainId The chain ID for the 1inch swap
 *  @param collateral The collateral contract object
 *  @param harvester The harvester contract object
 */
module.exports = async function reinvestCollateral(chainId, collateral, harvester) {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
                                      reinvest collateral rewards
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice make a 1inch api call
     *  @param {string} fromToken - the address of the token being swapped
     *  @param {string} toToken - the address of the token being received
     *  @param {string} amount - the amount of fromToken being swapped
     *  @returns {object} swapdata - data from the 1inch swap
     */
    const oneInchSwap = async (fromToken, toToken, amount) => {
        // api call
        const apiurl = `https://api.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${harvester.address}&slippage=10&disableEstimate=true&compatibilityMode=true&protocols=OPTIMISM_UNISWAP_V3,OPTIMISM_CURVE,OPTIMISM_BALANCER_V2,OPTIMISM_VELODROME,OPTIMISM_AAVE_V3&complexityLevel=1`

        // fetch data
        const swapdata = await fetch(apiurl).then((response) => response.json())

        // return 1inch bytes
        return swapdata
    }

    //
    // 1. Get harvester for this collateral (needed to get the optimal token to swap to).
    //
    const harvesterInfo = await harvester.getHarvester(collateral.address)

    //
    // 2. Get the cached optimal token. swapping to anything but this token will cause the transaction to revert
    //
    const wantToken = harvesterInfo.wantToken

    //
    // 3. do a static call to the cygnuscollateral contract get the tokens and amounts harvested
    //
    const { tokens, amounts } = await collateral.callStatic.getRewards()

    console.log("AMOUNT HARVESTED: %s", amounts[0])
    //
    // 4. create the call array of 1inch data which we will pass to the harvester
    //
    let calls = []

    // loop through each reward token and call 1inch
    for (let i = 0; i < tokens.length; i++) {
        // if amount harvester is greater than 0 and token is not wanttoken
        if (amounts[i].gt(0) && tokens[i] !== wantToken) {
            // call 1inch api
            const swapdata = await oneInchSwap(tokens[i], wantToken, amounts[i])

            // push to the `calls` array and remove selector of the 1inch swap function
            calls.push(swapdata.tx.data.toString().replace("0x12aa3caf", "0x"))
        }
        // if the amount is 0 or the token is wanttoken we pass empty bytes
        else {
            calls.push("0x") // empty call
        }
    }

    // return the bytes to pass to the collateral and harvester
    return calls
}