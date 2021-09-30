/*

  ,d                                       
  88                                       
MM88MMM ,adPPYYba,  ,adPPYba,  ,adPPYba,   
  88    ""     `Y8 a8"     "" a8"     "8a  
  88    ,adPPPPP88 8b         8b       d8  PRESALE TOKEN
  88,   88,    ,88 "8a,   ,aa "8a,   ,a8"  
  "Y888 `"8bbdP"Y8  `"Ybbd8"'  `"YbbdP"'   

Website     https://tacoparty.finance

*/
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/* PreTacoToken Presale
 After Presale you'll be able to swap this token for Taco. Ratio 1:0.993
*/
contract PreTacoToken is ERC20('PreTacoToken', 'PRETACO'), ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    address  constant presaleAddress = 0xCf7Db495dFb74302870fFE4aC8D8d19550d97fA8;
    
    IERC20 public USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    
    IERC20 preTacoToken = IERC20(address(this));

    uint256 public salePrice = 250;  // sale price in cents

    uint256 public constant pretacoMaximumSupply = 5000 * (10 ** 18); //5k

    uint256 public pretacoRemaining = pretacoMaximumSupply;
    
    uint256 public maxHardCap = 15000 * (10 ** 6); // 15k usdc

    uint256 public constant maxPreTacoPurchase = 200 * (10 ** 18); // 200 pretaco

    uint256 public startBlock;
    
    uint256 public endBlock;

    uint256 public constant presaleDuration = 179800; // 5 days aprox

    mapping(address => uint256) public userPreTacoTotally;

    event StartBlockChanged(uint256 newStartBlock, uint256 newEndBlock);
    event pretacoPurchased(address sender, uint256 usdcSpent, uint256 pretacoReceived);

    constructor(uint256 _startBlock) {
        startBlock  = _startBlock;
        endBlock    = _startBlock + presaleDuration;
        _mint(address(this), pretacoMaximumSupply);
    }

    function buyPreTaco(uint256 _usdcSpent) external nonReentrant {
        require(block.number >= startBlock, "presale hasn't started yet, good things come to those that wait");
        require(block.number < endBlock, "presale has ended, come back next time!");
        require(pretacoRemaining > 0, "No more PreTaco remains!");
        require(preTacoToken.balanceOf(address(this)) > 0, "No more PreTaco left!");
        require(_usdcSpent > 0, "not enough usdc provided");
        require(_usdcSpent <= maxHardCap, "PreTaco Presale hardcap reached");
        require(userPreTacoTotally[msg.sender] < maxPreTacoPurchase, "user has already purchased too much pretaco");

        uint256 pretacoPurchaseAmount = (_usdcSpent * 100000000000000) / salePrice;

        // if we dont have enough left, give them the rest.
        if (pretacoRemaining < pretacoPurchaseAmount)
            pretacoPurchaseAmount = pretacoRemaining;

        require(pretacoPurchaseAmount > 0, "user cannot purchase 0 pretaco");

        // shouldn't be possible to fail these asserts.
        assert(pretacoPurchaseAmount <= pretacoRemaining);
        assert(pretacoPurchaseAmount <= preTacoToken.balanceOf(address(this)));
        
        //send pretaco to user
        preTacoToken.safeTransfer(msg.sender, pretacoPurchaseAmount);
        // send usdc to presale address
    	USDC.safeTransferFrom(msg.sender, address(presaleAddress), _usdcSpent);

        pretacoRemaining = pretacoRemaining - pretacoPurchaseAmount;
        userPreTacoTotally[msg.sender] = userPreTacoTotally[msg.sender] + pretacoPurchaseAmount;

        emit pretacoPurchased(msg.sender, _usdcSpent, pretacoPurchaseAmount);

    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already started");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;
        endBlock   = _newStartBlock + presaleDuration;

        emit StartBlockChanged(_newStartBlock, endBlock);
    }

}