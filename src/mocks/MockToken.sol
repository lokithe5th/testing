pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console2.sol";

contract MockToken is ERC20 {

    mapping(address => bool) public blacklisted;

    uint8 internal customDecimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {
        customDecimals = _decimals;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (!_validTransfer(to)) return false;
        super.transferFrom(from, to, amount);
    }

    function transfer(address to, uint256 amount) public override returns(bool) {
        if (!_validTransfer(to)) return false;
        return super.transfer(to, amount);
    }

    function setBlacklist(address target, bool isBlacklisted) public {
        blacklisted[target] = isBlacklisted;
    }

    function _validTransfer(address to) public returns (bool) {
        return !blacklisted[to];
    }

    function decimals() public view override returns (uint8) {
        return customDecimals;
    }
}