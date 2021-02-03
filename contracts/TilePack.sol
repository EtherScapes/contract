pragma solidity ^0.5.11;

import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./Tile.sol";
import "./TileFactory.sol";
import "./ITilePack.sol";

/*
 *  TilePack - a randomized and openable pack of tiles that are tied to a scene.
 */
contract TilePack is ITilePack, Ownable, Pausable, ReentrancyGuard, TileFactory {
  using SafeMath for uint256;

  /*
   *  A TilePackOpened event is fired with the sceneId for which the pack is being purchased,
   *  the number of packs being purchased and the buyer address. The number of tiles sent
   *  is denoted by the `itemsMinted` variable.
   */
  event TilePackOpened(uint256 indexed sceneId, address indexed buyer, uint256 packsPurchased, uint256 itemsMinted);
  
  /*
   *  Warning event.
   */
  event Warning(string message, address account);

  /*
   *  Seed so random behaves "better".
   */  
  uint256 seed;
  
  /**
   * @param _proxyRegistryAddress The address of the OpenSea/Wyvern proxy registry
   *                              On Rinkeby: "0xf57b2c51ded3a29e6891aba85459d600256cf317"
   *                              On mainnet: "0xa5409ec958c83c3f309868babaca7c86dcb077c1"
   * @param _nftAddress The address of the non-fungible/semi-fungible item contract
   *                    that you want to mint/transfer with each open
   */
  constructor(
    address _proxyRegistryAddress,
    address _nftAddress
  ) TileFactory(
    _proxyRegistryAddress,
    _nftAddress
  ) public {
  }

  /*
   *  Owner only functions.
   */
  
  /**
   * @dev Improve pseudorandom number generator by letting the owner set the seed manually,
   * making attacks more difficult
   * @param _newSeed The new seed to use for the next transaction
   */
  function setSeed(uint256 _newSeed) public onlyOwner {
    seed = _newSeed;
  }

  ///////
  // MAIN FUNCTIONS
  //////

  function unpack(
    uint256 _sceneId,
    address _toAddress,
    uint256 _amount
  ) external {
    // This will underflow if msg.sender does not own enough tokens.
    _burn(msg.sender, _sceneId, _amount);

    // Mint nfts contained by this scene pack.
    _mint(_sceneId, _toAddress, _amount, "");
  }

  /**
   * @dev Open a pack manually and send what's inside to _toAddress
   * Convenience method for contract owner.
   */
  function open(
    uint256 _sceneId,
    address _toAddress,
    uint256 _amount
  ) external onlyOwner {
    _mint(_sceneId, _toAddress, _amount, "");
  }

  /**
   * @dev Main minting logic for packs
   * This is called via safeTransferFrom when TilePack extends TileFactory.
   * NOTE: prices and fees are determined by the sell order on OpenSea.
   */
  function _mint(
    uint256 _sceneId,
    address _toAddress,
    uint256 _amount,
    bytes memory /* _data */
  ) internal whenNotPaused nonReentrant {
    // Load settings for this box option
    Scene memory scene = scenes[_sceneId];
    
    require(_canMint(msg.sender, _sceneId, _amount), "TilePack#_mint: CANNOT_MINT");

    uint256 totalMinted = 0;

    // Iterate over the quantity of packs specified
    for (uint256 i = 0; i < _amount; i++) {
      // Iterate over the pack's set quantity
      uint256 quantitySent = 0;
      while (quantitySent < scene.packSize) {
        _sendTokenWithRandomPuzzleTile(_sceneId, _toAddress, 1);
        quantitySent += 1;
      }
      totalMinted += quantitySent;
    }

    // Event emissions
    emit TilePackOpened(_sceneId, _toAddress, _amount, totalMinted);
  }

  function withdraw() public onlyOwner {
    msg.sender.transfer(address(this).balance);
  }

  /////
  // Metadata methods
  /////

  function name() external view returns (string memory) {
    return "EtherScapes tile pack";
  }

  function symbol() external view returns (string memory) {
    return "TLPK";
  }

  function uri(uint256 _sceneId) external view returns (string memory) {
    return Strings.strConcat(
      baseMetadataURI,
      "scene/",
      Strings.uint2str(_sceneId)
    );
  }

  /////
  // HELPER FUNCTIONS
  /////

  // Returns the tokenId sent to _toAddress
  function _sendTokenWithRandomPuzzleTile(
    uint256 _sceneId,
    address _toAddress,
    uint256 _amount
  ) internal returns (uint256) {
    require(scenes[_sceneId].exists == true);
    // sceneTokens contains all available tokens for this scene - which is just
    // a big old lise of P * H * W tiles each of which has appropriate metadata
    // setup etc. We blindly grab from this list.
    uint256 numTiles = scenes[_sceneId].tilesWide.mul(scenes[_sceneId].tilesHigh);
    uint p = _random().mod(scenes[_sceneId].numPuzzles);
    uint i = _random().mod(numTiles);

    Tile nftContract = Tile(nftAddress);
    nftContract.mint(_toAddress, sceneTokens[_sceneId][p][i], _amount, "");
    return sceneTokens[_sceneId][p][i];
  }

  /**
   * @dev Pseudo-random number generator
   * NOTE: to improve randomness, generate it with an oracle
   */
  function _random() internal returns (uint256) {
    uint256 randomNumber = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender, seed)));
    seed = randomNumber;
    return randomNumber;
  }

  /**
   * @dev emit a Warning if we're not approved to transfer nftAddress
   */
  function _checkTokenApproval() internal {
    Tile nftContract = Tile(nftAddress);
    if (!nftContract.isApprovedForAll(owner(), address(this))) {
      emit Warning("TilePack contract is not approved for trading collectible by:", owner());
    }
  }

}
