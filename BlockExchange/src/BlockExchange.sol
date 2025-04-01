// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title BlockExchange
 * @dev A security token for SMEs on the Nairobi Block Exchange (NBX), built on ERC20.
 *      This contract creates its own security token during deployment and manages issuance,
 *      dividend distribution, governance, and regulatory compliance.
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Simple Security Token for SMEs
contract SecurityToken is ERC20 {
    uint8 private _decimals;
    address private _owner;
    
    constructor(string memory name, string memory symbol, uint8 decimalsValue, uint256 initialSupply, address treasury) 
        ERC20(name, symbol) 
    {
        _decimals = decimalsValue;
        _owner = msg.sender;
        _mint(treasury, initialSupply);
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function owner() public view returns (address) {
        return _owner;
    }
}

contract BlockExchange is Ownable {
    address public immutable securityTokenAddress;
    address public immutable usdtTokenAddress;
    address public immutable treasuryWallet;
    string public companyName;

    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256) private withdrawnDividends;
    uint256 public totalDividendsDistributed;
    mapping(address => uint256) public governanceVotes;

    // Event Logs
    event DividendsDistributed(uint256 amount);
    event DividendClaimed(address indexed shareholder, uint256 amount);
    event ShareholderWhitelisted(address indexed investor, bool status);
    event GovernanceVoteCasted(address indexed voter, uint256 votes);
    event TokensTransferred(address indexed token, address indexed from, address indexed to, uint256 amount);
    event TokenCreated(address indexed tokenId, string name, string symbol, uint256 initialSupply);

    /**
     * @dev Constructor to initialize the SME Security Token by creating a new ERC20 token
     * @param _companyName Name of the SME
     * @param _tokenSymbol Symbol for the security token
     * @param _initialSecurityTokenSupply Initial supply of security tokens
     * @param _usdtTokenAddress The address of USDT token for dividend payouts
     * @param _treasuryWallet Address of the company's treasury
     */
    constructor(
        string memory _companyName,
        string memory _tokenSymbol,
        uint256 _initialSecurityTokenSupply,
        address _usdtTokenAddress,
        address _treasuryWallet
    ) Ownable(msg.sender) {
        require(bytes(_companyName).length > 0, "Company name required");
        require(bytes(_tokenSymbol).length > 0, "Token symbol required");
        require(_usdtTokenAddress != address(0), "Invalid USDT address");
        require(_treasuryWallet != address(0), "Invalid treasury wallet");
        require(_initialSecurityTokenSupply > 0, "Initial supply must be greater than zero");

        companyName = _companyName;
        usdtTokenAddress = _usdtTokenAddress;
        treasuryWallet = _treasuryWallet;

        // Deploy the security token
        SecurityToken securityToken = new SecurityToken(
            _companyName, 
            _tokenSymbol, 
            6, // 6 decimals
            _initialSecurityTokenSupply,
            _treasuryWallet
        );
        securityTokenAddress = address(securityToken);

        isWhitelisted[treasuryWallet] = true;
        emit ShareholderWhitelisted(treasuryWallet, true);
        
        emit TokenCreated(securityTokenAddress, _companyName, _tokenSymbol, _initialSecurityTokenSupply);
    }

    function balanceOf(address tokenAddress, address account) external view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(account);
    }

    function totalTokenSupply(address tokenAddress) external view returns (uint256) {
        return IERC20(tokenAddress).totalSupply();
    }

    function whitelistInvestor(address investor, bool status) external onlyOwner {
        isWhitelisted[investor] = status;
        emit ShareholderWhitelisted(investor, status);
    }

    function transferTokens(address tokenAddress, address from, address to, uint256 amount) external {
        require(isWhitelisted[from] && isWhitelisted[to], "One or both parties not whitelisted");
        require(IERC20(tokenAddress).balanceOf(from) >= amount, "Insufficient balance");
        require(amount > 0, "Invalid amount");

        // If the caller is from, we use transferFrom
        if (from == msg.sender) {
            require(IERC20(tokenAddress).transfer(to, amount), "Token transfer failed");
        } else {
            // Otherwise we use transferFrom
            require(IERC20(tokenAddress).transferFrom(from, to, amount), "Token transferFrom failed");
        }

        emit TokensTransferred(tokenAddress, from, to, amount);
    }

    function distributeDividends(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(IERC20(usdtTokenAddress).balanceOf(treasuryWallet) >= amount, "Insufficient USDT balance");

        totalDividendsDistributed += amount;
        emit DividendsDistributed(amount);
    }

    function claimDividends() external {
        require(isWhitelisted[msg.sender], "Investor not whitelisted");
        uint256 shareholderBalance = IERC20(securityTokenAddress).balanceOf(msg.sender);
        require(shareholderBalance > 0, "No shares owned");

        uint256 claimableAmount =
            (totalDividendsDistributed * shareholderBalance) / IERC20(securityTokenAddress).totalSupply();
        require(claimableAmount > withdrawnDividends[msg.sender], "No dividends to claim");

        uint256 amountToWithdraw = claimableAmount - withdrawnDividends[msg.sender];
        withdrawnDividends[msg.sender] = claimableAmount;

        require(IERC20(usdtTokenAddress).transferFrom(treasuryWallet, msg.sender, amountToWithdraw), "USDT transfer failed");

        emit DividendClaimed(msg.sender, amountToWithdraw);
    }

    function castVote(uint256 votes) external {
        require(isWhitelisted[msg.sender], "Investor not whitelisted");
        require(IERC20(securityTokenAddress).balanceOf(msg.sender) >= votes, "Insufficient votes");

        governanceVotes[msg.sender] = votes;
        emit GovernanceVoteCasted(msg.sender, votes);
    }

    function setInitialUsdtBalance(uint256 amount) external onlyOwner {
        // This function is kept for compatibility but doesn't do anything in the ERC20 context
        // For ERC20, the actual token balances are tracked by the token contracts
    }
}