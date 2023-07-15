const hre = require("hardhat");
const ethers = hre.ethers;

/**
 * @notice Impersonate account for LP Token
 */
module.exports = async function Users() {
    // Ganache signers
    const [owner, daoReservesManager, safeAddress1] = await ethers.getSigners();

    const makeUser = async (address) => {
        // Lender: Random DAI Whale //
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [address],
        });

        const user = await ethers.provider.getSigner(address);

        return user;
    };

    // Lender
    const lenderAddress = "0xf89d7b9c864f589bbf53a82105107622b35eaa40";
    const lender2Address = "0xd165164cbab65004da73c596712687c16b981274";

    // Borrower
    const borrowerAddress = "0xe173cc94d4755b72eb9196cf50dbcd2cba54e348";
    const borrower2Address = "0xa05ee11735d861afa66bf06004cb61f7370b1d2e";


    const lender = await makeUser(lenderAddress);
    const lender2 = await makeUser(lender2Address);
    const borrower = await makeUser(borrowerAddress);
    const borrower2 = await makeUser(borrower2Address);

    // Return accounts
    return [owner, daoReservesManager, safeAddress1, lender, borrower, lender2, borrower2];
};
