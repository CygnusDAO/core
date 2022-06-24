module.exports = {
  skipFiles: ["mocks/", "test/"],
  configureYulOptimizer: true,
  providerOptions: { 
    provider: 'https://localhost:8545'
  }};
