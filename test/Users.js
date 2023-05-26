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
    const lenderAddress = "0x2487cb1a359c942312259bbc64a01cee32e9f539";
    const lender2Address = "0xd165164cbab65004da73c596712687c16b981274";

    // Borrower
    const borrowerAddress = "0xcaf4b694d626e55a073be1c6ac12f0a9acadfcb2";
    const borrower2Address = "0xa05ee11735d861afa66bf06004cb61f7370b1d2e";

    const lender = await makeUser(lenderAddress);
    const lender2 = await makeUser(lender2Address);
    const borrower = await makeUser(borrowerAddress);
    const borrower2 = await makeUser(borrower2Address);

    await owner.sendTransaction({
        to: borrowerAddress,
        value: ethers.utils.parseEther("1.0"),
    });

    await owner.sendTransaction({
        to: lenderAddress,
        value: ethers.utils.parseEther("1.0"),
    });

    // Return accounts
    return [owner, daoReservesManager, safeAddress1, lender, borrower, lender2, borrower2];
};
