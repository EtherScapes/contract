pragma solidity ^0.5.12;

/**
 *  TilePack is a generic interface for a pack of tiles.
 */
interface ITilePack {

  /**
   * Returns the name of this factory.
   */
  function name() external view returns (string memory);

  /**
   * Returns the symbol for this factory.
   */
  function symbol() external view returns (string memory);

  /**
   * Number of scenes that the factory supports.
   */
  function numScenes() external view returns (uint256);

  /**
   * @dev Returns whether the option ID can be minted. Can return false if the developer wishes to
   * restrict a total supply per option ID (or overall).
   */
  function canMint(uint256 _sceneId, uint256 _amount) external view returns (bool);

  /**
   * @dev Returns a URL specifying some metadata about the option. This metadata can be of the
   * same structure as the ERC1155 metadata.
   */
  function uri(uint256 _sceneId) external view returns (string memory);

  /**
   * Indicates that this is a factory contract. Ideally would use EIP 165 supportsInterface()
   */
  function supportsFactoryInterface() external view returns (bool);

  /**
   * Indicates the Wyvern schema name for assets in this lootbox, e.g. "ERC1155"
   */
  function factorySchemaName() external view returns (string memory);

  /**
    * @dev Mints or sends asset(s) in accordance to a specific address with a particular "option". This should be
    * callable only by the contract owner or the owner's Wyvern Proxy (later universal login will solve this).
    * Options should also be delineated 0 - (numOptions() - 1) for convenient indexing.
    * @param _sceneId the option id
    * @param _toAddress address of the future owner of the asset(s)
    * @param _amount amount of the option to mint
    */
  function open(uint256 _sceneId, address _toAddress, uint256 _amount) external;

  ////////
  // ADMINISTRATION
  ////////

  /**
   * @dev Withdraw lootbox revenue
   * Only accessible by contract owner
   */
  function withdraw() external;

  ///////
  // Get things to work on OpenSea with mock methods below
  ///////

  function safeTransferFrom(address _from, address _to, uint256 _sceneId, uint256 _amount, bytes calldata _data) external;

  function balanceOf(address _owner, uint256 _sceneId) external view returns (uint256);

  function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}