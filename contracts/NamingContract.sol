// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./escape/EscapeToken.sol";

/**
 * @title NamingContract
 * NamingContract - a contract to name etherscape solved puzzle tokens.
 */
contract NamingContract is Ownable
{
  using SafeMath for uint256;

  EscapeToken public escapeContractInstance;

  uint256 constant SCENE_NAMING_START_COST = 50; 
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
    address _escapeERC20Address
  )
    Ownable()
    public
  {
      escapeContractInstance = EscapeToken(_escapeERC20Address);
  }

/*
 *  Public.
 */

  /*
   *  Puzzle naming!
   */
  function nameTokenFor(address sender, uint256 puzzleTokenId, string calldata name) external {
    require(puzzleTokenId != 0, "invalid token");
    
    uint256 cost = puzzleTokenNamingCost[puzzleTokenId];
    if (cost == 0) {
        cost = SCENE_NAMING_START_COST;
    }

    escapeContractInstance.burn(sender, cost);
    puzzleTokenToPuzzleName[puzzleTokenId] = name;
    puzzleTokenNamingCost[puzzleTokenId] = cost.mul(SCENE_NAMING_MULTIPLIER);
    puzzleTokenNamedBy[puzzleTokenId] = sender;
  }
  
  function tokenNameInfo(uint256 puzzleTokenId) view external returns (uint256, string memory, address) {
    require(puzzleTokenId != 0, "invalid token");
    uint256 cost = puzzleTokenNamingCost[puzzleTokenId];
    if (cost == 0) {
        cost = SCENE_NAMING_START_COST;
    }
    return (cost, puzzleTokenToPuzzleName[puzzleTokenId], puzzleTokenNamedBy[puzzleTokenId]);
  }
}
