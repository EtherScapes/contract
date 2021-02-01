/* Contracts in this test */

const Tile = artifacts.require("../contracts/Tile.sol");


contract("Tile", (accounts) => {
  const CONTRACT_URI = 'https://raw.githubusercontent.com/etherscapes/metadata/master/contract-description.json';
  
  let myCollectible;
  before(async () => {
    myCollectible = await Tile.deployed();
  });

  describe('#constructor()', () => {
    it('should set the contractURI to the supplied value', async () => {
      assert.equal(await myCollectible.contractURI(), CONTRACT_URI);
    });
  });
});
