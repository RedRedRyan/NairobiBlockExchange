// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/BlockExchange.sol";

contract BlockExchangeTest is Test {
    BlockExchange public smeToken;
    address public owner;
    address public investor;
    address public treasuryWallet;
    address public mockHtsTokenId; // Mock HTS token ID
    address public mockUsdtTokenId; // Mock USDT token ID

    // Initial supply for the security token
    uint256 constant INITIAL_SUPPLY = 10000 * 10 ** 18; // 10,000 tokens
    uint256 constant INITIAL_USDT = 1000000 * 10 ** 18; // 1,000,000 USDT

    function setUp() public {
        owner = address(this);
        investor = address(0x1234);
        treasuryWallet = address(0x5678);
        mockHtsTokenId = address(0x9999); // Mock address for HTS security token
        mockUsdtTokenId = address(0x8888); // Mock address for USDT

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

        // Deploy the BlockExchange contract
        smeToken = new BlockExchange(
            "Test Company",
            mockHtsTokenId,
            mockUsdtTokenId,
            treasuryWallet,
            INITIAL_SUPPLY
        );

        // Whitelist the investor
        smeToken.whitelistInvestor(investor, true);

        // Set initial USDT balance for treasury (simulating HTS transfer)
        smeToken.setInitialUsdtBalance(INITIAL_USDT);
    }

    function testWhitelistInvestor() public {
        assertEq(smeToken.isWhitelisted(investor), true, "Investor should be whitelisted");
    }

    function testDistributeDividends() public {
        uint256 amount = 1000 * 10 ** 18; // 1000 USDT

        // Distribute dividends
        smeToken.distributeDividends(amount);

        assertEq(
            smeToken.totalDividendsDistributed(),
            amount,
            "Total dividends distributed should match the distributed amount"
        );
    }

    function testClaimDividends() public {
        uint256 dividendAmount = 1000 * 10 ** 18; // 1000 USDT to distribute

        // Simulate investor holding 10% of total supply
        uint256 investorBalance = INITIAL_SUPPLY / 10; // 1000 tokens
        smeToken.transferTokens(mockHtsTokenId, treasuryWallet, investor, investorBalance);

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
        uint256 votes = 500 * 10 ** 18; // 500 tokens worth of votes

        // Simulate investor holding some tokens
        smeToken.transferTokens(mockHtsTokenId, treasuryWallet, investor, votes);

        // Cast votes as investor
        vm.prank(investor);
        smeToken.castVote(votes);

        assertEq(
            smeToken.governanceVotes(investor),
            votes,
            "Investor governance votes should match the cast amount"
        );
    }

    // Helper function to simulate HTS balance checks (since we’re not on Hedera)
    function testInitialBalances() public {
        assertEq(
            smeToken.balanceOf(mockHtsTokenId, treasuryWallet),
            INITIAL_SUPPLY,
            "Treasury should start with initial security token supply"
        );
        assertEq(
            smeToken.balanceOf(mockUsdtTokenId, treasuryWallet),
            INITIAL_USDT,
            "Treasury should start with initial USDT balance"
        );
        assertEq(
            smeToken.totalTokenSupply(mockHtsTokenId),
            INITIAL_SUPPLY,
            "Total supply of security token should match initial supply"
        );
    }
}