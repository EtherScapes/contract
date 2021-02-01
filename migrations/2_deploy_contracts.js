const Tile = artifacts.require("Tile");
const TilePack = artifacts.require("TilePack");

// Set to false if you only want the collectible to deploy
const ENABLE_TILE_PACK = true;
// Set if you want to create your own collectible
const NFT_ADDRESS_TO_USE = undefined; // e.g. Enjin: '0xfaafdc07907ff5120a76b34b731b278c38d6043c'
// If you want to set preminted token ids for specific classes
const TOKEN_ID_MAPPING = undefined; // { [key: number]: Array<[tokenId: string]> }

module.exports = function(deployer, network) {
  // OpenSea proxy registry addresses for rinkeby and mainnet.
  let proxyRegistryAddress;
  if (network === 'rinkeby') {
    proxyRegistryAddress = "0xf57b2c51ded3a29e6891aba85459d600256cf317";
  } else {
    proxyRegistryAddress = "0xa5409ec958c83c3f309868babaca7c86dcb077c1";
  }

  if (!ENABLE_TILE_PACK) {
    deployer.deploy(Tile, proxyRegistryAddress,  {gas: 5000000});
  } else if (NFT_ADDRESS_TO_USE) {
    deployer.deploy(TilePack, proxyRegistryAddress, NFT_ADDRESS_TO_USE, {gas: 5000000})
      .then(setupPack);
  } else {
    deployer.deploy(Tile, proxyRegistryAddress, {gas: 5000000})
      .then(() => {
        return deployer.deploy(TilePack, proxyRegistryAddress, Tile.address, {gas: 5000000});
      })
      .then(setupPack);
  }
};

async function setupPack() {
  if (!NFT_ADDRESS_TO_USE) {
    const collectible = await Tile.deployed();
    await collectible.transferOwnership(TilePack.address);
  }

  if (TOKEN_ID_MAPPING) {
    const pack = await TilePack.deployed();
    for (const rarity in TOKEN_ID_MAPPING) {
      console.log(`Setting token ids for rarity ${rarity}`);
      const tokenIds = TOKEN_ID_MAPPING[rarity];
      await pack.setTokenIdsForClass(rarity, tokenIds);
    }
  }
}
