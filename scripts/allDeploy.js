const hre = require('hardhat');
const ethers = hre.ethers;
const { LedgerSigner } = require('@anders-t/ethers-ledger');

const { getAddress } = require('@ethersproject/address');

/*
 * Deployment checks:
 *
 * 1. Get addresses for NATIVE TOKEN, DAI and DAI AGGREGATOR for this chain
 * 2. Deploy Collateral Deployer
 * 3. Deploy Borrow Deployer
 * 4. Deploy Oracle with DAI Aggregator
 * 5. Deploy factory with addresses from 2,3,4 and reserves manager
 * 6. Deploy Router with factory address
 */
async function main() {

    let path = `44'/60'/3'/0/0`;

    // Deployer
    let deployer = new LedgerSigner(hre.ethers.provider, path);

    let deployerAddress = await deployer.getAddress();

    console.log('--------------------------------------------------------');

    console.log('Deploying with: %s', deployerAddress);

    console.log('Path: %s', deployerAddress);

    console.log('--------------------------------------------------------');

    // ═══════════════════ 1. NATIVE CHAIN TOKEN, DAI ADDRESS, DAI AGGREGATOR

    // Native AVAX
    let native = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    let daiAddress = '0xd586E7F844cEa2F87f50152665BCbc2C279D8d70';

    let daiAggregator = '0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300';

    // ═══════════════════ 2. COLLATERAL ORBITER

    // Collateral deployer
    let DenebFactory = await ethers.getContractFactory('DenebOrbiter');
    let Deneb = await DenebFactory.connect(deployer);
    let deneb = await Deneb.deploy();

    console.log('CollateralDeployer: %s', deneb.address);

    // ═══════════════════ 3. ALBIREO ORBITER

    // Borrow
    let AlbireoFactory = await ethers.getContractFactory('AlbireoOrbiter');
    let Albireo = await AlbireoFactory.connect(deployer);
    let albireo = await Albireo.deploy();

    console.log('BorrowDeployer: %s', albireo.address);

    // ═══════════════════ 4. ORACLE WITH DAI AGGREGATOR

    // Oracle
    let NebulaFactory = await ethers.getContractFactory('ChainlinkNebulaOracle');
    let Nebula = await NebulaFactory.connect(deployer);
    let nebula = await Nebula.deploy(daiAggregator);

    console.log('Nebula Oracle: %s', nebula.address);

    // ═══════════════════ 5. FACTORY

    let CygnusFactory = await ethers.getContractFactory('CygnusFactory');
    let Factory = await CygnusFactory.connect(deployer);
    let factory = await Factory.deploy(
        deployerAddress,
        deployerAddress,
        daiAddress,
        native,
        nebula.address,
    );

    console.log('Cygnus Factory: %s', factory.address);

    // ═══════════════════ 6. ROUTER

    // Router
    let RouterFactory = await ethers.getContractFactory('CygnusAltairX');
    let Router = await RouterFactory.connect(deployer);
    let router = await Router.deploy(factory.address);

    console.log('Router: %s', router.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
