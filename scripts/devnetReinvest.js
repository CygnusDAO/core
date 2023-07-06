// JS
const path = require("path");
// const chalk = require("chalk");

// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

// Permit2
const { PERMIT2_ADDRESS, MaxAllowanceExpiration } = require("@uniswap/permit2-sdk");

// Fixture
const Make = require(path.resolve(__dirname, "../test/Make.js"));
const Users = require(path.resolve(__dirname, "../test/Users.js"));

// Constants
//const ONE = ethers.utils.parseUnits("1", 18);
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

// Router calldata
const { leverageCalldata } = require(path.resolve(__dirname, "./aggregators/Aggregatoors.js"));
const { reinvestCalldata } = require(path.resolve(__dirname, "./reinvestors/Reinvestoors.js"));

const permit2Abi = require(path.resolve(__dirname, "./abis/permit2.json"));

// enum DexAggregator {
//    PARASWAP,
//    ONE_INCH
// }
const dexAggregator = 0; // Use 1inch

// Leverage and deleverage a collateral position
const reinvestCollateral = async () => {
    // Make Cygnus
    const [, factory, router, borrowable, collateral, usdc, lpToken, chainId] = await Make();
    const [owner, , , lender, borrower] = await Users();

    // Initialize pools
    await collateral.connect(owner).chargeVoid();
    await borrowable.connect(owner).chargeVoid();

    // Set interest rate to 1% base rate and 10% slope
    await borrowable.connect(owner).setInterestRateModel(BigInt(0.01e18), BigInt(0.1e18), 2, BigInt(0.8e18));

    /***** COLLATERAL *****/

    // Deploy harvester
    const Harvester = await ethers.getContractFactory("VeloHarvester");
    const harvester = await Harvester.deploy(factory.address);
    // Initialize harvester
    const { tokenA } = await harvester.getOptimalDstToken(lpToken.address);
    await harvester.initializeHarvester(collateral.address, tokenA, harvester.address);
    // Set harvester in the collateral
    await collateral.setHarvester(harvester.address);

    /***** BORROWABLE *****/

    // Deploy harvester
    const HarvesterB = await ethers.getContractFactory("SonneHarvester");
    const harvesterB = await HarvesterB.deploy(factory.address);
    // Initialize harvester
    await harvesterB.initializeHarvester(borrowable.address, usdc.address, borrowable.address);
    // Set harvester in the collateral
    await borrowable.setHarvester(harvesterB.address);

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

    //const _chainId = await owner.getChainId();

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

    const permit2 = new ethers.Contract(PERMIT2_ADDRESS, permit2Abi, ethers.provider);

    // Transfer LP from borrower to Owner
    await lpToken.connect(borrower).transfer(owner.address, BigInt(2e18));

    await permit2.connect(owner).approve(lpToken.address, collateral.address, BigInt(1000000e18), "28147497671");

    //---------- 4. Owner deposits using borrower address -----------//
    await collateral.connect(owner).deposit(BigInt(2e18), borrower._address, permit, '0x');

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
    await permit2.connect(owner).approve(usdc.address, borrowable.address, BigInt(1000000e18), "28147497671");

    // Transfer USD to owner
    await usdc.connect(lender).transfer(owner.address, BigInt(10000e6));

    //---------- 4. Owner deposits using borrower address -----------//
    await borrowable.connect(owner).deposit(BigInt(10000e6), lender._address, permitB, '0x');

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

    // 1. Approve borrow
    await borrowable.connect(borrower).approve(router.address, ethers.constants.MaxUint256);

    const collateralBalance = (await collateral.totalBalance()) / 1e18;
    const borrowableBalance = (await borrowable.totalBalance()) / 1e6;
    const borrowerInfo = await collateral.getBorrowerPosition(borrower._address);
    const cygLPBalanceBefore = (await collateral.balanceOf(borrower._address)) / 1e18;
    const { borrowBalance: borrowBalanceBefore } = await borrowable.getBorrowBalance(borrower._address);

    console.log("----------------------------------------");
    console.log("Principal         | %s USD", borrowerInfo.principal / 1e6);
    console.log("Borrow Balance    | %s USD", borrowerInfo.borrowBalance / 1e6);
    console.log("Price             | %s USD", borrowerInfo.price / 1e6);
    console.log("Position          | %s USD", borrowerInfo.positionUsd / 1e6);
    console.log("Health            | %s %%", borrowerInfo.health / 1e16);
    console.log("----------------------------------------");

    console.log("Collateral`s LP Balance BEFORE                 | %s LP Tokens", collateralBalance);
    console.log("Borrowable's USD Balance BEFORE                | %s USD", borrowableBalance);
    console.log("Borrower`s CygLP Balance                       | %s", cygLPBalanceBefore);
    console.log("Borrower`s borrow balance                      | %s", borrowBalanceBefore / 1e6);

    const nativeToken = await router.nativeToken();

    // 2. Build swapdata with aggregator
    const leverageCalls = await leverageCalldata(dexAggregator, chainId, lpToken, nativeToken, usdc.address, router, leverageAmount);

    // 3. Leverage
    await router.connect(borrower).leverage(
        lpToken.address, // LP Address
        collateral.address, // Collateral
        borrowable.address, // Borrowable
        leverageAmount, // USD Amount to leverage
        0, // Min LP Token received
        ethers.constants.MaxUint256, // Deadline
        "0x", // Permit data
        dexAggregator, // Enum  for dex aggregators
        leverageCalls, // Bytes array with 1inch data
    );

    console.log("----------------------------------------------------------------------------------------------");

    const collateralBalanceAfter = (await collateral.totalBalance()) / 1e18;
    const borrowableBalanceAfter = (await borrowable.totalBalance()) / 1e6;
    const _borrowerInfoAfter = await collateral.getBorrowerPosition(borrower._address);
    const cygLPBalanceAfter = (await collateral.balanceOf(borrower._address)) / 1e18;
    const { borrowBalance: borrowBalance } = await borrowable.getBorrowBalance(borrower._address);
    const util = (await borrowable.utilizationRate()) / 1e16;

    console.log("----------------------------------------");
    console.log("Principal         | %s USD", _borrowerInfoAfter.principal / 1e6);
    console.log("Borrow Balance    | %s USD", _borrowerInfoAfter.borrowBalance / 1e6);
    console.log("Price             | %s USD", _borrowerInfoAfter.price / 1e6);
    console.log("Position          | %s USD", _borrowerInfoAfter.positionUsd / 1e6);
    console.log("Health            | %s %%", _borrowerInfoAfter.health / 1e16);
    console.log("----------------------------------------");

    console.log("Collateral`s LP Balance AFTER                  | %s LP Tokens", collateralBalanceAfter);
    console.log("Borrowable's USD Balance AFTER                 | %s USD", borrowableBalanceAfter);
    console.log("Borrower`s CygLP Balance                       | %s", cygLPBalanceAfter);
    console.log("Borrower`s borrow balance                      | %s", borrowBalance / 1e6);
    console.log("Utilization Rate                               | %s%", util);

    await mine(300000);

    console.log("----------------------------------------------------------------------------------------------");
    console.log("                                  HARVEST COLLATERAL                                          ");
    console.log("----------------------------------------------------------------------------------------------");

    await borrowable.sync();
    const _borrowerInfoAfterV = await collateral.getBorrowerPosition(borrower._address);

    console.log("----------------------------------------");
    console.log("Principal         | %s USD", _borrowerInfoAfterV.principal / 1e6);
    console.log("Borrow Balance    | %s USD", _borrowerInfoAfterV.borrowBalance / 1e6);
    console.log("Price             | %s USD", _borrowerInfoAfterV.price / 1e6);
    console.log("Position          | %s USD", _borrowerInfoAfterV.positionUsd / 1e6);
    console.log("Health            | %s %%", _borrowerInfoAfterV.health / 1e16);
    console.log("----------------------------------------");

    // Get harvest calldata
    const swapdata = await reinvestCalldata(dexAggregator, chainId, collateral, harvester);

    // reinvest
    await harvester.reinvestRewards(dexAggregator, collateral.address, swapdata);

    // get balance
    const collateralBalanceReinvest = (await collateral.totalBalance()) / 1e18;

    console.log("Collateral`s LP Balance AFTER                  | %s LP Tokens", collateralBalanceReinvest);

    const borrowersPositionAfter = await collateral.getBorrowerPosition(borrower._address);

    console.log("----------------------------------------");
    console.log("Principal         | %s USD", borrowersPositionAfter.principal / 1e6);
    console.log("Borrow Balance    | %s USD", borrowersPositionAfter.borrowBalance / 1e6);
    console.log("Price             | %s USD", borrowersPositionAfter.price / 1e6);
    console.log("Position          | %s USD", borrowersPositionAfter.positionUsd / 1e6);
    console.log("Health            | %s %%", borrowersPositionAfter.health / 1e16);
    console.log("----------------------------------------");

    await mine(300000);

    // Get harvest calldata
    const swapdataB = await reinvestCalldata(dexAggregator, chainId, collateral, harvester);

    // reinvest
    await harvester.reinvestRewards(dexAggregator, collateral.address, swapdataB);

    await borrowable.sync();
    // get balance
    const collateralBalanceReinvestB = (await collateral.totalBalance()) / 1e18;

    console.log("Collateral`s LP Balance AFTER                  | %s LP Tokens", collateralBalanceReinvestB);

    const borrowersPositionAfterB = await collateral.getBorrowerPosition(borrower._address);

    console.log("----------------------------------------");
    console.log("Principal         | %s USD", borrowersPositionAfterB.principal / 1e6);
    console.log("Borrow Balance    | %s USD", borrowersPositionAfterB.borrowBalance / 1e6);
    console.log("Price             | %s USD", borrowersPositionAfterB.price / 1e6);
    console.log("Position          | %s USD", borrowersPositionAfterB.positionUsd / 1e6);
    console.log("Health            | %s %%", borrowersPositionAfterB.health / 1e16);
    console.log("----------------------------------------");

    await mine(300000);
    await borrowable.sync();

    const bx = (await borrowable.totalBalance()) / 1e6;

    console.log("Borrowable`s USD Balance Before               | %s USDC", bx);

    // Get harvest calldata
    const swapdataBorrowable = await reinvestCalldata(dexAggregator, chainId, borrowable, harvesterB);
    await borrowable.sync();
    // reinvest
    await harvesterB.reinvestRewards(dexAggregator, borrowable.address, swapdataBorrowable);
    await borrowable.sync();
    // get balance
    const borrowableBalAfter = (await borrowable.totalBalance()) / 1e6;

    console.log("Borrowable`s USD Balance After               | %s USDC", borrowableBalAfter);
};

reinvestCollateral();
