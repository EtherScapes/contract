const ESTile = artifacts.require("../contracts/ESTile.sol");
const EscapeToken = artifacts.require("../contracts/escape/EscapeToken.sol");

const config = require('../lib/configV1.js');

/* Useful aliases */
const toBN = web3.utils.toBN;

advanceTime = (time) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: '2.0',
      method: 'evm_increaseTime',
      params: [time],
      id: new Date().getTime()
    }, (err, result) => {
      if (err) { return reject(err) }
      return resolve(result)
    })
  })
}

advanceBlock = () => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: '2.0',
      method: 'evm_mine',
      id: new Date().getTime()
    }, (err, result) => {
      if (err) { return reject(err) }
      const newBlockHash = web3.eth.getBlock('latest').hash

      return resolve(newBlockHash)
    })
  })
}

advanceTimeAndBlock = async (time) => {
  await advanceTime(time)
  await advanceBlock()
  return Promise.resolve(web3.eth.getBlock('latest'))
}

contract("ESTile", (accounts) => {
  let instance, escToken;

  let tokenId = 0;

  let CREATOR_ROLE,
      MINTER_ROLE,
      CREATOR_ADMIN_ROLE,
      MINTER_ADMIN_ROLE;
 
  const SCENE_0 = toBN(1);
  const SCENE_0_NumPuzzles = 5;
  const SCENE_0_TilesPerPuzzle = 6;
  const SCENE_0_TileTokenCount = SCENE_0_NumPuzzles * SCENE_0_TilesPerPuzzle;

  const PUZZLE_0 = 0;
  const p0_start_token = 1;
  const p0_end_token = SCENE_0_TilesPerPuzzle;
  const p0_reward_token = (SCENE_0_TilesPerPuzzle * SCENE_0_NumPuzzles) + 1;

  const owner = accounts[0];
  const userA = accounts[1];
  const userB = accounts[2];
  const userCreator = accounts[3];
  const userMinter = accounts[4];
  const userRedeemer = accounts[5];

  before(async () => {
    instance = await ESTile.deployed();
    escToken = await EscapeToken.deployed();
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
    it('verify the maxTokenID matches expected amount - 1 initially', async () => {
      if (process.env.DEPLOY_SCENE0) {
        console.log(" -- skipping scene0 creation for test");
      } else {
        let maxTokenID = await instance.maxTokenID();
        assert.equal(1, maxTokenID.toNumber());
      }
    });

    it('creator should be able to define a new scene', async () => {
      if (process.env.DEPLOY_SCENE0) {
        console.log(" -- skipping scene0 creation for test");
      } else {
        let origMaxTokenID = await instance.maxTokenID();
        await instance.createScene(
          SCENE_0,
          SCENE_0_NumPuzzles,
          SCENE_0_TilesPerPuzzle,
          SCENE_0_TilesWide,
          100000, 500,    // 100k coins per scene, 5% drain per solve until 0.
          { from: userCreator }
        );
      }
    
      // Scene should contain np * h * w + 1 tokens registered, each with
      // total supply of 0.
      let maxTokenID = await instance.maxTokenID();
      assert.equal(maxTokenID.toNumber(), 1 + SCENE_0_NumPuzzles + (SCENE_0_NumPuzzles * SCENE_0_TilesPerPuzzle));

      const supply = await instance.totalSupply(maxTokenID);
      assert.ok(supply.eq(toBN(0)));
    });
  });

  describe('#uri()', () => {
    it('should get the default URI for any supplied value', async () => {
      let maxTokenID = await instance.maxTokenID();
      assert.equal(await instance.uri(1), config.ESTILE_API);
    });
  });

  describe('#mint()', () => {
    it('minter should be able to mint one of the initial cards at random', async () => {
      let randTokenId = Math.floor(Math.random() * SCENE_0_TileTokenCount);
      let randMintAmount = Math.floor(Math.random() * 100);

      const supplyInitial = await instance.totalSupply(randTokenId);

      await instance.mint(userA, randTokenId, randMintAmount, "0x0", { from: userMinter });

      const balance = await instance.balanceOf(userA, randTokenId);
      assert.ok(balance.eq(toBN(randMintAmount)));

      const supply = await instance.totalSupply(randTokenId);
      assert.ok(supply.eq(supplyInitial.add(toBN(randMintAmount))));
    });
  });

  describe('#safeTransferFrom()', () => {
    it('owner of a card should be able to transfer one to another user', async () => {
      let randTokenId = 4;
      let randMintAmount = 42;

      const supplyInitial = await instance.totalSupply(randTokenId);
      await instance.mint(userA, randTokenId, randMintAmount, "0x0", { from: userMinter });

      let balance = await instance.balanceOf(userA, randTokenId);
      assert.ok(balance.eq(toBN(randMintAmount)));

      let supply = await instance.totalSupply(randTokenId);
      assert.ok(supply.eq(supplyInitial.add(toBN(randMintAmount))));

      await instance.safeTransferFrom(userA, userB, randTokenId, 1, "0x0", { from: userA });

      balance = await instance.balanceOf(userA, randTokenId);
      assert.ok(balance.eq(toBN(randMintAmount - 1)));

      balance = await instance.balanceOf(userB, randTokenId);
      assert.ok(balance.eq(toBN(1)));

      supply = await instance.totalSupply(randTokenId);
      assert.ok(supply.eq(supplyInitial.add(toBN(randMintAmount))));
    });
  });

  describe('#redeem()', () => {
    it('owner of all puzzle tiles for a puzzle earns ESCAPE', async () => {
      // Give the redeemer user all the above tiles and try to redeem.
      for (let i = p0_start_token; i <= p0_end_token; i++) {
        await instance.mint(userRedeemer, i, 2, "0x0", { from: userMinter });
        let balance = await instance.balanceOf(userRedeemer, i);
        assert.ok(balance.eq(toBN(2)));
      }

      await instance.redeemPuzzle(SCENE_0, PUZZLE_0, { from: userRedeemer });
      for (let i = 0; i < SCENE_0_TilesPerPuzzle; i++) {
        const tileTokenId = await instance.sceneToPuzzleTileTokens(SCENE_0, PUZZLE_0, i);
        let balance = await instance.balanceOf(userRedeemer, tileTokenId);
        assert.ok(balance.eq(toBN(1)));
      }

      let balance = await instance.balanceOf(userRedeemer, p0_reward_token);
      assert.ok(balance.eq(toBN(1)));
      let escBalance = await escToken.balanceOf(userRedeemer);
      assert.ok(escBalance.eq(toBN(5000)));

      await instance.redeemPuzzle(SCENE_0, PUZZLE_0, { from: userRedeemer });
      for (let i = 0; i < SCENE_0_TilesPerPuzzle; i++) {
        const tileTokenId = await instance.sceneToPuzzleTileTokens(SCENE_0, PUZZLE_0, i);
        let balance = await instance.balanceOf(userRedeemer, tileTokenId);
        assert.ok(balance.eq(toBN(0)));
      }

      balance = await instance.balanceOf(userRedeemer, p0_reward_token);
      assert.ok(balance.eq(toBN(2)));
      escBalance = await escToken.balanceOf(userRedeemer);
      assert.ok(escBalance.eq(toBN(5000 + 4750)));
    });

    it('owner of puzzle tile can rename token', async () => {
      let escStartBalance = await escToken.balanceOf(userRedeemer);
      await instance.nameScenePuzzle(SCENE_0, PUZZLE_0, "Hello world!", { from: userRedeemer });
      let escEndBalance = await escToken.balanceOf(userRedeemer);
      assert.ok(escEndBalance.eq(toBN(escStartBalance.toNumber() - 50)));

      let result = await instance.getScenePuzzleInfo(SCENE_0, PUZZLE_0);
      assert.ok(result[0].eq(toBN(100)));
      assert.ok(result[1] == "Hello world!");
      assert.ok(result[2] == userRedeemer);

      await instance.nameScenePuzzle(SCENE_0, PUZZLE_0, "Goodbye, world!", { from: userRedeemer });

      result = await instance.getScenePuzzleInfo(SCENE_0, PUZZLE_0);
      assert.ok(result[0].eq(toBN(200)));
      assert.ok(result[1] == "Goodbye, world!");
      assert.ok(result[2] == userRedeemer);
    });
  });
});
