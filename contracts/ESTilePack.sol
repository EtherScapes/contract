// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

//import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BaseERC1155.sol";
import "./ESTile.sol";

/**
 * @title ESTilePack
 * ESTilePack - a contract for semi-fungible tokens
 */
contract ESTilePack is BaseERC1155
{
  using SafeMath for uint256;

  // Information for random card pack pulls
  uint256 seed;

  // NFT Contract
  ESTile public esTileContract;

  struct PackInfo {
    uint256 sceneId; // scene that this pack will generate tiles for.
    uint256 escapeCost; // Cost to buy pack in escape tokens, 0 = cannot buy.
    uint256 maxQuantity; // Max number of these packs sold.
    uint256 tilesPerPack; // Num tiles
    bool isPurchaseable; // If we can buy this for 0.01 eth a pack.
    bool exists;
  }

  // Mapping of all pack infos.
  mapping (uint256 => PackInfo) internal packs;

  // Mapping of packId -> how many of those packs we have left.
  mapping (uint256 => uint256) internal packsLeft;

  constructor(
    string memory _uri,
    address _nftAddress,
    address _proxyRegistryAddress
  )
    BaseERC1155(
      "EtherScape tile pack",
      "ESCpack",
      _uri,
      _proxyRegistryAddress
    )
    public
  {
    esTileContract = ESTile(_nftAddress);
  }

/**
 * Only Token Creator Functions
 **/
  function createPack(uint256 sceneId, uint256 escapeCost, uint256 tilesPerPack, uint256 packQuantity, bool isPurchaseable) external {
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


  // Open a pack
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


  // Open a pack
  function openFor(
    uint256 _packTokenId,
    uint256 _amount,
    address _recipient
  )
    public
  {
    // Operator check occurs here
    require(packs[_packTokenId].exists, "pack exists");
    require(
        _recipient == _msgSender() || isApprovedForAll(_recipient, _msgSender()),
        "ERC1155: caller is not owner nor approved"
    );

    // Burn the packs, decrease total supply
    _burn(_recipient, _packTokenId, _amount);
    totalSupply[_packTokenId] = totalSupply[_packTokenId].sub(_amount);
    
    // Iterate over the quantity of packs specified
    uint256 sz = packs[_packTokenId].tilesPerPack.mul(_amount);
    uint256[] memory tokenIdsToMint = new uint256[](sz);
    uint256[] memory quantitiesToMint = new uint256[](sz);
    
    uint256 tokenStart;
    uint256 numTiles;
    uint256 numPuzzles;
    (tokenStart, numTiles, numPuzzles) = esTileContract.tokenRangeForScene(packs[_packTokenId].sceneId);
    
    for (uint256 i = 0; i < packs[_packTokenId].tilesPerPack; i++) {
      quantitiesToMint[i] = 1;
    }
    for (uint256 packId = 0; packId < _amount; packId++) {
      for (uint256 i = 0; i < packs[_packTokenId].tilesPerPack; i++) {
        // Keep track of token IDs we're minting and their quantities
        tokenIdsToMint[i] = tokenStart + _random().mod(numTiles);
      }

      // Mint all of the tokens for this pack
      esTileContract.mintBatch(_recipient, tokenIdsToMint, quantitiesToMint, "");
    }
  }

  /* 
   * Override mint for the opened instantly packs.
   */
  function mint(
    address _to,
    uint256 _id,
    uint256 _amount,
    bytes memory _data
  )
    public override
  {
    packsLeft[_id].sub(_amount, "not enough packs left");
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
      packsLeft[_ids[i]].sub(_amounts[i], "not enough packs left");
    }
    super.mintBatch(_to, _ids, _amounts, _data);
  }
  
  function packCosts(uint256 _packId) view public returns (uint256, bool) {
    require(packs[_packId].exists);
    return (packs[_packId].escapeCost, packs[_packId].isPurchaseable);
  }

  /////
  // HELPER FUNCTIONS
  /////



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
