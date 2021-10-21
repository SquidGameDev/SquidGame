// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SquidToken is ERC20, Ownable  {

    constructor() ERC20("Squid", "Squid") { }
  
    function mint(address account, uint amount) public onlyOwner {
        _mint(account, amount);
    }
}