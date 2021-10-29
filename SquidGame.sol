// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SquidGame is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint public constant GAME_TIMEOUT = 10 minutes;
    uint8 public constant MAX_STEPS = 3;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    struct Game {
        uint pid;
        uint8 stepsLeft;
        uint amount;
        uint blockNumber;
        uint winAmount;
        uint startTime;
    }

    mapping(address => Game) public games;
    mapping(address => mapping (uint8 => uint8)) public choises;
    uint[] public winPercents = [100,30,10];
    IERC20 public immutable squid;

    event GameStarted(address indexed to, uint indexed pid, uint value);
    event GameFinished(address indexed to, uint indexed pid, uint value);
    event Step(address indexed to, uint8 step, bool isWin);

    constructor(IERC20 _squid) {
        squid = _squid;
    }

    function startGame(address sender, uint pid, uint amount) external onlyOwner {
        require(
            games[sender].stepsLeft == 0 || games[sender].startTime + GAME_TIMEOUT < block.timestamp,
            "finish previous game first"
        );

        // game timeout
        if (games[sender].stepsLeft > 0) {
            _safeSquidTransfer(BURN_ADDRESS, games[sender].amount);
        }

        games[sender].pid = pid;
        games[sender].amount = amount;
        games[sender].stepsLeft = MAX_STEPS;
        games[sender].blockNumber = block.number + 1;
        games[sender].winAmount = 0;
        games[sender].startTime = block.timestamp;

        emit GameStarted(sender, pid, amount);
    }

    function step(uint8 choise) external {
        Game storage game = games[msg.sender];

        require(game.stepsLeft > 0, "game hasn't started");
        require(game.startTime + GAME_TIMEOUT > block.timestamp, "game timeout");
        require(block.number > game.blockNumber, "early");

        uint seed = uint(blockhash(game.blockNumber));
        bool isWin = seed % 1000 >= 500;

        choises[msg.sender][MAX_STEPS - game.stepsLeft] = choise;
        game.stepsLeft -= 1;

        if (isWin) {
            game.blockNumber = block.number + 1;

            game.winAmount = game.amount * winPercents[game.stepsLeft] / 100;

            if (game.stepsLeft == 0) {
                finishGame();
            }
        } else {
            game.winAmount = 0;
            game.stepsLeft = 0;

            _safeSquidTransfer(BURN_ADDRESS, game.amount);

            emit GameFinished(msg.sender, game.pid, 0);
        }

        emit Step(msg.sender, games[msg.sender].stepsLeft, isWin);
    }

    function finishGame() public nonReentrant {
        Game storage game = games[msg.sender];

        require(game.startTime + GAME_TIMEOUT > block.timestamp, "game timeout");
        require(game.winAmount > 0, "didn't win any");

        _safeSquidTransfer(msg.sender, game.winAmount);

        if (game.amount > game.winAmount) {
            _safeSquidTransfer(BURN_ADDRESS, game.amount - game.winAmount);
        }

        emit GameFinished(msg.sender, game.pid, game.winAmount);

        game.winAmount = 0;
        game.stepsLeft = 0;
    }

    function _safeSquidTransfer(address _to, uint _amount) internal {
        uint squidBal = squid.balanceOf(address(this));
        if (_amount > squidBal) {
            squid.transfer(_to, squidBal);
        } else {
            squid.transfer(_to, _amount);
        }
    }
}
