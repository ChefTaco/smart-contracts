/*

  ,d                                       
  88                                       
MM88MMM ,adPPYYba,  ,adPPYba,  ,adPPYba,   
  88    ""     `Y8 a8"     "" a8"     "8a  
  88    ,adPPPPP88 8b         8b       d8  PRESALE TOKEN SWAPPER
  88,   88,    ,88 "8a,   ,aa "8a,   ,a8"  
  "Y888 `"8bbdP"Y8  `"Ybbd8"'  `"YbbdP"'   

Website     https://tacoparty.finance

Swap contract for the presale PreTaco!

*/

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "./PreTaco.sol";

contract PreTacoSwap is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Burn address
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    PreTacoToken immutable public preTacoToken;

    IERC20 immutable public tacoToken;

    address  tacoAddress;

    bool  hasBurnedUnsoldPresale;

    bool  redeemState;

    uint256 public startBlock;

    event PreTacoToTaco(address sender, uint256 amount);
    event burnUnclaimedTaco(uint256 amount);
    event startBlockChanged(uint256 newStartBlock);

    constructor(uint256 _startBlock, address _pretacoAddress, address _tacoAddress) {
        require(_pretacoAddress != _tacoAddress, "pretaco cannot be equal to taco");
        startBlock = _startBlock;
        preTacoToken = PreTacoToken(_pretacoAddress);
        tacoToken = IERC20(_tacoAddress);
    }

    function swapPreTacoForTaco() external nonReentrant {
        require(block.number >= startBlock, "pretaco still awake.");

        uint256 swapAmount = preTacoToken.balanceOf(msg.sender);
        require(tacoToken.balanceOf(address(this)) >= swapAmount, "Not Enough tokens in contract for swap");
        require(preTacoToken.transferFrom(msg.sender, BURN_ADDRESS, swapAmount), "failed sending pretaco" );
        tacoToken.safeTransfer(msg.sender, swapAmount);

        emit PreTacoToTaco(msg.sender, swapAmount);
    }

    function sendUnclaimedTacoToDeadAddress() external onlyOwner {
        require(block.number > preTacoToken.endBlock(), "can only send excess pretaco to dead address after presale has ended");
        require(!hasBurnedUnsoldPresale, "can only burn unsold presale once!");

        require(preTacoToken.pretacoRemaining() <= tacoToken.balanceOf(address(this)),
            "burning too much taco, check again please");

        if (preTacoToken.pretacoRemaining() > 0)
            tacoToken.safeTransfer(BURN_ADDRESS, preTacoToken.pretacoRemaining());
        hasBurnedUnsoldPresale = true;

        emit burnUnclaimedTaco(preTacoToken.pretacoRemaining());
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if presale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;

        emit startBlockChanged(_newStartBlock);
    }

}