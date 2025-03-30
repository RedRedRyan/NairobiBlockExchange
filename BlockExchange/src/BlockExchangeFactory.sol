// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BlockExchange.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BlockExchangeFactory is Ownable {
    // Array to store addresses of deployed BlockExchange instances
    address[] public deployedExchanges;

    // Mapping from SME name to deployed contract address
    mapping(string => address) public smeExchanges;

    // Event emitted each time a new BlockExchange is deployed
    event ExchangeDeployed(address indexed owner, address indexed exchangeAddress, string companyName);

    /**
     * @dev Constructor that passes the initialOwner to the Ownable base contract
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Deploys a new BlockExchange contract instance.
     * @param _companyName Name of the SME company.
     * @param _hederaTokenServiceTokenId The Hedera Token ID representing the security token.
     * @param _usdtTokenId The Hedera Token ID of USDT used for dividend payouts.
     * @param _treasuryWallet Address managing the treasury for dividend distributions.
     * @param _initialSecurityTokenSupply Initial supply of security tokens to allocate to treasury.
     * @return The address of the newly deployed BlockExchange contract.
     *
     * Note: The factory deploys the BlockExchange contract and transfers ownership
     *       to the caller (the SME admin).
     */
    function deployExchange(
        string memory _companyName,
        address _hederaTokenServiceTokenId,
        address _usdtTokenId,
        address _treasuryWallet,
        uint256 _initialSecurityTokenSupply
    ) external onlyOwner returns (address) {
        require(smeExchanges[_companyName] == address(0), "SME already has a contract");

        // Deploy a new BlockExchange contract with all required parameters
        BlockExchange newExchange = new BlockExchange(
            _companyName,
            _hederaTokenServiceTokenId,
            _usdtTokenId,
            _treasuryWallet,
            _initialSecurityTokenSupply
        );

        // Transfer ownership of the new exchange to the caller
        newExchange.transferOwnership(msg.sender);

        // Save the deployed contract details
        deployedExchanges.push(address(newExchange));
        smeExchanges[_companyName] = address(newExchange);

        // Emit the deployment event
        emit ExchangeDeployed(msg.sender, address(newExchange), _companyName);

        return address(newExchange);
    }

    /**
     * @dev Returns the number of deployed exchanges.
     * @return The count of deployed BlockExchange contracts.
     */
    function getDeployedExchangesCount() external view returns (uint256) {
        return deployedExchanges.length;
    }

    /**
     * @dev Returns the list of all deployed exchange contract addresses.
     * @return An array of deployed BlockExchange addresses.
     */
    function getDeployedExchanges() external view returns (address[] memory) {
        return deployedExchanges;
    }

    /**
     * @dev Retrieves the deployed contract address for a specific SME.
     * @param _companyName The name of the SME.
     * @return The address of the BlockExchange contract for the SME.
     */
    function getSMEContract(string memory _companyName) external view returns (address) {
        return smeExchanges[_companyName];
    }
}