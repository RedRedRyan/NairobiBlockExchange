// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title BlockExchange
 * @dev A security token for SMEs on the Nairobi Block Exchange (NBX), built on Hedera Hashgraph.
 *      This contract enables the issuance, dividend distribution, governance, and regulatory compliance
 *      of security tokens that represent shares in an SME. It uses on-chain balance tracking for both
 *      the security token and USDT (for dividends).
 *
 *      Key Features:
 *      - Uses Hedera Token Service (HTS) for security tokens and USDT
 *      - Implements on-chain KYC/AML compliance via whitelisting
 *      - Automated dividend distribution in USDT
 *      - DAO-based governance mechanisms for shareholders
 *      - On-chain balance tracking with balanceOf and totalTokenSupply functions
 */
import "./HederaTokenService.sol";
import "./HederaResponseCodes.sol";
import "./IHederaTokenService.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BlockExchange is Ownable, HederaTokenService {
    // Hedera Token Service (HTS) Token ID for this security token
    address public immutable hederaTokenServiceTokenId;

    // USDT Token ID on Hedera for dividend payouts
    address public immutable usdtTokenId;

    // Company Treasury Wallet for Dividend Distribution
    address public immutable treasuryWallet;

    // Company Metadata
    string public companyName;

    // KYC & Compliance Mapping (Whitelisted Investors)
    mapping(address => bool) public isWhitelisted;

    // Dividend Tracking: Tracks withdrawn dividends per shareholder
    mapping(address => uint256) private withdrawnDividends;

    // Total dividends distributed across all shareholders
    uint256 public totalDividendsDistributed;

    // Governance: Tracks voting power per shareholder
    mapping(address => uint256) public governanceVotes;

    // On-Chain Balance Tracking: tokenId => account => balanceVariation
    mapping(address => mapping(address => uint256)) public tokenBalances;

    // Total supply tracking per token
    mapping(address => uint256) public totalSupply;

    // Event Logs
    event DividendsDistributed(uint256 amount);
    event DividendClaimed(address indexed shareholder, uint256 amount);
    event ShareholderWhitelisted(address indexed investor, bool status);
    event GovernanceVoteCasted(address indexed voter, uint256 votes);
    event TokensTransferred(address indexed token, address indexed from, address indexed to, uint256 amount);

    /**
     * @dev Constructor to initialize the SME Security Token
     * @param _companyName Name of the SME
     * @param _hederaTokenServiceTokenId The Hedera Token ID representing this security token
     * @param _usdtTokenId The Hedera Token ID of USDT for dividend payouts
     * @param _treasuryWallet Address of the company's treasury for dividend distribution
     * @param _initialSecurityTokenSupply Initial supply of security tokens to allocate to treasury
     */
    constructor(
        string memory _companyName,
        address _hederaTokenServiceTokenId,
        address _usdtTokenId,
        address _treasuryWallet,
        uint256 _initialSecurityTokenSupply
    ) Ownable(msg.sender) {
        require(_hederaTokenServiceTokenId != address(0), "Invalid token ID");
        require(_usdtTokenId != address(0), "Invalid USDT token ID");
        require(_treasuryWallet != address(0), "Invalid treasury wallet");
        require(_initialSecurityTokenSupply > 0, "Initial supply must be greater than zero");

        companyName = _companyName;
        hederaTokenServiceTokenId = _hederaTokenServiceTokenId;
        usdtTokenId = _usdtTokenId;
        treasuryWallet = _treasuryWallet;

        // Initialize security token supply and balance for treasury
        totalSupply[hederaTokenServiceTokenId] = _initialSecurityTokenSupply;
        tokenBalances[hederaTokenServiceTokenId][treasuryWallet] = _initialSecurityTokenSupply;

        // Associate the contract with both tokens to enable interactions
        int256 responseCode = associateToken(address(this), hederaTokenServiceTokenId);
        require(responseCode == HederaResponseCodes.SUCCESS, "Security token association failed");
        responseCode = associateToken(address(this), usdtTokenId);
        require(responseCode == HederaResponseCodes.SUCCESS, "USDT association failed");
    }

    /**
     * @dev Returns the balance of a specific token for a specific account
     * @param tokenId The token ID to query (e.g., hederaTokenServiceTokenId or usdtTokenId)
     * @param account The account to check the balance for
     * @return The token balance of the account
     */
    function balanceOf(address tokenId, address account) external view returns (uint256) {
        return tokenBalances[tokenId][account];
    }

    /**
     * @dev Returns the total supply of a specific token
     * @param tokenId The token ID to query (e.g., hederaTokenServiceTokenId or usdtTokenId)
     * @return The total supply of the token
     */
    function totalTokenSupply(address tokenId) external view returns (uint256) {
        return totalSupply[tokenId];
    }

    /**
     * @dev Whitelist an investor for compliance purposes (KYC/AML)
     * @param investor The address of the investor
     * @param status True if whitelisted, false otherwise
     */
    function whitelistInvestor(address investor, bool status) external onlyOwner {
        isWhitelisted[investor] = status;
        emit ShareholderWhitelisted(investor, status);
    }

    /**
     * @dev Transfer tokens between accounts and update internal balances
     * @param tokenId The token ID to transfer (e.g., hederaTokenServiceTokenId or usdtTokenId)
     * @param from The sender’s address
     * @param to The receiver’s address
     * @param amount The amount of tokens to transfer
     */
    function transferTokens(address tokenId, address from, address to, uint256 amount) external {
        require(isWhitelisted[from] && isWhitelisted[to], "One or both parties not whitelisted");
        require(tokenBalances[tokenId][from] >= amount, "Insufficient balance");
        require(amount > 0 && amount <= 9223372036854775807, "Invalid amount");

        // Update internal balances
        tokenBalances[tokenId][from] -= amount;
        tokenBalances[tokenId][to] += amount;

        // Execute transfer via HTS
        int256 responseCode = transferToken(tokenId, from, to, int64(uint64(amount)));
        require(responseCode == HederaResponseCodes.SUCCESS, "Token transfer failed");

        emit TokensTransferred(tokenId, from, to, amount);
    }

    /**
     * @dev Distribute dividends to all token holders in USDT
     * @param amount Total amount of USDT to be distributed
     */
    function distributeDividends(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(tokenBalances[usdtTokenId][treasuryWallet] >= amount, "Insufficient USDT balance");

        // Increment total dividends distributed
        totalDividendsDistributed += amount;
        emit DividendsDistributed(amount);
    }

    /**
     * @dev Claim dividends for a shareholder in USDT
     */
    function claimDividends() external {
        require(isWhitelisted[msg.sender], "Investor not whitelisted");
        uint256 shareholderBalance = tokenBalances[hederaTokenServiceTokenId][msg.sender];
        require(shareholderBalance > 0, "No shares owned");

        // Calculate claimable amount based on shareholding proportion
        uint256 claimableAmount = (totalDividendsDistributed * shareholderBalance) / totalSupply[hederaTokenServiceTokenId];
        require(claimableAmount > withdrawnDividends[msg.sender], "No dividends to claim");

        // Determine amount to withdraw
        uint256 amountToWithdraw = claimableAmount - withdrawnDividends[msg.sender];
        withdrawnDividends[msg.sender] = claimableAmount;

        require(amountToWithdraw <= 9223372036854775807, "Amount too large");

        // Update USDT balances
        tokenBalances[usdtTokenId][treasuryWallet] -= amountToWithdraw;
        tokenBalances[usdtTokenId][msg.sender] += amountToWithdraw;

        // Transfer USDT from treasury to shareholder
        int256 responseCode = transferToken(usdtTokenId, treasuryWallet, msg.sender, int64(uint64(amountToWithdraw)));
        require(responseCode == HederaResponseCodes.SUCCESS, "USDT transfer failed");

        emit DividendClaimed(msg.sender, amountToWithdraw);
    }

    /**
     * @dev Cast a governance vote based on shareholding
     * @param votes Number of votes to cast
     */
    function castVote(uint256 votes) external {
        require(isWhitelisted[msg.sender], "Investor not whitelisted");
        require(tokenBalances[hederaTokenServiceTokenId][msg.sender] >= votes, "Insufficient votes");

        governanceVotes[msg.sender] = votes;
        emit GovernanceVoteCasted(msg.sender, votes);
    }

    /**
     * @dev Initialize the USDT balance for the treasury wallet
     * @param amount The initial amount of USDT to set (call after funding treasuryWallet)
     */
    function setInitialUsdtBalance(uint256 amount) external onlyOwner {
        require(tokenBalances[usdtTokenId][treasuryWallet] == 0, "USDT balance already set");
        tokenBalances[usdtTokenId][treasuryWallet] = amount;
    }
}