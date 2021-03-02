const ESTile = artifacts.require("../contracts/ESTile.sol");
const NamingContract = artifacts.require("../contracts/NamingContract.sol");
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
  let instance, escToken, namer;

  let tokenId = 0;

  let CREATOR_ROLE,
      MINTER_ROLE,
      CREATOR_ADMIN_ROLE,
      MINTER_ADMIN_ROLE;
 
  const SCENE_1 = toBN(1);
  const SCENE_1_NumPuzzles = 3;
  const SCENE_1_TilesPerPuzzle = 12;
  const SCENE_1_TileTokenCount = SCENE_1_NumPuzzles * SCENE_1_TilesPerPuzzle;

  const PUZZLE_1 = 0;
  const p0_start_token = 1;
  const p0_end_token = SCENE_1_TilesPerPuzzle;
  const p0_reward_token = (SCENE_1_TilesPerPuzzle * SCENE_1_NumPuzzles) + 1;

  const owner = accounts[0];
  const userA = accounts[1];
  const userB = accounts[2];
  const userCreator = accounts[3];
  const userMinter = accounts[4];
  const userRedeemer = accounts[5];
  const userTransferClaimer = accounts[6];

  before(async () => {
    instance = await ESTile.deployed();
    escToken = await EscapeToken.deployed();
    namer = await NamingContract.deployed();
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
          SCENE_1_NumPuzzles,
          SCENE_1_TilesPerPuzzle,
          1000,
          web3.utils.toWei("0.02", "ether"),
          web3.utils.toWei("5", "wei"),
          { from: userCreator }
        );
      }
    
      // Scene should contain np * h * w + 1 tokens registered, each with
      // total supply of 0.
      let maxTokenID = await instance.maxTokenID();
      assert.equal(maxTokenID.toNumber(), 1 + SCENE_1_NumPuzzles + (SCENE_1_NumPuzzles * SCENE_1_TilesPerPuzzle));

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
      let randTokenId = Math.floor(Math.random() * SCENE_1_TileTokenCount);
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

      await instance.redeemPuzzle(SCENE_1, PUZZLE_1, { from: userRedeemer });
      for (let i = 0; i < SCENE_1_TilesPerPuzzle; i++) {
        const tileTokenId = 1 + (0*SCENE_1_TilesPerPuzzle) + i;
        let balance = await instance.balanceOf(userRedeemer, tileTokenId);
        assert.ok(balance.eq(toBN(1)));
      }

      let balance = await instance.balanceOf(userRedeemer, p0_reward_token);
      assert.ok(balance.eq(toBN(1)));

      let escBalance = await escToken.balanceOf(userRedeemer);
      assert.ok(escBalance.eq(toBN(0)));

      let claimBalance = await instance.getClaimInfo({from: userRedeemer});
      assert.ok(claimBalance.eq(toBN(0)));
      await advanceTimeAndBlock(24 * 60 * 60 * 100); // 100 days
      claimBalance = await instance.getClaimInfo({from: userRedeemer});
      assert.ok(claimBalance.eq(toBN(100)));

      await instance.redeemPuzzle(SCENE_1, PUZZLE_1, { from: userRedeemer });
      for (let i = 0; i < SCENE_1_TilesPerPuzzle; i++) {
        const tileTokenId = 1 + (0*SCENE_1_TilesPerPuzzle) + i;
        let balance = await instance.balanceOf(userRedeemer, tileTokenId);
        assert.ok(balance.eq(toBN(0)));
      }

      balance = await instance.balanceOf(userRedeemer, p0_reward_token);
      assert.ok(balance.eq(toBN(2)));

      escBalance = await escToken.balanceOf(userRedeemer);
      assert.ok(escBalance.eq(toBN(0)));

      claimBalance = await instance.getClaimInfo({from: userRedeemer});
      assert.ok(claimBalance.eq(toBN(100)));

      await advanceTimeAndBlock(24 * 60 * 60 * 100); // 100 days

      // Now we should have 100 + 200 points saved up.
      claimBalance = await instance.getClaimInfo({from: userRedeemer});
      assert.ok(claimBalance.eq(toBN(100 + 200)));

      // Claim the 300 ESC.
      await instance.claimReward({from: userRedeemer});
      
      // Check that it is cleared.
      claimBalance = await instance.getClaimInfo({from: userRedeemer});
      assert.ok(claimBalance.eq(toBN(0)));

      // Check the ESC balance.
      escBalance = await escToken.balanceOf(userRedeemer);
      assert.ok(escBalance.eq(toBN(300)));
    });

    it('claims go away on transfer', async () => {
      // Give the redeemer user all the above tiles and try to redeem.
      for (let i = p0_start_token; i <= p0_end_token; i++) {
        await instance.mint(userTransferClaimer, i, 2, "0x0", { from: userMinter });
        let balance = await instance.balanceOf(userTransferClaimer, i);
        assert.ok(balance.eq(toBN(2)));
      }

      await instance.redeemPuzzle(SCENE_1, PUZZLE_1, { from: userTransferClaimer });
      for (let i = 0; i < SCENE_1_TilesPerPuzzle; i++) {
        const tileTokenId = 1 + (0*SCENE_1_TilesPerPuzzle) + i;
        let balance = await instance.balanceOf(userTransferClaimer, tileTokenId);
        assert.ok(balance.eq(toBN(1)));
      }

      let balance = await instance.balanceOf(userTransferClaimer, p0_reward_token);
      assert.ok(balance.eq(toBN(1)));

      let escBalance = await escToken.balanceOf(userTransferClaimer);
      assert.ok(escBalance.eq(toBN(0)));

      let claimBalance = await instance.getClaimInfo({from: userTransferClaimer});
      assert.ok(claimBalance.eq(toBN(0)));
      await advanceTimeAndBlock(24 * 60 * 60 * 100); // 100 days
      claimBalance = await instance.getClaimInfo({from: userTransferClaimer});
      assert.ok(claimBalance.eq(toBN(100)));

      await instance.redeemPuzzle(SCENE_1, PUZZLE_1, { from: userTransferClaimer });
      for (let i = 0; i < SCENE_1_TilesPerPuzzle; i++) {
        const tileTokenId = 1 + (0*SCENE_1_TilesPerPuzzle) + i;
        let balance = await instance.balanceOf(userTransferClaimer, tileTokenId);
        assert.ok(balance.eq(toBN(0)));
      }

      balance = await instance.balanceOf(userTransferClaimer, p0_reward_token);
      assert.ok(balance.eq(toBN(2)));

      escBalance = await escToken.balanceOf(userTransferClaimer);
      assert.ok(escBalance.eq(toBN(0)));

      // Claim balance should not have moved, we have not gone forward a day yet.
      claimBalance = await instance.getClaimInfo({from: userTransferClaimer});
      assert.ok(claimBalance.eq(toBN(100)));

      let bt = await web3.eth.getBlock("latest");
      console.log(bt);

      await advanceTimeAndBlock(24 * 60 * 60 * 100); // 100 days

      bt = await web3.eth.getBlock("latest");
      console.log(bt);

      // Now we should have 100 + 200 points saved up.
      claimBalance = await instance.getClaimInfo({from: userTransferClaimer});
      console.log(claimBalance.toNumber());
      assert.ok(claimBalance.eq(toBN(100 + 200)));

      // Transfer a token to userB - this should reduce our claim total.
      await instance.safeTransferFrom(userTransferClaimer, userB, p0_reward_token, 
                                      1, "0x0", { from: userTransferClaimer });
      
      bt = await web3.eth.getBlock("latest");
      claimBalance = await instance.getClaimInfo({from: userTransferClaimer});
      console.log(claimBalance.toNumber());
      assert.ok(claimBalance.eq(toBN(200)));
      
      // Claim the 300 ESC.
      await instance.claimReward({from: userTransferClaimer});
      
      // Check that it is cleared.
      claimBalance = await instance.getClaimInfo({from: userTransferClaimer});
      assert.ok(claimBalance.eq(toBN(0)));

      // Check the ESC balance, can only claim 200.
      escBalance = await escToken.balanceOf(userTransferClaimer);
      assert.ok(escBalance.eq(toBN(200)));
    });

    it('owner of puzzle tile can rename token', async () => {
    //   await escToken.mint(userRedeemer)

      let escStartBalance = await escToken.balanceOf(userRedeemer);
      await namer.nameScenePuzzle(SCENE_1, PUZZLE_1, "Hello world!", { from: userRedeemer });
      let escEndBalance = await escToken.balanceOf(userRedeemer);
      assert.ok(escEndBalance.eq(toBN(escStartBalance.toNumber() - 5)));

      let result = await namer.getScenePuzzleInfo(SCENE_1, PUZZLE_1);
      assert.ok(result[0].eq(toBN(10)));
      assert.ok(result[1] == "Hello world!");
      assert.ok(result[2] == userRedeemer);

      await namer.nameScenePuzzle(SCENE_1, PUZZLE_1, "Goodbye, world!", { from: userRedeemer });

      result = await namer.getScenePuzzleInfo(SCENE_1, PUZZLE_1);
      assert.ok(result[0].eq(toBN(20)));
      assert.ok(result[1] == "Goodbye, world!");
      assert.ok(result[2] == userRedeemer);
    });
  });
});
