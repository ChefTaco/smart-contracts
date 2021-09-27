// SPDX-License-Identifier: MIT

// Stock PCS NFT farm, which will be replaced prior to enablement on the site.

pragma solidity ^0.8.4;

import "contracts/TacoBunnies.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TacoBunniesFarm is Ownable {

    using SafeERC20 for IERC20;

    TacoBunnies public tacoBunnies;
    IERC20 public tacoToken;

    // Map if address can claim a NFT
    mapping(address => bool) public canClaim;

    // Map if address has already claimed a NFT
    mapping(address => bool) public hasClaimed;

    // starting block
    uint256 public startBlockNumber;

    // end block number to claim TACOs by burning NFT
    uint256 public endBlockNumber;

    // number of total bunnies burnt
    uint256 public countBunniesBurnt;

    // Number of TACOs a user can collect by burning her NFT
    uint256 public tacoPerBurn;

    // current distributed number of NFTs
    uint256 public currentDistributedSupply;

    // number of total NFTs distributed
    uint256 public totalSupplyDistributed;

    // baseURI (on IPFS)
    string private baseURI;

    // Map the token number to URI
    mapping(uint8 => string) private bunnyIdURIs;

    // number of initial series (i.e. different visuals)
    uint8 private numberOfBunnyIds;

    // Event to notify when NFT is successfully minted
    event TacoBunnyMint(
        address indexed to,
        uint256 indexed tokenId,
        uint8 indexed bunnyId
    );

    // Event to notify when NFT is successfully minted
    event TacoBunnyBurn(address indexed from, uint256 indexed tokenId);

    /**
     * @dev A maximum number of NFT tokens that is distributed by this contract
     * is defined as totalSupplyDistributed.
     */
    constructor(
        IERC20 _tacoToken,
        uint256 _totalSupplyDistributed,
        uint256 _tacoPerBurn,
        // string memory _baseURI,
        string memory _ipfsHash,
        uint256 _endBlockNumber
    ) {
        tacoBunnies = new TacoBunnies();
        tacoToken = _tacoToken;
        totalSupplyDistributed = _totalSupplyDistributed;
        tacoPerBurn = _tacoPerBurn;
        // baseURI = _baseURI;
        endBlockNumber = _endBlockNumber;

        // Other parameters initialized
        numberOfBunnyIds = 3;

        // Assign tokenURI to look for each bunnyId in the mint function
        bunnyIdURIs[0] = string(abi.encodePacked(_ipfsHash, "nftimages/TacoMargarita.jpeg"));
        bunnyIdURIs[1] = string(abi.encodePacked(_ipfsHash, "nftimages/TacoCat.jpeg"));
        bunnyIdURIs[2] = string(abi.encodePacked(_ipfsHash, "nftimages/TacoSupreme.jpeg"));

        // Set token names for each bunnyId
        tacoBunnies.setBunnyName(0, "Taco Margarita");
        tacoBunnies.setBunnyName(1, "Taco Cat");
        tacoBunnies.setBunnyName(2, "Taco Supreme");
    }

    /**
     * @dev Mint NFTs from the TacoBunnies contract.
     * Users can specify what bunnyId they want to mint. Users can claim once.
     * There is a limit on how many are distributed. It requires TACO balance to be >0.
     */
    function mintNFT(uint8 _bunnyId) external {
        // Check msg.sender can claim
        require(canClaim[msg.sender], "Cannot claim");
        // Check msg.sender has not claimed
        require(hasClaimed[msg.sender] == false, "Has claimed");
        // Check whether it is still possible to mint
        require(
            currentDistributedSupply < totalSupplyDistributed,
            "Nothing left"
        );
        // Check whether user owns any TACO
        require(tacoToken.balanceOf(msg.sender) > 0, "Must own TACO");
        // Check that the _bunnyId is within boundary:
        require(_bunnyId < numberOfBunnyIds, "bunnyId unavailable");
        // Update that msg.sender has claimed
        hasClaimed[msg.sender] = true;

        // Update the currentDistributedSupply by 1
        currentDistributedSupply += 1;

        string memory tokenURI = bunnyIdURIs[_bunnyId];

        uint256 tokenId = tacoBunnies.mint(
            address(msg.sender),
            tokenURI,
            _bunnyId
        );

        emit TacoBunnyMint(msg.sender, tokenId, _bunnyId);
    }

    /**
     * @dev Burn NFT from the TacoBunnies contract.
     * Users can burn their NFT to get a set number of TACO.
     * There is a cap on how many can be distributed for free.
     */
    function burnNFT(uint256 _tokenId) external {
        require(
            tacoBunnies.ownerOf(_tokenId) == msg.sender,
            "Not the owner"
        );
        require(block.number < endBlockNumber, "too late");

        tacoBunnies.burn(_tokenId);
        countBunniesBurnt += 1;
        tacoToken.safeTransfer(address(msg.sender), tacoPerBurn);
        emit TacoBunnyBurn(msg.sender, _tokenId);
    }

    /**
     * @dev Allow to set up the start number
     * Only the owner can set it.
     */
    function setStartBlockNumber() external onlyOwner {
        startBlockNumber = block.number;
    }

    /**
     * @dev Allow the contract owner to whitelist addresses.
     * Only these addresses can claim.
     */
    function whitelistAddresses(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            canClaim[users[i]] = true;
        }
    }

    /**
     * @dev It transfers the TACO tokens back to the chef address.
     * Only callable by the owner.
     */
    function withdrawTaco(uint256 _amount) external onlyOwner {
        require(block.number >= endBlockNumber, "too early");
        tacoToken.safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @dev It transfers the ownership of the NFT contract
     * to a new address.
     */
    function changeOwnershipNFTContract(address _newOwner) external onlyOwner {
        tacoBunnies.transferOwnership(_newOwner);
    }
}