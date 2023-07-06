// JS
const path = require("path");
// const chalk = require("chalk");

// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

// Permit2
const { PERMIT2_ADDRESS, AllowanceTransfer, MaxAllowanceExpiration } = require("@uniswap/permit2-sdk");

// Fixture
const Make = require(path.resolve(__dirname, "../test/Make.js"));
const Users = require(path.resolve(__dirname, "../test/Users.js"));

// We use the lender as liquidator for simplicity since they already have USDC
const cygnusLiquidate = async () => {
    // CONFIG
    const [, , router, borrowable, collateral, usdc, lpToken] = await Make();
    const [owner, , , lender, borrower] = await Users();

    // Charge allowances
    await collateral.connect(owner).chargeVoid();
    await borrowable.connect(owner).chargeVoid();

    // Set interest rate to 1% base rate and 10% slope
    await borrowable.connect(owner).setInterestRateModel(BigInt(0.01e18), BigInt(0.1e18), 2, BigInt(0.8e18));

    /***********************************************************************************************************
                                                     START LIQUIDATE
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
    await lpToken.connect(borrower).transfer(owner.address, BigInt(2e18));

    //---------- 4. Owner deposits using borrower address -----------//
    await collateral.connect(owner).deposit(BigInt(2e18), borrower._address, permit, signature);

    // Lender //

    //---------- 1. Approve Permit2 -------------//
    // Approve
    await usdc.connect(owner).approve(PERMIT2_ADDRESS, ethers.constants.MaxUint256);

    //---------- 2. Build Permit -----------//
    // AllowanceTransfer
    const permitB = {
        details: {
            token: usdc.address,
            amount: BigInt(10000e6),
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
    await usdc.connect(lender).transfer(owner.address, BigInt(10000e6));

    //---------- 4. Owner deposits using borrower address -----------//
    await borrowable.connect(owner).deposit(BigInt(10000e6), lender._address, permitB, signatureB);

    // Balance of vault tokens

    const cygLPBal = (await collateral.balanceOf(borrower._address)) / 1e18;
    const cygUsdBal = (await borrowable.balanceOf(lender._address)) / 1e6;

    console.log("Borrower's CygLP Balance                       | %s CygLP", cygLPBal);
    console.log("Lenders' CygUSD Balance                        | %s CygUSD", cygUsdBal);

    console.log("----------------------------------------------------------------------------------------------");
    console.log("                                        MAX BORROW                                            ");
    console.log("----------------------------------------------------------------------------------------------");

    // Get liquidity
    const { liquidity, shortfall } = await collateral.getAccountLiquidity(borrower._address);
    const usdBal = (await usdc.balanceOf(borrower._address)) / 1e6;
    const debtRatio = (await collateral.getDebtRatio(borrower._address)) / 1e16;
    console.log("Borrower`s USD Balance before borrow           | %s USD", usdBal);
    console.log("Borrower`s Debt Ratio before borrow            | %s%", debtRatio);
    console.log("Borrower`s Liquidity before borrow             | %s USD", liquidity / 1e6);
    console.log("Borrower`s Shortfall before borrow             | %s USD", shortfall / 1e6);

    // Approve borrow
    await borrowable.connect(borrower).borrowApprove(router.address, ethers.constants.MaxUint256);

    // prettier-ignore
    await router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, ethers.constants.MaxUint256, '0x')

    // Get liquidity
    const { liquidity: _liquidity, shortfall: _shortfall } = await collateral.getAccountLiquidity(borrower._address);
    const usdBalAfter = (await usdc.balanceOf(borrower._address)) / 1e6;
    const debtRatioAfter = (await collateral.getDebtRatio(borrower._address)) / 1e16;
    const _borrowBal = (await borrowable.getBorrowBalance(borrower._address)) / 1e6;
    console.log("Borrower`s USD Balance after borrow           | %s USD", usdBalAfter);
    console.log("Borrower`s USD debt after borrow              | %s USD", _borrowBal);
    console.log("Borrower`s Debt Ratio after borrow            | %s%", debtRatioAfter);
    console.log("Borrower`s Liquidity after borrow             | %s USD", _liquidity / 1e6);
    console.log("Borrower`s Shortfall after borrow             | %s USD", _shortfall / 1e6);

    console.log("----------------------------------------------------------------------------------------------");
    console.log("                                          ACCRUE                                              ");
    console.log("----------------------------------------------------------------------------------------------");

    await mine(1000);
    await borrowable.accrueInterest();

    // Get liquidity
    const { liquidity: liquidity_, shortfall: shortfall_ } = await collateral.getAccountLiquidity(borrower._address);
    const borrowBal_ = (await usdc.balanceOf(borrower._address)) / 1e6;
    const debtRatio_ = (await collateral.getDebtRatio(borrower._address)) / 1e16;
    console.log("Borrower`s USD debt after accrue              | %s USD", borrowBal_);
    console.log("Borrower`s Debt Ratio after accrue            | %s%", debtRatio_);
    console.log("Borrower`s Liquidity after accrue             | %s USD", liquidity_ / 1e6);
    console.log("Borrower`s Shortfall after accrue             | %s USD", shortfall_ / 1e6);

    console.log("----------------------------------------------------------------------------------------------");
    console.log("                                        LIQUIDATE                                             ");
    console.log("----------------------------------------------------------------------------------------------");

    const _liqUsdBal = (await usdc.balanceOf(lender._address)) / 1e6;
    console.log("Liquidator's USD Balance before liq.           | %s USD", _liqUsdBal);

    // We pass a number much above their liquidity but router does not use all
    const amount = BigInt(10000e6);

    // Checks that liquidate amount is never above borrowed balance in router (ie if user borrowed 20 usdc, router will repay 20 usdc, not 5000)
    await usdc.connect(lender).approve(router.address, ethers.constants.MaxUint256);

    // prettier-ignore
    await router.connect(lender).liquidate(borrowable.address, amount, borrower._address, lender._address, ethers.constants.MaxUint256);

    console.log("----------------------------------------------------------------------------------------------");

    const borrowerCygLPBal = (await collateral.balanceOf(borrower._address)) / 1e18;
    const lenderCygLPBal = (await collateral.balanceOf(lender._address)) / 1e18;
    const borrowBalanceAfterLiq = (await borrowable.getBorrowBalance(borrower._address)) / 1e6;
    const debtRatioAfterLiq = (await collateral.getDebtRatio(borrower._address)) / 1e16;
    const { liquidity: newLiq, shortfall: newShort } = await collateral.getAccountLiquidity(borrower._address);
    const liqUsdBal = (await usdc.balanceOf(lender._address)) / 1e6;

    console.log("Liquidator's new USD Balance                   | %s USD", liqUsdBal);
    console.log("Borrower CygLP Balance after liq.              | %s CygLP", borrowerCygLPBal);
    console.log("Liquidator CygLP Balance after liq.            | %s CygLP", lenderCygLPBal);
    console.log("Borrow Balance of borrower                     | %s USD", borrowBalanceAfterLiq);
    console.log("Borrower`s Debt Ratio after liq.               | %s%", debtRatioAfterLiq);
    console.log("Borrower`s Liquidity after liq.                | %s USD", newLiq / 1e6);
    console.log("Borrower`s Shortfall after liq.                | %s USD", newShort / 1e6);
};

cygnusLiquidate();
