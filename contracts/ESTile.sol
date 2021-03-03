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
   *  Etherscapes are usually M tile puzzles and each scene will have N
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

    uint256 maxTiles;
    uint256 tilesLeft;

    uint256 escapeCost;
    uint256 ethCost;
  }

  // Collect a way to keep track of all full puzzle token holders. This is a 
  // claim database which tracks the block at which a user has a claim for, this
  // is unique per completed puzzle token and per user.
  mapping (address => uint256[]) claims;
  mapping (address => uint256) public claimLength;
  
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

  uint256 public sceneCount;
  mapping (uint256 => Scene) internal scenes;

  // Debugging ... 
  // uint256 constant REWARD_INTERVAL = 2 seconds;
  uint256 constant REWARD_INTERVAL = 1 days;
    
  //////////////////////////////////////////////////////////////////////////////

  /*
   *  Constructor!
   */
  constructor(
    string memory _uri,
    address _proxyRegistryAddress,
    address _escapeERC20Address
  )
    BaseERC1155(
      "EtherScapes shards",
      "SHARD",
      _uri,
      _proxyRegistryAddress
    )
    public
  {
      maxTokenID = 1;
      sceneCount = 0;
      escapeTokenContract = EscapeToken(_escapeERC20Address);
  }

  //////////////////////////////////////////////////////////////////////////////

  /*
   *  Assign a scene worth of tokens, this will be based on the sceneId, the
   *  puzzleId and then width x height of tokens.
   */
  function createScene(
    uint256 numPuzzles,
    uint256 numTilesPerPuzzle,
    uint256 maxTilesForSale,
    uint256 ethCost,
    uint256 escapeCost
  )
    external
  {
    require(hasRole(CREATOR_ROLE, _msgSender()), "not a creator");
    require(numPuzzles > 0 && numTilesPerPuzzle > 0, "bad dims");
    require(escapeCost > 0, "bad cost");
    
    /*
     *  Create tokens to represent each puzzle in this scene. 
     *
     *  Each puzzle will have one additional token to track the completed puzzle
     *  that can only be acquired by burning all the subsequent puzzle tiles (1
     *  of each that make up the image).
     */
    sceneCount = sceneCount.add(1);

    uint256 sceneId = sceneCount;
    uint256 tid = maxTokenID;
    uint256 numTokens = numTilesPerPuzzle
                          .add(1)
                          .mul(numPuzzles);
    maxTokenID = maxTokenID.add(numTokens);

    Scene storage s = scenes[sceneId];
    s.exists = true;
    s.numPuzzles = numPuzzles;
    s.numTilesPerPuzzle = numTilesPerPuzzle;
    s.startToken = tid;
    s.tilesLeft = maxTilesForSale;
    s.maxTiles = maxTilesForSale;
    s.ethCost = ethCost;
    s.escapeCost = escapeCost;
  }

  //////////////////////////////////////////////////////////////////////////////

  /*
   *  Public and inter-contract queries for scene desc info.
   */
  function sceneExists(uint256 sceneId) view external returns (bool) { return (scenes[sceneId].exists == true); }
  function sceneShardInfo(uint256 sceneId) view external returns (uint256, uint256, uint256) { return (scenes[sceneId].tilesLeft, scenes[sceneId].ethCost, scenes[sceneId].escapeCost); }
  function tokenRangeForScene(uint256 sceneId) view public returns (uint256, uint256, uint256) {
    return (scenes[sceneId].startToken, scenes[sceneId].numTilesPerPuzzle, scenes[sceneId].numPuzzles);
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
    uint256 puzzleTokenId = getPuzzleToken(sceneId, puzzleId);
    uint256 tileTokenStart = getTileToken(sceneId, puzzleId, 0);
    uint256 tilesPerPuzzle = scenes[sceneId].numTilesPerPuzzle;
    for (uint256 i = 0; i < tilesPerPuzzle; i++) {
      uint256 tid = tileTokenStart.add(i);
      totalSupply[tid] = totalSupply[tid].sub(1);
      _burn(msg.sender, tid, 1);
    }
    
    // Figure out the reward (full image token) for this pictureId and award it
    // the the sender who just burned all their puzzle tokens! In this case we 
    // bypass the mint() logic and directly award the token here as this is now
    // mintable by the redemption.
    totalSupply[puzzleTokenId] = totalSupply[puzzleTokenId].add(1);
    _mint(msg.sender, puzzleTokenId, 1, "");
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
                          .div(REWARD_INTERVAL);
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
    for (uint s = 1; s <= sceneCount; s++) {
      uint256 pts = scenes[s].startToken
                      .add(scenes[s].numPuzzles.mul(scenes[s].numTilesPerPuzzle));
      uint256 pte = pts.add(scenes[s].numPuzzles);
      if (id >= pts && id < pte) return true;
    }
    return false;
  }

  function getSceneForToken
  (
    uint256 id
  ) 
    view
    internal
    returns (uint256) 
  {
    for (uint s = 1; s <= sceneCount; s++) {
      uint256 pts = scenes[s].startToken;
      uint256 pte = pts
                      .add(scenes[s].numPuzzles)
                      .add(scenes[s].numPuzzles.mul(scenes[s].numTilesPerPuzzle));
      if (id >= pts && id < pte) return s;
    }
    revert("bad scene");
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
          uint256 claimIdx = claimLength[to];
          for (uint n = 0; n < amounts[i]; n++) {
            if (claims[to].length > claimIdx) {
              claims[to][claimIdx] = now;
            } else {
              claims[to].push(now);
            }
            claimIdx = claimIdx.add(1);
          }
          claimLength[to] = claimIdx;
        }
        if (from != address(0)) {
          // This is a burn or a transfer, remove claims.
          claimLength[from] = claimLength[from].sub(amounts[i]);
        }
      } else {
        /* else this is a non puzzle token, these are limited by scene */
        uint256 sid = getSceneForToken(ids[i]);
        if (from == address(0)) {
          scenes[sid].tilesLeft = scenes[sid].tilesLeft.sub(amounts[i]);
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
    public
    view
    returns (uint256) 
  {
    require(scenes[sceneId].exists == true, "scene does not exist");
    require(scenes[sceneId].numPuzzles > puzzleId);
    return scenes[sceneId].startToken
            .add(puzzleId)
            .add(scenes[sceneId].numTilesPerPuzzle.mul(scenes[sceneId].numPuzzles));
  }
}
