let Oracle;
let oracle;

/** This is a description of the foo function. */
async function main() {

  Oracle = await ethers.getContractFactory('ChainlinkNebulaOracle');
  oraclex = await Oracle.deploy('0x51D7180edA2260cc4F6e4EebB82FEF5c3c2B8300');

  console.log('Oracle deployed to: ', oraclex.address)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
