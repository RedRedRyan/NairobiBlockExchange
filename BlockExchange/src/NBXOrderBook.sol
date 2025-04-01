// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BlockExchange.sol";
import "./BlockExchangeFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title NBXOrderBook
 * @dev Order book and matching engine for trading security tokens between users
 */
contract NBXOrderBook is Ownable, ReentrancyGuard {
    BlockExchangeFactory public factory;

    // Fee configuration
    uint256 public tradingFeePercentage = 25; // 0.25% in basis points (100 = 1%)
    address public feeCollector;

    // Order expiration setting
    uint256 public constant MAX_ORDER_AGE = 30 days;

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
        IERC20(exchange.usdtTokenAddress()).transferFrom(msg.sender, address(this), totalCost);

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
        _insertBuyOrder(tokenAddress, orderId);

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
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);

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
        _insertSellOrder(tokenAddress, orderId);

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
                IERC20(exchange.usdtTokenAddress()).transfer(order.maker, remainingCost);
            }
        } else {
            // SELL
            uint256 remainingAmount = order.amount - order.filledAmount;
            if (remainingAmount > 0) {
                IERC20(order.tokenAddress).transfer(order.maker, remainingAmount);
            }
        }

        // Clean order list occasionally to optimize gas
        if (block.timestamp % 10 == 0) {
            _cleanFilledOrders(order.tokenAddress, order.orderType == OrderType.BUY);
        }

        emit OrderCancelled(orderId);
    }

    /**
     * @dev Cancel expired orders (anyone can call)
     * @param orderId ID of the order to cancel
     */
    function cancelExpiredOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.OPEN, "Order not open");
        require(block.timestamp > order.timestamp + MAX_ORDER_AGE, "Order not expired");

        order.status = OrderStatus.CANCELLED;

        // Return reserved assets
        BlockExchange exchange = _getExchangeForToken(order.tokenAddress);

        if (order.orderType == OrderType.BUY) {
            uint256 remainingAmount = order.amount - order.filledAmount;
            uint256 remainingCost = (remainingAmount * order.price) / 1e6;
            if (remainingCost > 0) {
                IERC20(exchange.usdtTokenAddress()).transfer(order.maker, remainingCost);
            }
        } else {
            // SELL
            uint256 remainingAmount = order.amount - order.filledAmount;
            if (remainingAmount > 0) {
                IERC20(order.tokenAddress).transfer(order.maker, remainingAmount);
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
     * @dev Check if a specific provider has active orders at a specific price point
     * @param _provider Address of the provider
     * @param tokenAddress Address of the token
     * @param price Price point to check
     * @param isBid Whether to check buy orders (true) or sell orders (false)
     */
    function hasActiveOrder(address _provider, address tokenAddress, uint256 price, bool isBid)
        external
        view
        returns (bool)
    {
        uint256[] storage ordersList = isBid ? buyOrders[tokenAddress] : sellOrders[tokenAddress];

        for (uint256 i = 0; i < ordersList.length; i++) {
            Order storage order = orders[ordersList[i]];
            if (order.maker == _provider && order.price == price && order.status == OrderStatus.OPEN) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Get the best bid (highest buy price) and its size for a token
     * @param tokenAddress Address of the token
     * @return price Price of the best bid
     * @return amount Size of the best bid
     */
    function getBestBid(address tokenAddress) external view returns (uint256, uint256) {
        uint256[] storage tokenBuyOrders = buyOrders[tokenAddress];
        if (tokenBuyOrders.length == 0) return (0, 0);

        uint256 bestPrice = 0;
        uint256 bestAmount = 0;

        for (uint256 i = 0; i < tokenBuyOrders.length; i++) {
            Order storage order = orders[tokenBuyOrders[i]];
            if (order.status == OrderStatus.OPEN && order.price > bestPrice) {
                bestPrice = order.price;
                bestAmount = order.amount - order.filledAmount;
            }
        }

        return (bestPrice, bestAmount);
    }

    /**
     * @dev Get the best ask (lowest sell price) and its size for a token
     * @param tokenAddress Address of the token
     * @return price Price of the best ask
     * @return amount Size of the best ask
     */
    function getBestAsk(address tokenAddress) external view returns (uint256, uint256) {
        uint256[] storage tokenSellOrders = sellOrders[tokenAddress];
        if (tokenSellOrders.length == 0) return (0, 0);

        uint256 bestPrice = type(uint256).max;
        uint256 bestAmount = 0;

        for (uint256 i = 0; i < tokenSellOrders.length; i++) {
            Order storage order = orders[tokenSellOrders[i]];
            if (order.status == OrderStatus.OPEN && (bestPrice == type(uint256).max || order.price < bestPrice)) {
                bestPrice = order.price;
                bestAmount = order.amount - order.filledAmount;
            }
        }

        return (bestPrice == type(uint256).max ? 0 : bestPrice, bestAmount);
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

        // Check if order is expired
        if (block.timestamp > buyOrder.timestamp + MAX_ORDER_AGE) {
            buyOrder.status = OrderStatus.CANCELLED;
            return;
        }

        uint256[] storage tokenSellOrders = sellOrders[buyOrder.tokenAddress];

        // Find and match with eligible sell orders
        for (uint256 i = 0; i < tokenSellOrders.length && buyOrder.filledAmount < buyOrder.amount; i++) {
            Order storage sellOrder = orders[tokenSellOrders[i]];

            if (sellOrder.status != OrderStatus.OPEN) continue;
            if (sellOrder.price > buyOrder.price) continue; // Price too high
            if (sellOrder.maker == buyOrder.maker) continue; // Prevent self-trading

            // Check if sell order is expired
            if (block.timestamp > sellOrder.timestamp + MAX_ORDER_AGE) {
                sellOrder.status = OrderStatus.CANCELLED;
                continue;
            }

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
            IERC20(buyOrder.tokenAddress).transfer(buyOrder.maker, matchAmount);

            // Transfer USDT to seller
            IERC20(exchange.usdtTokenAddress()).transfer(sellOrder.maker, sellerReceives);

            // Collect fee
            if (fee > 0) {
                IERC20(exchange.usdtTokenAddress()).transfer(feeCollector, fee);
                emit FeesCollected(exchange.usdtTokenAddress(), feeCollector, fee);
            }

            emit OrderFilled(sellOrder.id, sellOrder.maker, buyOrder.maker, matchAmount, executionPrice);
        }

        // Clean up order book occasionally
        if (block.timestamp % 10 == 0) {
            _cleanFilledOrders(buyOrder.tokenAddress, false); // Clean sell orders
        }

        // Refund excess USDT if order was not fully filled and is no longer open
        if (buyOrder.status != OrderStatus.OPEN && buyOrder.filledAmount < buyOrder.amount) {
            uint256 remainingAmount = buyOrder.amount - buyOrder.filledAmount;
            uint256 remainingCost = (remainingAmount * buyOrder.price) / 1e6;

            if (remainingCost > 0) {
                BlockExchange exchange = _getExchangeForToken(buyOrder.tokenAddress);
                IERC20(exchange.usdtTokenAddress()).transfer(buyOrder.maker, remainingCost);
            }
        }
    }

    /**
     * @dev Attempts to match a sell order with existing buy orders
     */
    function _matchSellOrder(Order storage sellOrder) internal {
        if (sellOrder.status != OrderStatus.OPEN) return;

        // Check if order is expired
        if (block.timestamp > sellOrder.timestamp + MAX_ORDER_AGE) {
            sellOrder.status = OrderStatus.CANCELLED;
            return;
        }

        uint256[] storage tokenBuyOrders = buyOrders[sellOrder.tokenAddress];

        // Find and match with eligible buy orders
        for (uint256 i = 0; i < tokenBuyOrders.length && sellOrder.filledAmount < sellOrder.amount; i++) {
            Order storage buyOrder = orders[tokenBuyOrders[i]];

            if (buyOrder.status != OrderStatus.OPEN) continue;
            if (buyOrder.price < sellOrder.price) continue; // Price too low
            if (buyOrder.maker == sellOrder.maker) continue; // Prevent self-trading

            // Check if buy order is expired
            if (block.timestamp > buyOrder.timestamp + MAX_ORDER_AGE) {
                buyOrder.status = OrderStatus.CANCELLED;
                continue;
            }

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
            IERC20(sellOrder.tokenAddress).transfer(buyOrder.maker, matchAmount);

            // Transfer USDT to seller
            IERC20(exchange.usdtTokenAddress()).transfer(sellOrder.maker, sellerReceives);

            // Collect fee
            if (fee > 0) {
                IERC20(exchange.usdtTokenAddress()).transfer(feeCollector, fee);
                emit FeesCollected(exchange.usdtTokenAddress(), feeCollector, fee);
            }

            emit OrderFilled(buyOrder.id, buyOrder.maker, sellOrder.maker, matchAmount, executionPrice);
        }

        // Clean up order book occasionally
        if (block.timestamp % 10 == 0) {
            _cleanFilledOrders(sellOrder.tokenAddress, true); // Clean buy orders
        }

        // Return unsold tokens if order was not fully filled and is no longer open
        if (sellOrder.status != OrderStatus.OPEN && sellOrder.filledAmount < sellOrder.amount) {
            uint256 remainingAmount = sellOrder.amount - sellOrder.filledAmount;

            if (remainingAmount > 0) {
                IERC20(sellOrder.tokenAddress).transfer(sellOrder.maker, remainingAmount);
            }
        }
    }

    /**
     * @dev Helper function to clean filled or cancelled orders from the order list
     * @param tokenAddress Address of the token
     * @param isBid Whether to clean buy orders (true) or sell orders (false)
     */
    function _cleanFilledOrders(address tokenAddress, bool isBid) internal {
        uint256[] storage ordersList = isBid ? buyOrders[tokenAddress] : sellOrders[tokenAddress];

        uint256 i = 0;
        while (i < ordersList.length) {
            if (orders[ordersList[i]].status != OrderStatus.OPEN) {
                ordersList[i] = ordersList[ordersList.length - 1];
                ordersList.pop();
            } else {
                i++;
            }
        }
    }

    /**
     * @dev Helper function to insert a buy order with price-time priority (highest price first)
     * @param tokenAddress Address of the token
     * @param orderId ID of the order to insert
     */
    function _insertBuyOrder(address tokenAddress, uint256 orderId) internal {
        uint256[] storage orderList = buyOrders[tokenAddress];

        // If empty, just add
        if (orderList.length == 0) {
            orderList.push(orderId);
            return;
        }

        Order storage newOrder = orders[orderId];

        // Find insertion point (highest price first)
        uint256 i = 0;
        while (
            i < orderList.length && orders[orderList[i]].status == OrderStatus.OPEN
                && orders[orderList[i]].price >= newOrder.price
        ) {
            i++;
        }

        // Insert at position i
        orderList.push(orderList[orderList.length - 1]); // Make space
        for (uint256 j = orderList.length - 1; j > i; j--) {
            orderList[j] = orderList[j - 1];
        }
        orderList[i] = orderId;
    }

    /**
     * @dev Helper function to insert a sell order with price-time priority (lowest price first)
     * @param tokenAddress Address of the token
     * @param orderId ID of the order to insert
     */
    function _insertSellOrder(address tokenAddress, uint256 orderId) internal {
        uint256[] storage orderList = sellOrders[tokenAddress];

        // If empty, just add
        if (orderList.length == 0) {
            orderList.push(orderId);
            return;
        }

        Order storage newOrder = orders[orderId];

        // Find insertion point (lowest price first)
        uint256 i = 0;
        while (
            i < orderList.length && orders[orderList[i]].status == OrderStatus.OPEN
                && orders[orderList[i]].price <= newOrder.price
        ) {
            i++;
        }

        // Insert at position i
        orderList.push(orderList[orderList.length - 1]); // Make space
        for (uint256 j = orderList.length - 1; j > i; j--) {
            orderList[j] = orderList[j - 1];
        }
        orderList[i] = orderId;
    }

    /**
     * @dev Helper to get the BlockExchange instance for a token
     */
    function _getExchangeForToken(address tokenAddress) internal view returns (BlockExchange) {
        address[] memory exchanges = factory.getDeployedExchanges();

        for (uint256 i = 0; i < exchanges.length; i++) {
            BlockExchange exchange = BlockExchange(exchanges[i]);
            if (exchange.securityTokenAddress() == tokenAddress) {
                return exchange;
            }
        }

        return BlockExchange(address(0));
    }
}