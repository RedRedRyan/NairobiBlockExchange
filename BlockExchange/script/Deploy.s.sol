// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/BlockExchange.sol";
import "../src/BlockExchangeFactory.sol";
import "../src/NBXOrderBook.sol";
import "../src/NBXLiquidityProvider.sol";

contract DeployScript is Script {
    function run() external {
        // Load environment variables - this is the standard way to get private keys in Foundry
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdtTokenAddress = vm.envAddress("USDT_TOKEN_ADDRESS");
        address treasuryWallet = vm.envAddress("TREASURY_WALLET");
        address feeCollector = vm.envAddress("FEE_COLLECTOR_ADDRESS");

        // Start broadcasting transactions using the loaded private key
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy BlockExchangeFactory
        BlockExchangeFactory factory = new BlockExchangeFactory();

        // Step 2: Define parameters for BlockExchange deployment
        string memory companyName = "Example Company";
        string memory tokenSymbol = "EXC";
        uint256 initialSupply = 1_000_000 * 10 ** 6; // 1 million tokens with 6 decimals

        // Step 3: Deploy a BlockExchange instance via the factory
        address exchangeAddress = factory.deployExchange(
            companyName, tokenSymbol, initialSupply, usdtTokenAddress, treasuryWallet
        );

        // Get the deployed BlockExchange instance
        BlockExchange exchange = BlockExchange(exchangeAddress);

        // Step 4: Deploy NBXOrderBook
        NBXOrderBook orderBook = new NBXOrderBook(address(factory), feeCollector);

        // Step 5: Deploy NBXLiquidityProvider
        NBXLiquidityProvider liquidityProvider =
            new NBXLiquidityProvider(address(factory), address(orderBook), usdtTokenAddress);

        // Step 6: Set initial USDT balance in the BlockExchange contract
        // This can be adjusted based on your requirements
        uint256 initialUsdtBalance = 1_000_000 * 10 ** 6; // 1 million USDT with 6 decimals
        exchange.setInitialUsdtBalance(initialUsdtBalance);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log the deployed contract addresses for reference
        console.log("Deployment complete!");
        console.log("BlockExchangeFactory deployed at:", address(factory));
        console.log("BlockExchange deployed at:", exchangeAddress);
        console.log("NBXOrderBook deployed at:", address(orderBook));
        console.log("NBXLiquidityProvider deployed at:", address(liquidityProvider));
    }
}