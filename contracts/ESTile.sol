// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./BaseERC1155.sol";
import "./NamingContract.sol";
import "./escape/EscapeToken.sol";

/**
 * @title ESTile
 * ESTile - a contract for semi-fungible tokens
 */
contract ESTile is BaseERC1155
{
  using SafeMath for uint256;

  uint256 seed;

  EscapeToken internal escapeTokenContract;
  NamingContract internal namingContract;

  // Keep track of each token type that we allocate - these are the tile tokens
  // and the full puzzle tokens. 
  mapping (uint256 => uint256) public tokenCounts;

  // For each scene, we have N puzzles with H*W puzzle tiles - keep track of em.
  mapping (uint256 => mapping( uint256 => uint256[])) public sceneToPuzzleTileTokens;

  // Finally, each scene and each puzzle in that scene has a unique token to 
  // signify burning the tiles and owning the finished puzzle. This also means
  // that the creator of this token would have earned any possibly credits left
  // in this scenes reward pool.
  mapping (uint256 => mapping( uint256 => uint256)) internal sceneToPuzzleToken;

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
    
    // These are the dimensions of all tiles in this scene.
    uint256 tilesWide;
    uint256 tilesHigh;

    uint256 puzzleRewardTotal; // Total ESCAPE credits mintable for this scene.
    uint256 puzzleRewardRate;  // Rate at which each puzzle will drain the total 5 => .05% => 5/10000

    uint256 startToken;
    uint256 numTiles;
  }

  // TODO: internal
  uint256 sceneCount;
  mapping (uint256 => Scene) public scenes;
  mapping (uint256 => uint256) public sceneRewardLeft;

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
      "EtherScape puzzle tile",
      "ESCtile",
      _uri,
      _proxyRegistryAddress
    )
    public
  {
      maxTokenID = 1;
      escapeTokenContract = EscapeToken(_escapeERC20Address);
      namingContract = NamingContract(_namingContractAddress);
  }


/**
 * Only Token Creator Functions
 **/

  /*
   *  Assign a scene worth of tokens, this will be based on the sceneId, the
   *  puzzleId and then width x height of tokens.
   */
  function createScene(
    uint256 sceneId,
    uint256 numPuzzles,
    uint256 puzzleWidth,
    uint256 puzzleHeight,
    uint256 puzzleRewardTotal,
    uint256 puzzleRewardRate
  )
    external
  {
    require(hasRole(CREATOR_ROLE, _msgSender()), "not a creator");
    require(numPuzzles > 0 && puzzleHeight > 0 && puzzleWidth > 0, "bad dims");
    require(scenes[sceneId].exists == false, "scene already here");

    Scene storage s = scenes[sceneId];
    s.exists = true;
    s.numPuzzles = numPuzzles;
    s.tilesHigh = puzzleHeight;
    s.tilesWide = puzzleWidth;
    s.puzzleRewardTotal = puzzleRewardTotal;
    s.puzzleRewardRate = puzzleRewardRate;
    
    // Setup the total scene reward for this scene that is available.
    sceneRewardLeft[sceneId] = puzzleRewardTotal;

    uint256 tid = maxTokenID;
    s.startToken = tid;
    s.numTiles = numPuzzles.mul(puzzleWidth.mul(puzzleHeight));

    /*
     *  Create tokens to represent each puzzle in this scene. 
     *
     *  Each puzzle will have one additional token to track the completed puzzle
     *  that can only be acquired by burning all the subsequent puzzle tiles (1
     *  of each that make up the image).
     */
    for (uint256 _p = 0; _p < numPuzzles; _p++) {
      for (uint256 _h = 0; _h < puzzleHeight; _h++) {
        for (uint256 _w = 0; _w < puzzleWidth; _w++) {
          sceneToPuzzleTileTokens[sceneId][_p].push(tid);
          tid = tid.add(1);
        }
      }
    }
    for (uint256 _p = 0; _p < numPuzzles; _p++) {
      sceneToPuzzleToken[sceneId][_p] = tid;
      tid = tid.add(1);
    }

    // Update latest id with the last 
    maxTokenID = tid;
  }
  function scenePuzzles(uint256 sceneId) view external returns (uint256) {
    return scenes[sceneId].numPuzzles;
  }
  function sceneTiles(uint256 sceneId) view external returns (uint256) {
    return scenes[sceneId].tilesWide.mul(scenes[sceneId].tilesHigh);
  }
  function sceneExists(uint256 sceneId) view external returns (bool) {
    return (scenes[sceneId].exists == true);
  }
  function puzzleRewardInfo(uint256 sceneId) view external returns (uint256, uint256, uint256) {
    return (scenes[sceneId].puzzleRewardTotal, scenes[sceneId].puzzleRewardRate, sceneRewardLeft[sceneId]);
  }

/*
 *  Public.
 */
//   function randomSceneTile(uint256 _sceneId) external returns (uint256) {
//     uint pidx = _random().mod(scenes[_sceneId].numPuzzles);
//     uint tidx = _random().mod(scenes[_sceneId].tilesHigh.mul(scenes[_sceneId].tilesWide));
//     return sceneToPuzzleTileTokens[_sceneId][pidx][tidx];
//   }


  function tokenRangeForScene(uint256 sceneId) view public returns (uint256, uint256, uint256) {
    // Tokens start at (1 -> puzzles in scene * tiles per puzzle) +  puzzles in scene.
    return (scenes[sceneId].startToken, scenes[sceneId].numTiles, scenes[sceneId].numPuzzles);
  }

  /*
   *  For a given scene, and puzzle - checks that the sender owns at-least one 
   *  each of the tile tokens that make up the puzzle. If so the sender burns 
   *  the tokens, and two items are awarded to the sender:
   *    1. A completed token for the scene / puzzle
   *    2. A randomly choosen reward pack potentially of a limited scene
   *    The second reward might have to be figured out by the TilePack. In this
   *    case the tile pack would need to be the one that `redeemPuzzle`s.
   */
  function redeemPuzzle(uint256 sceneId, uint256 puzzleId) external returns (uint256) {
    require(scenes[sceneId].exists == true, "scene does not exist");
    require(puzzleId < scenes[sceneId].numPuzzles, "invalid puzzle requested");
    
    uint256 puzzleTokenId = sceneToPuzzleToken[sceneId][puzzleId];
    require(puzzleTokenId != 0, "invalid puzzle token");
    
    uint256 tilesPerPuzzle = scenes[sceneId].tilesHigh.mul(scenes[sceneId].tilesWide);
    for (uint256 i = 0; i < tilesPerPuzzle; i++) {
        if (balanceOf(msg.sender, sceneToPuzzleTileTokens[sceneId][puzzleId][i]) <= 0) {
            revert("do not have all puzzle tokens");
        }
    }
    for (uint256 i = 0; i < tilesPerPuzzle; i++) {
        _burn(msg.sender, sceneToPuzzleTileTokens[sceneId][puzzleId][i], 1);
    }
    
    // Figure out the reward (full image token) for this pictureId and award it
    // the the sender who just burned all their puzzle tokens!
    _mint(msg.sender, puzzleTokenId, 1, "");

    // Mint additional ESCAPE tokens for the puzzle solver. The reward that the 
    // solver gets is the `left * (rate / 10000)` of the pool. This can be per
    // scene - and can be set to something like 5% (500) for example.
    if (sceneRewardLeft[sceneId] > 0) {
      uint256 amt = sceneRewardLeft[sceneId].mul(500).div(10000);
      sceneRewardLeft[sceneId] = sceneRewardLeft[sceneId].sub(amt);
      escapeTokenContract.mintForAccount(msg.sender, amt);
    }
  }

  function nameScenePuzzle(uint256 sceneId, uint256 puzzleId, string calldata name) external {
    require(scenes[sceneId].exists == true, "scene does not exist");
    require(puzzleId < scenes[sceneId].numPuzzles, "invalid puzzle requested");
    uint256 puzzleTokenId = sceneToPuzzleToken[sceneId][puzzleId];
    namingContract.nameTokenFor(msg.sender, puzzleTokenId, name);
  }

  function getScenePuzzleInfo(uint256 sceneId, uint256 puzzleId) public view returns (uint256, string memory, address) {
    return namingContract.tokenNameInfo(sceneToPuzzleToken[sceneId][puzzleId]);
  }
}
