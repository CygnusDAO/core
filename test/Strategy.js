// Hardhat
const hre = require("hardhat");

/**
 * @notice Setup of Collateral strategt
 */
module.exports = async function Strategy() {
  // ---------------------------- Cygnus Void --------------------------------

  // Dex router
  const voidRouter = "0x1b02da8cb0d097eb8d57a175b88c7d8b47997506";

  // Masterchef for this LP Token
  const masterChef = "0x0769fd68dfb93167989c6f7254cd0d766fb2841f";

  // reward token
  const rewardToken = "0x0b3f868e0be5597d5db7feb59e1cadbb0fdda50a";

  // Pool ID in the masterchef
  const pid = 0;

  const rewardTokenB = '0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590'

  // Return standard + optional void (router, masterchef, reward token, pid, swapfee)
  return [voidRouter, masterChef, rewardToken, pid, rewardTokenB];
};
