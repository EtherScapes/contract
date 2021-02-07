const truffleAssert = require('truffle-assertions');

const ESTile = artifacts.require("../contracts/ESTile.sol");
const ESTilePack = artifacts.require("../contracts/ESTilePack.sol");
const ESTileWrapper = artifacts.require("../contracts/ESTileWrapper.sol");
const EscapeToken = artifacts.require("../contracts/escape/EscapeToken.sol");

/* Useful aliases */
const toBN = web3.utils.toBN;

contract("ESTileWrapper", (accounts) => {
  let instance,
    escapeTokenInstance,
    esTileInstance,
    esTilePackInstance,
    packId;

  const SCENE_0 = toBN(1);
  const SCENE_0_NumPuzzles = 5;
  const SCENE_0_TilesHigh = 2;
  const SCENE_0_TilesWide = 3;
  const SCENE_0_TilesPerPuzzle = SCENE_0_TilesHigh * SCENE_0_TilesWide;
  const SCENE_0_TileTokenCount = SCENE_0_NumPuzzles * SCENE_0_TilesPerPuzzle;
  
  const PACK_0 = 1;
  const PACK_0_EscapeCost = 100;
  const PACK_0_Quantitiy = 1000;
  const PACK_0_NumTiles = 10;

  const owner = accounts[0];
  const userA = accounts[1];
  const userB = accounts[2];
  const userC = accounts[3];
  const uniswapPool = accounts[accounts.length-1];

  before(async () => {
    instance = await ESTileWrapper.deployed();
    escapeTokenInstance = await EscapeToken.deployed();
    esTileInstance = await ESTile.deployed();
    esTilePackInstance = await ESTilePack.deployed();
    await esTileInstance.createScene(SCENE_0, SCENE_0_NumPuzzles, 
                                     SCENE_0_TilesHigh, SCENE_0_TilesWide, 100000, 500, 
                                     { from: owner });
    
    // function createPack(uint256 sceneId, uint256 escapeCost, uint256 tilesPerPack, uint256 packQuantity, bool isPurchaseable) external {
    await esTilePackInstance.createPack(SCENE_0, PACK_0_EscapeCost, PACK_0_NumTiles, 
                                        PACK_0_Quantitiy, true, { from: owner });

    await escapeTokenInstance.mintForAccount(userA, 5000);
    await escapeTokenInstance.mintForAccount(userB, 50000000);
    let balance = await escapeTokenInstance.balanceOf(userA);
    assert.ok(balance.eq(toBN(5000)));
  });

  describe('ESCAPE based pack purchase', () => {
    it("should redeem escape tokens for a pack", 
      async () => {
        await instance.buyPacksForCredits(PACK_0, 5, {from: userA});
        let balance = await escapeTokenInstance.balanceOf(userA);
        assert.ok(balance.eq(toBN(5000 - (100 * 5)))); // should spend escape.

        balance = await esTilePackInstance.balanceOf(userA, PACK_0);
        assert.ok(balance.eq(toBN(5))); // should have 5 packs.
      });

    it("should open packs it has purchased", 
      async () => {
        await esTilePackInstance.open(PACK_0, 4, {from: userA});
        balance = await esTilePackInstance.balanceOf(userA, PACK_0);
        assert.ok(balance.eq(toBN(1))); // should have 1 pack, 4 opened
      });
    
    it("should open last pack it has purchased", 
      async () => {
        await esTilePackInstance.open(PACK_0, 1, {from: userA});
        balance = await esTilePackInstance.balanceOf(userA, PACK_0);
        assert.ok(balance.eq(toBN(0))); // should have 0 packs, 5 opened
      });

    it("should not buy too many packs", 
      async () => {
        truffleAssert.fails(
          instance.buyPacksForCredits(PACK_0, 100000, {from: userB}),
          truffleAssert.ErrorType.revert,
          'not enough packs left'
        );
      });
  });

  describe('ETH based pack purchase', () => {
    it("should redeem 0.1 ETH for a pack", 
      async () => {
        await instance.buyPacksForETH(PACK_0, 1, {from: userC, value: web3.utils.toWei("0.1", "ether")});
        balance = await esTilePackInstance.balanceOf(userC, PACK_0);
        assert.ok(balance.eq(toBN(1))); // should have 5 packs.
      });
    
    it("should open last pack it has purchased", 
      async () => {
        await esTilePackInstance.open(PACK_0, 1, {from: userC});
        balance = await esTilePackInstance.balanceOf(userC, PACK_0);
        assert.ok(balance.eq(toBN(0))); // should have 0 packs, 5 opened
      });

    it("should not buy too many packs", 
      async () => {
        truffleAssert.fails(
          instance.buyPacksForETH(PACK_0, 1001, {from: userC}),
          truffleAssert.ErrorType.revert,
          'not enough packs left'
        );
      });
  });

});
