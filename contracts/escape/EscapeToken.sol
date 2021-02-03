// SPDX-License-Identifier: MIT

/**
 *
 * note: several functions here are overriden, this contract is NOT
 * meant to be used in production, it is a modified version of the
 * Escapeies contract used on mainnet, and it is only intended for
 * testing functions in the wrapper / proxy contract(s).
 *
 **/

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./EscapeERC20.sol";

interface IUniswapV2Pair {
    function sync() external;
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract EscapeToken is EscapeERC20, Ownable {
    using SafeMath for uint256;

    address public pauser;
    address public esTileAddress;
    bool public paused;

    // MODIFIERS
    modifier onlyPauser() {
        require(pauser == _msgSender(), "EscapeToken: caller is not the pauser.");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "EscapeToken: paused");
        _;
    }

    modifier onlyMinter() {
        require(esTileAddress == _msgSender(), "Ownable: caller is not the esTileAddress");
        _;
    }

    modifier onlyOwnerOrEsTileContract() {
        require(esTileAddress == _msgSender() || owner() == _msgSender(), "Ownable: caller is not the owner or esTileAddress");
        _;
    }
    
    // EVENTS
    constructor()
    public
    Ownable()
    EscapeERC20("EtherScapes credits", "ESCAPE")
    {
        _mint(msg.sender, 0);
        setPauser(msg.sender);
        paused = false;
    }

    function setMinter(address _esTileAddressAddress) external onlyOwner {
        esTileAddress = _esTileAddressAddress;
    }
    
    function _mint(address account, uint256 amount) internal override onlyOwnerOrEsTileContract {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function mintForAccount(address account, uint256 amount) external onlyOwnerOrEsTileContract {
        _mint(account, amount);
    }

    // PAUSE
    function setPauser(address newPauser) public onlyOwner {
        require(newPauser != address(0), "EscapeToken: pauser is the zero address.");
        pauser = newPauser;
    }

    function unpause() external onlyPauser {
        paused = false;
    }

    // TOKEN TRANSFER HOOK

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        require(!paused || msg.sender == pauser, "EscapeToken: token transfer while paused and not pauser role.");
    }

    function getInfoFor(address addr) public view returns (uint256) {
        return  balanceOf(addr);
    }



    
}
