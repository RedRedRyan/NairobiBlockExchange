// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/BlockExchange.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract BlockExchangeTest is Test {
    SMESecurityToken public smeToken;
    address public owner;
    address public investor;
    address public treasuryWallet;
    MockERC20 public mockUSDT;

    function setUp() public {
        owner = address(this);
        investor = address(0x1234);
        treasuryWallet = address(0x5678);

        // Deploy a mock USDT token with minting capability
        mockUSDT = new MockERC20("Mock USDT", "USDT");
        mockUSDT.mint(treasuryWallet, 1000000 * 10 ** 18); // Mint 1,000,000 USDT

        // Deploy the SMESecurityToken contract (ensure this exists)
        smeToken = new SMESecurityToken(
            "Test Company",
            address(0x9999), // Mock HTS Token ID
            address(mockUSDT),
            treasuryWallet
        );

        // Whitelist the investor
        smeToken.whitelistInvestor(investor, true);
    }

    function testWhitelistInvestor() public {
        assertEq(smeToken.isWhitelisted(investor), true);
    }

    function testDistributeDividends() public {
        uint256 amount = 1000 * 10 ** 18;
        mockUSDT.mint(address(this), amount);
        mockUSDT.approve(address(smeToken), amount);

        smeToken.distributeDividends(amount);

        assertEq(smeToken.totalDividendsDistributed(), amount);
    }

    function testClaimDividends() public {
        uint256 amount = 1000 * 10 ** 18;
        mockUSDT.mint(address(this), amount);
        mockUSDT.approve(address(smeToken), amount);

        smeToken.distributeDividends(amount);

        // Simulate investor holding 10% of total supply
        uint256 totalSupply = 10000 * 10 ** 18;
        uint256 investorBalance = totalSupply / 10; // 1,000 tokens

        vm.deal(investor, investorBalance);

        uint256 claimableAmount = (amount * investorBalance) / totalSupply;

        vm.prank(investor);
        smeToken.claimDividends();

        assertEq(mockUSDT.balanceOf(investor), claimableAmount);
    }

    function testCastVote() public {
        uint256 votes = 500;

        vm.prank(investor);
        smeToken.castVote(votes);

        assertEq(smeToken.governanceVotes(investor), votes);
    }
}
