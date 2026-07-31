// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
    // ------------------------------------------ //
    // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
    // ------------------------------------------ //
    using SafeMath for uint256;
    uint256 public totalSupply;
    uint256 public decimals = 18;
    string public name = "Test token";
    string public symbol = "TEST";
    mapping(address => uint256) public balanceOf;
    // ------------------------------------------ //
    // ----- END: DO NOT EDIT THIS SECTION ------ //
    // ------------------------------------------ //

    // ---- ERC-20 allowances ----
    mapping(address => mapping(address => uint256)) private _allowances;

    // ---- Holder tracking (1-based index) ----
    address[] private _holders;
    mapping(address => uint256) private _holderIndex;

    // ---- Dividend tracking ----
    mapping(address => uint256) private _withdrawableDividend;

    // Tracking helper function
    function _addHolder(address account) private {
        if (_holderIndex[account] == 0) {
            _holders.push(account);
            _holderIndex[account] = _holders.length;
        }
    }

    // Internal Helper: Swap and Pop (O(1) Array Deletion)
    function _removeHolder(address account) private {
        uint256 index = _holderIndex[account];
        if (index == 0) return; 

        uint256 lastIndex = _holders.length;
        if (index != lastIndex) {
            address lastHolder = _holders[lastIndex - 1];
            _holders[index - 1] = lastHolder;
            _holderIndex[lastHolder] = index;
        }
        _holders.pop();
        _holderIndex[account] = 0;
    }

    function _transfer(address from, address to, uint256 value) private {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(to != address(0), "Address zero detected");

        bool toWasZero = (balanceOf[to] == 0);

        balanceOf[from] -= value;
        balanceOf[to] += value;

        // Update holder registry for sender if their balance hits strictly 0
        if (balanceOf[from] == 0) {
            _removeHolder(from);
        }

        // Update holder registry for recipient
        if (value > 0 && toWasZero) {
            _addHolder(to);
        }
    }

    // IERC20 Interfaces
    function allowance(address owner,address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender,uint256 value) external override returns (bool) {
        require(spender != address(0), "Address zero detected");
        _allowances[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to,uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from,address to,uint256 value) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= value, "transfer amount exceeds allowance");
        currentAllowance -= value;
        _allowances[from][msg.sender] = currentAllowance;
        _transfer(from, to, value);
        return true;
    }

    // IMintableToken Interfaces
    function mint() external payable override {
        require(msg.value > 0, "Token: must send ETH to mint");

        bool wasZero = (balanceOf[msg.sender] == 0);

        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;

        // Add them to the holder array if this is their first token
        if (wasZero) {
            _addHolder(msg.sender);
        }
    }

    function burn(address payable dest) external override {
        require(dest != address(0), "Address zero detected");
        uint256 amount = balanceOf[msg.sender];
        require(amount > 0, "No balance to burn");

        // Zero out their balance and subtract from total supply
        balanceOf[msg.sender] = 0;
        totalSupply -= amount;

        // Completely remove them from the holder array
        _removeHolder(msg.sender);

        // Refund their underlying ETH
        dest.transfer(amount);
    }

    // IDividends Interfaces
    function getNumTokenHolders() external view override returns (uint256) {
        return _holders.length;
    }

    function getTokenHolder(uint256 index) external view override returns (address) {
        if (index == 0 || index > _holders.length) return address(0);
        return _holders[index - 1];
    }

    function recordDividend() external payable override {
        require(msg.value > 0, "Token: must send ETH as dividend");
        require(_holders.length > 0, "No token holders");

        uint256 dividend = msg.value;
        uint256 supply = totalSupply;

        // DIRECT README INSTRUCTION: "Dividends are assigned by looping through the list of holders."
        for (uint256 i = 0; i < _holders.length; i++) {
            address holder = _holders[i];
            // Math: (Dividend * User Balance) / Total Supply
            uint256 share = ((dividend) * (balanceOf[holder])) / (supply);
            // Persistently record their share in a dedicated mapping
            _withdrawableDividend[holder] += share;
        }
    }

    function getWithdrawableDividend(address payee) external view override returns (uint256) {
        return _withdrawableDividend[payee];
    }

    function withdrawDividend(address payable dest) external override {
        require(dest != address(0), "Address zero detected");
        uint256 amount = _withdrawableDividend[msg.sender];
        require(amount > 0, "Insufficient dividend to withdraw");

        // CRITICAL: Set to zero BEFORE transferring ETH to prevent Re-entrancy attacks
        _withdrawableDividend[msg.sender] = 0;

        // Send standard ETH
        dest.transfer(amount);
    }
}
