// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

//////////////////////////////////////////////////////////////////////////////

import "./escape/EscapeToken.sol";
import "./ESTile.sol";

//////////////////////////////////////////////////////////////////////////////

/*
 *  ESTileWrapper implements a contract which allows tile packs to be purcahsed
 *  for ESCAPE or ETH.
 */
contract ESTileWrapper is Ownable
{
  using SafeMath for uint256;

  //////////////////////////////////////////////////////////////////////////////

  EscapeToken public escapeTokenContract;
  ESTile public esTileContract;

  //////////////////////////////////////////////////////////////////////////////

  uint256 seed;

  constructor(
    address _escapeAddress,
    address _estileAddress
  )
    Ownable()
    public
  {
    escapeTokenContract = EscapeToken(_escapeAddress);
    esTileContract = ESTile(_estileAddress);
  }

  //////////////////////////////////////////////////////////////////////////////

  /*
   *  Update contract address for the ESCAPE token.
   */
  function setEscapeTokenAddress(
    address _address
  )
    external
    onlyOwner
  {
    require(_address != address(0), "Can't set zero address");
    escapeTokenContract = EscapeToken(_address);
  }
  
  /*
   *  Update contract address for the ESTile contract.
   */
  function setESTileAddress(
    address _address
  )
    external
    onlyOwner
  {
    require(_address != address(0), "Can't set zero address");
    esTileContract = ESTile(_address);
  }

  //////////////////////////////////////////////////////////////////////////////

  function _mintTokensForScene(
    address recipient,
    uint256 sceneId,
    uint256 count
  )
    internal 
  {
    uint256 tokenStart;
    uint256 numTiles;
    uint256 numPuzzles;
    (tokenStart, numTiles, numPuzzles) = esTileContract.tokenRangeForScene(sceneId);
    uint256 numTilesInScene = numTiles.mul(numPuzzles);
    
    uint256[] memory tokenIdsToMint = new uint256[](count);
    uint256[] memory quantitiesToMint = new uint256[](count);

    for (uint256 i = 0; i < count; i++) {
      tokenIdsToMint[i] = tokenStart.add(_random().mod(numTilesInScene));
      quantitiesToMint[i] = 1;
    }

    esTileContract.mintBatch(recipient, tokenIdsToMint, quantitiesToMint, "");
  }

  function buyTilesForEscape(
    uint256 sceneId,
    uint256 count
  )
    public 
  {
    uint256 cost = count.mul(5 wei);
    require(cost > 0);
    escapeTokenContract.burn(_msgSender(), cost);
    _mintTokensForScene(msg.sender, sceneId, count);
  }

  function buyTilesForETH(
    uint256 sceneId,
    uint256 count
  )
    payable public 
  {
    uint256 tilesCost = count.mul(0.01 ether);
    require(msg.value >= tilesCost, "not enough eth");
    _mintTokensForScene(msg.sender, sceneId, count);
  }

  //////////////////////////////////////////////////////////////////////////////

  function withdrawBalance() 
    public 
    onlyOwner 
  {
    uint256 balance = address(this).balance;
    require(balance > 0, "no balance left");
    address payable owner = payable(owner());
    owner.transfer(balance);
  }

  function _random()
    internal
    returns (uint256)
  {
    uint256 randomNumber = uint256(
      keccak256(
        abi.encodePacked(
          blockhash(block.number - 1),
          msg.sender,
          seed
        )
      )
    );
    seed = randomNumber;
    return randomNumber;
  }

  function setSeed(
    uint256 _newSeed
  )
    public
    onlyOwner
  {
    seed = _newSeed;
  }
}
