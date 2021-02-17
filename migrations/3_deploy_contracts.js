const ESTile = artifacts.require("ESTile");
const ESTilePack = artifacts.require("ESTilePack");
const ESTileWrapper = artifacts.require("ESTileWrapper");
const NamingContract = artifacts.require("NamingContract");
const EscapeToken = artifacts.require("EscapeToken");

const config = require('../lib/configV1.js');

const SETUP_PACKS = false;

async function setupPostDeployment(network, escapeTokenAddress) {
  console.log("Setup inter-contract roles...");
  const tilePack = await ESTilePack.deployed();
  const tile = await ESTile.deployed();
  const escape = await EscapeToken.deployed();
  const wrapper = await ESTileWrapper.deployed();

  console.log("ESTile        = ", tile.address);
  console.log("ESTilePack    = ", tilePack.address);
  console.log("EscapeToken   = ", escape.address);
  console.log("ESTileWrapper = ", wrapper.address);

  // The escape token needs to grant the tile contract minter rights.
  await escape.setMinter(tile.address);

  // MINTER_ROLE is the same keccak in both contracts
  const MINTER_ROLE = await tile.MINTER_ROLE();

  // Grant the ESTilePack permission to mint ESTiles
  await tile.grantRole(MINTER_ROLE, tilePack.address);

  // Grant the ESTileWrapper permission to mint ESTilePack
  await tilePack.grantRole(MINTER_ROLE, wrapper.address);

  if (network === 'rinkeby') {
    // Grant test minter on Rinkeby
    await tilePack.grantRole(MINTER_ROLE, '0xD4F8fdD249ba41323880CefECEBca2Ab590D571F');
  }

  if (process.env.DEPLOY_SCENE0) {
    console.log("Creating scene 1 and pack 1");
    const SCENE0 = 1;

    await tile.createScene(
      SCENE0, // sceneId, scene id 1
      5,      // numPuzzles, 5 puzzles
      6,      // numTilesPerPuzzle, 6 tiles 
      100000, // puzzleRewardTotal, 100k ESCAPEs per scene
      500     // puzzleRewardRate, 5%
    );
    
    await tilePack.createPack(
      SCENE0, 
      1000,     // 1000 escapes per pack
      10,       // 10 tiles per pack
      1200,     // 1000 packs for sale, 200 airdrop budget
      true      // can be purchased for 0.1 eth per pack ;
    );
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
  let escapeTokenMainnetAddress; // FIX THIS ONCE WE DEPLOY THE ESCAPE TOKEN
  let context = this;

  if (network.indexOf('mainnet') === -1) {
    escapeTokenAddress = EscapeToken.address;
    console.log("Using developmet EscapeToken at address", escapeTokenAddress);
  } else {
    if (escapeTokenMainnetAddress) {
        // Token address provided! using default of:
        escapeTokenAddress = escapeTokenMainnetAddress;
        console.log("Using deployed escape token - ", escapeTokenAddress);
    } else {
        escapeTokenAddress = EscapeToken.address;
        console.log("Using just deployed EcapeToken at address", escapeTokenAddress);
    }
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
            .then(setupPostDeployment.bind(this, network, escapeTokenAddress));
        });
    });
};

