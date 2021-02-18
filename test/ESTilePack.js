const truffleAssert = require('truffle-assertions');

const config = require('../lib/configV1.js');

const ESTilePack = artifacts.require("../contracts/ESTilePack.sol");
const ESTile = artifacts.require("../contracts/ESTile.sol");

/* Useful aliases */
const toBN = web3.utils.toBN;

contract("ESTilePack", (accounts) => {
  let instance,
    esTileInstance;

  const SCENE_0_PACK = toBN(1);
  // Feat: auto-create-open pack
  // const SCENE_0_OPEN = toBN(2);

  let cardPackLog = [];

  let CREATOR_ROLE,
      MINTER_ROLE,
      CREATOR_ADMIN_ROLE,
      MINTER_ADMIN_ROLE,
      CARD_MINTER_ROLE;

  const SCENE_0 = toBN(0);
  const SCENE_0_NumPuzzles = 5;
  const SCENE_0_TilesPerPuzzle = 6;
  const SCENE_0_TileTokenCount = SCENE_0_NumPuzzles * SCENE_0_TilesPerPuzzle;
    
  const owner = accounts[0];
  const userA = accounts[1];
  const userB = accounts[2];
  const userCreator = accounts[3];
  const userMinter = accounts[4];
  const userRando = accounts[5];
  const userBuyer = accounts[6];

  before(async () => {
    esTileInstance = await ESTile.deployed();
    instance = await ESTilePack.deployed();

    if (process.env.DEPLOY_SCENE0) {
      console.log(" -- skipping scene0 creation for test");
    } else {
      await esTileInstance.createScene(SCENE_0, SCENE_0_NumPuzzles, 
                                        SCENE_0_TilesPerPuzzle,
                                        { from: owner });
    }
  });

  after(async () => {
    console.log("Packs Opened:")
    console.log(cardPackLog);
    //await esTileInstance.revokeRole(CARD_MINTER_ROLE, instance.address, {from: owner});
  });

  describe('Access Control: Add creator and minter roles', () => {
    it('should be able to get all roles',
      async () => {
        CREATOR_ROLE = await instance.CREATOR_ROLE();
        MINTER_ROLE = await instance.MINTER_ROLE();
        CREATOR_ADMIN_ROLE = await instance.CREATOR_ADMIN_ROLE();
        MINTER_ADMIN_ROLE = await instance.MINTER_ADMIN_ROLE();
        assert.isOk(CREATOR_ROLE);
        assert.isOk(MINTER_ROLE);
        assert.isOk(CREATOR_ADMIN_ROLE);
        assert.isOk(MINTER_ADMIN_ROLE);
      });

    it('owner should be able to add new creator',
      async () => {
        let creatorsInitial = (await instance.getRoleMemberCount(CREATOR_ROLE)).toNumber();
        await instance.grantRole(CREATOR_ROLE, userCreator, {from: owner});
        assert.equal((await instance.getRoleMemberCount(CREATOR_ROLE)).toNumber(), creatorsInitial + 1);
        assert.isOk(await instance.hasRole(CREATOR_ROLE, userCreator));
      });

    it('owner should be able to add new minter',
      async () => {
        let mintersInitial = (await instance.getRoleMemberCount(MINTER_ROLE)).toNumber();
        await instance.grantRole(MINTER_ROLE, userMinter, {from: owner});
        assert.equal((await instance.getRoleMemberCount(MINTER_ROLE)).toNumber(), mintersInitial + 1);
        assert.isOk(await instance.hasRole(MINTER_ROLE, userMinter));
      });
  });

  describe('#create()', () => {
    it('creator should be able to define a new valid pack type', async () => {
      let origMaxTokenID = await instance.maxTokenID();

      // Feat: auto-create-open pack - comment applies only if feat enabled.
      // This will create two tokens, one for the scene pack itself as a tradeable
      // and another as a instantly opened variant of the scene which also can be
      // purchased via a opensea / rarible etc market.
      if (process.env.DEPLOY_SCENE0) {
        console.log(" -- skipping pack0 creation for test");
      } else {
        const PACK0_TILES = 10;
        const PACK0_ESC_COST = 50;
        const PACK0_NUM_PACKS = 100;
        await instance.createPack(SCENE_0, PACK0_ESC_COST, PACK0_TILES, 
                                  PACK0_NUM_PACKS, true, { from: userCreator });
        let maxTokenID = await instance.maxTokenID();
        assert.equal(origMaxTokenID.toNumber() + 1, maxTokenID.toNumber());
      }

      let maxTokenID = await instance.maxTokenID();
      const supply = await instance.totalSupply(maxTokenID);
      assert.ok(supply.eq(toBN(0)));
    });

  });

  describe('#uri()', () => {
    it('should get the default URI for any supplied value', async () => {
      let maxTokenID = await instance.maxTokenID();
      assert.equal(await instance.uri(1), config.PACK_API);
    });
  });

  describe('#mint()', () => {
    it('minter should be able to mint a scene-0 pack to userA', async () => {
      let maxTokenID = await instance.maxTokenID();
      let randMintAmount = Math.floor(Math.random() * 10);
      const supplyInitial = await instance.totalSupply(maxTokenID);
      await instance.mint(userA, maxTokenID, randMintAmount, "0x0", { from: userMinter });

      const balance = await instance.balanceOf(userA, maxTokenID);
      assert.ok(balance.eq(toBN(randMintAmount)));

      const supply = await instance.totalSupply(maxTokenID);
      assert.ok(supply.eq(supplyInitial.add(toBN(randMintAmount))));
    });
  });

  describe('#safeTransferFrom()', () => {
    it('owner of a box should be able to transfer sceone to another user', async () => {
      let randMintAmount = Math.floor(Math.random() * 10);

      const supplyInitial = await instance.totalSupply(SCENE_0_PACK);
      const balanceInitial = await instance.balanceOf(userA, SCENE_0_PACK);

      await instance.mint(userA, SCENE_0_PACK, randMintAmount, "0x0", { from: userMinter });

      let balance = await instance.balanceOf(userA, SCENE_0_PACK);
      assert.ok(balance.eq(balanceInitial.add(toBN(randMintAmount))));

      let supply = await instance.totalSupply(SCENE_0_PACK);
      assert.ok(supply.eq(supplyInitial.add(toBN(randMintAmount))));

      await instance.safeTransferFrom(userA, userB, SCENE_0_PACK, 1, "0x0", { from: userA });

      balance = await instance.balanceOf(userA, SCENE_0_PACK);
      assert.ok(balance.eq(balanceInitial.add(toBN(randMintAmount - 1))));

      balance = await instance.balanceOf(userB, SCENE_0_PACK);
      assert.ok(balance.eq(toBN(1)));

      supply = await instance.totalSupply(SCENE_0_PACK);
      assert.ok(supply.eq(supplyInitial.add(toBN(randMintAmount))));
    });
  });


  /**
   * Box-specific
   **/

  describe('Access Control: ESTile should grant minter access to ESTilePack', () => {
    it('ESTile should grant ESTilePack minting permission',
      async () => {
        CARD_MINTER_ROLE = await esTileInstance.MINTER_ROLE();
        assert.isOk(CARD_MINTER_ROLE);

        await esTileInstance.grantRole(CARD_MINTER_ROLE, instance.address, {from: owner});
        assert.isOk(await esTileInstance.hasRole(CARD_MINTER_ROLE, owner));
        assert.isOk(await esTileInstance.hasRole(CARD_MINTER_ROLE, instance.address));
      });
  });

  describe('#open()', () => {
    it('send some boxes of type 1 to the user to open',
      async () => {
        let boxTokenId = SCENE_0_PACK;
        let boxTokenAmount = 10;

        let boxBalanceInitial = await instance.balanceOf(userA, boxTokenId);

        await instance.mint(userA, boxTokenId, boxTokenAmount, "0x0", { from: userMinter });

        // Verify that number of boxes increased
        let balance = await instance.balanceOf(userA, boxTokenId);
        assert.ok(balance.eq(boxBalanceInitial.add(toBN(boxTokenAmount))));
      });

    async function openBoxes(_user, boxTokenId, boxTokenAmount) {
      let boxBalanceInitial = await instance.balanceOf(_user, boxTokenId);

      let tx = await instance.open(boxTokenId, boxTokenAmount, { from: _user });
      let logs = tx.logs;

      let pack = [];
      let countBatchTransfers = 0;
      for (let idx = 0; idx < logs.length; idx++) {
        if (logs[idx].event === 'TransferBatch') {
          countBatchTransfers++;

          pack.push(logs[idx].args.ids.map((a) => a.toNumber(0)));
        }
      }
      cardPackLog.push(pack);

      // Verify total number of batch transfers
      assert.equal(boxTokenAmount, countBatchTransfers);

      // Verify that number of boxes decreased
      balance = await instance.balanceOf(_user, boxTokenId);
      assert.ok(balance.eq(boxBalanceInitial.sub(toBN(boxTokenAmount))));
    }

    async function openBoxesFor(toUser, fromUser, boxTokenId, boxTokenAmount) {
      let boxBalanceInitial = await instance.balanceOf(toUser, boxTokenId);

      let tx = await instance.openFor(boxTokenId, boxTokenAmount, toUser, { from: fromUser });
      let logs = tx.logs;

      let pack = [];
      let countBatchTransfers = 0;
      for (let idx = 0; idx < logs.length; idx++) {
        if (logs[idx].event === 'TransferBatch') {
          countBatchTransfers++;

          pack.push(logs[idx].args.ids.map((a) => a.toNumber(0)));
        }
      }
      cardPackLog.push(pack);

      // Verify total number of batch transfers
      assert.equal(boxTokenAmount, countBatchTransfers);

      // Verify that number of boxes decreased
      balance = await instance.balanceOf(toUser, boxTokenId);
      assert.ok(balance.eq(boxBalanceInitial.sub(toBN(boxTokenAmount))));
    }

    it('should be able to open a single ESTilePack type 1 and receive cards',
      async () => {
        let boxTokenId = SCENE_0_PACK;
        let boxTokenAmount = 1;

        await openBoxes(userA, boxTokenId, boxTokenAmount);
      });

    it('should be able to open multiple ESTilePack type 1 and receive cards',
      async () => {
        let boxTokenId = SCENE_0_PACK;
        let boxTokenAmount = 3;

        await openBoxes(userA, boxTokenId, boxTokenAmount);
      });

    it('should not be able to open a box if you don\'t have cards',
      () => {
        truffleAssert.fails(
          instance.open(SCENE_0_PACK, 1, { from: userRando }),
          truffleAssert.ErrorType.revert,
          'ERC1155: burn amount exceeds balance'
        );
      });

    // it('should NOT be able to open a ESTilePack through wrapper without giving consent',
    //   () => {
    //     truffleAssert.fails(
    //       esTilePackWithERC20Instance.open(1, 1, { from: userA }),
    //       truffleAssert.ErrorType.revert,
    //       'ERC1155: caller is not owner nor approved'
    //     );
    //   });

    it('should NOT be able to open a ESTilePack type 1 on behalf of another wallet person without approval',
      () => {
        truffleAssert.fails(
          instance.openFor(1, 1, userA, { from: userRando }),
          truffleAssert.ErrorType.revert,
          'ERC1155: caller is not owner nor approved'
        );
      });

    it('should be able to open a ESTilePack type 1 on behalf of another wallet person and have them receive cards',
      async () => {
        let boxTokenId = 1;
        let boxTokenAmount = 1;

        await instance.mint(userA, boxTokenId, boxTokenAmount + 2, "0x0", { from: userMinter });
        await instance.setApprovalForAll(userRando, true, { from: userA });
        await openBoxesFor(userA, userRando, boxTokenId, boxTokenAmount);
      });

    it('cannot make too many packs!',
      async () => {
        let boxTokenId = 1;
        let boxTokenAmount = 1;

        truffleAssert.fails(
            instance.mint(userA, boxTokenId, 100000, "0x0", { from: userMinter }),
            truffleAssert.ErrorType.revert,
            'not enough packs left'
          );
        
        await instance.mint(userA, boxTokenId, 10, "0x0", { from: userMinter });
      });
  });
});
