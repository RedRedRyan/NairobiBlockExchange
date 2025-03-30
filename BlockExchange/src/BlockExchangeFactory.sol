// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BlockExchange.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BlockExchangeFactory is Ownable {
    address[] public deployedExchanges;
    mapping(string => address) public smeExchanges;

    event ExchangeDeployed(address indexed owner, address indexed exchangeAddress, string companyName);

    constructor() Ownable(msg.sender) {}

    function deployExchange(
        string memory _companyName,
        string memory _tokenSymbol,
        uint256 _initialSecurityTokenSupply,
        address _usdtTokenId,
        address _treasuryWallet
    ) external payable onlyOwner returns (address) {
        require(smeExchanges[_companyName] == address(0), "SME already has a contract");

        BlockExchange newExchange = new BlockExchange{value: msg.value}(
            _companyName, _tokenSymbol, _initialSecurityTokenSupply, _usdtTokenId, _treasuryWallet
        );

        newExchange.transferOwnership(msg.sender);

        deployedExchanges.push(address(newExchange));
        smeExchanges[_companyName] = address(newExchange);

        emit ExchangeDeployed(msg.sender, address(newExchange), _companyName);
        return address(newExchange);
    }

    function getDeployedExchangesCount() external view returns (uint256) {
        return deployedExchanges.length;
    }

    function getDeployedExchanges() external view returns (address[] memory) {
        return deployedExchanges;
    }

    function getSMEContract(string memory _companyName) external view returns (address) {
        return smeExchanges[_companyName];
    }
}
