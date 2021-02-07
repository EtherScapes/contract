// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./EscapeERC20.sol";

contract TestERC20 is EscapeERC20, Ownable {
    using SafeMath for uint256;

    constructor(string memory name, string memory symbol)
    public
    Ownable()
    EscapeERC20(name, symbol)
    {}

    function mint(address _to, uint256 _amount) public onlyOwner {
        return _mint(_to, _amount);
    }
}