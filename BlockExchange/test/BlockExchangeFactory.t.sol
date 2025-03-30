// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BlockExchangeFactory.sol";
import "../src/BlockExchange.sol";

contract BlockExchangeFactoryTest is Test {
    BlockExchangeFactory factory;
    address owner = address(1);
    address smeAdmin = address(2);
    address mockUsdtId = address(0x8888);
    address treasuryWallet = address(0x5678);
    address hederaTokenServiceAddress = address(0x167);

    uint256 constant INITIAL_SUPPLY = 10000 * 10 ** 6; // 10,000 tokens

    function setUp() public {
        vm.startPrank(owner);
        factory = new BlockExchangeFactory();
        vm.stopPrank();
    }

    function testDeployExchange() public {
        console.log("Starting testDeployExchange");
        vm.startPrank(owner);
        vm.deal(owner, 30 ether); // Ensure owner has enough ETH

        // Mock createFungibleToken generically
        vm.mockCall(
            hederaTokenServiceAddress,
            abi.encodeWithSelector(IHederaTokenService.createFungibleToken.selector),
            abi.encode(int256(0), address(0x9999)) // SUCCESS and token address
        );

        // Mock associateToken calls (two calls in constructor)
        vm.mockCall(
            hederaTokenServiceAddress,
            abi.encodeWithSelector(IHederaTokenService.associateToken.selector),
            abi.encode(int256(0)) // SUCCESS
        );

        address exchangeAddr =
            factory.deployExchange{value: 20 ether}("TestCompany", "TCO", INITIAL_SUPPLY, mockUsdtId, treasuryWallet);
        console.log("Exchange deployed at:", exchangeAddr);

        assertEq(factory.getDeployedExchangesCount(), 1, "Deployed exchanges count should be 1");
        assertEq(factory.getSMEContract("TestCompany"), exchangeAddr, "SME contract address should match");

        BlockExchange exchange = BlockExchange(exchangeAddr);
        assertEq(exchange.owner(), owner, "Owner should be the deployer");

        vm.stopPrank();
    }

    function testCannotDeployDuplicateCompany() public {
        console.log("Starting testCannotDeployDuplicateCompany");
        vm.startPrank(owner);
        vm.deal(owner, 50 ether); // Ensure owner has enough ETH

        // Mock createFungibleToken generically
        vm.mockCall(
            hederaTokenServiceAddress,
            abi.encodeWithSelector(IHederaTokenService.createFungibleToken.selector),
            abi.encode(int256(0), address(0x9999)) // SUCCESS and token address
        );

        // Mock associateToken calls (two calls in constructor)
        vm.mockCall(
            hederaTokenServiceAddress,
            abi.encodeWithSelector(IHederaTokenService.associateToken.selector),
            abi.encode(int256(0)) // SUCCESS
        );

        // First deployment
        address firstExchangeAddr =
            factory.deployExchange{value: 20 ether}("TestCompany", "TCO", INITIAL_SUPPLY, mockUsdtId, treasuryWallet);
        console.log("First exchange deployed at:", firstExchangeAddr);

        // Second deployment should revert
        vm.expectRevert("SME already has a contract");
        factory.deployExchange{value: 20 ether}("TestCompany", "TCO", INITIAL_SUPPLY, mockUsdtId, treasuryWallet);
        console.log("Second deployment attempted and reverted as expected");

        vm.stopPrank();
    }
}
