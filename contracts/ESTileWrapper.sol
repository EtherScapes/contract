// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./escape/EscapeToken.sol";
import "./ESTilePack.sol";

/*
 *  ESTileWrapper implements a contract which allows tile packs to be purcahsed
 *  for ESCAPE or ETH.
 */
contract ESTileWrapper is Ownable
{
  using SafeMath for uint256;

  //////////////////////////////////////////////////////////////////////////////

  EscapeToken public escapeTokenContract;
  ESTilePack public esTilePackInstance;

  //////////////////////////////////////////////////////////////////////////////

  constructor(
    address _tendAddress,
    address _boxAddress
  )
    Ownable()
    public
  {
    escapeTokenContract = EscapeToken(_tendAddress);
    esTilePackInstance = ESTilePack(_boxAddress);
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
   *  Update contract address for the ESTilePack contract.
   */
  function setTilePackContractAddress(
    address _address
  )
    external
    onlyOwner
  {
    require(_address != address(0), "Can't set zero address");
    esTilePackInstance = ESTilePack(_address);
  }

  //////////////////////////////////////////////////////////////////////////////

  function buyPacksForCredits(
    uint256 _packId, 
    uint256 count
  ) 
    public 
  {
    uint256 packCostInCredits;
    bool canBuyForEth;
    (packCostInCredits, canBuyForEth) = esTilePackInstance.packCosts(_packId);
    packCostInCredits = packCostInCredits.mul(count);
    require(packCostInCredits > 0, "cannot cost 0 credits");
    require(escapeTokenContract.balanceOf(_msgSender()) >= packCostInCredits, "not enough escape to burn");
    escapeTokenContract.burn(_msgSender(), packCostInCredits);
    esTilePackInstance.mint(_msgSender(), _packId, count, "");
  }

  function buyPacksForETH(
    uint256 _packId,
    uint256 count
  ) 
    payable public 
  {
    uint256 packCostInCredits;
    bool canBuyForEth;
    (packCostInCredits, canBuyForEth) = esTilePackInstance.packCosts(_packId);
    require(canBuyForEth, "some things money can't buy");
    uint256 packCost = count.mul(0.1 ether);
    require(msg.value == packCost, "not enough eth");
    esTilePackInstance.mint(_msgSender(), _packId, count, "");
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
}
