const TestERC20 = artifacts.require("TestERC20");
const ESTilePack = artifacts.require("ESTilePack");
// const ESTilePackWithERC20 = artifacts.require("ESTilePackWithERC20");
const config = require('../lib/configV1.js');

module.exports = async function(deployer, network, accounts) {
  // Temp, don't deploy on mainnet
  if (network.indexOf('mainnet') !== -1) {
    return;
  }

  let erc20, withdrawAddress, perPackAmount;
  if (network.indexOf('mainnet') !== -1) {
    erc20 = '';
    withdrawAddress = "0x56d76411919Ab8F86D0972b24a9986943193b306";
    perPackAmount = web3.utils.toWei("0.01", "ether");
  } else {
    // Deploy a fake
    await deployer.deploy(TestERC20, "Coin Artist Test", "$COINTEST");
    erc20 = (await TestERC20.deployed()).address;
    withdrawAddress = accounts[accounts.length-1];
  }
};
