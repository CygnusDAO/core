const hre = require('hardhat');
const ethers = hre.ethers;

/*////////////////////////////////////////////////////////////
 /                                                           /
 /    IMPERSONATE ACCOUNTS FOR LP TOKEN AND DAI              /
 /                                                           /
 /    LP Token: 0x454E67025631C065d3cFAD6d71E6892f74487a15   /
 /                                                           /
 ////////////////////////////////////////////////////////////*/
module.exports = async function Users() {
    // Ganache signers
    const [owner, daoReservesManager, safeAddress1] = await ethers.getSigners();

    // Lender
    const lenderAddress = '0x7851dc7cf893242dfb5fe283116d68cfb8a828fe';

    // Borrower
    const borrowerAddress = '0x0f1410a815105f4429a404d2101890aa11d97951';

    // Lender: Random DAI Whale //
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [lenderAddress],
    });

    const lender = await ethers.provider.getSigner(lenderAddress);

    // Borrower: Random LP Whale //
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [borrowerAddress],
    });
    const borrower = await ethers.provider.getSigner(borrowerAddress);

    // Return accounts
    return [owner, daoReservesManager, safeAddress1, lender, borrower];
};
