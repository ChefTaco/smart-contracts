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

    // Transfer tax rate in basis points. (0.7%)
    uint16 public constant transferTaxRate = 70;
    // Burn rate % of transfer tax. (default 2/7ths = 0.285714285% of total amount).
    uint32 public constant burnRate = 285714285;
    // Default # of tokens to mint
    uint256 public constant MINT_AMOUNT = 10000 ether;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public immutable feeAddress;

    constructor(address feeaddr) {
        require(feeaddr != address(0x0), 'usdc is zero');
        feeAddress = feeaddr;

        _mint(address(msg.sender), MINT_AMOUNT);
        minted = minted + MINT_AMOUNT;
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

    // Transfer tax
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
     if (recipient == BURN_ADDRESS || recipient == feeAddress || sender == feeAddress) {
            super._transfer(sender, recipient, amount);
        } else {
            // default tax is 0.7% of every transfer
            uint256 taxAmount = amount * transferTaxRate / 10000;
            uint256 burnAmount = (taxAmount * burnRate) / 1000000000;
            uint256 liquidityAmount = taxAmount - burnAmount;

            // default 99.3% of transfer sent to recipient
            uint256 sendAmount = amount - taxAmount;

            require(amount == sendAmount + taxAmount &&
                        taxAmount == burnAmount + liquidityAmount, "sum error");

            super._transfer(sender, BURN_ADDRESS, burnAmount);
            burned = burned + burnAmount;
            super._transfer(sender, feeAddress, liquidityAmount);
            super._transfer(sender, recipient, sendAmount);
            amount = sendAmount;
        }
    }
}