// JS
const path = require("path");
const chalk = require("chalk");

// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

// Permit2
const { PERMIT2_ADDRESS, AllowanceTransfer, MaxAllowanceExpiration } = require("@uniswap/permit2-sdk");

// Fixture
const Make = require(path.resolve(__dirname, "../test/Make.js"));
const Users = require(path.resolve(__dirname, "../test/Users.js"));

// Reinvest
//const { reinvestCalldata } = require(path.resolve(__dirname, "./reinvestors/Reinvestoors.js"));
//
// enum DexAggregator {
//    PARASWAP,
//    ONE_INCH_LEGACY,
//    ONE_INCH_V2
// }
//const dexAggregator = 0; // Use 1inch

// Simple Borrow
const x1VaultHarvest = async () => {
    // CONFIG
    const [, hangar18, router, borrowable, collateral, usdc, lpToken, , rewarder, vault, daoReserves, cygToken] = await Make();
    const [owner, usdReserves, , lender, borrower] = await Users();

    // Charge allowances
    await collateral.connect(owner).chargeVoid();
    await borrowable.connect(owner).chargeVoid();

    // Set interest rate to 1% base rate and 10% slope
    await borrowable.connect(owner).setInterestRateModel(BigInt(0.01e18), BigInt(0.13e18), 2, BigInt(0.8e18));

    // Deploy harvester
    const Harvester = await ethers.getContractFactory("VeloHarvester");
    const harvester = await Harvester.deploy(hangar18.address);
    await harvester.initializeHarvester(collateral.address, "0x4200000000000000000000000000000000000006", harvester.address);
    await collateral.setHarvester(harvester.address);

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
    await lpToken.connect(borrower).transfer(owner.address, BigInt(4e18));

    //---------- 4. Owner deposits using borrower address -----------//
    await collateral.connect(owner).deposit(BigInt(4e18), borrower._address, permit, signature);

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
    const { health: health_v1 } = await collateral.getBorrowerPosition(borrower._address);
    const tbBefore = (await borrowable.totalBalance()) / 1e6;

    console.log("Borrower`s USD Balance before borrow           | %s USD", usdBal);
    console.log("Borrower`s Debt Ratio before borrow            | %s%", health_v1 / 1e16);
    console.log("Borrower`s Liquidity before borrow             | %s USD", liquidity / 1e6);
    console.log("Borrower`s Shortfall before borrow             | %s USD", shortfall / 1e6);
    console.log("Borrowable`s Total Balance before borrow       | %s USD", tbBefore);

    // Approve borrow
    await borrowable.connect(borrower).approve(router.address, ethers.constants.MaxUint256);

    // prettier-ignore
    await router.connect(borrower).borrow(borrowable.address, liquidity, borrower._address, ethers.constants.MaxUint256, '0x')

    console.log("----------------------------------------------------------------------------------------------");

    // Get liquidity
    const { liquidity: _liquidity, shortfall: _shortfall } = await collateral.getAccountLiquidity(borrower._address);
    const usdBalAfter = (await usdc.balanceOf(borrower._address)) / 1e6;
    const { health: health_v2 } = await collateral.getBorrowerPosition(borrower._address);
    const _borrowBal = (await borrowable.getBorrowBalance(borrower._address)) / 1e6;
    const tbAfter = (await borrowable.totalBalance()) / 1e6;

    console.log("Borrower`s USD Balance after borrow           | %s USD", usdBalAfter);
    console.log("Borrower`s USD debt after borrow              | %s USD", _borrowBal);
    console.log("Borrower`s Debt Ratio after borrow            | %s%", health_v2 / 1e16);
    console.log("Borrower`s Liquidity after borrow             | %s USD", _liquidity / 1e6);
    console.log("Borrower`s Shortfall after borrow             | %s USD", _shortfall / 1e6);
    console.log("Borrowable`s Total Balance after borrow       | %s USD", tbAfter);

    const loan = usdBalAfter - usdBal;

    console.log("Borrower's Loan                               | %s USD", chalk.cyan("+" + loan));
    console.log("----------------------------------------------------------------------------------------------");

    console.log("----------------------------------------------------------------------------------------------");
    console.log("                                        HARVEST CYG                                           ");
    console.log("----------------------------------------------------------------------------------------------");

    // Mine 100k blocks
    await mine(400000);

    const userInfo = await rewarder.getUserInfo(borrowable.address, 1, borrower._address);
    const pendingCyg = await rewarder.pendingCyg(borrowable.address, 1, borrower._address);
    const cygBalance = await cygToken.balanceOf(borrower._address);

    console.log("User Info: Shares before harvest              | %s Shares", userInfo.shares / 1e18);
    console.log("User Info: Reward Debt before harvest         | %s Reward Debt", userInfo.rewardDebt / 1e18);
    console.log("Pending CYG before harvest                    | %s CYG", pendingCyg / 1e18);
    console.log("Cyg Balance before harvest                    | %s CYG", cygBalance / 1e18);

    await rewarder.connect(borrower).collect(borrowable.address, 1, borrower._address);

    console.log("----------------------------------------------------------------------------------------------");

    const _userInfo = await rewarder.getUserInfo(borrowable.address, 1, borrower._address);
    const _pendingCyg = await rewarder.pendingCyg(borrowable.address, 1, borrower._address);
    const _cygBalance = await cygToken.balanceOf(borrower._address);
    const pacing = await rewarder.epochRewardsPacing();
    const progress = await rewarder.epochProgression();

    console.log("User Info: Shares after harvest               | %s Shares", _userInfo.shares / 1e18);
    console.log("User Info: Reward Debt after harvest          | %s Reward Debt", _userInfo.rewardDebt / 1e18);
    console.log("Pending CYG after harvest                     | %s CYG", _pendingCyg / 1e18);
    console.log("Cyg Balance after harvest                     | %s CYG", _cygBalance / 1e18);
    console.log("CYG Epoch Rewards pacing                      | %s%", pacing / 1e16);
    console.log("Epoch Progression                             | %s%", progress / 1e16);

    // Send some CYG to staker #2
    await cygToken.connect(borrower).transfer(lender._address, _cygBalance.mul(BigInt(0.2e18)).div(BigInt(1e18)));

    console.log("Balance of staker #2: %s CYG", (await cygToken.balanceOf(borrower._address)) / 1e18);
    console.log("Balance of staker #1: %s CYG", (await cygToken.balanceOf(lender._address)) / 1e18);

    console.log("----------------------------------------------------------------------------------------------");
    console.log("                                      CYGNUS X1 VAULT                                         ");
    console.log("----------------------------------------------------------------------------------------------");

    // VELO
    const rewardsToken = await ethers.getContractAt("CygnusERC20", await collateral.rewardToken());
    // OP
    const rewardsToken2 = await ethers.getContractAt("CygnusERC20", "0x4200000000000000000000000000000000000042");

    // Initialize Velo and OP
    await vault.addRewardToken(rewardsToken.address);
    await vault.addRewardToken(rewardsToken2.address);

    const cygStakedBalance = await vault.cygStakedBalance();
    const rewardTokenBal = await vault.lastRewardBalance(rewardsToken.address);
    const rewardToken2Bal = await vault.lastRewardBalance(rewardsToken2.address);
    const isRewardToken = await vault.isRewardToken(rewardsToken.address);
    const isRewardToken2 = await vault.isRewardToken(rewardsToken2.address);
    const allRewardsToken = await vault.rewardTokensLength();
    const veloBal = await rewardsToken.balanceOf(borrower._address);
    const opBal = await rewardsToken2.balanceOf(borrower._address);
    const veloBalL = await rewardsToken.balanceOf(lender._address);
    const opBalL = await rewardsToken2.balanceOf(lender._address);

    console.log("CYG Token Balance (vault internal)            | %s CYG", cygStakedBalance / 1e18);
    console.log("VELO Balance (vault internal)                 | %s VELO", rewardTokenBal / 1e18);
    console.log("OP Balance (vault internal)                   | %s OP", rewardToken2Bal / 1e18);
    console.log("Is reward Token?                              | %s", isRewardToken);
    console.log("Is reward Token? (OP)                         | %s", isRewardToken2);
    console.log("Reward tokens initialized                     | %s initialized tokens", allRewardsToken);
    console.log("User's VELO balance before X1 Vault           | %s VELO", chalk.redBright(veloBal / 1e18));
    console.log("User's OP balance before X1 Vault             | %s OP", chalk.redBright(opBal / 1e18));
    console.log("User 2's VELO balance before X1 Vault         | %s VELO", chalk.redBright(veloBalL / 1e18));
    console.log("User 2's OP balance before X1 Vault           | %s OP", chalk.redBright(opBalL / 1e18));
    console.log("----------------------------------------------------------------------------------------------");

    console.log("Both Deposit CYG when vault has 0 balance of any token");

    await cygToken.connect(borrower).approve(vault.address, ethers.constants.MaxUint256);
    await cygToken.connect(lender).approve(vault.address, ethers.constants.MaxUint256);
    await vault.connect(lender).deposit(await cygToken.balanceOf(lender._address));
    await vault.connect(borrower).deposit(await cygToken.balanceOf(borrower._address));

    console.log("----------------------------------------------------------------------------------------------");

    const _cygStakedBalance = await vault.cygStakedBalance();
    const _rewardTokenBal = await vault.lastRewardBalance(rewardsToken.address);
    const _rewardTokenBal2 = await vault.lastRewardBalance(rewardsToken2.address);

    console.log("CYG Token Balance (vault internal)            | %s CYG", _cygStakedBalance / 1e18);
    console.log("VELO Balance (vault internal)                 | %s VELO", _rewardTokenBal / 1e18);
    console.log("OP Balance (vault internal)                   | %s OP", _rewardTokenBal2 / 1e18);

    console.log("----------------------------------------------------------------------------------------------");

    console.log("...Harvester harvests VELO and sends to vault...");

    // First set the x1 reward to 100%
    await harvester.updateX1VaultWeight(BigInt(1e18));
    // Harvest VELO to vault
    await harvester.harvestToX1Vault(collateral.address);
    // Send some 40 OP to vault as a test
    await rewardsToken2.connect(borrower).transfer(vault.address, BigInt(40e18));

    /// Do this to get view functions, but depositing/withdrawing will do it automatically
    await vault.updateReward(rewardsToken2.address);
    await vault.updateReward(rewardsToken.address);

    const cygStakedBalance_ = await vault.cygStakedBalance();
    const rewardTokenBal_ = await vault.lastRewardBalance(rewardsToken.address);
    const rewardTokenBal2_ = await vault.lastRewardBalance(rewardsToken2.address);

    console.log("CYG Token Balance (vault internal)            | %s CYG", cygStakedBalance_ / 1e18);
    console.log("VELO Balance (vault internal)                 | %s VELO", rewardTokenBal_ / 1e18);
    console.log("OP Balance (vault internal)                   | %s OP", rewardTokenBal2_ / 1e18);
    console.log("----------------------------------------------------------------------------------------------");

    const pendingToken0 = await vault.pendingReward(borrower._address, rewardsToken.address);
    const pendingToken1 = await vault.pendingReward(borrower._address, rewardsToken2.address);
    const _pendingToken0 = await vault.pendingReward(lender._address, rewardsToken.address);
    const _pendingToken1 = await vault.pendingReward(lender._address, rewardsToken2.address);
    // Now velo has OP and VELO

    console.log("Staker #1 - Pending Rewards: VELO             | %s VELO", pendingToken0 / 1e18);
    console.log("Staker #1 - Pending Rewards: OP               | %s OP", pendingToken1 / 1e18);
    console.log("Staker #2 - Pending Rewards: VELO             | %s VELO", _pendingToken0 / 1e18);
    console.log("Staker #2 - Pending Rewards: OP               | %s OP", _pendingToken1 / 1e18);
    console.log("----------------------------------------------------------------------------------------------");

    await vault.connect(borrower).deposit(BigInt(0));
    await vault.connect(lender).deposit(BigInt(0));

    const _veloBal = await rewardsToken.balanceOf(borrower._address);
    const _opBal = await rewardsToken2.balanceOf(borrower._address);
    const _veloBalL = await rewardsToken.balanceOf(lender._address);
    const _opBalL = await rewardsToken2.balanceOf(lender._address);

    console.log("User's VELO balance after X1 Vault            | %s VELO", chalk.redBright(_veloBal / 1e18));
    console.log("User's OP balance after X1 Vault              | %s OP", chalk.redBright(_opBal / 1e18));
    console.log("User 2's VELO balance after X1 Vault          | %s VELO", chalk.redBright(_veloBalL / 1e18));
    console.log("User 2's OP balance after X1 Vault            | %s OP", chalk.redBright(_opBalL / 1e18));

    console.log("----------------------------------------------------------------------------------------------");
    console.log("                                       DAO RESERVES                                           ");
    console.log("----------------------------------------------------------------------------------------------");

    await daoReserves.addShuttle(0);

    const cygUsdBefore = await borrowable.balanceOf(daoReserves.address);

    console.log("Balance of DAO Reserves before mine           | %s CygUSD", chalk.yellowBright(cygUsdBefore / 1e6));
    console.log("Total Borrows Before                          | %s USD", (await borrowable.totalBorrows()) / 1e6);
    await mine(8000000);
    console.log("----------------------------------------------------------------------------------------------");
    // Mint CygUSD
    await borrowable.sync();
    const cygUsdAfter = await borrowable.balanceOf(daoReserves.address);

    console.log("Balance of DAO Reserves after mine            | %s CygUSD", chalk.yellowBright(cygUsdAfter / 1e6));
    console.log("Total Borrows after                           | %s USD", (await borrowable.totalBorrows()) / 1e6);
    await vault.addRewardToken(usdc.address);
    console.log("Add USDC to the X1 Vault");

    // Fund X1
    await daoReserves.fundX1VaultUSDAll();

    await vault.updateReward(usdc.address);

    const pending0U = await vault.pendingReward(borrower._address, usdc.address);
    const pending1U = await vault.pendingReward(lender._address, usdc.address);
    const daoPos = await borrowable.balanceOf(usdReserves.address);

    console.log("Staker #1's pending USDC Reward               | %s USDC", chalk.yellowBright(pending0U / 1e6));
    console.log("Staker #2's pending USDC Reward               | %s USDC", chalk.yellowBright(pending1U / 1e6));
    console.log("DAO Positions CygUSD Reserves                 | %s CygUSD", chalk.yellowBright(daoPos / 1e6));
};

x1VaultHarvest();
