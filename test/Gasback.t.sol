// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {Gasback} from "../src/Gasback.sol";

contract GasbackTest is SoladyTest {
    Gasback public gasback;

    function setUp() public {
        gasback = new Gasback();
        vm.deal(address(gasback), 2 ** 160);
    }

    function testConvertGasback(uint256 baseFee, uint256 gasToBurn) public {
        baseFee = _bound(baseFee, 0, 2 ** 20 - 1);
        gasToBurn = _bound(gasToBurn, 0, 2 ** 20 - 1);
        address pranker = address(111);
        assertEq(pranker.balance, 0);
        vm.fee(baseFee);
        vm.prank(pranker);
        (bool success,) = address(gasback).call(abi.encode(gasToBurn));
        assertTrue(success);
        assertEq(pranker.balance, gasToBurn * baseFee * 0.9 ether / 1 ether);
    }

    function testConvertGasback() public {
        testConvertGasback(100, 333);
    }
}
