const hre = require("hardhat");
const ethers = hre.ethers;

/**
 * @notice Impersonate account for LP Token
 */
module.exports = async function Users() {
  // Ganache signers
  const [owner, daoReservesManager, safeAddress1] = await ethers.getSigners();

  // Lender
  const lenderAddress = "0x7b7b957c284c2c227c980d6e2f804311947b84d0";

  // Borrower
  const borrowerAddress = "0x8d2c76d83af250ee7fcb16307a2addc87e91fd3f";

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
