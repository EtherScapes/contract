// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./BaseERC1155.sol";
import "./ESTile.sol";

/*
 *  ESTilePack implements a ERC1155 collectable pack-of-tiles. Packs can be 
 *  created and opened by this contract to get ESTile tokens for scenes.
 *
 *  Unlike the tile tokens which have no preset limit, the packs are limited and
 *  indirectly limit the tiles and tokens.
 */
contract ESTilePack is BaseERC1155
{
  using SafeMath for uint256;
  
  //////////////////////////////////////////////////////////////////////////////
  
  struct PackInfo {
    uint256 sceneId; // scene that this pack will generate tiles for.
    uint256 escapeCost; // Cost to buy pack in escape tokens, 0 = cannot buy.
    uint256 maxQuantity; // Max number of these packs sold.
    uint256 tilesPerPack; // Num tiles
    bool isPurchaseable; // If we can buy this for 0.10 eth a pack.
    bool exists;
  }

  //////////////////////////////////////////////////////////////////////////////

  /*
   *  Allow the owner to update the seed to improve randomness, maybe use an
   *  oracle eventually.
   */
  uint256 seed;

  /*
   *  Reference to the ESTile contract which should grant us rights to mint tile
   *  tokens.
   */
  ESTile public esTileContract;
  
  /*
   *  Mapping of created packs and their descriptions.
   */
  mapping (uint256 => PackInfo) internal packs;

  /*
   *  Maintain a hard cap on each pack - mint() will be limited by `packLeft`.
   */
  mapping (uint256 => uint256) internal packsLeft;

  //////////////////////////////////////////////////////////////////////////////
  
  /*
   *  Contract constructor, setup the base ERC1155 token and the data URI using
   *  the {id} substitution to save gas.
   */
  constructor(
    string memory _uri,
    address _nftAddress,
    address _proxyRegistryAddress
  )
    BaseERC1155(
      "EtherScapes shard pack",
      "SPAC",
      _uri,
      _proxyRegistryAddress
    )
    public
  {
    esTileContract = ESTile(_nftAddress);
  }

  //////////////////////////////////////////////////////////////////////////////

  /*
   *  Create a pack for a given scene. Packs are the only tokens we issue in 
   *  this ERC1155 contract. A pack unlocks tiles in a scene, can be purchased
   *  for ESCAPE credits and release N tiles on pack open. Some packs will be
   *  purchaseable for ETH and some only for ESCAPE.
   */
  function createPack(
    uint256 sceneId,
    uint256 escapeCost,
    uint256 tilesPerPack,
    uint256 packQuantity,
    bool isPurchaseable
  ) 
    external 
  {
    require(hasRole(CREATOR_ROLE, _msgSender()), "Not a creator");
    require(esTileContract.sceneExists(sceneId), "not a valid scene");

    // Keep track of the latest ID
    maxTokenID = maxTokenID.add(1);
    uint256 packTokenId = maxTokenID;
    PackInfo storage p = packs[packTokenId];
    p.exists = true;
    p.sceneId = sceneId;
    p.escapeCost = escapeCost;
    p.isPurchaseable = isPurchaseable;
    p.tilesPerPack = tilesPerPack;
    p.maxQuantity = packQuantity;
    packsLeft[packTokenId] = packQuantity;
  }

  //////////////////////////////////////////////////////////////////////////////
    
  function numPacksCreated() view public returns (uint256) { return maxTokenID; }

  /*
   *  Returns the pack and associated info for the pack. This is usually
   *  the sceneId, the cost to buy it, how many max and how many are left.
   *
   *  Returns:
   *    sceneId, escapeCost, isPurchaseable, tilesPerPack, maxQuant, packsLeft
   */
  function getPackInfo(
    uint256 packId
  ) 
    view 
    public 
    returns (uint256, uint256, bool, uint256, uint256, uint256) 
  {
    require(packs[packId].exists, "invalid pack");
    return (packs[packId].sceneId, 
            packs[packId].escapeCost, packs[packId].isPurchaseable, 
            packs[packId].tilesPerPack, 
            packs[packId].maxQuantity, packsLeft[packId]);
  }

  function packCosts(
    uint256 _packId
  ) 
    view 
    public 
    returns (uint256, bool) 
  {
    require(packs[_packId].exists);
    return (packs[_packId].escapeCost, packs[_packId].isPurchaseable);
  }

  //////////////////////////////////////////////////////////////////////////////

  /*
   *  User visible function to open() N number of packs. Each pack opened will
   *  burn the pack token, and mint the tile tokens required.
   */
  function open(
    uint256 _packId,
    uint256 _amount
  )
    external
  {
    // Open on behalf of ourself
    require(_packId != 0, "invalid pack, cannot open");
    openFor(_packId, _amount, _msgSender());
  }


  /*
   *  Open a pack for a approved user.
   */
  function openFor(
    uint256 _packTokenId,
    uint256 _amount,
    address _recipient
  )
    public
  {
    require(packs[_packTokenId].exists, "pack exists");
    require(
        _recipient == _msgSender() || isApprovedForAll(_recipient, _msgSender()),
        "ERC1155: caller is not owner nor approved"
    );

    // Burn the packs, decrease total supply
    _burn(_recipient, _packTokenId, _amount);
    totalSupply[_packTokenId] = totalSupply[_packTokenId].sub(_amount);
    
    // Iterate over the quantity of packs specified
    uint256 sz = packs[_packTokenId].tilesPerPack; //.mul(_amount);
    uint256[] memory tokenIdsToMint = new uint256[](sz);
    uint256[] memory quantitiesToMint = new uint256[](sz);
    
    uint256 tokenStart;
    uint256 numTiles;
    uint256 numPuzzles;
    (tokenStart, numTiles, numPuzzles) = esTileContract.tokenRangeForScene(packs[_packTokenId].sceneId);
    uint256 numTilesInScene = numTiles.mul(numPuzzles);
    
    for (uint256 packId = 0; packId < _amount; packId++) {
      for (uint256 i = 0; i < packs[_packTokenId].tilesPerPack; i++) {
        // Keep track of token IDs we're minting and their quantities
        tokenIdsToMint[i] = tokenStart.add(_random().mod(numTilesInScene));
        quantitiesToMint[i] = 1;
      }
      // Mint all of the tokens for this pack
      esTileContract.mintBatch(_recipient, tokenIdsToMint, quantitiesToMint, "");
    }
  }

  //////////////////////////////////////////////////////////////////////////////

  function mint(
    address _to,
    uint256 _id,
    uint256 _amount,
    bytes memory _data
  )
    public override
  {
    packsLeft[_id] = packsLeft[_id].sub(_amount, "not enough packs left");
    super.mint(_to, _id, _amount, _data);
  }

  function mintBatch(
    address _to,
    uint256[] memory _ids,
    uint256[] memory _amounts,
    bytes memory _data
  )
    public override
  {
    for (uint256 i = 0; i < _ids.length; i++) {
      packsLeft[_ids[i]] = packsLeft[_ids[i]].sub(_amounts[i], "not enough packs left");
    }
    super.mintBatch(_to, _ids, _amounts, _data);
  }

  //////////////////////////////////////////////////////////////////////////////

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
