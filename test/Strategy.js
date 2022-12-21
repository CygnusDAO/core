// JS
const fs = require('fs');
const path = require('path');

// Hardhat
const hre = require('hardhat');
const ethers = hre.ethers;

/*////////////////////////////////////////////////////////////
 /                                                           /
 /              SETUP OF COLLATERAL STRATEGIES               /
 /                                                           /
 ////////////////////////////////////////////////////////////*/
module.exports = async function Strategy() {

    // ---------------------------- Cygnus Void --------------------------------

    // Dex router
    const voidRouter = '0x60ae616a2155ee3d9a68541ba4544862310933d4';

    // Masterchef for this LP Token
    const masterChef = '0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F';

    // reward token
    const rewardToken = '0x6e84a6216ea6dacc71ee8e6b0a5b7322eebc0fdd';

    // Pool ID in the masterchef
    const pid = 6;

    // Return standard + optional void (router, masterchef, reward token, pid, swapfee)
    return [voidRouter, masterChef, rewardToken, pid];
};
