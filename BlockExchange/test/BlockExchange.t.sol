// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/BlockExchange.sol";

contract BlockExchangeTest is Test {
    BlockExchange public smeToken;
    address public owner;
    address public investor;
    address public treasuryWallet;
    address public mockUsdtTokenId; // Mock USDT token ID

    // Initial supply for the security token (6 decimals)
    uint256 constant INITIAL_SUPPLY = 10000 * 10 ** 6; // 10,000 tokens
    uint256 constant INITIAL_USDT = 1000000 * 10 ** 6; // 1,000,000 USDT

    function setUp() public {
        owner = address(this);
        investor = address(0x1234);
        treasuryWallet = address(0x5678);
        mockUsdtTokenId = address(0x8888); // Mock address for USDT

        // Mock HTS precompile success for createFungibleToken
        vm.mockCall(
            address(0x167),
            abi.encodeWithSelector(IHederaTokenService.createFungibleToken.selector),
            abi.encode(HederaResponseCodes.SUCCESS, address(0x9999)) // Mock token ID
        );

        // Mock HTS precompile success for associateToken
        vm.mockCall(
            address(0x167),
            abi.encodeWithSelector(IHederaTokenService.associateToken.selector),
            abi.encode(HederaResponseCodes.SUCCESS)
        );

        // Mock HTS precompile success for transferToken
        vm.mockCall(
            address(0x167),
            abi.encodeWithSelector(IHederaTokenService.transferToken.selector),
            abi.encode(HederaResponseCodes.SUCCESS)
        );

        // Deploy the BlockExchange contract with 20 HBAR (mocked value)
        smeToken =
            new BlockExchange{value: 20 ether}("Test Company", "TCO", INITIAL_SUPPLY, mockUsdtTokenId, treasuryWallet);

        // Whitelist the investor (treasuryWallet is already whitelisted by constructor)
        smeToken.whitelistInvestor(investor, true);

        // Set initial USDT balance for treasury
        smeToken.setInitialUsdtBalance(INITIAL_USDT);
    }

    function testTokenCreation() public view {
        assertEq(smeToken.companyName(), "Test Company", "Company name should match");
        assertEq(smeToken.treasuryWallet(), treasuryWallet, "Treasury wallet should match");
        assertEq(
            smeToken.totalTokenSupply(smeToken.hederaTokenServiceTokenId()),
            INITIAL_SUPPLY,
            "Initial supply should match"
        );
        assertEq(
            smeToken.balanceOf(smeToken.hederaTokenServiceTokenId(), treasuryWallet),
            INITIAL_SUPPLY,
            "Treasury should have initial supply"
        );
    }

    function testWhitelistInvestor() public view {
        assertEq(smeToken.isWhitelisted(investor), true, "Investor should be whitelisted");
        assertEq(smeToken.isWhitelisted(treasuryWallet), true, "Treasury should be whitelisted by default");
    }

    function testDistributeDividends() public {
        uint256 amount = 1000 * 10 ** 6; // 1000 USDT
        smeToken.distributeDividends(amount);
        assertEq(
            smeToken.totalDividendsDistributed(),
            amount,
            "Total dividends distributed should match the distributed amount"
        );
    }

    function testClaimDividends() public {
        uint256 dividendAmount = 1000 * 10 ** 6; // 1000 USDT to distribute

        // Simulate investor holding 10% of total supply
        uint256 investorBalance = INITIAL_SUPPLY / 10; // 1000 tokens
        smeToken.transferTokens(smeToken.hederaTokenServiceTokenId(), treasuryWallet, investor, investorBalance);

        // Distribute dividends
        smeToken.distributeDividends(dividendAmount);

        // Calculate expected claimable amount (10% of dividends)
        uint256 expectedClaimable = (dividendAmount * investorBalance) / INITIAL_SUPPLY;

        // Claim dividends as investor
        vm.prank(investor);
        smeToken.claimDividends();

        // Check investor's USDT balance
        assertEq(
            smeToken.balanceOf(mockUsdtTokenId, investor),
            expectedClaimable,
            "Investor should have claimed the correct USDT amount"
        );

        // Check treasury USDT balance decreased
        assertEq(
            smeToken.balanceOf(mockUsdtTokenId, treasuryWallet),
            INITIAL_USDT - expectedClaimable,
            "Treasury USDT balance should decrease by claimed amount"
        );
    }

    function testCastVote() public {
        uint256 votes = 500 * 10 ** 6; // 500 tokens worth of votes

        // Simulate investor holding some tokens
        smeToken.transferTokens(smeToken.hederaTokenServiceTokenId(), treasuryWallet, investor, votes);

        // Cast votes as investor
        vm.prank(investor);
        smeToken.castVote(votes);

        assertEq(smeToken.governanceVotes(investor), votes, "Investor governance votes should match the cast amount");
    }

    function testInitialBalances() public view {
        assertEq(
            smeToken.balanceOf(smeToken.hederaTokenServiceTokenId(), treasuryWallet),
            INITIAL_SUPPLY,
            "Treasury should start with initial security token supply"
        );
        assertEq(
            smeToken.balanceOf(mockUsdtTokenId, treasuryWallet),
            INITIAL_USDT,
            "Treasury should start with initial USDT balance"
        );
        assertEq(
            smeToken.totalTokenSupply(smeToken.hederaTokenServiceTokenId()),
            INITIAL_SUPPLY,
            "Total supply of security token should match initial supply"
        );
    }
}
