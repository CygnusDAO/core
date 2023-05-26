// JS
const path = require("path");
// const chalk = require("chalk");

// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

// Permit2
const { PERMIT2_ADDRESS, AllowanceTransfer, MaxAllowanceExpiration } = require("@uniswap/permit2-sdk");

// Fixture
const Make = require(path.resolve(__dirname, "../test/Make.js"));
const Users = require(path.resolve(__dirname, "../test/Users.js"));

// SwapData
const leverageSwapData = require(path.resolve(__dirname, "./aggregation-router-v5/Leverage.js"));
const deleverageSwapData = require(path.resolve(__dirname, "./aggregation-router-v5/Deleverage.js"));

// Constants
const ONE = ethers.utils.parseUnits("1", 18);

// Leverage and deleverage a collateral position
const cygnusLeverage = async () => {
    // CONFIG
    const [, hangar18, router, borrowable, collateral, usdc, lpToken, chainId] = await Make();
    const [owner, , , lender, borrower] = await Users();

    // Charge allowances
    await collateral.connect(owner).chargeVoid();
    await borrowable.connect(owner).chargeVoid();

    /***********************************************************************************************************
                                                     START LEVERAGE
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
    console.log("                                          LEVERAGE                                            ");
    console.log("----------------------------------------------------------------------------------------------");

    //// Leverage amount is max liquidity * xLeverage
    const { liquidity } = await collateral.getAccountLiquidity(borrower._address);
    const leverageAmount = liquidity * 8;
    console.log("Leverage Amount                                | %s USD", leverageAmount / 1e6);

    // 1. Approve master borrow at the factory
    await hangar18.connect(borrower).setMasterBorrowApproval(router.address);

    const collateralBalance = (await collateral.totalBalance()) / 1e18;
    const borrowableBalance = (await borrowable.totalBalance()) / 1e6;
    const userDebtRatioBefore = (await collateral.getDebtRatio(borrower._address)) / 1e16;
    const cygLPBalanceBefore = (await collateral.balanceOf(borrower._address)) / 1e18;
    const borrowBalanceBefore = (await borrowable.getBorrowBalance(borrower._address)) / 1e6;

    console.log("Collateral`s LP Balance BEFORE                 | %s LP Tokens", collateralBalance);
    console.log("Borrowable's USD Balance BEFORE                | %s USD", borrowableBalance);
    console.log("Borrower`s Debt Ratio BEFORE                   | %s%", userDebtRatioBefore);
    console.log("Borrower`s CygLP Balance                       | %s", cygLPBalanceBefore);
    console.log("Borrower`s borrow balance                      | %s", borrowBalanceBefore);

    const nativeToken = await router.nativeToken();

    // 2. Build 1inch data
    // prettier-ignore
    const leverageCalls = await leverageSwapData(chainId, lpToken, nativeToken, usdc.address, router.address, leverageAmount); // Build 1inch data

    // 3. Leverage
    // prettier-ignore
    await router.connect(borrower).leverage(collateral.address, borrowable.address, leverageAmount, 0, ethers.constants.MaxUint256, leverageCalls, "0x");

    console.log("----------------------------------------------------------------------------------------------");

    const collateralBalanceAfter = (await collateral.totalBalance()) / 1e18;
    const borrowableBalanceAfter = (await borrowable.totalBalance()) / 1e6;
    const userDebtRatioAfter = (await collateral.getDebtRatio(borrower._address)) / 1e16;
    const cygLPBalanceAfter = (await collateral.balanceOf(borrower._address)) / 1e18;
    const borrowBalance = (await borrowable.getBorrowBalance(borrower._address)) / 1e6;
    const util = (await borrowable.utilizationRate()) / 1e16;

    console.log("Collateral`s LP Balance AFTER                  | %s LP Tokens", collateralBalanceAfter);
    console.log("Borrowable's USD Balance AFTER                 | %s USD", borrowableBalanceAfter);
    console.log("Borrower`s Debt Ratio                          | %s%", userDebtRatioAfter);
    console.log("Borrower`s CygLP Balance                       | %s", cygLPBalanceAfter);
    console.log("Borrower`s borrow balance                      | %s", borrowBalance);
    console.log("Utilization Rate                               | %s%", util);

    console.log("----------------------------------------------------------------------------------------------");
    console.log("                                        DELEVERAGE                                            ");
    console.log("----------------------------------------------------------------------------------------------");

    // Deleveraging requires 1 approval, allowing the router to use user's CygLP
    await collateral.connect(borrower).approve(router.address, ethers.constants.MaxUint256);

    // Convert borrowBalance to LP and CygLP respectively
    const _borrowBal = await borrowable.getBorrowBalance(borrower._address);
    const _lpPrice = await collateral.getLPTokenPrice();
    const er = await collateral.exchangeRate();

    const deleverageLPAmount = _borrowBal.mul(ONE).div(_lpPrice);
    const deleverageCygLPAmount = _borrowBal.mul(ONE).div(_lpPrice).mul(er).div(ONE);

    console.log("Deleverage LP Amount                           | %s LP Tokens", deleverageLPAmount / 1e18);
    console.log("Deleverage CygLP Amount                        | %s CygLP", deleverageCygLPAmount / 1e18);

    // 1. Build 1inch Data
    // prettier-ignore
    const deleverageCalls = await deleverageSwapData(chainId, lpToken, usdc.address, router.address, deleverageLPAmount);

    // 2. Deleverage
    // prettier-ignore
    await router.connect(borrower).deleverage(collateral.address, borrowable.address, deleverageCygLPAmount, 0, ethers.constants.MaxUint256, deleverageCalls, "0x");

    const _collateralBalanceAfter = (await collateral.totalBalance()) / 1e18;
    const _borrowableBalanceAfter = (await borrowable.totalBalance()) / 1e6;
    const _userDebtRatioAfter = (await collateral.getDebtRatio(borrower._address)) / 1e16;
    const _cygLPBalanceAfter = (await collateral.balanceOf(borrower._address)) / 1e18;
    const _borrowBalance = (await borrowable.getBorrowBalance(borrower._address)) / 1e6;
    const _util = (await borrowable.utilizationRate()) / 1e16;

    console.log("Collateral`s LP Balance after deleverage       | %s LP Tokens", _collateralBalanceAfter);
    console.log("Borrowable's USD Balance after deleverage      | %s USD", _borrowableBalanceAfter);
    console.log("Borrower`s Debt Ratio after deleverage         | %s%", _userDebtRatioAfter);
    console.log("Borrower`s CygLP Balance after deleverage      | %s", _cygLPBalanceAfter);
    console.log("Borrower`s borrow balance after deleverage     | %s", _borrowBalance);
    console.log("Utilization Rate ater deleverage               | %s", _util);
}

cygnusLeverage();
