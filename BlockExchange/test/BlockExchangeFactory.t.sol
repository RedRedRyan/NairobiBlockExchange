// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/BlockExchangeFactory.sol";

contract BlockExchangeFactoryTest is Test {
    BlockExchangeFactory factory;
    address owner = address(1);

    function setUp() public {
        vm.prank(owner);
        factory = new BlockExchangeFactory();
    }

    function testInitialState() public {
        assertEq(factory.getDeployedExchangesCount(), 0);
        assertEq(factory.owner(), owner);
    }
}
