// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {FeeVaultSplitter} from "../src/FeeVaultSplitter.sol";
import {Gasback} from "../src/Gasback.sol";

contract MockBaseFeeVault {
    address public recipient;
    bool public shouldRevert;

    constructor(address recipient_) payable {
        recipient = recipient_;
    }

    function setShouldRevert(bool value) public {
        shouldRevert = value;
    }

    function withdraw() public {
        require(!shouldRevert);
        (bool success,) = recipient.call{value: address(this).balance}("");
        require(success);
    }

    receive() external payable {}
}

contract GasbackTest is SoladyTest {
    address internal constant SYSTEM = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;

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
        assertEq(pranker.balance, _ethToGive(gasToBurn, baseFee));
    }

    function testConvertGasback() public {
        testConvertGasback(100, 333);
    }

    function testConvertGasbackMaxBaseFee() public {
        uint256 newMaxBaseFee = 42;
        vm.prank(SYSTEM);
        gasback.setGasbackMaxBaseFee(newMaxBaseFee);
        vm.fee(newMaxBaseFee + 1);

        uint256 gasToBurn = 333;

        address pranker = address(111);
        assertEq(pranker.balance, 0);
        vm.prank(pranker);
        (bool success,) = address(gasback).call(abi.encode(gasToBurn));
        assertTrue(success);
        assertEq(pranker.balance, 0);
    }

    function testConvertGasbackCodelessBaseFeeVaultPassesThrough() public {
        vm.deal(address(gasback), 0);
        vm.prank(SYSTEM);
        gasback.setBaseFeeVault(address(42));
        vm.fee(1 gwei);

        address pranker = address(111);
        vm.prank(pranker);
        (bool success,) = address(gasback).call(abi.encode(uint256(1_000_000)));
        assertTrue(success);
        assertEq(pranker.balance, 0);
        assertEq(address(gasback).balance, 0);
    }

    function testConvertGasbackRevertingBaseFeeVaultPassesThrough() public {
        vm.deal(address(gasback), 0);
        MockBaseFeeVault vault = new MockBaseFeeVault(address(gasback));
        vault.setShouldRevert(true);
        uint256 vaultBalance = 1 ether;
        vm.deal(address(vault), vaultBalance);
        vm.prank(SYSTEM);
        gasback.setBaseFeeVault(address(vault));
        vm.fee(1 gwei);

        address pranker = address(111);
        vm.prank(pranker);
        (bool success,) = address(gasback).call(abi.encode(uint256(1_000_000)));
        assertTrue(success);
        assertEq(pranker.balance, 0);
        assertEq(address(gasback).balance, 0);
        assertEq(address(vault).balance, vaultBalance);
    }

    function testConvertGasbackPullsFromDirectRecipientBaseFeeVault() public {
        vm.deal(address(gasback), 0);
        MockBaseFeeVault vault = new MockBaseFeeVault(address(gasback));
        uint256 baseFee = 1 gwei;
        uint256 gasToBurn = 1_000_000;
        uint256 ethToGive = _ethToGive(gasToBurn, baseFee);
        vm.deal(address(vault), ethToGive);
        vm.prank(SYSTEM);
        gasback.setBaseFeeVault(address(vault));
        vm.fee(baseFee);

        address pranker = address(111);
        vm.prank(pranker);
        (bool success,) = address(gasback).call(abi.encode(gasToBurn));
        assertTrue(success);
        assertEq(pranker.balance, ethToGive);
        assertEq(address(gasback).balance, 0);
        assertEq(address(vault).balance, 0);
    }

    function testConvertGasbackPullsFromSplitterRecipientBaseFeeVault() public {
        vm.deal(address(gasback), 0);
        address externalPayee = address(0xBEEF);
        address[] memory payees = new address[](2);
        payees[0] = address(gasback);
        payees[1] = externalPayee;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 80;
        shares[1] = 20;
        FeeVaultSplitter splitter = new FeeVaultSplitter(payees, shares);
        MockBaseFeeVault vault = new MockBaseFeeVault(address(splitter));
        uint256 baseFee = 1 gwei;
        uint256 gasToBurn = 1_000_000;
        uint256 ethToGive = _ethToGive(gasToBurn, baseFee);
        vm.deal(address(vault), ethToGive * 2);
        vm.prank(SYSTEM);
        gasback.setBaseFeeVault(address(vault));
        vm.fee(baseFee);

        address pranker = address(111);
        vm.prank(pranker);
        (bool success,) = address(gasback).call(abi.encode(gasToBurn));
        assertTrue(success);
        assertEq(pranker.balance, ethToGive);
        assertEq(address(vault).balance, 0);
        assertEq(address(splitter).balance, 0);
        assertEq(externalPayee.balance, (ethToGive * 2 * 20) / 100);
        assertEq(address(gasback).balance, (ethToGive * 2 * 80) / 100 - ethToGive);
    }

    function testConvertGasbackRevertsInnerWithdrawWhenSplitterShareInsufficient() public {
        vm.deal(address(gasback), 0);
        address externalPayee = address(0xBEEF);
        address[] memory payees = new address[](2);
        payees[0] = address(gasback);
        payees[1] = externalPayee;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 50;
        shares[1] = 50;
        FeeVaultSplitter splitter = new FeeVaultSplitter(payees, shares);
        MockBaseFeeVault vault = new MockBaseFeeVault(address(splitter));
        uint256 baseFee = 1 gwei;
        uint256 gasToBurn = 1_000_000;
        uint256 ethToGive = _ethToGive(gasToBurn, baseFee);
        vm.deal(address(vault), ethToGive);
        vm.prank(SYSTEM);
        gasback.setBaseFeeVault(address(vault));
        vm.fee(baseFee);

        address pranker = address(111);
        vm.prank(pranker);
        (bool success,) = address(gasback).call(abi.encode(gasToBurn));
        assertTrue(success);
        assertEq(pranker.balance, 0);
        assertEq(address(gasback).balance, 0);
        assertEq(address(vault).balance, ethToGive);
        assertEq(address(splitter).balance, 0);
        assertEq(externalPayee.balance, 0);
    }

    function testTriggerBaseFeeVaultWithdrawRevertsWhenCallerIsNotSelf() public {
        vm.expectRevert();
        gasback.triggerBaseFeeVaultWithdraw(0);
    }

    function testFallbackDoesNotAccrue() public {
        vm.fee(100);
        vm.prank(address(111));
        (bool success,) = address(gasback).call(abi.encode(uint256(1000)));
        assertTrue(success);
        assertEq(gasback.accrued(), 0);
    }

    function testWithdrawAccruedRevertsWhenCallerUnauthorized() public {
        address unauthorized = address(0xBAD);
        assertFalse(gasback.isAuthorizedAccrualWithdrawer(unauthorized));
        vm.prank(unauthorized);
        vm.expectRevert();
        gasback.withdrawAccrued(address(0xCAFE), 0);

        assertEq(gasback.accrued(), 0);
    }

    function testWithdrawReconcilesAccruedDownToBalance() public {
        uint256 accruedAmount = 1 ether;
        _setAccrued(accruedAmount);

        vm.deal(address(gasback), accruedAmount);
        vm.prank(SYSTEM);
        assertTrue(gasback.withdraw(address(0xCAFE), accruedAmount / 4));

        uint256 remaining = accruedAmount - accruedAmount / 4;
        assertEq(gasback.accrued(), remaining);
        assertEq(address(gasback).balance, remaining);
    }

    function testWithdrawLeavesAccruedWhenBufferCovers() public {
        uint256 accruedAmount = 1 ether;
        _setAccrued(accruedAmount);

        vm.deal(address(gasback), accruedAmount * 10);
        vm.prank(SYSTEM);
        assertTrue(gasback.withdraw(address(0xCAFE), accruedAmount));

        assertEq(gasback.accrued(), accruedAmount);
        assertEq(address(gasback).balance, accruedAmount * 9);
    }

    function testSetGasbackRatioNumeratorRevertsWhenValueAboveDenominator() public {
        uint256 value = gasback.GASBACK_RATIO_DENOMINATOR() + 1;
        vm.prank(SYSTEM);
        vm.expectRevert();
        gasback.setGasbackRatioNumerator(value);
    }

    function testSetGasbackRatioNumeratorAcceptsScriptValue() public {
        uint256 value = 0.9 ether;
        vm.prank(SYSTEM);
        assertTrue(gasback.setGasbackRatioNumerator(value));
        assertEq(gasback.gasbackRatioNumerator(), value);
    }

    function _ethToGive(uint256 gasToBurn, uint256 baseFee) internal view returns (uint256) {
        return (gasToBurn * baseFee * gasback.gasbackRatioNumerator())
            / gasback.GASBACK_RATIO_DENOMINATOR();
    }

    function _setAccrued(uint256 amount) internal {
        vm.store(address(gasback), _accruedSlot(), bytes32(amount));
        assertEq(gasback.accrued(), amount);
    }

    function _accruedSlot() internal pure returns (bytes32) {
        return bytes32(uint256(uint72(bytes9(keccak256("GASBACK_STORAGE")))) + 3);
    }
}
