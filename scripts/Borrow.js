// JS
const path = require("path");
const chalk = require("chalk");

// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

// Permit2
const { PERMIT2_ADDRESS, AllowanceTransfer, MaxAllowanceExpiration } = require("@uniswap/permit2-sdk");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

// Fixture
const Make = require(path.resolve(__dirname, "../test/Make.js"));
const Users = require(path.resolve(__dirname, "../test/Users.js"));

// Swapdata

// Simple Borrow
const cygnusBorrow = async () => {
    // CONFIG
    const [, , router, borrowable, collateral, usdc, lpToken] = await Make();
    const [owner, , , lender, borrower] = await Users();

    // Charge allowances
    await collateral.connect(owner).chargeVoid();
    await borrowable.connect(owner).chargeVoid();

    // Set interest rate to 1% base rate and 10% slope
    await borrowable.connect(owner).setInterestRateModel(BigInt(0), BigInt(0), 2, BigInt(0.8e18));

    /***********************************************************************************************************
                                                 START FLASH LIQUIDATE
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
    await lpToken.connect(borrower).transfer(owner.address, BigInt(0.5e18));

    //---------- 4. Owner deposits using borrower address -----------//
    await collateral.connect(owner).deposit(BigInt(0.5e18), borrower._address, permit, signature);

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
    const { health } = await collateral.getBorrowerPosition(borrower._address);
    const tbBefore = (await borrowable.totalBalance()) / 1e6;

    console.log("Borrower`s USD Balance before borrow           | %s USD", usdBal);
    console.log("Borrower`s Health before borrow                | %s%", health / 1e16);
    console.log("Borrower`s Liquidity before borrow             | %s USD", liquidity / 1e6);
    console.log("Borrower`s Shortfall before borrow             | %s USD", shortfall / 1e6);
    console.log("Borrowable`s Total Balance before borrow       | %s USD", tbBefore);

    // Approve Borrow
    await borrowable.connect(borrower).approve(router.address, ethers.constants.MaxUint256);

    const firstDeposit = BigInt(liquidity) / BigInt(2);

    // Borrow
    await router.connect(borrower).borrow(borrowable.address, firstDeposit, borrower._address, ethers.constants.MaxUint256, "0x");

    console.log("----------------------------------------------------------------------------------------------");

    // Get liquidity
    const { liquidity: _liquidity, shortfall: _shortfall } = await collateral.getAccountLiquidity(borrower._address);
    const usdBalAfter = (await usdc.balanceOf(borrower._address)) / 1e6;
  const { health: _health } = await collateral.getBorrowerPosition(borrower._address);
    const { principal: pri_, borrowBalance: br_ } = await borrowable.getBorrowBalance(borrower._address);
    const tbAfter = (await borrowable.totalBalance()) / 1e6;

    console.log("Borrower`s USD Balance after borrow           | %s USD", usdBalAfter);
    console.log("Borrower`s USD principal after borrow              | %s USD", pri_ / 1e6);
    console.log("Borrower`s USD debt after borrow              | %s USD", br_ / 1e6);
    console.log("Borrower`s Health after borrow                | %s%", _health / 1e16);
    console.log("Borrower`s Liquidity after borrow             | %s USD", _liquidity / 1e6);
    console.log("Borrower`s Shortfall after borrow             | %s USD", _shortfall / 1e6);
    console.log("Borrowable`s Total Balance after borrow       | %s USD", tbAfter);

    const loan = usdBalAfter - usdBal;

    console.log("----------------------------------------------------------------------------------------------");
    console.log("Borrower's Loan                               | %s USD", chalk.cyan("+" + loan));
    console.log("----------------------------------------------------------------------------------------------");

    const newLiq = await collateral.getAccountLiquidity(borrower._address);
    console.log("NEW LIQ: %s", newLiq.liquidity);
    console.log("SECOND BORROW");
    await mine(10000);
    await router.connect(borrower).borrow(borrowable.address, newLiq.liquidity, borrower._address, ethers.constants.MaxUint256, "0x");

    // Get liquidity
    const { liquidity: liquidity_ } = await collateral.getAccountLiquidity(borrower._address);
    const usdBalAfter_ = (await usdc.balanceOf(borrower._address)) / 1e6;
    //const debtRatioAfter = (await collateral.getDebtRatio(borrower._address)) / 1e16;
    const { principal: _pri, borrowBalance: _br } = await borrowable.getBorrowBalance(borrower._address);
    const tbAfter_ = (await borrowable.totalBalance()) / 1e6;

    console.log("Borrower`s USD Balance after borrow           | %s USD", usdBalAfter_);
    console.log("Borrower`s USD principal after borrow         | %s USD", _pri / 1e6);
    console.log("Borrower`s USD debt after borrow              | %s USD", _br / 1e6);
    //console.log("Borrower`s Debt Ratio after borrow            | %s%", debtRatioAfter);
    console.log("Borrower`s Liquidity after borrow             | %s USD", liquidity_ / 1e6);
    console.log("Borrowable`s Total Balance after borrow       | %s USD", tbAfter_);

    await router.connect(borrower).borrow(borrowable.address, BigInt(1), borrower._address, ethers.constants.MaxUint256, "0x");
};

cygnusBorrow();
