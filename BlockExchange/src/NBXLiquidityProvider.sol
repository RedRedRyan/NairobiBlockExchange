// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BlockExchange.sol";
import "./BlockExchangeFactory.sol";
import "./NBXOrderBook.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Interface for Hedera Token Service token
interface IHTS {
    function associate(address token) external;
    function dissociate(address token) external;
    function transferToken(address token, address to, uint256 amount) external returns (bool);
    function transferTokenFrom(address token, address from, address to, uint256 amount) external returns (bool);
    function allowance(address token, address owner, address spender) external view returns (uint256);
    function approve(address token, address spender, uint256 amount) external returns (bool);
    function getBalance(address token, address account) external view returns (uint256);
}

/**
 * @title NBXLiquidityProvider
 * @dev Incentivizes market makers to provide liquidity for security tokens
 */
contract NBXLiquidityProvider is Ownable(msg.sender), ReentrancyGuard {
    BlockExchangeFactory public factory;
    NBXOrderBook public orderBook;

    // Liquidity provider registration
    struct LiquidityProvider {
        address provider;
        uint256 registrationDate;
        bool active;
        uint256 totalRewardsEarned;
        uint256 currentLockedAmount;
    }

    // Incentive program details
    struct IncentiveProgram {
        address tokenAddress;
        uint256 spreadRequirement; // Max spread in basis points (100 = 1%)
        uint256 minOrderSize; // Minimum order size in tokens
        uint256 minLockupAmount; // Minimum USDT to lock as collateral
        uint256 rewardRate; // Daily reward rate in basis points (100 = 1%)
        uint256 programEnd; // Timestamp when the program ends
        bool active;
    }

    // Storage
    mapping(address => LiquidityProvider) public liquidityProviders;
    mapping(address => IncentiveProgram) public incentivePrograms;
    mapping(address => mapping(address => uint256)) public lockedCollateral; // token => provider => amount
    mapping(address => uint256) public totalLiquidityRewards; // token => rewards

    // Events
    event LiquidityProviderRegistered(address indexed provider);
    event LiquidityProviderDeactivated(address indexed provider);
    event IncentiveProgramCreated(address indexed tokenAddress, uint256 rewardRate, uint256 programEnd);
    event IncentiveProgramUpdated(address indexed tokenAddress, bool active);
    event CollateralLocked(address indexed provider, address indexed tokenAddress, uint256 amount);
    event CollateralReleased(address indexed provider, address indexed tokenAddress, uint256 amount);
    event RewardsPaid(address indexed provider, address indexed tokenAddress, uint256 amount);

    // HTS service address and USDT token address
    IHTS public htsService;
    address public usdtTokenAddress;

    // Constants
    uint256 public constant PRECISION = 10000; // For basis points calculations
    uint256 public constant DAY_IN_SECONDS = 86400;

    constructor(
        address _factoryAddress,
        address _orderBookAddress,
        address _htsServiceAddress,
        address _usdtTokenAddress
    ) {
        factory = BlockExchangeFactory(_factoryAddress);
        orderBook = NBXOrderBook(_orderBookAddress);
        htsService = IHTS(_htsServiceAddress);
        usdtTokenAddress = _usdtTokenAddress;

        // Associate this contract with the USDT token
        htsService.associate(usdtTokenAddress);
    }

    /**
     * @dev Register as a liquidity provider
     */
    function registerAsLiquidityProvider() external {
        require(liquidityProviders[msg.sender].provider == address(0), "Already registered");

        liquidityProviders[msg.sender] = LiquidityProvider({
            provider: msg.sender,
            registrationDate: block.timestamp,
            active: true,
            totalRewardsEarned: 0,
            currentLockedAmount: 0
        });

        emit LiquidityProviderRegistered(msg.sender);
    }

    /**
     * @dev Admin function to create an incentive program for a token
     */
    function createIncentiveProgram(
        address _tokenAddress,
        uint256 _spreadRequirement,
        uint256 _minOrderSize,
        uint256 _minLockupAmount,
        uint256 _rewardRate,
        uint256 _durationInDays
    ) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_spreadRequirement > 0, "Spread requirement must be positive");
        require(_minOrderSize > 0, "Min order size must be positive");
        require(_minLockupAmount > 0, "Min lockup amount must be positive");
        require(_rewardRate > 0 && _rewardRate <= 10000, "Invalid reward rate");
        require(_durationInDays > 0, "Duration must be positive");

        uint256 programEnd = block.timestamp + (_durationInDays * DAY_IN_SECONDS);

        incentivePrograms[_tokenAddress] = IncentiveProgram({
            tokenAddress: _tokenAddress,
            spreadRequirement: _spreadRequirement,
            minOrderSize: _minOrderSize,
            minLockupAmount: _minLockupAmount,
            rewardRate: _rewardRate,
            programEnd: programEnd,
            active: true
        });

        emit IncentiveProgramCreated(_tokenAddress, _rewardRate, programEnd);
    }

    /**
     * @dev Update the status of an incentive program
     */
    function updateIncentiveProgram(address _tokenAddress, bool _active) external onlyOwner {
        require(incentivePrograms[_tokenAddress].tokenAddress != address(0), "Program doesn't exist");

        incentivePrograms[_tokenAddress].active = _active;

        emit IncentiveProgramUpdated(_tokenAddress, _active);
    }

    /**
     * @dev Lock collateral to participate in an incentive program
     */
    function lockCollateral(address _tokenAddress, uint256 _amount) external nonReentrant {
        require(liquidityProviders[msg.sender].active, "Not an active liquidity provider");
        require(incentivePrograms[_tokenAddress].active, "Incentive program not active");
        require(block.timestamp < incentivePrograms[_tokenAddress].programEnd, "Program has ended");
        require(_amount >= incentivePrograms[_tokenAddress].minLockupAmount, "Amount below minimum");

        // Check if provider has sufficient allowance
        require(htsService.allowance(usdtTokenAddress, msg.sender, address(this)) >= _amount, "Insufficient allowance");

        // Transfer HTS USDT from provider to contract
        require(htsService.transferTokenFrom(usdtTokenAddress, msg.sender, address(this), _amount), "Transfer failed");

        // Update records
        lockedCollateral[_tokenAddress][msg.sender] += _amount;
        liquidityProviders[msg.sender].currentLockedAmount += _amount;

        emit CollateralLocked(msg.sender, _tokenAddress, _amount);
    }

    /**
     * @dev Release locked collateral after program ends
     */
    function releaseCollateral(address _tokenAddress) external nonReentrant {
        require(lockedCollateral[_tokenAddress][msg.sender] > 0, "No collateral locked");
        require(
            block.timestamp > incentivePrograms[_tokenAddress].programEnd || !incentivePrograms[_tokenAddress].active,
            "Program still active"
        );

        uint256 amount = lockedCollateral[_tokenAddress][msg.sender];

        // Update records
        lockedCollateral[_tokenAddress][msg.sender] = 0;
        liquidityProviders[msg.sender].currentLockedAmount -= amount;

        // Transfer HTS USDT back to provider
        require(htsService.transferToken(usdtTokenAddress, msg.sender, amount), "Transfer failed");

        emit CollateralReleased(msg.sender, _tokenAddress, amount);
    }

    /**
     * @dev Check if a provider meets the spread requirements
     */
    function meetsSpreadRequirements(address _provider, string memory _companyName,address _tokenAddress) public view returns (bool) {
        IncentiveProgram memory program = incentivePrograms[_tokenAddress];
        if (!program.active) return false;

        // Get the exchange for this token
        address exchangeAddress = factory.getSMEContract(_companyName);
        if (exchangeAddress == address(0)) return false;

        // Get best bid and ask
        (uint256 bestBidPrice, uint256 bestBidSize) = orderBook.getBestBid(exchangeAddress);
        (uint256 bestAskPrice, uint256 bestAskSize) = orderBook.getBestAsk(exchangeAddress);

        // Check if provider has active orders at these prices
        bool hasBid = orderBook.hasActiveOrder(_provider, exchangeAddress, bestBidPrice, true);
        bool hasAsk = orderBook.hasActiveOrder(_provider, exchangeAddress, bestAskPrice, false);

        // Check order sizes
        bool bidSizeOk = bestBidSize >= program.minOrderSize;
        bool askSizeOk = bestAskSize >= program.minOrderSize;

        // Calculate spread
        if (bestBidPrice == 0 || bestAskPrice == 0) return false;

        uint256 spread = ((bestAskPrice - bestBidPrice) * PRECISION) / bestBidPrice;

        return hasBid && hasAsk && bidSizeOk && askSizeOk && spread <= program.spreadRequirement;
    }
    /**
 * @dev Calculate daily rewards for a provider
 */
function calculateDailyReward(address _provider, string memory _companyName, address _tokenAddress) public view returns (uint256) {
    if (!meetsSpreadRequirements(_provider, _companyName, _tokenAddress)) return 0;

    uint256 locked = lockedCollateral[_tokenAddress][_provider];
    uint256 rate = incentivePrograms[_tokenAddress].rewardRate;

    return (locked * rate) / PRECISION;
}

    /**
     * @dev Claim rewards for a token
     */
    function claimRewards(address _tokenAddress,string memory _companyName) external nonReentrant {
        require(liquidityProviders[msg.sender].active, "Not an active liquidity provider");
        require(incentivePrograms[_tokenAddress].active, "Program not active");
        require(lockedCollateral[_tokenAddress][msg.sender] > 0, "No collateral locked");

        uint256 reward = calculateDailyReward(msg.sender,_companyName, _tokenAddress);
        require(reward > 0, "No rewards to claim");

        // Update records
        liquidityProviders[msg.sender].totalRewardsEarned += reward;
        totalLiquidityRewards[_tokenAddress] += reward;

        // Transfer HTS rewards to provider
        require(htsService.transferToken(usdtTokenAddress, msg.sender, reward), "Transfer failed");

        emit RewardsPaid(msg.sender, _tokenAddress, reward);
    }

    /**
     * @dev Deactivate a liquidity provider
     */
    function deactivateProvider(address _provider) external onlyOwner {
        require(liquidityProviders[_provider].active, "Provider not active");

        liquidityProviders[_provider].active = false;

        emit LiquidityProviderDeactivated(_provider);
    }

    /**
     * @dev Fund the contract with HTS USDT for rewards
     */
    function fundRewards(uint256 _amount) external onlyOwner {
        require(htsService.transferTokenFrom(usdtTokenAddress, msg.sender, address(this), _amount), "Transfer failed");
    }

    /**
     * @dev Emergency withdraw function for owner
     */
    function emergencyWithdraw(address _token, uint256 _amount) external onlyOwner {
        require(htsService.transferToken(_token, owner(), _amount), "Transfer failed");
    }

    /**
     * @dev Associate this contract with a new token
     */
    function associateToken(address _token) external onlyOwner {
        htsService.associate(_token);
    }

    /**
     * @dev Dissociate this contract from a token
     */
    function dissociateToken(address _token) external onlyOwner {
        htsService.dissociate(_token);
    }
}
