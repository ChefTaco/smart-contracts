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

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

// Just a nice, simple Taco token. The burn() function is called by a Burner contract.

contract TacoParty is ERC20, Ownable, ERC20Permit, ERC20Votes {

    uint256 public burned;

    // Transfer tax rate in basis points. (0.7%)
    uint16 public constant transferTaxRate = 70;
    // Burn rate % of transfer tax. (default 2/7ths = 0.285714285% of total amount).
    uint32 public constant burnRate = 285714285;
    // Default # of tokens to mint
    uint256 public constant MINT_AMOUNT = 10000 ether;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public immutable feeAddress;

    constructor(address feeaddr) ERC20("TacoParty", "TACO") ERC20Permit("TacoParty") {
        require(feeaddr != address(0x0), 'usdc is zero');
        feeAddress = feeaddr;

        _mint(address(msg.sender), MINT_AMOUNT);
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) public {
        require (balanceOf(msg.sender)>=_amount);
        _burn(msg.sender, _amount);
        burned += _amount;
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
            burned += burnAmount;
            super._transfer(sender, feeAddress, liquidityAmount);
            super._transfer(sender, recipient, sendAmount);
            amount = sendAmount;
        }
    }

    // Required for Governance
    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}