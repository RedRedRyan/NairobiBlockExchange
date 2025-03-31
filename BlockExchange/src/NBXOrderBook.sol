// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BlockExchange.sol";
import "./BlockExchangeFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title NBXOrderBook
 * @dev Order book and matching engine for trading security tokens between users
 */
contract NBXOrderBook is Ownable, ReentrancyGuard {
    BlockExchangeFactory public factory;

    // Fee configuration
    uint256 public tradingFeePercentage = 25; // 0.25% in basis points (100 = 1%)
    address public feeCollector;

    enum OrderType {
        BUY,
        SELL
    }
    enum OrderStatus {
        OPEN,
        FILLED,
        CANCELLED
    }

    struct Order {
        uint256 id;
        address maker;
        address tokenAddress;
        uint256 amount;
        uint256 price; // Price in USDT (*10^6)
        OrderType orderType;
        OrderStatus status;
        uint256 timestamp;
        uint256 filledAmount;
    }

    // Order tracking
    uint256 public nextOrderId = 1;
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public userOrders;

    // Token order books (token address => order IDs)
    mapping(address => uint256[]) public buyOrders;
    mapping(address => uint256[]) public sellOrders;

    // Events
    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address indexed tokenAddress,
        uint256 amount,
        uint256 price,
        OrderType orderType
    );
    event OrderFilled(
        uint256 indexed orderId, address indexed maker, address indexed taker, uint256 amount, uint256 price
    );
    event OrderCancelled(uint256 indexed orderId);
    event FeesCollected(address token, address collector, uint256 amount);

    constructor(address _factory, address _feeCollector) Ownable(msg.sender) {
        factory = BlockExchangeFactory(_factory);
        feeCollector = _feeCollector;
    }

    /**
     * @dev Creates a new buy order
     * @param tokenAddress Address of the security token
     * @param amount Amount of tokens to buy
     * @param price Price per token in USDT
     */
    function createBuyOrder(address tokenAddress, uint256 amount, uint256 price) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(price > 0, "Price must be greater than 0");

        BlockExchange exchange = _getExchangeForToken(tokenAddress);
        require(address(exchange) != address(0), "Token not supported");

        // Check if user is whitelisted
        require(exchange.isWhitelisted(msg.sender), "User not whitelisted");

        // Reserve USDT from user
        uint256 totalCost = (amount * price) / 1e6;
        exchange.transferTokens(exchange.usdtTokenId(), msg.sender, address(this), totalCost);

        // Create order
        uint256 orderId = nextOrderId++;
        orders[orderId] = Order({
            id: orderId,
            maker: msg.sender,
            tokenAddress: tokenAddress,
            amount: amount,
            price: price,
            orderType: OrderType.BUY,
            status: OrderStatus.OPEN,
            timestamp: block.timestamp,
            filledAmount: 0
        });

        userOrders[msg.sender].push(orderId);
        buyOrders[tokenAddress].push(orderId);

        // Try to match with existing sell orders
        _matchOrders(orderId);

        emit OrderCreated(orderId, msg.sender, tokenAddress, amount, price, OrderType.BUY);
    }

    /**
     * @dev Creates a new sell order
     * @param tokenAddress Address of the security token
     * @param amount Amount of tokens to sell
     * @param price Price per token in USDT
     */
    function createSellOrder(address tokenAddress, uint256 amount, uint256 price) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(price > 0, "Price must be greater than 0");

        BlockExchange exchange = _getExchangeForToken(tokenAddress);
        require(address(exchange) != address(0), "Token not supported");

        // Check if user is whitelisted
        require(exchange.isWhitelisted(msg.sender), "User not whitelisted");

        // Reserve tokens from user
        exchange.transferTokens(tokenAddress, msg.sender, address(this), amount);

        // Create order
        uint256 orderId = nextOrderId++;
        orders[orderId] = Order({
            id: orderId,
            maker: msg.sender,
            tokenAddress: tokenAddress,
            amount: amount,
            price: price,
            orderType: OrderType.SELL,
            status: OrderStatus.OPEN,
            timestamp: block.timestamp,
            filledAmount: 0
        });

        userOrders[msg.sender].push(orderId);
        sellOrders[tokenAddress].push(orderId);

        // Try to match with existing buy orders
        _matchOrders(orderId);

        emit OrderCreated(orderId, msg.sender, tokenAddress, amount, price, OrderType.SELL);
    }

    /**
     * @dev Cancels an open order
     * @param orderId ID of the order to cancel
     */
    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.maker == msg.sender, "Not order owner");
        require(order.status == OrderStatus.OPEN, "Order not open");

        order.status = OrderStatus.CANCELLED;

        // Return reserved assets
        BlockExchange exchange = _getExchangeForToken(order.tokenAddress);

        if (order.orderType == OrderType.BUY) {
            uint256 remainingAmount = order.amount - order.filledAmount;
            uint256 remainingCost = (remainingAmount * order.price) / 1e6;
            if (remainingCost > 0) {
                exchange.transferTokens(exchange.usdtTokenId(), address(this), order.maker, remainingCost);
            }
        } else {
            // SELL
            uint256 remainingAmount = order.amount - order.filledAmount;
            if (remainingAmount > 0) {
                exchange.transferTokens(order.tokenAddress, address(this), order.maker, remainingAmount);
            }
        }

        emit OrderCancelled(orderId);
    }

    /**
     * @dev Get active buy orders for a token
     * @param tokenAddress Address of the security token
     */
    function getActiveBuyOrders(address tokenAddress) external view returns (uint256[] memory) {
        uint256[] memory allOrders = buyOrders[tokenAddress];
        uint256 activeCount = 0;

        // Count active orders
        for (uint256 i = 0; i < allOrders.length; i++) {
            if (orders[allOrders[i]].status == OrderStatus.OPEN) {
                activeCount++;
            }
        }

        // Create array of active orders
        uint256[] memory activeOrders = new uint256[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allOrders.length; i++) {
            if (orders[allOrders[i]].status == OrderStatus.OPEN) {
                activeOrders[index] = allOrders[i];
                index++;
            }
        }

        return activeOrders;
    }

    /**
     * @dev Get active sell orders for a token
     * @param tokenAddress Address of the security token
     */
    function getActiveSellOrders(address tokenAddress) external view returns (uint256[] memory) {
        uint256[] memory allOrders = sellOrders[tokenAddress];
        uint256 activeCount = 0;

        // Count active orders
        for (uint256 i = 0; i < allOrders.length; i++) {
            if (orders[allOrders[i]].status == OrderStatus.OPEN) {
                activeCount++;
            }
        }

        // Create array of active orders
        uint256[] memory activeOrders = new uint256[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allOrders.length; i++) {
            if (orders[allOrders[i]].status == OrderStatus.OPEN) {
                activeOrders[index] = allOrders[i];
                index++;
            }
        }

        return activeOrders;
    }

    /**
     * @dev Get user's active orders
     * @param user Address of the user
     */
    function getUserActiveOrders(address user) external view returns (uint256[] memory) {
        uint256[] memory allOrders = userOrders[user];
        uint256 activeCount = 0;

        // Count active orders
        for (uint256 i = 0; i < allOrders.length; i++) {
            if (orders[allOrders[i]].status == OrderStatus.OPEN) {
                activeCount++;
            }
        }

        // Create array of active orders
        uint256[] memory activeOrders = new uint256[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allOrders.length; i++) {
            if (orders[allOrders[i]].status == OrderStatus.OPEN) {
                activeOrders[index] = allOrders[i];
                index++;
            }
        }

        return activeOrders;
    }

    /**
     * @dev Update trading fee percentage
     * @param _feePercentage Fee in basis points (100 = 1%)
     */
    function setTradingFeePercentage(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 100, "Fee too high"); // Max 1%
        tradingFeePercentage = _feePercentage;
    }

    /**
     * @dev Update fee collector address
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Invalid address");
        feeCollector = _feeCollector;
    }

    /**
     * @dev Internal function to match an order against the order book
     */
    function _matchOrders(uint256 orderId) internal {
        Order storage newOrder = orders[orderId];

        if (newOrder.orderType == OrderType.BUY) {
            _matchBuyOrder(newOrder);
        } else {
            _matchSellOrder(newOrder);
        }
    }

    /**
     * @dev Attempts to match a buy order with existing sell orders
     */
    function _matchBuyOrder(Order storage buyOrder) internal {
        if (buyOrder.status != OrderStatus.OPEN) return;

        uint256[] storage tokenSellOrders = sellOrders[buyOrder.tokenAddress];

        // Find and match with eligible sell orders
        for (uint256 i = 0; i < tokenSellOrders.length && buyOrder.filledAmount < buyOrder.amount; i++) {
            Order storage sellOrder = orders[tokenSellOrders[i]];

            if (sellOrder.status != OrderStatus.OPEN) continue;
            if (sellOrder.price > buyOrder.price) continue; // Price too high

            // Calculate match amount
            uint256 remainingBuyAmount = buyOrder.amount - buyOrder.filledAmount;
            uint256 remainingSellAmount = sellOrder.amount - sellOrder.filledAmount;
            uint256 matchAmount = remainingBuyAmount < remainingSellAmount ? remainingBuyAmount : remainingSellAmount;

            if (matchAmount == 0) continue;

            // Use the sell price (better for the buyer)
            uint256 executionPrice = sellOrder.price;
            uint256 totalCost = (matchAmount * executionPrice) / 1e6;

            // Calculate fee
            uint256 fee = (totalCost * tradingFeePercentage) / 10000;
            uint256 sellerReceives = totalCost - fee;

            // Update order status
            buyOrder.filledAmount += matchAmount;
            sellOrder.filledAmount += matchAmount;

            if (sellOrder.filledAmount >= sellOrder.amount) {
                sellOrder.status = OrderStatus.FILLED;
            }

            if (buyOrder.filledAmount >= buyOrder.amount) {
                buyOrder.status = OrderStatus.FILLED;
            }

            // Execute the trade
            BlockExchange exchange = _getExchangeForToken(buyOrder.tokenAddress);

            // Transfer tokens to buyer
            exchange.transferTokens(buyOrder.tokenAddress, address(this), buyOrder.maker, matchAmount);

            // Transfer USDT to seller
            exchange.transferTokens(exchange.usdtTokenId(), address(this), sellOrder.maker, sellerReceives);

            // Collect fee
            if (fee > 0) {
                exchange.transferTokens(exchange.usdtTokenId(), address(this), feeCollector, fee);
                emit FeesCollected(exchange.usdtTokenId(), feeCollector, fee);
            }

            emit OrderFilled(sellOrder.id, sellOrder.maker, buyOrder.maker, matchAmount, executionPrice);
        }

        // Refund excess USDT if order was not fully filled and is no longer open
        if (buyOrder.status != OrderStatus.OPEN && buyOrder.filledAmount < buyOrder.amount) {
            uint256 remainingAmount = buyOrder.amount - buyOrder.filledAmount;
            uint256 remainingCost = (remainingAmount * buyOrder.price) / 1e6;

            if (remainingCost > 0) {
                BlockExchange exchange = _getExchangeForToken(buyOrder.tokenAddress);
                exchange.transferTokens(exchange.usdtTokenId(), address(this), buyOrder.maker, remainingCost);
            }
        }
    }

    /**
     * @dev Attempts to match a sell order with existing buy orders
     */
    function _matchSellOrder(Order storage sellOrder) internal {
        if (sellOrder.status != OrderStatus.OPEN) return;

        uint256[] storage tokenBuyOrders = buyOrders[sellOrder.tokenAddress];

        // Find and match with eligible buy orders
        for (uint256 i = 0; i < tokenBuyOrders.length && sellOrder.filledAmount < sellOrder.amount; i++) {
            Order storage buyOrder = orders[tokenBuyOrders[i]];

            if (buyOrder.status != OrderStatus.OPEN) continue;
            if (buyOrder.price < sellOrder.price) continue; // Price too low

            // Calculate match amount
            uint256 remainingSellAmount = sellOrder.amount - sellOrder.filledAmount;
            uint256 remainingBuyAmount = buyOrder.amount - buyOrder.filledAmount;
            uint256 matchAmount = remainingSellAmount < remainingBuyAmount ? remainingSellAmount : remainingBuyAmount;

            if (matchAmount == 0) continue;

            // Use the buy price (better for the seller)
            uint256 executionPrice = buyOrder.price;
            uint256 totalCost = (matchAmount * executionPrice) / 1e6;

            // Calculate fee
            uint256 fee = (totalCost * tradingFeePercentage) / 10000;
            uint256 sellerReceives = totalCost - fee;

            // Update order status
            sellOrder.filledAmount += matchAmount;
            buyOrder.filledAmount += matchAmount;

            if (buyOrder.filledAmount >= buyOrder.amount) {
                buyOrder.status = OrderStatus.FILLED;
            }

            if (sellOrder.filledAmount >= sellOrder.amount) {
                sellOrder.status = OrderStatus.FILLED;
            }

            // Execute the trade
            BlockExchange exchange = _getExchangeForToken(sellOrder.tokenAddress);

            // Transfer tokens to buyer
            exchange.transferTokens(sellOrder.tokenAddress, address(this), buyOrder.maker, matchAmount);

            // Transfer USDT to seller
            exchange.transferTokens(exchange.usdtTokenId(), address(this), sellOrder.maker, sellerReceives);

            // Collect fee
            if (fee > 0) {
                exchange.transferTokens(exchange.usdtTokenId(), address(this), feeCollector, fee);
                emit FeesCollected(exchange.usdtTokenId(), feeCollector, fee);
            }

            emit OrderFilled(buyOrder.id, buyOrder.maker, sellOrder.maker, matchAmount, executionPrice);
        }

        // Return unsold tokens if order was not fully filled and is no longer open
        if (sellOrder.status != OrderStatus.OPEN && sellOrder.filledAmount < sellOrder.amount) {
            uint256 remainingAmount = sellOrder.amount - sellOrder.filledAmount;

            if (remainingAmount > 0) {
                BlockExchange exchange = _getExchangeForToken(sellOrder.tokenAddress);
                exchange.transferTokens(sellOrder.tokenAddress, address(this), sellOrder.maker, remainingAmount);
            }
        }
    }

    /**
     * @dev Helper to get the BlockExchange instance for a token
     */
    function _getExchangeForToken(address tokenAddress) internal view returns (BlockExchange) {
        address[] memory exchanges = factory.getDeployedExchanges();

        for (uint256 i = 0; i < exchanges.length; i++) {
            BlockExchange exchange = BlockExchange(exchanges[i]);
            if (exchange.hederaTokenServiceTokenId() == tokenAddress) {
                return exchange;
            }
        }

        return BlockExchange(address(0));
    }
}
