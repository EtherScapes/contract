pragma solidity ^0.5.11;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "./ITileFactory.sol";
import "./Tile.sol";
import "./Strings.sol";

// WIP
contract TileFactory is ITileFactory, Ownable, ReentrancyGuard {
  using Strings for string;
  using SafeMath for uint256;

  address public proxyRegistryAddress;
  address public nftAddress;
  string constant internal baseMetadataURI = "https://raw.githubusercontent.com/etherscapes/metadata/master/";
  uint256 constant UINT256_MAX = ~uint256(0);

  /**
   * Optionally set this to a small integer to enforce limited existence per option/token ID
   * (Otherwise rely on sell orders on OpenSea, which can only be made by the factory owner.)
   */
  uint256 constant SUPPLY_PER_TOKEN_ID = (10000);

  /*
   *  Scenes are N number of pictures that have been split into a jigsaw. 
   *  Etherscapes are usually 6x4 tile puzzles and each scene will have N
   *  number of images within the scene - some unlockable via the packs for 
   *  sale, some unlockable only via solving puzzles (collect all 24 tiles in a
   *  single puzzle).
   */
  struct Scene {
      bool exists;
      uint256 rewardsScene;

      // tiles per pack
      uint packSize;

      // The number of purchaseable vs unlockable puzzles.
      uint numPuzzles;
      // These are the dimensions of all tiles in this scene.
      uint tilesWide;
      uint tilesHigh;
  }

  /*
   *  Manually created scenes and their storage.
   */
  mapping (uint256 => Scene) public scenes;
  uint256 sceneCount;

  /*
   *  Contract tokenIDs for each scene. These are limited to the count specified
   *  above.
   */
  mapping (uint256 => uint256) public sceneIDToTokenID;

  /*
   *  A mapping of sceneId -> a list of all tile tokens assigned to this scene.
   */
  mapping (uint256 => uint256[]) public sceneTokens;


  constructor(address _proxyRegistryAddress, address _nftAddress) public {
    proxyRegistryAddress = _proxyRegistryAddress;
    nftAddress = _nftAddress;
    sceneCount = 0;
  }

  function makeScene(uint256 sceneId, uint ps, uint np, uint w, uint h, uint256 rewardSceneId) public onlyOwner {
    require(sceneId != 0);
    require(scenes[sceneId].exists != true);
    require(ps > 0 && np > 0 && w > 0 && h > 0);
    require(sceneIDToTokenID[sceneId] == 0, "TileFactory#makeScene: SCENE_ID_EXISTS");

    scenes[sceneId] = Scene({
      exists: true,
      rewardsScene: rewardSceneId,
      packSize: ps,
      numPuzzles: np,
      tilesWide: w, 
      tilesHigh: h
    });
    sceneCount = sceneCount + 1;

    Tile nftContract = Tile(nftAddress);
    uint256 sceneTokenId = nftContract.create(
                              msg.sender, 0,  
                              Strings.strConcat(baseMetadataURI, "scene/{id}/meta.json"), 
                              "0x0");
    sceneIDToTokenID[sceneId] = sceneTokenId;
    for (uint _p=0; _p < np; _p++) {
      for (uint _h=0; _h < h; _h++) {
        for (uint _w=0; _w < w; _w++) {
          string memory tile = Strings.strConcat(Strings.uint2str(_p), "/", Strings.uint2str(_h), "-", Strings.uint2str(_w));
          // Force the creation for this tile in this scene, with 0 initial supply.
          uint256 puzzleTileTokenId = nftContract.create(msg.sender, 0,  
                                        Strings.strConcat(baseMetadataURI, "scene/{id}/", tile, ".json"), 
                                        "0x0");
          
          // Store it in the list of tokens created for this scene.
          sceneTokens[sceneId].push(puzzleTileTokenId);
        }
      }
    }
  }

  /////
  // IFACTORY METHODS
  /////

  function name() external view returns (string memory) {
    return "EtherScapes Scene Packs";
  }

  function symbol() external view returns (string memory) {
    return "ESSP";
  }

  function supportsFactoryInterface() external view returns (bool) {
    return true;
  }

  function factorySchemaName() external view returns (string memory) {
    return "ERC1155";
  }

  function numScenes() external view returns (uint256) {
    return sceneCount;
  }

  function canMint(uint256 _sceneId, uint256 _amount) external view returns (bool) {
    return _canMint(msg.sender, _sceneId, _amount);
  }

  function mint(uint256 _sceneId, address _toAddress, uint256 _amount, bytes calldata _data) external nonReentrant() {
    return _mint(_sceneId, _toAddress, _amount, _data);
  }

  function uri(uint256 _sceneId) external view returns (string memory) {
    return Strings.strConcat(
      baseMetadataURI, "scene/", Strings.uint2str(_sceneId), "/meta.json");
  }

  /**
   * @dev Mint packs (for each sceneId) - this enforces the number of packs 
   *      per scene. 
   */
  function _mint(
    uint256 _sceneId,
    address _toAddress,
    uint256 _amount,
    bytes memory _data
  ) internal {
    require(_canMint(msg.sender, _sceneId, _amount), "TileFactory#_mint: CANNOT_MINT_MORE");
    
    uint256 id = sceneIDToTokenID[_sceneId];
    require(id != 0, "TileFactory#_mint: INVALID_SCENE");
    
    /*
     *  Here we create `scene` tokens - these are essentially the card packs that we can open.
     *  These will be limited by the TileFactory logic.
     */
    Tile nftContract = Tile(nftAddress);
    nftContract.mint(_toAddress, id, _amount, _data);
  }

  /**
   * Get the factory's ownership of SceneID.
   * Should be the amount it can still mint.
   * NOTE: Called by `canMint`
   */
  function balanceOf(
    address _owner,
    uint256 _sceneId
  ) public view returns (uint256) {
    if (!_isOwnerOrProxy(_owner)) {
      // Only the factory owner or owner's proxy can have supply
      return 0;
    }

    // This can be a scene, or a tile - scenes are limited to the SUPPLY_PER_TOKEN_ID
    // while the tiles themselves are random and unlimited but cannot be minted once
    // a fixed number of packs have been sold for a given scene. Scenes are guaranteed
    // to be minted by the owner of the contract when setting up each drop. This means
    // that if we hit a non-valid scene - we return max supply. If we hit a valid scene
    // we return the current supply.
    uint256 id = sceneIDToTokenID[_sceneId];
    if (id == 0) {
      return 0;
    }

    Tile nftContract = Tile(nftAddress);
    uint256 currentSupply = nftContract.totalSupply(id);
    return SUPPLY_PER_TOKEN_ID.sub(currentSupply);
  }

  /**
   * Hack to get things to work automatically on OpenSea.
   * Use safeTransferFrom so the frontend doesn't have to worry about different method names.
   */
  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _sceneId,
    uint256 _amount,
    bytes calldata _data
  ) external {
    _mint(_sceneId, _to, _amount, _data);
  }

  //////
  // Below methods shouldn't need to be overridden or modified
  //////

  function isApprovedForAll(
    address _owner,
    address _operator
  ) public view returns (bool) {
    return owner() == _owner && _isOwnerOrProxy(_operator);
  }

  function _canMint(
    address _fromAddress,
    uint256 _sceneId,
    uint256 _amount
  ) internal view returns (bool) {
    return _amount > 0 && balanceOf(_fromAddress, _sceneId) >= _amount;
  }

  function _isOwnerOrProxy(
    address _address
  ) internal view returns (bool) {
    ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
    return owner() == _address || address(proxyRegistry.proxies(owner())) == _address;
  }
}
