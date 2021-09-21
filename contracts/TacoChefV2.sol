/*

  ,d                                       
  88                                       
MM88MMM ,adPPYYba,  ,adPPYba,  ,adPPYba,   
  88    ""     `Y8 a8"     "" a8"     "8a  
  88    ,adPPPPP88 8b         8b       d8  CHEF  
  88,   88,    ,88 "8a,   ,aa "8a,   ,a8"  
  "Y888 `"8bbdP"Y8  `"Ybbd8"'  `"YbbdP"'   

    Website     https://tacoparty.finance

    Note: We used the Sandman Delirium MasterChef as a Paladin-audited base, as it is MIT licensed.  
    The MC also has an added section for Variable Emissions.

*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "contracts/TacoToken.sol";

// Taco Dev:  We start with standard Sandman Delirium MC fork, with added mint to the burn address, and hooks
//   for variable emissions (updates mass if needed and calls an emissions rate function)
//   Variable emissions and emission change policies will be documented in online references.

// MasterChef is the master of Taco. He can make Taco and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once TACO is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of TACOs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTacoPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTacoPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. TACOs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that TACOs distribution occurs.
        uint256 accTacoPerShare;   // Accumulated TACOs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint256 lpSupply;
    }

    uint256 public tacoMaximumSupply = 100 * (10 ** 3) * (10 ** 18); // 100,000 taco

    // The TACO TOKEN!
    TacoParty public immutable taco;
    // TACO tokens created per block.
    uint256 public tacoPerBlock;
    // Deposit Fee address
    address public feeAddress;

    // TD: Added burn counter
    uint256 public burnCounter;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when TACO mining starts.
    uint256 public startBlock;
    // The block number when TACO mining ends.
    uint256 public emmissionEndBlock = type(uint256).max;
    // Maximum emission rate.
    uint256 public constant MAX_EMISSION_RATE = 1000000000000000000;
    // Add a settable % multiplier for all emissions (>= 1 and < 100)
    //   (Will not allow zero, which would disable emissions)
    uint32 public emissionsThrottle = 100;

    event addPool(uint256 indexed pid, address lpToken, uint256 allocPoint, uint256 depositFeeBP);
    event setPool(uint256 indexed pid, address lpToken, uint256 allocPoint, uint256 depositFeeBP);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetEmissionRate(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetStartBlock(uint256 newStartBlock);
    
    constructor(
        TacoParty _taco,
        address _feeAddress,
        uint256 _tacoPerBlock,
        uint256 _startBlock
    ) {
        require(_feeAddress != address(0), "!nonzero");

        taco = _taco;
        feeAddress = _feeAddress;
        tacoPerBlock = _tacoPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) external onlyOwner nonDuplicated(_lpToken) {
        // Make sure the provided token is ERC20
        _lpToken.balanceOf(address(this));

        require(_depositFeeBP <= 401, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolExistence[_lpToken] = true;

        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accTacoPerShare : 0,
        depositFeeBP : _depositFeeBP,
        lpSupply: 0
        }));

        emit addPool(poolInfo.length - 1, address(_lpToken), _allocPoint, _depositFeeBP);
    }

    // Update the given pool's TACO allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external onlyOwner {
        require(_depositFeeBP <= 401, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;

        emit setPool(_pid, address(poolInfo[_pid].lpToken), _allocPoint, _depositFeeBP);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        // As we set the multiplier to 0 here after emmissionEndBlock
        // deposits aren't blocked after farming ends.
        if (_from > emmissionEndBlock)
            return 0;
        if (_to > emmissionEndBlock)
            return emmissionEndBlock - _from;
        else
            return _to - _from;
    }

    // View function to see pending TACOs on frontend.
    function pendingTaco(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTacoPerShare = pool.accTacoPerShare;
        if (block.number > pool.lastRewardBlock && pool.lpSupply != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tacoReward = (multiplier * tacoPerBlock * pool.allocPoint) / totalAllocPoint;
            accTacoPerShare = accTacoPerShare + ((tacoReward * 1e12) / pool.lpSupply);
        }

        return ((user.amount * accTacoPerShare) /  1e12) - user.rewardDebt;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // TD: Added public view to return the Burn counter
    function getBurnCount() public view returns (uint256 count) {
            return burnCounter;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tacoReward = (multiplier * tacoPerBlock * pool.allocPoint) / totalAllocPoint;

        // This shouldn't happen, but just in case we stop rewards.
        if (taco.totalSupply() > tacoMaximumSupply)
            tacoReward = 0;
        else if ((taco.totalSupply() + tacoReward) > tacoMaximumSupply)
            tacoReward = tacoMaximumSupply - taco.totalSupply();

        if (tacoReward > 0)
            taco.mint(address(this), tacoReward);

        // Added Mint to burn a % of rewards
        taco.mint(address(0xdead), tacoReward / 20);
        burnCounter += tacoReward / 20;

        // The first time we reach Taco max supply we solidify the end of farming.
        if (taco.totalSupply() >= tacoMaximumSupply && emmissionEndBlock == type(uint256).max)
            emmissionEndBlock = block.number;

        pool.accTacoPerShare = pool.accTacoPerShare + ((tacoReward * 1e12) / pool.lpSupply);
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for TACO allocation.
    //      Note: Web UI 'Harvest' just uses the Deposit function with 0 amount
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = ((user.amount * pool.accTacoPerShare) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                safeTacoTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)) - balanceBefore; // Catches transfer fee token deposits
            require(_amount > 0, "we dont accept deposits of 0 size");

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = (_amount * pool.depositFeeBP) / 10000;
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount + _amount - depositFee;
                pool.lpSupply = pool.lpSupply + _amount - depositFee;
            } else {
                user.amount = user.amount + _amount;
                pool.lpSupply = pool.lpSupply + _amount;
            }
        }
        user.rewardDebt = (user.amount * pool.accTacoPerShare) / 1e12;

        // Add a mass update for emissions, if needed
        updateEmissionIfNeeded();

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = ((user.amount * pool.accTacoPerShare) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            safeTacoTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount - _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            pool.lpSupply = pool.lpSupply - _amount;
        }
        user.rewardDebt = (user.amount * pool.accTacoPerShare) / 1e12;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);

        // In the case of an accounting error, we choose to let the user emergency withdraw anyway
        if (pool.lpSupply >=  amount)
            pool.lpSupply = pool.lpSupply - amount;
        else
            pool.lpSupply = 0;

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe taco transfer function, just in case if rounding error causes pool to not have enough TACOs.
    function safeTacoTransfer(address _to, uint256 _amount) internal {
        uint256 tacoBal = taco.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > tacoBal) {
            transferSuccess = taco.transfer(_to, tacoBal);
        } else {
            transferSuccess = taco.transfer(_to, _amount);
        }
        require(transferSuccess, "safeTacoTransfer: transfer failed");
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "!nonzero");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;

        emit SetStartBlock(startBlock);
    }

    // this should be updated every 5 mins or so via Variable Emissions, so likely never called
    function setEmissionRate(uint256 _tacoPerBlock) public onlyOwner {
        require(_tacoPerBlock > 0);
        require(_tacoPerBlock <= MAX_EMISSION_RATE, 'Above max emissions.'); // added for safety

        massUpdatePools();
        tacoPerBlock = _tacoPerBlock;
        
        emit SetEmissionRate(msg.sender, tacoPerBlock, _tacoPerBlock);
    }

    //
    // Taco Dev: Added Variable emissions code
    //  We keep it simple and opt for a linear, rather than floating point logarithmic function
    //
    //
    IERC20 public usdc;
    uint public topPrice = 100; // 100$ upped initial top
    uint public bottomPrice = 1; // 1$
    uint public lastBlockUpdate = 0;
    uint public emissionUpdateInterval = 50; // now approx 5 mins at 2 blocks/seconds (Paladin high severity finding fix) 
    address public usdcTacoLP = address(0x0); // set after listing.

    event UpdateEmissionRate(address indexed user, uint256 goosePerBlock);

    // For checking prices to link emission rate
    function setUSDCAddress(address _address) public onlyOwner {
        require (_address!=address(0));
        usdc = IERC20(_address);
    }

    // For checking prices to link emission rate
    function setUSDCTacoLPAddress(address _address) public onlyOwner {
        require (_address!=address(0));  // added for good measure
        usdcTacoLP = _address;
    }    

    function updateEmissionIfNeeded() public {

        if (usdcTacoLP==address(0x0)){
            return; 
        }
    
        uint priceCents = bottomPrice * 100;
        if (block.number - lastBlockUpdate > emissionUpdateInterval) {
            lastBlockUpdate = block.number;
        
            uint tacoBalance = taco.balanceOf(usdcTacoLP);
          
            if (tacoBalance > 0) {
                // usdc token decimals = 6, token decimals = 18 ,(18-x)=12 + 2  = 14 to convert to cents
                priceCents = usdc.balanceOf(usdcTacoLP) * 1e14 / tacoBalance;
            }

            // Update pools before changing the emission rate
            massUpdatePools();
            uint256 emissionRatePercent = getEmissionRatePercent(priceCents);
            tacoPerBlock = MAX_EMISSION_RATE / 100 * emissionRatePercent;
        }
    }

    function getTacoPriceCents() public view returns (uint256 spc){
         uint tacoBalance = taco.balanceOf(usdcTacoLP);
          if (tacoBalance > 0) {
            uint256 priceCents = usdc.balanceOf(usdcTacoLP) * 1e14 / tacoBalance;
            return priceCents;
          }
          return 0;
    }

    // Manually reduce emissions by a fixed percent.  This is to better align the date of the end of farming.
    function setEmissionsThrottle(uint32 throttleAmt) public onlyOwner {
        require(throttleAmt >= 1, 'below min throttle');
        require(throttleAmt <= 100, 'above max amount');
        emissionsThrottle = throttleAmt;
        updateEmissionIfNeeded();
    }

    function getEmissionRatePercent(uint256 tacoPriceCents) public view returns (uint256 epr) {
        
        if (tacoPriceCents>=topPrice*100){return (1);}
        if (tacoPriceCents<=bottomPrice*100){return (100);}

        uint256 tacoPricePercentOfTop = (tacoPriceCents * 100) / (topPrice * 100);

        tacoPricePercentOfTop = (tacoPricePercentOfTop * 100) / (emissionsThrottle * 100);

        uint256 tacoEmissionPercent = 100 - tacoPricePercentOfTop;
        if (tacoEmissionPercent <= 0)
            tacoEmissionPercent = 1;

        return tacoEmissionPercent;
    }

    function updateEmissionParameters(uint _topPrice, uint _bottomPrice, uint _emissionUpdateInterval) public onlyOwner {
        topPrice = _topPrice;
        bottomPrice = _bottomPrice;
        emissionUpdateInterval = _emissionUpdateInterval;
    }

    //Update emission rate
    function updateEmissionRate(uint256 _tacoPerBlock) public onlyOwner {
        require(_tacoPerBlock <= MAX_EMISSION_RATE, 'Too high'); // fix for Paladin low finding
        massUpdatePools();
        tacoPerBlock = _tacoPerBlock;
        emit UpdateEmissionRate(msg.sender, _tacoPerBlock);
    }
}