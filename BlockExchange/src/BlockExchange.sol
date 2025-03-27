// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title BlockExchange
 * @dev A security token for SMEs on the Nairobi Block Exchange (NBX), built on Hedera Hashgraph.
 *      This contract enables the issuance, dividend distribution, governance, and regulatory compliance
 *      of security tokens that represent shares in an SME.
 *
 *      Key Features:
 *      - Uses Hedera Token Service (HTS) for security tokens
 *      - Implements on-chain KYC/AML compliance
 *      - Automated dividend distribution in USDT (HTS stablecoin)
 *      - Real-time auditable financial data for regulators
 *      - DAO-based governance mechanisms for shareholders
 */

import "@hashgraph/hedera-token-service/contracts/HTS.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract BlockExchange is Ownable {
    using SafeMath for uint256;

    // Hedera Token Service (HTS) Token ID for this security token
    address public immutable htsTokenId;
    
    // USDT Token ID on Hedera for dividend payouts
    address public immutable usdtTokenId;
    
    // Company Treasury Wallet for Dividend Distribution
    address public immutable treasuryWallet;
    
    // Company Metadata
    string public companyName;

    // KYC & Compliance Mapping (Whitelisted Investors)
    mapping(address => bool) public isWhitelisted;

    // Dividend Tracking
    mapping(address => uint256) private withdrawnDividends;
    uint256 public totalDividendsDistributed;
    
    // Governance (Shareholder Voting Power)
    mapping(address => uint256) public governanceVotes;
    
    // Event Logs
    event DividendsDistributed(uint256 amount);
    event DividendClaimed(address indexed shareholder, uint256 amount);
    event ShareholderWhitelisted(address indexed investor, bool status);
    event GovernanceVoteCasted(address indexed voter, uint256 votes);
    
    /**
     * @dev Constructor to initialize the SME Security Token
     * @param _companyName Name of the SME
     * @param _htsTokenId The Hedera Token ID representing this security token
     * @param _usdtTokenId The Hedera Token ID of USDT for dividend payouts
     * @param _treasuryWallet Address of the company's treasury for dividend distribution
     */
    constructor(
        string memory _companyName,
        address _htsTokenId,
        address _usdtTokenId,
        address _treasuryWallet
    ) {
        require(_htsTokenId != address(0), "Invalid token ID");
        require(_usdtTokenId != address(0), "Invalid USDT token ID");
        require(_treasuryWallet != address(0), "Invalid treasury wallet");

        companyName = _companyName;
        htsTokenId = _htsTokenId;
        usdtTokenId = _usdtTokenId;
        treasuryWallet = _treasuryWallet;
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
     * @dev Distribute dividends to all token holders in USDT
     * @param amount Total amount to be distributed
     */
    function distributeDividends(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(HTS.balanceOf(usdtTokenId, treasuryWallet) >= amount, "Insufficient USDT balance");

        totalDividendsDistributed = totalDividendsDistributed.add(amount);
        emit DividendsDistributed(amount);
    }

    /**
     * @dev Claim dividends for a shareholder in USDT
     */
    function claimDividends() external {
        require(isWhitelisted[msg.sender], "Investor not whitelisted");
        uint256 shareholderBalance = HTS.balanceOf(htsTokenId, msg.sender);
        require(shareholderBalance > 0, "No shares owned");
        
        uint256 claimableAmount = (totalDividendsDistributed.mul(shareholderBalance)) / HTS.totalSupply(htsTokenId);
        require(claimableAmount > withdrawnDividends[msg.sender], "No dividends to claim");
        
        uint256 amountToWithdraw = claimableAmount.sub(withdrawnDividends[msg.sender]);
        withdrawnDividends[msg.sender] = claimableAmount;

        HTS.transferToken(usdtTokenId, treasuryWallet, msg.sender, amountToWithdraw);
        emit DividendClaimed(msg.sender, amountToWithdraw);
    }

    /**
     * @dev Cast a governance vote based on shareholding
     */
    function castVote(uint256 votes) external {
        require(isWhitelisted[msg.sender], "Investor not whitelisted");
        uint256 shareholderBalance = HTS.balanceOf(htsTokenId, msg.sender);
        require(shareholderBalance >= votes, "Insufficient votes");
        
        governanceVotes[msg.sender] = votes;
        emit GovernanceVoteCasted(msg.sender, votes);
    }
}
