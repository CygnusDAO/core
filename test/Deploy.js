// Hardhat
const chai = require("chai");
const { solidity } = require("ethereum-waffle");
const { expect } = chai;
const hre = require("hardhat");

// Custom
const Make = require("./Make.js");
const Users = require("./Users.js");
const Strategy = require("./Strategy.js");

// Node
const fs = require("fs");
const path = require("path");

// Ethers
const addressZero = ethers.constants.AddressZero;
const max = ethers.constants.MaxUint256;

// Matchers
chai.use(solidity);

context("Deploy Lending Pool", function () {
  describe("Deploys pool", function () {
    it("Deployed the pool", async () => {
      // Cygnus contracts and underlyings
      let [oracle, factory, router, borrowable, collateral, usdc, lpToken] = await Make();

      let [voidRouter, masterChef, rewardToken, pid, swapFee] = await Strategy();

      // Users
      let [owner, daoReservesManager, safeAddress2, lender, borrower] = await Users();
      expect(await borrowable.totalSupply()).to.eq(0);
    });
  });
});
