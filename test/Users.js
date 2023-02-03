const hre = require("hardhat");
const ethers = hre.ethers;

/**
 * @notice Impersonate account for LP Token
 */
module.exports = async function Users() {
  // Ganache signers
  const [owner, daoReservesManager, safeAddress1] = await ethers.getSigners();

  // Lender
  const lenderAddress = "0xc882b111a75c0c657fc507c04fbfcd2cc984f071";

  // Borrower
  const borrowerAddress = "0x9854179bbbda1154f439116d31a646b15ec26e2d";

  // Lender: Random DAI Whale //
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [lenderAddress],
  });

  const lender = await ethers.provider.getSigner(lenderAddress);

  // Borrower: Random LP Whale //
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [borrowerAddress],
  });
  const borrower = await ethers.provider.getSigner(borrowerAddress);

  // Return accounts
  return [owner, daoReservesManager, safeAddress1, lender, borrower];
};
