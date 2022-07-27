const hre = require('hardhat');
const ethers = hre.ethers;

// Custom
const make = require('../test/make.js');
const users = require('../test/users.js');

// OE
const { time } = require('@openzeppelin/test-helpers');

// Ethers
const addressZero = ethers.constants.AddressZero;
const max = ethers.constants.MaxUint256;

async function deploy() {
    // Cygnus contracts and underlyings
    let [
        oracle,
        factory,
        router,
        borrowable,
        collateral,
        dai,
        lpToken,
        voidRouter,
        masterChef,
        rewardToken,
        pid,
        swapFee,
    ] = await make();

    // Users
    [owner, daoReservesManager, safeAddress2, lender, borrower] = await users();

    // INITIALIZE VOID

    // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
    await collateral.connect(owner).chargeVoid(voidRouter, masterChef, rewardToken, 6, 997);

    /********************************************************************************************************
   
    
     CYGNUS INTERACTIONS - Connect to the router and test mint functions for borrow and collateral contracts.
                         - Increase debt ratio to 100% and keep liquidation incentive to 5% to do a max leverage
                           
    
     
     ********************************************************************************************************/

    // Increase debt ratio to 100%, the maximum amount
    await collateral.connect(owner).setDebtRatio(BigInt(1e18));

    // Price of 1 LP Token of joe/avax in dai
    const oneLPToken = await collateral.getLPTokenPrice();

    console.log('----------------------------------------------------------------------------------------------');
    console.log('PRICE OF 1 LP TOKEN                            | %s DAI', oneLPToken / 1e18);
    console.log('----------------------------------------------------------------------------------------------');

    let lpTokenBalanceBeforeDeposit = await lpToken.balanceOf(borrower._address) / 1e18;
    console.log('Borrower`s LP balance before deposit           | %s LP Tokens', lpTokenBalanceBeforeDeposit)

    let daiBalanceBeforeDeposit = await dai.balanceOf(lender._address) / 1e18
    console.log('Lender`s DAI balance before deposit            | %s DAI', daiBalanceBeforeDeposit);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('Borrower deposits 100 LPs, Lender deposits 25,000  DAI');
    console.log('----------------------------------------------------------------------------------------------');

    // Borrower: Deposits 100 LP Token = ~740 usd
    await lpToken.connect(borrower).approve(router.address, max);
    await router.connect(borrower).mint(collateral.address, BigInt(100e18), borrower._address, max);

    // Lender: Deposits 1000 dai
    await dai.connect(lender).approve(router.address, max);
    await router.connect(lender).mint(borrowable.address, BigInt(25000e18), lender._address, max);


    console.log('BEFORE LEVERAGE');

    console.log('----------------------------------------------------------------------------------------------');

    const cygLPBalanceBeforeL = await collateral.balanceOf(borrower._address);
    console.log('Borrower`s CygLP balance before leverage       | %s CygLP', cygLPBalanceBeforeL / 1e18);

    const albireoBalanceBeforeL = await borrowable.totalBalance();
    console.log('Borrowable`s totalBalance before leverage      | %s DAI', albireoBalanceBeforeL / 1e18);

    const cygLPTotalBalanceBeforeL = await collateral.totalBalance();
    console.log('Collateral`s totalBalance before leverage      | %s LP Tokens', cygLPTotalBalanceBeforeL / 1e18);

    const daiBalanceBeforeL = await dai.balanceOf(borrower._address);
    console.log('Borrower`s DAI balance before leverage         | %s DAI', daiBalanceBeforeL / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('AFTER LEVERAGE');
    console.log('----------------------------------------------------------------------------------------------');

    // Borrower: Approve borrow
    await borrowable.connect(borrower).borrowApprove(router.address, max);

    // Borrower 4x leverage (borrows DAI equivalent to 300 LP Tokens)
    await router
        .connect(borrower)
        .leverage(collateral.address, BigInt(oneLPToken) * BigInt(300), borrower._address, max, '0x');

    // Borrower`s borrow balance
    const borrowBalanceAfter = await borrowable.getBorrowBalance(borrower._address);
    console.log('Borrower`s borrow balance after x4 leverage    | %s DAI', borrowBalanceAfter / 1e18);

    // Debt Ratio of borrower
    console.log(
        'Borrower`s debt ratio after x4 leverage        | %s',
        await collateral.getDebtRatio(borrower._address),
    );

    // CygLP balance of borrower
    const denebBalanceAfterL = await collateral.balanceOf(borrower._address);
    console.log('Borrower`s CygLP balance after x4 leverage     | %s CygLP', denebBalanceAfterL / 1e18);

    // CygDAI totalBalance
    const albireoBalanceAfterL = await borrowable.totalBalance();
    console.log('Borrowable`s totalBalance after x4 leverage    | %s DAI', albireoBalanceAfterL / 1e18);

    // CygLP totalBalance
    const totalBalanceC = await collateral.totalBalance();
    console.log('Collateral`s totalBalance after x4 leverage    | %s LP Tokens', totalBalanceC / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('REINVEST REWARDS');
    console.log('----------------------------------------------------------------------------------------------');

    // Create
    const rewardTokenContract = await dai.attach(rewardToken);

    const reinvestorBalance = await rewardTokenContract.balanceOf(safeAddress2.address);
    const balanceBeforeReinvest = await collateral.totalBalance();

    console.log('Collateral`s totalBalance before reinvesting   | %s LP Tokens', balanceBeforeReinvest / 1e18);
    console.log('Reinvesto`s balanceOf token before reinvest    | %s JOE (or other)', reinvestorBalance / 1e18);

    // Increase 18 days
    await time.increase(60 * 60 * 24 * 18);

    console.log('18 days pass...');

    await collateral.connect(safeAddress2).reinvestRewards_y7b();
    const reinvestorBalanceAfter = await rewardTokenContract.balanceOf(safeAddress2.address);
    const balanceAfterReinvest = await collateral.totalBalance();

    console.log('Collateral`s totalBalance after reinvest       | %s LP Tokens', balanceAfterReinvest / 1e18);
    console.log('Reinvestor`s balanceOf token after reinvest    | %s JOE (or other)', reinvestorBalanceAfter / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('AFTER DELEVERAGE');
    console.log('----------------------------------------------------------------------------------------------');

    // Deleverage up to original deposited amount + estimate of swap fees (0.3% for each swap and we're doing 6 swaps max)
    await collateral.connect(borrower).approve(router.address, max);
    const maxBalance = await collateral.balanceOf(borrower._address);
    await router.connect(borrower).deleverage(collateral.address, BigInt(maxBalance) - BigInt(91.5e18), max, '0x');

    const newBalance = await collateral.balanceOf(borrower._address);

    // Redeem CygLP
    await router.connect(borrower).redeem(collateral.address, newBalance, borrower._address, max, '0x');

    const finalDenebBalance = await collateral.balanceOf(borrower._address);
    const finalAlbireoBalance = await borrowable.totalBalance();
    const outstandingBalance = await borrowable.getBorrowBalance(borrower._address);
    const totalBalanceD = await collateral.totalBalance();

    console.log('Borrower`s borrow balance after deleverage     | %s DAI', outstandingBalance / 1e18);
    console.log('Borrower`s CygLP balance after deleverage      | %s CygLP', finalDenebBalance / 1e18);
    console.log('Borrowable`s totalBalance after deleverage     | %s DAI', finalAlbireoBalance / 1e18);
    console.log('Collateral`s totalBalance after deleverage     | %s LP Tokens', totalBalanceD / 1e18);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('REDEEM AND LEAVE CYGNUS FOREVER');
    console.log('----------------------------------------------------------------------------------------------');

    const balanceCygDaiLender = await borrowable.balanceOf(lender._address);

    // Redeem CygDAI
    await borrowable.connect(lender).approve(router.address, max);
    await router.connect(lender).redeem(borrowable.address, balanceCygDaiLender, lender._address, max, '0x');

    const finalLPBalance = await lpToken.balanceOf(borrower._address);
    const finalDaiBalance = await dai.balanceOf(lender._address);
    const daiBalanceAfter = await dai.balanceOf(borrower._address);

    // If doing a full deleverage the router converts eveyrthing to DAI, sends back owed amount to borrowable and
    // transfers remaining DAI to borrower. It is best to not deleverage 100% of the position, instead calc balance
    console.log('Borrower`s DAI balance after de-leverage       | %s DAI', daiBalanceAfter / 1e18);
    console.log('Lender`s DAI balance after redeem and exit     | %s DAI', finalDaiBalance / 1e18);
    console.log('Borrower`s LP balance after redeem and exit    | %s', finalLPBalance / 1e18);

    // Collateral balance and supply
    console.log('totalBalance of collateral after full redeem   | %s LPs', (await collateral.totalBalance()) / 1e19);
    console.log('totalSupply of collateral after full redeem    | %s CygLP', (await collateral.totalSupply()) / 1e18);

    // Borrowables balance and supply
    // Only DAI left and CygDAI are dao reserves
    let totalSupply = (await borrowable.totalSupply()) / 1e18;
    console.log('totalBalance of borrowable after full redeem   | %s DAI', (await borrowable.totalBalance()) / 1e18);
    console.log('totalSupply of borrowable after full redeem    | %s CygDAI', totalSupply);

    let reserves = (await borrowable.balanceOf(daoReservesManager.address)) / 1e18;
    console.log('CygnusDAOReserves` balanceOf CygDAI            | %s CygDAI', reserves);
}

deploy();
/*
module.exports = {
    deploy,
};
*/
