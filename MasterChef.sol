// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./SquidGame.sol";
import "./SquidToken.sol";


contract MasterChef is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;


    // Info of each user.
    struct UserInfo {
        uint amount;         // How many LP tokens the user has provided.
        uint rewardDebt;     // Reward debt. See explanation below.
        uint nextHarvestUntil; // When can the user harvest again.
        uint rewardKept;
    }

    // Info of each pool.
    struct PoolInfo {
        uint amount;
        IERC20 lpToken;           // Address of LP token contract.
        uint allocPoint;       // How many allocation points assigned to this pool. SQUID to distribute per block.
        uint lastRewardBlock;  // Last block number that SQUID distribution occurs.
        uint accSquidPerPower;   // Accumulated SQUID per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    uint public constant HARVEST_INTERVAL = 8 hours;

    // The block number when Squid mining starts.
    uint public immutable startBlock;
    SquidToken public immutable squid;
    SquidGame public immutable squidGame;

    // Squid tokens created per block.
    uint public squidPerBlock = 1e18;
    // Deposit Fee address
    address public feeAddress;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint = 0;

    // Referrers
    mapping (address => address) public referrer;
    mapping (address => mapping (uint8 => uint)) public referrals;
    mapping (address => uint) public referrerReward;
    uint16[] public referrerRewardRate = [ 600, 300, 100 ];

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated:duplicated");
        _;
    }

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event Claim(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);

    event AddPool(uint indexed pid, uint allocPoint, IERC20 lpToken, uint16 depositFeeBP, bool withUpdate);
    event SetPool(uint indexed pid, uint allocPoint, uint16 depositFeeBP, bool withUpdate);

    event SetFee(address indexed fee);
    event UpdateEmissionRate(uint squidPerBlock);

    constructor (
        SquidToken _squid,
        SquidGame _squidGame,
        address _feeAddress,
        uint _startBlock
    ) {
        require(_feeAddress != address(0), "address can't be 0");
        require(_squid.decimals() == 18, "invalid squid token");

        squid = _squid;
        squidGame = _squidGame;
        feeAddress = _feeAddress;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) nonDuplicated(_lpToken) external onlyOwner {
        require(_depositFeeBP <= 500, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            _massUpdatePools();
        }

        poolExistence[_lpToken] = true;

        _lpToken.balanceOf(address(this));

        uint lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint += _allocPoint;
        poolInfo.push(PoolInfo({
            amount:0,
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accSquidPerPower: 0,
            depositFeeBP: _depositFeeBP
        }));

        emit AddPool(poolInfo.length - 1, _allocPoint, _lpToken, _depositFeeBP, _withUpdate);
    }

    // Update the given pool's SQUID allocation point and deposit fee. Can only be called by the owner.
    function set(uint _pid, uint _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external onlyOwner {
        require(_depositFeeBP <= 500, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            _massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;

        emit SetPool(_pid, _allocPoint, _depositFeeBP, _withUpdate);
    }

    function setFeeAddress(address _feeAddress) external {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        require(_feeAddress != address(0), "!nonzero");

        feeAddress = _feeAddress;

        emit SetFee(_feeAddress);
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint _squidPerBlock) external onlyOwner {
        require(_squidPerBlock <= 10 * 1e18,"Too high");

        _massUpdatePools();
        squidPerBlock = _squidPerBlock;

        emit UpdateEmissionRate(_squidPerBlock);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function _massUpdatePools() internal {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            _updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function _updatePool(uint _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.amount == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint blockAmount = block.number - pool.lastRewardBlock;
        uint squidReward = blockAmount * squidPerBlock * pool.allocPoint / totalAllocPoint;

        squid.mint(address(this), squidReward);
        pool.accSquidPerPower += squidReward * 1e12 / pool.amount;
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for Squid allocation.
    function deposit(uint _pid, uint _amount, address _ref) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _updatePool(_pid);
        user.rewardKept += _pendingSquid(_pid, msg.sender);

        if(_amount > 0) {
            if (user.nextHarvestUntil == 0) {
                user.nextHarvestUntil = block.timestamp + HARVEST_INTERVAL;
            }

            uint balance = pool.lpToken.balanceOf(address(this));

            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);

            uint amount = pool.lpToken.balanceOf(address(this)) - balance;

            if(pool.depositFeeBP > 0){
                uint depositFee = amount * pool.depositFeeBP / 10000;
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                amount -= depositFee;
            }

            user.amount += amount;
            pool.amount += amount;
        }

        user.rewardDebt = user.amount * pool.accSquidPerPower / 1e12;

        if (_ref != address(0) && _ref != msg.sender && referrer[msg.sender] == address(0)) {
            referrer[msg.sender] = _ref;

            // direct ref
            referrals[_ref][0] += 1;
            referrals[_ref][1] += referrals[msg.sender][0];
            referrals[_ref][2] += referrals[msg.sender][1];

            // direct refs from direct ref
            address ref1 = referrer[_ref];
            if (ref1 != address(0)) {
                referrals[ref1][1] += 1;
                referrals[ref1][2] += referrals[msg.sender][0];

                // their refs
                address ref2 = referrer[ref1];
                if (ref2 != address(0)) {
                    referrals[ref2][2] += 1;
                }
            }
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint _pid, uint _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        _updatePool(_pid);
        user.rewardKept += _pendingSquid(_pid, msg.sender);

        if (_amount > 0) {
            pool.lpToken.safeTransfer(msg.sender, _amount);
            user.amount -= _amount;
            pool.amount -= _amount;
        }

        user.rewardDebt = user.amount * pool.accSquidPerPower / 1e12;

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        pool.amount -= user.amount;
        uint amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardKept = 0;
        user.nextHarvestUntil = 0;

        pool.lpToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    function _rewardReferrers(uint baseAmount) internal {
        address ref = msg.sender;
        for (uint8 i = 0; i < referrerRewardRate.length; i++) {
            ref = referrer[ref];
            if (ref == address(0)) {
                break;
            }

            uint reward = baseAmount * referrerRewardRate[i] / 10000;
            squid.mint(ref, reward);
            referrerReward[ref] += reward;
        }
    }

    function claim(uint _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(block.timestamp >= user.nextHarvestUntil, "too soon");

        _updatePool(_pid);

        uint pending = user.rewardKept + _pendingSquid(_pid, msg.sender);

        require(pending > 0, "Nothing to claim");

        _rewardReferrers(pending);

        uint harvest = pending / 10;
        _safeSquidTransfer(msg.sender, harvest);
        _safeSquidTransfer(address(squidGame), pending - harvest);
        squidGame.startGame(msg.sender, pending - harvest);

        emit Claim(msg.sender, _pid, pending);

        user.rewardKept = 0;
        user.rewardDebt = user.amount * pool.accSquidPerPower / 1e12;

        user.nextHarvestUntil = block.timestamp + HARVEST_INTERVAL;
    }

    function pendingSquid(uint _pid, address _user) public view returns (uint) {
        return userInfo[_pid][_user].rewardKept + _pendingSquid(_pid, _user);
    }

    // DO NOT includes kept reward
    function _pendingSquid(uint _pid, address _user) internal view returns (uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accSquidPerPower = pool.accSquidPerPower;

        if (block.number > pool.lastRewardBlock && pool.amount != 0 && totalAllocPoint > 0) {
            uint blockAmount = block.number - pool.lastRewardBlock;
            uint squidReward = blockAmount * squidPerBlock * pool.allocPoint / totalAllocPoint;
            accSquidPerPower += squidReward * 1e12 / pool.amount;
        }

        return user.amount * accSquidPerPower / 1e12 - user.rewardDebt;
    }

    // Safe SQUID transfer function, just in case if rounding error causes pool to not have enough Squids.
    function _safeSquidTransfer(address _to, uint _amount) internal {
        uint squidBal = squid.balanceOf(address(this));
        if (_amount > squidBal) {
            squid.transfer(_to, squidBal);
        } else {
            squid.transfer(_to, _amount);
        }
    }
}
