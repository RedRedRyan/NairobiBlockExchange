// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/BlockExchangeFactory.sol";
import "../src/BlockExchange.sol";

contract BlockExchangeFactoryTest is Test {
    BlockExchangeFactory factory;
    address owner = address(1);
    address smeAdmin = address(2);
    address mockTokenId = address(3);
    address mockUsdtId = address(4);
    address treasuryWallet = address(5);

    // Initial supply for the security token
    uint256 constant INITIAL_SUPPLY = 10000 * 10 ** 18; // 10,000 tokens

    function setUp() public {
        vm.startPrank(owner);
        // Mock HTS precompile success for associateToken
        vm.mockCall(
            address(0x167),
            abi.encodeWithSelector(IHederaTokenService.associateToken.selector),
            abi.encode(HederaResponseCodes.SUCCESS)
        );
        // Mock HTS precompile success for transferToken (for later tests if needed)
        vm.mockCall(
            address(0x167),
            abi.encodeWithSelector(IHederaTokenService.transferToken.selector),
            abi.encode(HederaResponseCodes.SUCCESS)
        );
        factory = new BlockExchangeFactory();
        vm.stopPrank();
    }

    function testDeployExchange() public {
        vm.startPrank(owner);
        address exchangeAddr =
            factory.deployExchange("TestCompany", mockTokenId, mockUsdtId, treasuryWallet, INITIAL_SUPPLY);
        vm.stopPrank();

        // Verify exchange was deployed
        assertEq(factory.getDeployedExchangesCount(), 1, "Deployed exchanges count should be 1");
        assertEq(factory.getSMEContract("TestCompany"), exchangeAddr, "SME contract address should match");

        // Verify ownership was transferred
        BlockExchange exchange = BlockExchange(exchangeAddr);
        assertEq(exchange.owner(), owner, "Owner should be the deployer");
    }

    function testCannotDeployDuplicateCompany() public {
        vm.startPrank(owner);
        factory.deployExchange("TestCompany", mockTokenId, mockUsdtId, treasuryWallet, INITIAL_SUPPLY);

        // Try to deploy with same company name
        vm.expectRevert("SME already has a contract");
        factory.deployExchange("TestCompany", mockTokenId, mockUsdtId, treasuryWallet, INITIAL_SUPPLY);
        vm.stopPrank();
    }
}
