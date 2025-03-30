// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title BlockExchange
 * @dev A security token for SMEs on the Nairobi Block Exchange (NBX), built on Hedera Hashgraph.
 *      This contract creates its own security token during deployment and manages issuance,
 *      dividend distribution, governance, and regulatory compliance.
 */
import "./HederaTokenService.sol";
import "./HederaResponseCodes.sol";
import "./IHederaTokenService.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BlockExchange is Ownable, HederaTokenService {
    address public immutable hederaTokenServiceTokenId;
    address public immutable usdtTokenId;
    address public immutable treasuryWallet;
    string public companyName;

    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256) private withdrawnDividends;
    uint256 public totalDividendsDistributed;
    mapping(address => uint256) public governanceVotes;
    mapping(address => mapping(address => uint256)) public tokenBalances;
    mapping(address => uint256) public totalSupply;

    // Event Logs
    event DividendsDistributed(uint256 amount);
    event DividendClaimed(address indexed shareholder, uint256 amount);
    event ShareholderWhitelisted(address indexed investor, bool status);
    event GovernanceVoteCasted(address indexed voter, uint256 votes);
    event TokensTransferred(address indexed token, address indexed from, address indexed to, uint256 amount);
    event TokenCreated(address indexed tokenId, string name, string symbol, uint256 initialSupply);

    /**
     * @dev Constructor to initialize the SME Security Token by creating a new HTS token
     * @param _companyName Name of the SME
     * @param _tokenSymbol Symbol for the security token
     * @param _initialSecurityTokenSupply Initial supply of security tokens
     * @param _usdtTokenId The Hedera Token ID of USDT for dividend payouts
     * @param _treasuryWallet Address of the company's treasury
     */
    constructor(
        string memory _companyName,
        string memory _tokenSymbol,
        uint256 _initialSecurityTokenSupply,
        address _usdtTokenId,
        address _treasuryWallet
    ) payable Ownable(msg.sender) {
        require(bytes(_companyName).length > 0, "Company name required");
        require(bytes(_tokenSymbol).length > 0, "Token symbol required");
        require(_usdtTokenId != address(0), "Invalid USDT token ID");
        require(_treasuryWallet != address(0), "Invalid treasury wallet");
        require(_initialSecurityTokenSupply > 0, "Initial supply must be greater than zero");
        require(_initialSecurityTokenSupply <= 9223372036854775807, "Initial supply exceeds int64 max");

        companyName = _companyName;
        usdtTokenId = _usdtTokenId;
        treasuryWallet = _treasuryWallet;

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](0);
        IHederaTokenService.HederaToken memory token = IHederaTokenService.HederaToken({
            name: _companyName,
            symbol: _tokenSymbol,
            memo: "",
            treasury: _treasuryWallet,
            tokenSupplyType: true,
            maxSupply: int64(uint64(_initialSecurityTokenSupply)),
            freezeDefault: false,
            tokenKeys: keys,
            expiry: IHederaTokenService.Expiry({second: 0, autoRenewAccount: address(0), autoRenewPeriod: 0})
        });

        // Call HTS precompile directly with value
        (bool success, bytes memory result) = address(0x167).call{value: msg.value}(
            abi.encodeWithSelector(
                IHederaTokenService.createFungibleToken.selector,
                token,
                _initialSecurityTokenSupply,
                6 // 6 decimals
            )
        );
        require(success, "Token creation call failed");
        (int256 responseCode, address createdTokenId) = abi.decode(result, (int256, address));
        require(responseCode == HederaResponseCodes.SUCCESS, "Token creation failed");
        hederaTokenServiceTokenId = createdTokenId;

        totalSupply[hederaTokenServiceTokenId] = _initialSecurityTokenSupply;
        tokenBalances[hederaTokenServiceTokenId][treasuryWallet] = _initialSecurityTokenSupply;

        isWhitelisted[treasuryWallet] = true;
        emit ShareholderWhitelisted(treasuryWallet, true);

        int256 assocResponse = associateToken(address(this), hederaTokenServiceTokenId);
        require(assocResponse == HederaResponseCodes.SUCCESS, "Security token association failed");
        assocResponse = associateToken(address(this), usdtTokenId);
        require(assocResponse == HederaResponseCodes.SUCCESS, "USDT association failed");

        emit TokenCreated(hederaTokenServiceTokenId, _companyName, _tokenSymbol, _initialSecurityTokenSupply);
    }

    function balanceOf(address tokenId, address account) external view returns (uint256) {
        return tokenBalances[tokenId][account];
    }

    function totalTokenSupply(address tokenId) external view returns (uint256) {
        return totalSupply[tokenId];
    }

    function whitelistInvestor(address investor, bool status) external onlyOwner {
        isWhitelisted[investor] = status;
        emit ShareholderWhitelisted(investor, status);
    }

    function transferTokens(address tokenId, address from, address to, uint256 amount) external {
        require(isWhitelisted[from] && isWhitelisted[to], "One or both parties not whitelisted");
        require(tokenBalances[tokenId][from] >= amount, "Insufficient balance");
        require(amount > 0 && amount <= 9223372036854775807, "Invalid amount");

        tokenBalances[tokenId][from] -= amount;
        tokenBalances[tokenId][to] += amount;

        int256 responseCode = transferToken(tokenId, from, to, int64(uint64(amount)));
        require(responseCode == HederaResponseCodes.SUCCESS, "Token transfer failed");

        emit TokensTransferred(tokenId, from, to, amount);
    }

    function distributeDividends(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(tokenBalances[usdtTokenId][treasuryWallet] >= amount, "Insufficient USDT balance");

        totalDividendsDistributed += amount;
        emit DividendsDistributed(amount);
    }

    function claimDividends() external {
        require(isWhitelisted[msg.sender], "Investor not whitelisted");
        uint256 shareholderBalance = tokenBalances[hederaTokenServiceTokenId][msg.sender];
        require(shareholderBalance > 0, "No shares owned");

        uint256 claimableAmount =
            (totalDividendsDistributed * shareholderBalance) / totalSupply[hederaTokenServiceTokenId];
        require(claimableAmount > withdrawnDividends[msg.sender], "No dividends to claim");

        uint256 amountToWithdraw = claimableAmount - withdrawnDividends[msg.sender];
        withdrawnDividends[msg.sender] = claimableAmount;

        require(amountToWithdraw <= 9223372036854775807, "Amount too large");

        tokenBalances[usdtTokenId][treasuryWallet] -= amountToWithdraw;
        tokenBalances[usdtTokenId][msg.sender] += amountToWithdraw;

        int256 responseCode = transferToken(usdtTokenId, treasuryWallet, msg.sender, int64(uint64(amountToWithdraw)));
        require(responseCode == HederaResponseCodes.SUCCESS, "USDT transfer failed");

        emit DividendClaimed(msg.sender, amountToWithdraw);
    }

    function castVote(uint256 votes) external {
        require(isWhitelisted[msg.sender], "Investor not whitelisted");
        require(tokenBalances[hederaTokenServiceTokenId][msg.sender] >= votes, "Insufficient votes");

        governanceVotes[msg.sender] = votes;
        emit GovernanceVoteCasted(msg.sender, votes);
    }

    function setInitialUsdtBalance(uint256 amount) external onlyOwner {
        require(tokenBalances[usdtTokenId][treasuryWallet] == 0, "USDT balance already set");
        tokenBalances[usdtTokenId][treasuryWallet] = amount;
    }
}
