/*
 *
 * Custom revert error messages for Chainlink oracle
 *
 */
const ChainlinkNebulaErrors = {
  /*
   *  ChainlinkNebulaOracle.sol
   *
   */
  PAIR_ALREADY_INITIALIZED: "ChainlinkNebulaOracle__PairAlreadyInitialized",

  PAIR_NOT_INITIALIZED:  "ChainlinkNebulaOracle__PairNotInitialized",

  MSG_SENDER_NOT_ADMIN: "ChainlinkNebulaOracle__MsgSenderNotAdmin",

  ADMIN_CANT_BE_ADDRESSZERO: "ChainlinkNebulaOracle__AdminCantBeZero"
};

module.exports = {
  ChainlinkNebulaErrors,
}
