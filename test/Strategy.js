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
  const masterChef = "0xf4d73326c13a4fc5fd7a064217e12780e9bd62c3";

  // reward token
  const rewardToken = "0xd4d42F0b6DEF4CE0383636770eF773390d85c61A";

  // Pool ID in the masterchef
  const pid = 13;

  const rewardTokenB = '0x6694340fc020c5E6B96567843da2df01b2CE1eb6'

  // Return standard + optional void (router, masterchef, reward token, pid, swapfee)
  return [voidRouter, masterChef, rewardToken, pid, rewardTokenB];
};
