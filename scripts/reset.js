await network.provider.request({
  method: "hardhat_reset",
  params: [
    {
      forking: {
        jsonRpcUrl: "https://api.avax-test.network/ext/bc/C/rpc",
        blockNumber: 18467382,
      },
    },
  ],
});

