const EscapeToken = artifacts.require("EscapeToken");
const ESTileWrapper = artifacts.require("ESTileWrapper");
const NamingContract = artifacts.require("NamingContract");

module.exports = function(deployer, network, accounts) {
  if (network.indexOf('mainnet') === -1) {
    let instance;
    deployer.deploy(EscapeToken)
      .then((inst) => {
        instance = inst;
        console.log("Unpausing the Escape contract")
        return instance.unpause();

        // TODO: Add role here?
      })
      .then(() => {
        if (network.indexOf('development') === -1) {
        //   console.log("Setting the Uniswap pool")
        //   return instance.setUniswapPool();
        } else {
        //   console.log("Setting an arbitrary Uniswap pool")
        //   return instance.overrideUniswapPool(accounts[accounts.length-1]);
        }
      })
      .then(() => {
        // console.log("Adding to the Uniswap pool")
        // return instance.addToUniswapPool();
        console.log("Deploying Namer contract");
        return deployer.deploy(NamingContract, instance.address);
      })
      /*.then(() => {
        console.log("Deploying the Wrapper OVERRIDE")
        return deployer.deploy(ESTileWrapper, instance.address, "0x45F7AD3B6103175Ba9a6Ba56Ca3a1E5d9FC7Bc68", 1, 1);
      })*/
      .then(() => {
        // process.exit();
      });
  }
};
