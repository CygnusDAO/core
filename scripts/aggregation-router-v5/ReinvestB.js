// Hardhat
const hre = require("hardhat")
const ethers = hre.ethers

/**
 *  @notice Simple reinvest for borrowable/single token rewards
 *  @notice The `destReceiver` from the 1inch swap is the borrowable address. This means we are optimistically
 *          sending the swapped amount to the borrowable as opposed to collateral LP strategy which the harvester
 *          is the receiver of the tokens (omitting destReceiver will default to the contract sending the tx). This
 *          is done for single token rewards where we do not have to convert to LPs (ie converting tokenX to USDC).
 *
 *  @param  chainId The chain ID for the 1inch swap
 *  @param  borrowable The borrowable contract object
 *  @param  harvester The harvester contract object
 */
module.exports = async function reinvestBorrowable(chainId, borrowable, harvester) {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
                                      Reinvest Borrowable Rewards
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */
    // One mantissa
    const ONE = ethers.utils.parseUnits("1", 18)

    /**
     *  @notice Make a 1inch API call
     *  @param {string} fromToken - The address of the token being swapped
     *  @param {string} toToken - The address of the token being received
     *  @param {string} amount - The amount of fromToken being swapped
     *  @returns {object} swapData - Data from the 1inch swap
     */
    const oneInchSwap = async (fromToken, toToken, amount) => {
        // Api call
        const apiUrl = `https://api.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${harvester.address}&destReceiver=${borrowable.address}&slippage=5&disableEstimate=true&compatibilityMode=true&protocols=OPTIMISM_UNISWAP_V3,OPTIMISM_CURVE,OPTIMISM_BALANCER_V2,OPTIMISM_VELODROME,OPTIMISM_AAVE_V3`

        // Fetch data
        const swapdata = await fetch(apiUrl).then((response) => response.json())

        // Return 1inch bytes
        return swapdata
    }

    /**
     *
     *  1. Get harvester for this borrowable (needed to get the optimal token to swap to).
     *
     */
    const harvesterInfo = await harvester.getHarvester(borrowable.address)

    /**
     *
     *  2. Get the cached optimal token. swapping to anything but this token will cause the transaction to revert
     *
     */
    const wantToken = harvesterInfo.wantToken
    // Note: Collateral strategies do not have this step as the reward is removed just before adding liquidity
    // Get the CygnusX1Vault reward to remove from swap amount
    const vaultReward = await harvester.x1VaultReward()

    /**
     *
     *  3. Do a static call to the CygnusBorrow contract get the tokens and amounts harvested
     *
     */
    const { tokens, amounts } = await borrowable.callStatic.getRewards()

    /**
     *
     *  4. create the call array of 1inch data which we will pass to the harvester
     *
     */
    let calls = []

    // Loop through each reward token and call 1inch
    for (let i = 0; i < tokens.length; i++) {
        // Amount to swap = amount we have minus the vault reward
        const amountToSwap = amounts[i].mul(ONE.sub(vaultReward)).div(ONE)

        // if amount harvested is greater than 0 and token is not wanttoken
        if (amountToSwap.gt(0) && tokens[i] !== wantToken) {
            // Call 1inch api
            const swapdata = await oneInchSwap(tokens[i], wantToken, amountToSwap)

            // push to the `calls` array and remove selector of the 1inch swap function
            calls.push(swapdata.tx.data.toString().replace("0x12aa3caf", "0x"))
        }
        // if the amount is 0 or the token is wantToken we pass empty bytes
        else {
            calls.push("0x") // empty call
        }
    }

    return calls
}
