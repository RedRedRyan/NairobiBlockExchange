// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// Simple ERC20 token for testing
contract MockUSDT is ERC20 {
    uint8 private _decimals;
    
    constructor(string memory name, string memory symbol, uint8 decimalsValue, uint256 initialSupply, address treasuryWallet) 
        ERC20(name, symbol) 
    {
        _decimals = decimalsValue;
        _mint(treasuryWallet, initialSupply);
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

contract DeployMockUSDTScript is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasuryWallet = vm.envAddress("TREASURY_WALLET");

        // Initial supply of mock USDT (10 million with 6 decimals)
        uint256 initialSupply = 10_000_000 * 10 ** 6;

        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy a standard ERC20 token instead of using Hedera Token Service
        MockUSDT mockUSDT = new MockUSDT(
            "Mock USDT", 
            "mUSDT", 
            6, // 6 decimals (standard for USDT)
            initialSupply,
            treasuryWallet
        );

        // Log the token address for use in other deployment scripts
        console.log("Mock USDT Token deployed at:", address(mockUSDT));
        console.log("Treasury wallet (holds initial supply):", treasuryWallet);
        console.log("Initial supply:", initialSupply);

        vm.stopBroadcast();
    }
}
