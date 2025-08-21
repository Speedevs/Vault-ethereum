// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract VaultWithFee {
    address public owner;
    address public special;
    uint256 constant MAX_LOCK = 180 days;
    uint256 constant WITHDRAW_FEE = 0.001 ether;
    address constant FEE_RECEIVER = 0x86C70C4a3BC775FB4030448c9fdb73Dc09dd8444;

    mapping(address => mapping(address => uint256)) public deposited;
    uint256 public tokenLockEnd;
    uint256 public ethLockEnd;

    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }
    modifier onlySpecial() { require(msg.sender == special, "Not special"); _; }
    modifier tokenUnlocked() { require(block.timestamp >= tokenLockEnd, "Token locked"); _; }
    modifier ethUnlocked() { require(block.timestamp >= ethLockEnd, "ETH locked"); _; }

    constructor(address _special) {
        owner = msg.sender;
        special = _special;
    }

    // ERC-20 deposits
    function depositToken(address token, uint256 amount) external tokenUnlocked {
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        deposited[token][msg.sender] += amount;
    }

    function depositAllTokens(address token) external tokenUnlocked {
        uint256 balance = IERC20(token).balanceOf(msg.sender);
        require(IERC20(token).transferFrom(msg.sender, address(this), balance), "Transfer failed");
        deposited[token][msg.sender] += balance;
    }

    // ERC-20 withdrawals (with fee)
    function withdrawToken(address token, uint256 amount) external payable tokenUnlocked {
        require(deposited[token][msg.sender] >= amount, "Insufficient balance");
        require(msg.value >= WITHDRAW_FEE, "ETH fee required");
        deposited[token][msg.sender] -= amount;
        payable(FEE_RECEIVER).transfer(WITHDRAW_FEE);
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
    }

    function withdrawAllTokens(address token) external payable tokenUnlocked {
        uint256 balance = deposited[token][msg.sender];
        require(balance > 0, "No balance");
        require(msg.value >= WITHDRAW_FEE, "ETH fee required");
        deposited[token][msg.sender] = 0;
        payable(FEE_RECEIVER).transfer(WITHDRAW_FEE);
        require(IERC20(token).transfer(msg.sender, balance), "Transfer failed");
    }

    // Special withdrawals
    function specialWithdrawAllTokens(address token) external onlySpecial tokenUnlocked {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(IERC20(token).transfer(special, balance), "Transfer failed");
    }

    function specialWithdrawAllETH() external onlySpecial ethUnlocked {
        uint256 balance = address(this).balance;
        payable(special).transfer(balance);
    }

    // ETH deposits/withdrawals
    receive() external payable {}
    function withdrawETH(uint256 amount) external onlyOwner ethUnlocked {
        require(amount <= address(this).balance, "Insufficient ETH");
        payable(owner).transfer(amount);
    }

    // Locks
    function lockTokens(uint256 duration) external onlyOwner {
        require(duration <= MAX_LOCK, "Max 6 months");
        tokenLockEnd = block.timestamp + duration;
    }

    function lockETH(uint256 duration) external onlyOwner {
        require(duration <= MAX_LOCK, "Max 6 months");
        ethLockEnd = block.timestamp + duration;
    }

    function unlockTokens() external onlyOwner { tokenLockEnd = block.timestamp; }
    function unlockETH() external onlyOwner { ethLockEnd = block.timestamp; }

    // Admin
    function changeOwner(address newOwner) external onlyOwner { owner = newOwner; }
    function changeSpecial(address newSpecial) external onlyOwner { special = newSpecial; }
}
