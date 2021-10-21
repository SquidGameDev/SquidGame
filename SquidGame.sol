// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SquidGame is Ownable {
    // using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Game {
        uint8 stepsLeft;
        uint256 amount;
        uint256 blockNumber;
        uint256 winAmount;
        uint8 lostStep;
        uint256 startTime;
    }
    
    mapping(address => Game) public games;
    uint256[] public winPercents = [100,30,10,0];
    IERC20 public immutable squid;

    
    event GameStarted(address indexed to, uint256 value);
    event GameFinished(address indexed to, uint256 value);
    event Step(address indexed to, uint8 step, bool isWin);

    constructor(IERC20 _squid) public {
        squid = _squid;
    }

    function startGame(address sender, uint256 amount) external onlyOwner {
        require(games[msg.sender].stepsLeft == 0, "finish previous game first");
        
        games[sender].amount = amount;
        games[sender].stepsLeft = 3;
        games[sender].blockNumber = block.number + 1;
        games[sender].winAmount = 0;
        games[sender].lostStep = 3;
        games[sender].startTime = block.timestamp;
        
        emit GameStarted(sender, amount);
    }
    
    function step() external {
        require(games[msg.sender].stepsLeft > 0, "game hasn't started");
        require(block.number > games[msg.sender].blockNumber, "early");
        
        uint256 seed = uint(blockhash(games[msg.sender].blockNumber));
        bool isWin = seed % 1000 >= 500;
        
        games[msg.sender].stepsLeft -= 1;
        
        if (isWin) {
            games[msg.sender].blockNumber = block.number + 1;
            
            games[msg.sender].winAmount = games[msg.sender].amount * winPercents[games[msg.sender].stepsLeft];
            
            if (games[msg.sender].stepsLeft == 0) {
                finishGame();
            }
            
        } else {
            games[msg.sender].winAmount = 0;
            games[msg.sender].lostStep = games[msg.sender].stepsLeft;
            games[msg.sender].stepsLeft = 0;
            
            emit GameFinished(msg.sender, 0);
        }
        
        emit Step(msg.sender, games[msg.sender].stepsLeft, isWin);
    }
    
    function finishGame() public {
        require(games[msg.sender].winAmount > 0, "didn't win any");
        
        _safeSquidTransfer(msg.sender, games[msg.sender].winAmount);
        
        games[msg.sender].winAmount = 0;
        games[msg.sender].stepsLeft = 0;
        
        emit GameFinished(msg.sender, games[msg.sender].winAmount);
    }
    
    function _safeSquidTransfer(address _to, uint256 _amount) internal {
        uint256 squidBal = squid.balanceOf(address(this));
        if (_amount > squidBal) {
            squid.transfer(_to, squidBal);
        } else {
            squid.transfer(_to, _amount);
        }
    }
}