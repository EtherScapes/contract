// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./BaseERC1155.sol";
import "./NamingContract.sol";
import "./escape/EscapeToken.sol";

/*
 *  ESTile - This is a ERC1155 contract which allows for tiles and completed 
 *  puzzles to be tokenized. Scenes are a collection of puzzles, and puzzles
 *  are a collection of tiles. 
 *
 *  Basic rules:
 *  
 *  Only this contract can mint the finished puzzle tokens, and it will only
 *  do so when the a user tx trades in all N puzzle tiles for the said puzzle.
 *
 *  Only the creator can create scenes.
 *
 *  Only the minter can mint tiles and tokens.
 */
contract ESTile is BaseERC1155
{
  using SafeMath for uint256;

  /*
   *  Scenes are N number of pictures that have been split into a jigsaw. 
   *  Etherscapes are usually 6x4 tile puzzles and each scene will have N
   *  number of images within the scene - some unlockable via the packs for 
   *  sale, some unlockable only via solving puzzles (collect all N tiles in a
   *  single puzzle).
   */
  struct Scene {
    bool exists;
    
    // The number of purchaseable vs unlockable puzzles.
    uint256 numPuzzles;
    
    // Number of shards in a single puzzle.
    uint256 numTilesPerPuzzle;

    // The startToken for a scene is the first tile token of the first puzzle in
    // the scene. The startToken + (i * numTilesPerPuzzle) gets us the i'th 
    // puzzle's first tile token and so on. The start token + (numPuzzles * 
    // numTilesPerPuzzle) will get us to the first completed puzzle token.
    uint256 startToken;
  }

  // Collect a way to keep track of all full puzzle token holders. This is a 
  // claim database which tracks the block at which a user has a claim for, this
  // is unique per completed puzzle token and per user.
  mapping (address => uint256[]) claims;
  mapping (address => uint256) claimLength;
  
  /*
   *  Seed so the owner can update randomness once in a while. Eventually this
   *  can be replaced with an oracle.
   */
  uint256 seed;

  /*
   *  Deployed contracts that we interact with. 
   *
   *  The EscapeToken is needed so we can issue ESCAPE credits based on the 
   *  scene bonus pool (if applicable).
   *
   *  The NamingContract is needed to rename finished puzzles that the owner has
   *  solved (and owns the finished puzzle tile for).
   */
  EscapeToken internal escapeTokenContract;
  NamingContract internal namingContract;

  uint256 public sceneCount;
  mapping (uint256 => Scene) internal scenes;
  
  //////////////////////////////////////////////////////////////////////////////

  /*
   *  Constructor!
   */
  constructor(
    string memory _uri,
    address _proxyRegistryAddress,
    address _escapeERC20Address,
    address _namingContractAddress
  )
    BaseERC1155(
      "EtherScape shards",
      "SHARD",
      _uri,
      _proxyRegistryAddress
    )
    public
  {
      maxTokenID = 1;
      escapeTokenContract = EscapeToken(_escapeERC20Address);
      namingContract = NamingContract(_namingContractAddress);
  }

  //////////////////////////////////////////////////////////////////////////////

  /*
   *  Assign a scene worth of tokens, this will be based on the sceneId, the
   *  puzzleId and then width x height of tokens.
   */
  function createScene(
    uint256 sceneId,
    uint256 numPuzzles,
    uint256 numTilesPerPuzzle
  )
    external
  {
    require(hasRole(CREATOR_ROLE, _msgSender()), "not a creator");
    require(numPuzzles > 0 && numTilesPerPuzzle > 0, "bad dims");
    require(scenes[sceneId].exists == false, "scene already here");

    Scene storage s = scenes[sceneId];
    s.exists = true;
    s.numPuzzles = numPuzzles;
    s.numTilesPerPuzzle = numTilesPerPuzzle;
    
    // Setup the total scene reward for this scene that is available.
    // s.puzzleRewardTotal = puzzleRewardTotal;
    // s.puzzleRewardRate = puzzleRewardRate;
    // sceneRewardLeft[sceneId] = puzzleRewardTotal;
    
    uint256 tid = maxTokenID;
    s.startToken = tid;

    /*
     *  Create tokens to represent each puzzle in this scene. 
     *
     *  Each puzzle will have one additional token to track the completed puzzle
     *  that can only be acquired by burning all the subsequent puzzle tiles (1
     *  of each that make up the image).
     */
    uint256 numTokens = numTilesPerPuzzle
                          .add(1)
                          .mul(numPuzzles);

    // for (uint256 _p = 0; _p < numPuzzles; _p++) {
    //   for (uint256 _i = 0; _i < numTilesPerPuzzle; _i++) {
    //     sceneToPuzzleTileTokens[sceneId][_p].push(tid);
    //     tid = tid.add(1);
    //   }
    // }
    // for (uint256 _p = 0; _p < numPuzzles; _p++) {
    //   sceneToPuzzleToken[sceneId][_p] = tid;
    //   tid = tid.add(1);
    // }

    // Update latest id with the last 
    maxTokenID = maxTokenID.add(numTokens);
    sceneCount = sceneCount.add(1);
  }

  //////////////////////////////////////////////////////////////////////////////

  /*
   *  Public and inter-contract queries for scene desc info.
   */
  function sceneExists(uint256 sceneId) view external returns (bool) { return (scenes[sceneId].exists == true); }
  function tokenRangeForScene(uint256 sceneId) view public returns (uint256, uint256, uint256) {
    return (scenes[sceneId].startToken, scenes[sceneId].numTilesPerPuzzle, scenes[sceneId].numPuzzles);
  }
  function getScenePuzzleInfo(uint256 sceneId, uint256 puzzleId) public view returns (uint256, string memory, address) {
    return namingContract.tokenNameInfo(getPuzzleToken(sceneId, puzzleId));
  }
  
  //////////////////////////////////////////////////////////////////////////////

  /*
   *  User - contract interaction.
   */

  /*
   *  For a given scene, and puzzle - checks that the sender owns at-least one 
   *  each of the tile tokens that make up the puzzle. If so the sender burns 
   *  the tokens, and earns ESC and the completed token for the puzzle.
   */
  function redeemPuzzle(
    uint256 sceneId,
    uint256 puzzleId
  ) 
    external 
    returns (uint256) 
  {
    require(scenes[sceneId].exists == true, "scene does not exist");
    uint256 puzzleTokenId = getPuzzleToken(sceneId, puzzleId);
    uint256 tileTokenStart = getTileToken(sceneId, puzzleId, 0);
    uint256 tilesPerPuzzle = scenes[sceneId].numTilesPerPuzzle;
    for (uint256 i = 0; i < tilesPerPuzzle; i++) {
      uint256 tid = tileTokenStart.add(i);
      if (balanceOf(msg.sender, tileTokenStart.add(i)) <= 0) {
        revert("do not have all puzzle tokens");
      }
      totalSupply[tid] = totalSupply[tid].sub(1);
      _burn(msg.sender, tid, 1);
    }
    
    // Figure out the reward (full image token) for this pictureId and award it
    // the the sender who just burned all their puzzle tokens! In this case we 
    // bypass the mint() logic and directly award the token here as this is now
    // mintable by the redemption.
    totalSupply[puzzleTokenId] = totalSupply[puzzleTokenId].add(1);
    _mint(msg.sender, puzzleTokenId, 1, "");

    // Push a claim with this block number for this token.
    // claims[msg.sender].push(now);

    // // Mint additional ESCAPE tokens for the puzzle solver. The reward that the 
    // // solver gets is the `left * (rate / 10000)` of the pool. This can be per
    // // scene - and can be set to something like 5% (500) for example.
    // if (sceneRewardLeft[sceneId] > 0) {
    //   uint256 amt = sceneRewardLeft[sceneId].mul(scenes[sceneId].puzzleRewardRate).div(10000);
    //   sceneRewardLeft[sceneId] = sceneRewardLeft[sceneId].sub(amt);
    //   escapeTokenContract.mintForAccount(msg.sender, amt);
    // }
  }

  /*
   *  A claim is opened anytime a puzzle is solved, each claim is worth one 
   *  ESCAPE per day. When a token is transferred - you give up your oldest 
   *  claim! So it is best to claim rewards before transferring any completed 
   *  puzzle tokens.
   */
  function getClaimInfo()
    view 
    public 
    returns (uint256) 
  {
    uint256 total = 0;
    for (uint256 i = 0; i < claimLength[msg.sender]; i++) {
      uint256 reward = now.sub(claims[msg.sender][i])
                          .div(1 days);
      total = total.add(reward);
    }
    return total;
  } 

  function claimReward()
    public 
  {
    uint256 total = getClaimInfo();
    require(total > 0);
    for (uint256 i = 0; i < claimLength[msg.sender]; i++) {
      claims[msg.sender][i] = now;
    }
    escapeTokenContract.mintForAccount(msg.sender, total);
  } 

  function isPuzzleTokenId
  (
    uint256 id
  ) 
    view
    internal
    returns (bool) 
  {
    for (uint s = 0; s < sceneCount; s++) {
      uint256 pts = scenes[s].startToken
                      .add(scenes[s].numPuzzles.mul(scenes[s].numTilesPerPuzzle));
      uint256 pte = pts.add(scenes[s].numPuzzles);
      if (id >= pts && id < pte) return true;
    }
    return false;
  }

  function _beforeTokenTransfer
  (
    address /*operator*/,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory /*data*/
  )
    internal
    override
  {
    /*
     *  A new token was minted! If it is a full piece token - add the tracking
     *  for its claim here.
     */
    for (uint i = 0; i < ids.length; i++) {
      if (isPuzzleTokenId(ids[i])) {
        if (to != address(0)) {
          // New token minted, and its a puzzle token - add a claim for the 
          // count minted here.
          for (uint n = 0; n < amounts[i]; n++) {
            if (claims[to].length > claimLength[to]) {
              claims[to][claimLength[to]] = now;
            } else {
              claims[to].push(now);
            }
            claimLength[to] = claimLength[to].add(1);
          }
        }
        if (from != address(0)) {
          // This is a burn or a transfer, remove claims.
          claimLength[from] = claimLength[from].sub(amounts[i]);
        }
      }
    }
  }
  
  function getTileToken(
    uint256 sceneId,
    uint256 puzzleId,
    uint256 tileNum
  )
    internal 
    view
    returns (uint256) 
  {
    require(scenes[sceneId].exists == true, "scene does not exist");
    require(scenes[sceneId].numPuzzles > puzzleId);
    require(scenes[sceneId].numTilesPerPuzzle > tileNum);
    return scenes[sceneId].startToken
            .add(tileNum)
            .add(scenes[sceneId].numTilesPerPuzzle.mul(puzzleId));
  }

  function getPuzzleToken(
    uint256 sceneId,
    uint256 puzzleId
  )
    internal 
    view
    returns (uint256) 
  {
    require(scenes[sceneId].exists == true, "scene does not exist");
    require(scenes[sceneId].numPuzzles > puzzleId);
    return scenes[sceneId].startToken
            .add(puzzleId)
            .add(scenes[sceneId].numTilesPerPuzzle.mul(scenes[sceneId].numPuzzles));
  }

  /*
   *  Name a puzzle in a scene using the NamingContract (which has no idea about
   *  scenes or puzzles, just tokens). This will only invoke the naming contract
   *  if we have the appropriate puzzle token (solved picture).
   */
  function nameScenePuzzle(
    uint256 sceneId,
    uint256 puzzleId,
    string calldata name
  )
    external 
  {
    uint256 puzzleTokenId = getPuzzleToken(sceneId, puzzleId);
    require(balanceOf(msg.sender, puzzleTokenId) > 0, "only rename owned puzzles");
    namingContract.nameTokenFor(msg.sender, puzzleTokenId, name);
  }
}
