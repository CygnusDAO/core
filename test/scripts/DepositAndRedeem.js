const hre = require('hardhat');
const ethers = hre.ethers;

// Custom
const Make = require('../test/Make.js');
const Users = require('../test/Users.js');
const Strategy = require('../test/Strategy.js');

// OE
const { time } = require('@openzeppelin/test-helpers');

// Ethers
const addressZero = ethers.constants.AddressZero;
const max = ethers.constants.MaxUint256;

async function deploy() {
    // Cygnus contracts and underlyings
    let [oracle, factory, router, borrowable, collateral, dai, lpToken] = await Make();

    // Users
    let [owner, daoReservesManager, safeAddress2, lender, borrower] = await Users();

    // Strateg}
    let [voidRouter, masterChef, rewardToken, pid, swapFee] = await Strategy();

    // ═════════════════════ INITIALIZE VOID ═══════════════════════════════════════════════════════════════

    // Initialize with: TRADERJOE ROUTER / MiniChefV3 proxy / JOE / pool id / swapfee
    await collateral.connect(owner).chargeVoid(voidRouter, masterChef, rewardToken, 6, 997);

    console.log('----------------------------------------------------------------------------------------------');
    console.log('Price of LP Token                    | %s DAI', (await collateral.getLPTokenPrice()) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('INITIAL BALANCES OF LENDER/BORROWER');
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Borrower`s LP balance before Cyg     | %s LPs', (await lpToken.balanceOf(borrower._address)) / 1e18);
    console.log('Borrower`s DAI balance before Cyg    | %s DAI', (await dai.balanceOf(borrower._address)) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');
    console.log('Lender`s LP balance before Cyg       | %s LPs', (await lpToken.balanceOf(lender._address)) / 1e18);
    console.log('Lender`s DAI balance before Cyg      | %s DAI', (await dai.balanceOf(lender._address)) / 1e18);
    console.log('----------------------------------------------------------------------------------------------');

    /*******************************************************************************************************
   
    
                            INTERACTIONS
    
     
      ******************************************************************************************************/

    console.log('------------------------------------------------------------------------------');
    console.log('Borrower deposits 100 LPs, Lender deposits 4000 DAI');
    console.log('------------------------------------------------------------------------------');

    console.log('Total Balance of borrowable before   | %s DAI', (await borrowable.totalBalance()) / 1e18);
    console.log('Total Balance of collateral before   | %s DAI', (await borrowable.totalBalance()) / 1e18);

    // Borrower: Approve router in LP and mint CygLP
    await lpToken.connect(borrower).approve(router.address, max);
    await router.connect(borrower).mint(collateral.address, BigInt(100e18), borrower._address, max);

    // Lender: Approve router in dai and mint Cygdai
    await dai.connect(lender).approve(router.address, max);
    await router.connect(lender).mint(borrowable.address, BigInt(4000e18), lender._address, max);

    console.log('Total Balance of borrowable after    | %s DAI', (await borrowable.totalBalance()) / 1e18);
    console.log('Total Balance of collateral after    | %s LPs', (await collateral.totalBalance()) / 1e18);

    // Borrow
    await borrowable.connect(borrower).borrowApprove(router.address, max);
    await router.connect(borrower).borrow(borrowable.address, BigInt(300e18), borrower._address, max, '0x');

    console.log('Borrower`s DAI balance after borrow  | %s DAI', (await dai.balanceOf(borrower._address)) / 1e18);
    console.log('Lenders`s DAI balance after deposit  | %s DAI', (await dai.balanceOf(lender._address)) / 1e18);

    console.log('------------------------------------------------------------------------------');
    console.log('Reinvest rewards');
    console.log('------------------------------------------------------------------------------');

    console.log('Total Balance of collateral before   | %s LPs', (await collateral.totalBalance()) / 1e18);
    console.log('Exchange Rate of CygLP to collateral | %s', (await collateral.exchangeRate()) / 1e18);

    console.log('------------------------------------------------------------------------------');
    console.log('7 days.... ');
    console.log('------------------------------------------------------------------------------');

    await time.increase(60 * 60 * 24 * 7);

    await collateral.reinvestRewards_y7b();

    console.log('Total Balance of collateral after    | %s LPs', (await collateral.totalBalance()) / 1e18);
    console.log('Exchange Rate of CygLP to collateral | %s', (await collateral.exchangeRate()) / 1e18);

    console.log('------------------------------------------------------------------------------');
    console.log('Repay loan and redeem');
    console.log('------------------------------------------------------------------------------');

    // To repay just send borrower some dai
    // Impersonate a random dai holder
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: ['0xb760ef4751fe4e11c308d668f3ffB76ACfFB8285'],
    });

    const lender2 = await ethers.provider.getSigner('0xb760ef4751fe4e11c308d668f3ffB76ACfFB8285');
    await dai.connect(lender2).transfer(borrower._address, BigInt(400e18));

    await borrowable.accrueInterest();
    let borrowBalance = await borrowable.getBorrowBalance(borrower._address);
    console.log('Borrower`s amount to repay           | %s DAI', borrowBalance / 1e18);

    // Approve and repay dai (the router does the calculation to Make sure repay amount is never above owed amount)
    await dai.connect(borrower).approve(router.address, max);
    await router.connect(borrower).repay(borrowable.address, BigInt(400e18), borrower._address, max);

    // Redeem borrower
    const balanceBorrower = await collateral.balanceOf(borrower._address);
    await collateral.connect(borrower).approve(router.address, max);
    await router.connect(borrower).redeem(collateral.address, balanceBorrower, borrower._address, max, '0x');

    // Redeem lender
    const balanceLender = await borrowable.balanceOf(lender._address);
    await borrowable.connect(lender).approve(router.address, max);
    await router.connect(lender).redeem(borrowable.address, balanceLender, lender._address, max, '0x');

    // Should be a bit higher due to reinvest rewards
    console.log('Borrower`s LP balance after redeem   | %s LPs', (await lpToken.balanceOf(borrower._address)) / 1e18);
    console.log('Lender`s DAI balance after redeem    | %s DAI', (await dai.balanceOf(lender._address)) / 1e18);
    console.log('------------------------------------------------------------------------------');
}

deploy();
/*
module.exports = {
    deploy,
};
*/
