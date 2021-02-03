/* libraries used */

const truffleAssert = require('truffle-assertions');

const vals = require('../lib/testValuesCommon.js');

/* Contracts in this test */

const MockProxyRegistry = artifacts.require(
  "../contracts/MockProxyRegistry.sol"
);
const TileFactory = artifacts.require("../contracts/TileFactory.sol");
const Tile = artifacts.require("../contracts/Tile.sol");
const TestForReentrancyAttack = artifacts.require(
  "../contracts/TestForReentrancyAttack.sol"
);


/* Useful aliases */

const toBN = web3.utils.toBN;


/* NOTE:
   * We rely on the accident of collectible token IDs starting at 1, and mint
     our SCENE_0 token first to make option ID match token ID for SCENE_0 and
     SCENE_1.
   * We never mint SCENE_BASIC tokens, as there is no zero token ID in the
     collectible.
   * For testing paths that must work if no token has been minted, use SCENE_BASIC.
   * We mint SCENE_0 and SCENE_1 while testing mint().
   * Therefore any tests that must work with and without tokens minted, use
     SCENE_BASIC for unminted and SCENE_0 for minted, *after* mint() is tested.
   * Do not test transferFrom() with SCENE_BASIC as that would create the token as 3.
     transferFrom() uses _create, which is tested in create(), so this is fine.
*/

contract("TileFactory", (accounts) => {
  // As set in (or inferred from) the contract
  const SCENE_BASIC = 0;
  const SCENE_0 = 1;
  const SCENE_1 = 2;
  const NUM_OPTIONS = 3;
  const NO_SUCH_SCENE = NUM_OPTIONS + 10;
  
  const owner = accounts[0];
  const userA = accounts[1];
  const userB = accounts[2];
  const proxyForOwner = accounts[8];

  let myFactory;
  let myCollectible;
  let attacker;
  let proxy;

  // To install the proxy mock and the attack contract we deploy our own
  // instances of all the classes here rather than using the ones that Truffle
  // deployed.

  before(async () => {
    proxy = await MockProxyRegistry.new();
    await proxy.setProxy(owner, proxyForOwner);
    myCollectible = await Tile.new(proxy.address);
    myFactory = await TileFactory.new(
      proxy.address,
      myCollectible.address);
    await myCollectible.transferOwnership(myFactory.address);
    //await myCollectible.setFactoryAddress(myFactory.address);
    attacker = await TestForReentrancyAttack.new();
    await attacker.setFactoryAddress(myFactory.address);
  });

  // This also tests the proxyRegistryAddress and nftAddress accessors.

  describe('#constructor()', () => {
    it('should set proxyRegistryAddress to the supplied value', async () => {
      assert.equal(await myFactory.proxyRegistryAddress(), proxy.address);
      assert.equal(await myFactory.nftAddress(), myCollectible.address);
    });
  });

  describe('#name()', () => {
    it('should return the correct name', async () => {
      assert.equal(await myFactory.name(), 'EtherScapes Scene Packs');
    });
  });

  describe('#symbol()', () => {
    it('should return the correct symbol', async () => {
      assert.equal(await myFactory.symbol(), 'ESSP');
    });
  });

  describe('#supportsFactoryInterface()', () => {
    it('should return true', async () => {
      assert.isOk(await myFactory.supportsFactoryInterface());
    });
  });

  describe('#factorySchemaName()', () => {
    it('should return the schema name', async () => {
      assert.equal(await myFactory.factorySchemaName(), 'ERC1155');
    });
  });

  describe('#numOptions()', () => {
    it('should return the correct number of options, 0 at start', async () => {
      assert.equal(await myFactory.numScenes(), 0);
    });
  });

  //NOTE: We test this early relative to its place in the source code as we
  //      mint tokens that we rely on the existence of in later tests here.

  // TODO: Re-enable mint()
  describe('#mint()', () => {
    it('unmade scenes should not be mintable', async () => {
      const quantity = toBN(10);
      await truffleAssert.fails(
                myFactory.mint(SCENE_0, userA, quantity, "0x0", { from: owner }),
                truffleAssert.ErrorType.revert);
    });
    
    it("should make a scene", async () => {
      const packSize = 4;
      const tileH = 2;
      const tileW = 2;
      const cost = web3.utils.toWei("10", "finney");
      await myFactory.makeScene(SCENE_0, packSize, cost, tileW, tileH);
    });

    it("should add puzzles to a scene x4", async () => {
      await myFactory.addScenePuzzles(SCENE_0, 4);
    });

    it("should allow owner to mint", async () => {
      const quantity = toBN(10);
      await myFactory.mint(SCENE_0, userA, quantity, "0x0", { from: owner });

      // Check that the recipient got the correct quantity
      const balanceUserA = await myCollectible.balanceOf(userA, SCENE_0);
      assert.isOk(balanceUserA.eq(quantity));

      // Check that balance is correct
      const balanceOf = await myFactory.balanceOf(owner, SCENE_0);
      assert.isOk(balanceOf.eq(toBN(9990)));

      // Check that total supply is correct
      const totalSupply = await myCollectible.totalSupply(SCENE_0);
      assert.isOk(totalSupply.eq(quantity));
    });

    it('should be purchaseable by user', async () => {
      const option = SCENE_0;
      const amount = toBN(1);
      const cost = web3.utils.toWei("10", "finney");
      const receipt = await myFactory.buyScenePack(SCENE_0, 1, 
                                                   {from: userB, value: cost});
      const balanceOf = await myFactory.balanceOf(userB, SCENE_0);
      console.log(balanceOf);
      assert.isOk(balanceOf.eq(toBN(1)));
    });

    // it('should be openable by user', async () => {
    //     const option = SCENE_0;
    //     const amount = toBN(1);
    //     const cost = web3.utils.toWei("10", "finney");
    //     const receipt = await myFactory.buyScenePack(SCENE_0, 1, 
    //                                                  {from: userB, value: cost});
    //     const balanceOf = await myFactory.balanceOf(userB, SCENE_0);
    //     assert.isOk(balanceOf.eq(toBN(1)));
    //   });

//     it('should successfully use both create or mint internally', async () => {
//       const quantity = toBN(1000);
//       const total = quantity.mul(toBN(2));
//       // It would be nice to check the logs from these, but:
//       // https://ethereum.stackexchange.com/questions/71785/how-to-test-events-that-were-sent-by-inner-transaction-delegate-call
//       // Will use create.
//       await myFactory.mint(SCENE_1, userA, quantity, "0x0", { from: owner });
//       // Will use mint
//       await myFactory.mint(SCENE_1, userB, quantity, "0x0", { from: owner });
//       // Check that the recipients got the correct quantity
//       const balanceUserA = await myCollectible.balanceOf(userA, SCENE_1);
//       assert.isOk(balanceUserA.eq(quantity));
//       const balanceUserB = await myCollectible.balanceOf(userB, SCENE_1);
//       assert.isOk(balanceUserB.eq(quantity));
//       // Check that balance is correct
//       const balanceOf = await myFactory.balanceOf(owner, SCENE_1);
//       assert.isOk(balanceOf.eq(vals.MAX_UINT256_BN.sub(total)));
//       // Check that total supply is correct
//       const totalSupply1 = await myCollectible.totalSupply(2);
//       assert.isOk(totalSupply1.eq(total));
//     });

//     it('should allow proxy to mint', async () => {
//       const quantity = toBN(100);
//       //FIXME: move all quantities to top level constants
//       const total = toBN(1100);
//       await myFactory.mint(
//         SCENE_0,
//         userA,
//         quantity,
//         "0x0",
//         { from: proxyForOwner }
//       );
//       // Check that the recipient got the correct quantity
//       const balanceUserA = await myCollectible.balanceOf(userA, SCENE_0);
//       assert.isOk(balanceUserA.eq(total));
//       // Check that balance is correct
//       const balanceOf = await myFactory.balanceOf(owner, SCENE_0);
//       assert.isOk(balanceOf.eq(vals.MAX_UINT256_BN.sub(total)));
//       // Check that total supply is correct
//       const totalSupply = await myCollectible.totalSupply(SCENE_0);
//       assert.isOk(totalSupply.eq(total));
//     });
  });

  describe('#canMint()', () => {
    it('should return false for zero _amount', async () => {
      assert.isNotOk(await myFactory.canMint(SCENE_BASIC, 0, { from: userA }));
      assert.isNotOk(await myFactory.canMint(SCENE_BASIC, 0, { from: owner }));
      assert.isNotOk(
        await myFactory.canMint(SCENE_BASIC, 0, { from: proxyForOwner })
      );
    });

    it('should return false for non-owner and non-proxy', async () => {
      assert.isNotOk(await myFactory.canMint(SCENE_BASIC, 100, { from: userA }));
    });

  });

//   describe('#uri()', () => {
//     it('should return the correct uri for an option', async () =>
//       assert.equal(await myFactory.uri(SCENE_BASIC), `${vals.URI_BASE}factory/0`)
//       );

//     it('should format any number as an option uri', async () =>
//        assert.equal(
//          await myFactory.uri(vals.MAX_UINT256),
//          `${vals.URI_BASE}factory/${toBN(vals.MAX_UINT256).toString()}`
//        ));
//   });

  describe('#balanceOf()', () => {
    // it('should return 0 for un-minted token', async () => {
    //   const balanceProxy = await myFactory.balanceOf(
    //     proxyForOwner,
    //     NO_SUCH_SCENE
    //   );
    //   assert.isOk(balanceProxy.eq(0));
    // });

    it('should return zero for non-owner or non-proxy', async () => {
      assert.isOk((await myFactory.balanceOf(userA, SCENE_BASIC)).eq(toBN(0)));
      assert.isOk((await myFactory.balanceOf(userB, SCENE_1)).eq(toBN(0)));
    });
  });

  //NOTE: we should test safeTransferFrom with both an existing and not-yet-
  //      created token to exercise both paths in its calls of _create().
  //      But we test _create() in create() and we don't reset the contracts
  //      between describe() calls so we only test one path here, and let
  //      the other be tested in create().

  describe('#safeTransferFrom()', () => {
    // it('should work for owner()', async () => {
    //   const amount = toBN(100);
    //   const userBBalance = await myCollectible.balanceOf(userB, SCENE_0);
    //   await myFactory.safeTransferFrom(
    //     vals.ADDRESS_ZERO,
    //     userB,
    //     SCENE_0,
    //     amount,
    //     "0x0"
    //   );
    //   const newUserBBalance = await myCollectible.balanceOf(userB, SCENE_0);
    //   assert.isOk(newUserBBalance.eq(userBBalance.add(amount)));
    // });

    // it('should work for proxy', async () => {
    //   const amount = toBN(100);
    //   const userBBalance = await myCollectible.balanceOf(userB, SCENE_0);
    //   await myFactory.safeTransferFrom(
    //     vals.ADDRESS_ZERO,
    //     userB,
    //     SCENE_0,
    //     100,
    //     "0x0",
    //     { from: proxyForOwner }
    //   );
    //   const newUserBBalance = await myCollectible.balanceOf(userB, SCENE_0);
    //   assert.isOk(newUserBBalance.eq(userBBalance.add(amount)));
    // });

    it('should not be callable by non-owner() and non-proxy', async () => {
      const amount = toBN(100);
      await truffleAssert.fails(
        myFactory.safeTransferFrom(
          vals.ADDRESS_ZERO,
          userB,
          SCENE_0,
          amount,
          "0x0",
          { from: userB }
        ),
        truffleAssert.ErrorType.revert,
        'TileFactory#_mint: CANNOT_MINT_MORE'
      );
    });
  });

  describe('#isApprovedForAll()', () => {
    it('should approve owner as both _owner and _operator', async () => {
      assert.isOk(
        await myFactory.isApprovedForAll(owner, owner)
      );
    });

    it('should not approve non-owner as _owner', async () => {
      assert.isNotOk(
        await myFactory.isApprovedForAll(userA, owner)
      );
      assert.isNotOk(
        await myFactory.isApprovedForAll(userB, userA)
      );
    });

    it('should not approve non-proxy address as _operator', async () => {
      assert.isNotOk(
        await myFactory.isApprovedForAll(owner, userB)
      );
    });

    it('should approve proxy address as _operator', async () => {
      assert.isOk(
        await myFactory.isApprovedForAll(owner, proxyForOwner)
      );
    });

    it('should reject proxy as _operator for non-owner _owner', async () => {
      assert.isNotOk(
        await myFactory.isApprovedForAll(userA, proxyForOwner)
      );
    });
  });

  /**
   * NOTE: This check is difficult to test in a development
   * environment, due to the OwnableDelegateProxy. To get around
   * this, in order to test this function below, you'll need to:
   *
   * 1. go to TileFactory.sol, and
   * 2. modify _isOwnerOrProxy
   *
   * --> Modification is:
   *      comment out
   *         return owner() == _address || address(proxyRegistry.proxies(owner())) == _address;
   *      replace with
   *         return true;
   * Then run, you'll get the reentrant error, which passes the test
   **/

  describe('Re-Entrancy Check', () => {
    it('Should have the correct factory address set',
       async () => {
         assert.equal(await attacker.factoryAddress(), myFactory.address);
       });

    // With unmodified code, this fails with:
    //   TileFactory#_mint: CANNOT_MINT_MORE
    // which is the correct behavior (no reentrancy) for the wrong reason
    // (the attacker is not the owner or proxy).

    xit('Minting from factory should disallow re-entrancy attack',
       async () => {
         await truffleAssert.passes(
           myFactory.mint(1, userA, 1, "0x0", { from: owner })
         );
         await truffleAssert.passes(
           myFactory.mint(1, userA, 1, "0x0", { from: userA })
         );
         await truffleAssert.fails(
           myFactory.mint(
             1,
             attacker.address,
             1,
             "0x0",
             { from: attacker.address }
           ),
           truffleAssert.ErrorType.revert,
           'ReentrancyGuard: reentrant call'
         );
       });
  });
});
