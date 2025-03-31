// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/BlockExchange.sol";
import "../src/BlockExchangeFactory.sol";
import "../src/NBXOrderBook.sol";
import "../src/NBXLiquidityProvider.sol";

contract DeployScript is Script {
    function run() external {
        // Start broadcasting transactions using the private key from the environment
        vm.startBroadcast();

        // Step 1: Deploy BlockExchangeFactory
        BlockExchangeFactory factory = new BlockExchangeFactory();
        
        // Step 2: Define parameters for BlockExchange deployment
        string memory companyName = "Example Company";
        string memory tokenSymbol = "EXC";
        uint256 initialSupply = 1_000_000 * 10**6; // 1 million tokens with 6 decimals
        address usdtTokenId = 0xYourUsdtTokenAddressHere; // Replace with actual USDT token address on Hedera
        address treasuryWallet = 0xYourTreasuryAddressHere; // Replace with your treasury wallet address
        uint256 tokenCreationFee = 100 * 10**8; // 100 HBAR in tinybars for token creation on Hedera

        // Step 3: Deploy a BlockExchange instance via the factory
        address exchangeAddress = factory.deployExchange{value: tokenCreationFee}(
            companyName,
            tokenSymbol,
            initialSupply,
            usdtTokenId,
            treasuryWallet
        );

        // Step 4: Deploy NBXOrderBook
        address feeCollector = 0xYourFeeCollectorAddressHere; // Replace with your fee collector address
        NBXOrderBook orderBook = new NBXOrderBook(address(factory), feeCollector);

        // Step 5: Deploy NBXLiquidityProvider
        NBXLiquidityProvider liquidityProvider = new NBXLiquidityProvider(
            address(factory),
            address(orderBook),
            usdtTokenId
        );

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log the deployed contract addresses for reference
        console.log("BlockExchangeFactory deployed at:", address(factory));
        console.log("BlockExchange deployed at:", exchangeAddress);
        console.log("NBXOrderBook deployed at:", address(orderBook));
        console.log("NBXLiquidityProvider deployed at:", address(liquidityProvider));
    }
}