// SPDX-License-Identifier: MIT

/*
  ,d                                       
  88                                       
MM88MMM ,adPPYYba,  ,adPPYba,  ,adPPYba,   
  88    ""     `Y8 a8"     "" a8"     "8a  
  88    ,adPPPPP88 8b         8b       d8  TOKEN
  88,   88,    ,88 "8a,   ,aa "8a,   ,a8"  
  "Y888 `"8bbdP"Y8  `"Ybbd8"'  `"YbbdP"'   

Website     https://tacoparty.finance
*/

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Just a nice, simple Taco token. The burn() function is called by a Burner contract.

contract TacoParty is ERC20("TacoParty", "TACO"), Ownable {

    uint256 public minted;
    uint256 public burned;

    constructor() {
        _mint(address(msg.sender), 1000 ether);
        minted = minted + 1000 ether;
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
        minted = minted + _amount;
    }

    function burn(uint256 _amount) public {
        require (balanceOf(msg.sender)>=_amount);
        _burn(msg.sender, _amount);
        burned = burned + _amount;
    }

    function getOwner() external view returns (address) {
        return owner();
    }
}