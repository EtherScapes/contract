// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./escape/EscapeToken.sol";
import "./ESTile.sol";

/**
 * @title NamingContract
 * NamingContract - a contract to name etherscape solved puzzle tokens.
 */
contract NamingContract is Ownable
{
  using SafeMath for uint256;

  EscapeToken public escapeContractInstance;
  ESTile public estileContract;

  uint256 constant SCENE_NAMING_START_COST = 5; 
  uint256 constant SCENE_NAMING_MULTIPLIER = 2; // 2x after each naming.

  // Each scene puzzle may also have a unique name (up to 32 bytes). Note that
  // this is a mapping from the puzzleTokenToPuzzleName which means it is 
  // indexed by the token of the completed puzzle not the scene / puzzle etc.
  mapping (uint256 => string) puzzleTokenToPuzzleName;
  
  // Since each puzzle's naming cost goes up by N* each time it is renamed, 
  // we maintian the current cost for each tile etc. All cost starts off at
  // SCENE_NAMING_START_COST credits.
  mapping (uint256 => uint256) puzzleTokenNamingCost;
  mapping (uint256 => address) puzzleTokenNamedBy;

  /*
   *  Constructor!
   */
  constructor(
    address _escapeERC20Address,
    address _estileAddress
  )
    Ownable()
    public
  {
      escapeContractInstance = EscapeToken(_escapeERC20Address);
      estileContract = ESTile(_estileAddress);
  }

/*
 *  Public.
 */

  /*
   *  Puzzle naming!
   */

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
    uint256 puzzleTokenId = estileContract.getPuzzleToken(sceneId, puzzleId);
    require(estileContract.balanceOf(msg.sender, puzzleTokenId) > 0, "only rename owned puzzles");
    
    uint256 cost = puzzleTokenNamingCost[puzzleTokenId];
    if (cost == 0) {
      cost = SCENE_NAMING_START_COST;
    }

    escapeContractInstance.burn(msg.sender, cost);
    puzzleTokenToPuzzleName[puzzleTokenId] = name;
    puzzleTokenNamingCost[puzzleTokenId] = cost.mul(SCENE_NAMING_MULTIPLIER);
    puzzleTokenNamedBy[puzzleTokenId] = msg.sender;
  }

  function getScenePuzzleInfo(
    uint256 sceneId, 
    uint256 puzzleId
  ) 
    public 
    view 
    returns (uint256, string memory, address) 
  {
    uint256 puzzleTokenId = estileContract.getPuzzleToken(sceneId, puzzleId);
    require(puzzleTokenId != 0, "invalid token");
    uint256 cost = puzzleTokenNamingCost[puzzleTokenId];
    if (cost == 0) {
        cost = SCENE_NAMING_START_COST;
    }
    return (cost, puzzleTokenToPuzzleName[puzzleTokenId], puzzleTokenNamedBy[puzzleTokenId]);
  }
  
}
