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
   *  sale, some unlockable only via solving puzzles (collect all 24 tiles in a
   *  single puzzle).
   */
  struct Scene {
    bool exists;
    
    // The number of purchaseable vs unlockable puzzles.
    uint256 numPuzzles;
    
    // Number of shards in a single puzzle.
    uint256 numTilesPerPuzzle;

    uint256 puzzleRewardTotal; // Total ESCAPE credits mintable for this scene.
    uint256 puzzleRewardRate;  // Rate at which each puzzle will drain the total 5 => .05% => 5/10000

    uint256 startToken;
  }
  
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

  /*
   *  For each scene, we have N puzzles with H*W puzzle tiles.
   */
  mapping (uint256 => mapping( uint256 => uint256[])) public sceneToPuzzleTileTokens;

  /*
   *  Additoinally, each scene and each puzzle in that scene has a unique token 
   *  to signify burning the tiles and owning the finished puzzle. This also 
   *  means that the creator of this token would have earned any possibly 
   *  credits left in this scenes reward pool.
   */
  mapping (uint256 => mapping( uint256 => uint256)) internal sceneToPuzzleToken;

  uint256 public sceneCount;
  mapping (uint256 => Scene) internal scenes;
  mapping (uint256 => uint256) internal sceneRewardLeft;
  
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
    uint256 numTilesPerPuzzle,
    uint256 puzzleRewardTotal,
    uint256 puzzleRewardRate
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
    s.puzzleRewardTotal = puzzleRewardTotal;
    s.puzzleRewardRate = puzzleRewardRate;
    sceneRewardLeft[sceneId] = puzzleRewardTotal;
    
    uint256 tid = maxTokenID;
    s.startToken = tid;

    /*
     *  Create tokens to represent each puzzle in this scene. 
     *
     *  Each puzzle will have one additional token to track the completed puzzle
     *  that can only be acquired by burning all the subsequent puzzle tiles (1
     *  of each that make up the image).
     */
    for (uint256 _p = 0; _p < numPuzzles; _p++) {
      for (uint256 _i = 0; _i < numTilesPerPuzzle; _i++) {
        sceneToPuzzleTileTokens[sceneId][_p].push(tid);
        tid = tid.add(1);
      }
    }
    for (uint256 _p = 0; _p < numPuzzles; _p++) {
      sceneToPuzzleToken[sceneId][_p] = tid;
      tid = tid.add(1);
    }

    // Update latest id with the last 
    maxTokenID = tid;
    sceneCount = sceneCount.add(1);
  }

  //////////////////////////////////////////////////////////////////////////////

  /*
   *  Public and inter-contract queries for scene desc info.
   */
  function sceneExists(uint256 sceneId) view external returns (bool) { return (scenes[sceneId].exists == true); }
  function scenePuzzles(uint256 sceneId) view external returns (uint256) { return scenes[sceneId].numPuzzles; }
  function sceneTiles(uint256 sceneId) view external returns (uint256) { return scenes[sceneId].numTilesPerPuzzle; }
  function tokenRangeForScene(uint256 sceneId) view public returns (uint256, uint256, uint256) {
    // Tokens start at (1 -> puzzles in scene * tiles per puzzle) +  puzzles in scene.
    return (scenes[sceneId].startToken, scenes[sceneId].numTilesPerPuzzle, scenes[sceneId].numPuzzles);
  }
  
  function getScenePuzzleInfo(uint256 sceneId, uint256 puzzleId) public view returns (uint256, string memory, address) {
    return namingContract.tokenNameInfo(sceneToPuzzleToken[sceneId][puzzleId]);
  }
  
  function puzzleRewardInfo(uint256 sceneId) view external returns (uint256, uint256, uint256) {
    return (scenes[sceneId].puzzleRewardTotal, scenes[sceneId].puzzleRewardRate, sceneRewardLeft[sceneId]);
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
    require(puzzleId < scenes[sceneId].numPuzzles, "invalid puzzle requested");
    
    uint256 puzzleTokenId = sceneToPuzzleToken[sceneId][puzzleId];
    require(puzzleTokenId != 0, "invalid puzzle token");
    
    uint256 tilesPerPuzzle = scenes[sceneId].numTilesPerPuzzle;
    for (uint256 i = 0; i < tilesPerPuzzle; i++) {
        if (balanceOf(msg.sender, sceneToPuzzleTileTokens[sceneId][puzzleId][i]) <= 0) {
            revert("do not have all puzzle tokens");
        }
    }
    for (uint256 i = 0; i < tilesPerPuzzle; i++) {
        uint256 tid = sceneToPuzzleTileTokens[sceneId][puzzleId][i];
        totalSupply[tid] = totalSupply[tid].sub(1);
        _burn(msg.sender, tid, 1);
    }
    
    // Figure out the reward (full image token) for this pictureId and award it
    // the the sender who just burned all their puzzle tokens!
    mint(msg.sender, puzzleTokenId, 1, "");

    // Mint additional ESCAPE tokens for the puzzle solver. The reward that the 
    // solver gets is the `left * (rate / 10000)` of the pool. This can be per
    // scene - and can be set to something like 5% (500) for example.
    if (sceneRewardLeft[sceneId] > 0) {
      uint256 amt = sceneRewardLeft[sceneId].mul(scenes[sceneId].puzzleRewardRate).div(10000);
      sceneRewardLeft[sceneId] = sceneRewardLeft[sceneId].sub(amt);
      escapeTokenContract.mintForAccount(msg.sender, amt);
    }
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
    require(scenes[sceneId].exists == true, "scene does not exist");
    require(puzzleId < scenes[sceneId].numPuzzles, "invalid puzzle requested");
    uint256 puzzleTokenId = sceneToPuzzleToken[sceneId][puzzleId];
    require(balanceOf(msg.sender, puzzleTokenId) > 0, "only rename owned puzzles");
    namingContract.nameTokenFor(msg.sender, puzzleTokenId, name);
  }
}
