const ESTile = artifacts.require("ESTile");
const ESTilePack = artifacts.require("ESTilePack");
const ESTileWrapper = artifacts.require("ESTileWrapper");
const NamingContract = artifacts.require("NamingContract");
const EscapeToken = artifacts.require("EscapeToken");

const config = require('../lib/configV1.js');


async function setupCardsAndPacks(network, escapeTokenAddress) {
  console.log("Setup inter-contract roles...");
  const tilePack = await ESTilePack.deployed();
  const tile = await ESTile.deployed();
  const escape = await EscapeToken.deployed();

  console.log(tilePack.address);

  // The escape token needs to grant the tile contract minter rights.
  await escape.setMinter(tile.address);

  // MINTER_ROLE is the same keccak in both contracts
  const MINTER_ROLE = await tile.MINTER_ROLE();

  // Grant the ESTilePack permission to mint ESTiles
  await tile.grantRole(MINTER_ROLE, tilePack.address);

  // Grant the ESTileWrapper permission to mint ESTilePack
  const wrapper = await ESTileWrapper.deployed();
  await tilePack.grantRole(MINTER_ROLE, wrapper.address);

  // Grant the ESTileWrapper permission to mint ESCAPE tokens on redeem.

  if (network === 'rinkeby') {
    // Grant test minter on Rinkeby
    await tilePack.grantRole(MINTER_ROLE, '0x636c54bA584fC0e81F772c27c44CDbE773b18313');
  }
}

module.exports = function(deployer, network) {
  // OpenSea proxy registry addresses for rinkeby and mainnet.
  let proxyRegistryAddress;
  if (network === 'rinkeby') {
    proxyRegistryAddress = "0xf57b2c51ded3a29e6891aba85459d600256cf317";
  } else if (network === 'mainnet') {
    proxyRegistryAddress = "0xa5409ec958c83c3f309868babaca7c86dcb077c1";
  } else {
    proxyRegistryAddress = "0x0000000000000000000000000000000000000000";
  }

  // Escape contract
  let escapeTokenAddress;
  let namingContractAddress;
  let context = this;

  if (network.indexOf('mainnet') === -1) {
    escapeTokenAddress = EscapeToken.address;
    console.log("Using developmet EscapeToken at address", escapeTokenAddress);
  } else {
    escapeTokenAddress = '0x1453Dbb8A29551ADe11D89825CA812e05317EAEB';
  }

  namingContractAddress = NamingContract.address;
  console.log("Deploying ESTile");
  deployer.deploy(ESTile, config.ESTILE_API, proxyRegistryAddress, escapeTokenAddress, namingContractAddress)
    .then((instance) => {
      console.log("ESTile addr = ", instance.address);
      console.log("Deploying ESTilePack");
      return deployer.deploy(ESTilePack, config.PACK_API, instance.address, proxyRegistryAddress)
        .then((instanceBox) => {
          console.log("Deploying ESTileWrapper");
          return deployer.deploy(ESTileWrapper, escapeTokenAddress, instanceBox.address)
            .then(setupCardsAndPacks.bind(this, network, escapeTokenAddress));
        });
    });
};

