pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor(address to) public ERC20("Gold", "GLD") {
        _mint(to, 1000000000000000000000);
    }
}
