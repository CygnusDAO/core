const hre = require("hardhat");
const ethers = hre.ethers;
const fs = require("fs");
const path = require("path");

/**
 *  @notice Build 1inch swaps using AggregationRouterV4. Inspired by https://github.com/smye/1inch-swap/
 *
 *          The reason we can calculate what each proceeding swap will be is by decoding the data from the previous
 *          swap for `toTokenAmount`. We then in our periphery contract override the `amount` variable to check for
 *          small differences and pass this to the 1Inch Aggregator.
 */
module.exports = async function SwapCallData(chainId, lpToken, usdc, router, deleverageLpAmount, borrower) {
    const hypervisorAbi = fs.readFileSync(path.resolve(__dirname, "../abis/ihypervisor.json")).toString();
    const hypervisor = new ethers.Contract(lpToken.address, hypervisorAbi, borrower);

    const x = await hypervisor.withdraw(deleverageLpAmount, borrower.address, borrower.address, [0, 0, 0, 0]);
    console.log(x);
    let calls = [];

    return calls;
};
