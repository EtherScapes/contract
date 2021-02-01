pragma solidity ^0.5.11;

import "./ERC1155Tradable.sol";

/*
 *  Tile - a contract for etherscapes jigsaw tiles.
 */
contract Tile is ERC1155Tradable {
  constructor(address _proxyRegistryAddress)
  ERC1155Tradable(
    "EtherScape Tile",
    "ESTL",
    _proxyRegistryAddress
  ) public {
    _setBaseMetadataURI("https://raw.githubusercontent.com/etherscapes/metadata/master/");
  }

  /*
   *  Describe where to find the contracts JSON description.
   */
   function contractURI() public pure returns (string memory) {
    return "https://raw.githubusercontent.com/etherscapes/metadata/master/contract-description.json";
  }
}
