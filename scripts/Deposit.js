// JS
const path = require("path");
//const chalk = require('chalk');

// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

// Fixture
const Make = require(path.resolve(__dirname, "../test/Make.js"));
const Users = require(path.resolve(__dirname, "../test/Users.js"));

// Permit2
const { PERMIT2_ADDRESS, AllowanceTransfer, MaxAllowanceExpiration } = require("@uniswap/permit2-sdk");

// Simple deposit and redeem
const cygnusDeposit = async () => {
    // CONFIG
    const [, , , borrowable, collateral, usdc, lpToken] = await Make();
    const [owner, , , lender, borrower] = await Users();

    // Charge allowances
    await collateral.connect(owner).chargeVoid();
    await borrowable.connect(owner).chargeVoid();

    /***********************************************************************************************************
                                                     START DEPOSIT
     ***********************************************************************************************************/

    // Price of 1 LP Token
    const oneLPToken = (await collateral.getLPTokenPrice()) / 1e6;

    console.log("----------------------------------------------------------------------------------------------");
    console.log("PRICE OF 1 LP TOKEN                            | %s USDC", oneLPToken);
    console.log("----------------------------------------------------------------------------------------------");

    const lpBalBefore = (await lpToken.balanceOf(borrower._address)) / 1e18;
    const usdBalBefore = (await usdc.balanceOf(lender._address)) / 1e6;

    console.log("Borrower`s LP balance before deposit           | %s LP Tokens", lpBalBefore);
    console.log("Lender`s USDC balance before deposit           | %s USDC", usdBalBefore);

    console.log("----------------------------------------------------------------------------------------------");
    console.log("                                          DEPOSIT                                             ");
    console.log("----------------------------------------------------------------------------------------------");

    const _chainId = await owner.getChainId();

    // Borrower//

    //---------- 1. Approve Permit2 -------------//
    await lpToken.connect(owner).approve(PERMIT2_ADDRESS, ethers.constants.MaxUint256);

    //---------- 2. Build Permit -----------//
    const permit = {
        details: {
            // Address of the token we are allowing to be transfegreenBright
            token: lpToken.address,
            // Amount we are approving
            amount: BigInt(100e18),
            // The expiration for the allowance
            expiration: MaxAllowanceExpiration,
            // User nonce. Ideally on frontend we should query the nonce at the router
            nonce: 0,
        },
        // The spender of the token (collateral address)
        spender: collateral.address,
        // The deadline for the signature
        sigDeadline: ethers.constants.MaxUint256,
    };

    //---------- 3. Sign Permit -----------//
    // Permit data
    const permitDataA = AllowanceTransfer.getPermitData(permit, PERMIT2_ADDRESS, _chainId);
    // Signature
    const signature = await owner._signTypedData(permitDataA.domain, permitDataA.types, permitDataA.values);
    // Transfer LP from borrower to Owner
    await lpToken.connect(borrower).transfer(owner.address, BigInt(0.00002e18));

    //---------- 4. Owner deposits using borrower address -----------//
    await collateral.connect(owner).deposit(BigInt(0.00002e18), borrower._address, permit, signature);

    // Lender //

    //---------- 1. Approve Permit2 -------------//
    // Approve
    await usdc.connect(owner).approve(PERMIT2_ADDRESS, ethers.constants.MaxUint256);

    //---------- 2. Build Permit -----------//
    // AllowanceTransfer
    const permitB = {
        details: {
            token: usdc.address,
            amount: BigInt(100000e6),
            expiration: MaxAllowanceExpiration,
            nonce: 0,
        },
        spender: borrowable.address,
        sigDeadline: ethers.constants.MaxUint256,
    };

    //---------- 3. Sign Permit -----------//
    // Permit data
    const permitDataB = AllowanceTransfer.getPermitData(permitB, PERMIT2_ADDRESS, _chainId);
    // Signature
    const signatureB = await owner._signTypedData(permitDataB.domain, permitDataB.types, permitDataB.values);
    // Transfer USD to owner
    await usdc.connect(lender).transfer(owner.address, BigInt(100000e6));

    //---------- 4. Owner deposits using borrower address -----------//
    await borrowable.connect(owner).deposit(BigInt(100000e6), lender._address, permitB, signatureB);

    // Balance of vault tokens

    const cygLPBal = (await collateral.balanceOf(borrower._address)) / 1e18;
    const cygUsdBal = (await borrowable.balanceOf(lender._address)) / 1e6;

    console.log("Borrower's CygLP Balance                       | %s CygLP", cygLPBal);
    console.log("Lenders' CygUSD Balance                        | %s CygUSD", cygUsdBal);

    console.log("----------------------------------------------------------------------------------------------");
    console.log("                                           REDEEM                                             ");
    console.log("----------------------------------------------------------------------------------------------");

    // Borrower//
    // Redeem collateral
    await collateral.connect(borrower).redeem(cygLPBal, borrower._address, borrower._address);

    // Lender//
    // Redeem Borrowable
    await borrowable.connect(lender).redeem(cygUsdBal, lender._address, lender._address);

    // Vault token balances
    const _cygLPBal = (await collateral.balanceOf(borrower._address)) / 1e18;
    const _cygUsdBal = (await borrowable.balanceOf(lender._address)) / 1e6;
    const _lpBal = (await lpToken.balanceOf(borrower._address)) / 1e18;
    const _usdBal = (await usdc.balanceOf(lender._address)) / 1e6;
    const balanceB = (await borrowable.totalBalance()) / 1e6;
    const supplyB = (await borrowable.totalSupply()) / 1e6;
    const balanceC = (await collateral.totalBalance()) / 1e18;
    const supplyC = (await collateral.totalSupply()) / 1e18;

    console.log("Borrower's CygLP Balance                       | %s CygLP", _cygLPBal);
    console.log("Lenders' CygUSD Balance                        | %s CygUSD", _cygUsdBal);
    console.log("Borrower's LP Balance                          | %s LP Tokens", _lpBal);
    console.log("Lenders' USD Balance                           | %s USD", _usdBal);

    console.log("----------------------------------------------------------------------------------------------");

    console.log("Borrowable's Total Balance                     | %s USD", balanceB);
    console.log("Borrowable's Total Supply                      | %s CygUSD", supplyB);
    console.log("Collateral's Total Balance                     | %s LP Tokens", balanceC);
    console.log("Collateral's Total Supply                      | %s CygLP", supplyC);
};

cygnusDeposit();
