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
  
  let PACK_0 = 1;
  let PACK_0_EscapeCost = 1000;
  let PACK_0_Quantitiy = 1200;
  let PACK_0_NumTiles = 10;
  
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
    if (process.env.DEPLOY_SCENE0) {
      console.log(" -- skipping scene0 & pack0 creation for test");
    } else {
      await esTileInstance.createScene(SCENE_0, SCENE_0_NumPuzzles, 
                                      SCENE_0_TilesHigh, SCENE_0_TilesWide, 
                                      100000, 500, 
                                      { from: owner });
      
      await esTilePackInstance.createPack(SCENE_0, PACK_0_EscapeCost, 
                                          PACK_0_NumTiles, PACK_0_Quantitiy, 
                                          true, 
                                          { from: owner });
    }
      

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
        assert.ok(balance.eq(toBN(5000 - (1000 * 5)))); // should spend escape.

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
          instance.buyPacksForCredits(PACK_0, 1300, {from: userB}),
          truffleAssert.ErrorType.revert,
          'not enough packs left'
        );
      });
  });

  describe('ETH based pack purchase', () => {
    it("should have no eth balance", 
      async () => {
        truffleAssert.fails(
          instance.withdrawBalance({from: owner}),
          truffleAssert.ErrorType.revert,
          "no balance left");
      })
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
    
    it("should have eth balance (0.1) to withdraw", 
      async () => {
        let ethBal = await web3.eth.getBalance(owner);
        await instance.withdrawBalance({from: owner});
        let newEthBal = await web3.eth.getBalance(owner);
        
        let ob = web3.utils.fromWei(ethBal);
        let nb = web3.utils.fromWei(newEthBal);
        assert.ok(ob < nb - 0.01); // Fees
      })
  });

});
