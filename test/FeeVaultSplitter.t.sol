// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {FeeVaultSplitter} from "../src/FeeVaultSplitter.sol";

contract RejectingPayee {
    receive() external payable {
        revert("I reject ETH");
    }
}

contract ReentrantPayee {
    FeeVaultSplitter public splitter;
    bool public didReenter;

    function setSplitter(FeeVaultSplitter splitter_) external {
        splitter = splitter_;
    }

    receive() external payable {
        if (!didReenter) {
            didReenter = true;
            (bool success,) = address(splitter).call{value: 1}("");
            require(success, "reenter failed");
        }
    }
}

contract FeeVaultSplitterTest is SoladyTest {
    event PaymentFailed(address to, uint256 amount, bytes reason);
    event PaymentReceived(address from, uint256 amount);
    event PaymentReleased(address to, uint256 amount);

    FeeVaultSplitter public splitter;

    /// @dev fuzz helpers

    // Struct to reduce stack depth in fuzz tests
    struct FuzzTestState {
        address[] fuzzPayees;
        uint256[] fuzzShares;
        uint256[] initialBalances;
        uint256 totalSharesSum;
        uint256 cumulativeTotalPaid;
        FeeVaultSplitter fuzzSplitter;
    }

    function _deployDefaultSplitter() internal returns (FeeVaultSplitter) {
        return new FeeVaultSplitter(payees, shares);
    }

    function _addressSendValueRevertReason() internal pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "Error(string)", "Address: unable to send value, recipient may have reverted"
        );
    }

    function _createFuzzTestState(uint8 numPayees, uint256 addrOffset)
        internal
        returns (FuzzTestState memory state)
    {
        state.fuzzPayees = new address[](numPayees);
        state.fuzzShares = new uint256[](numPayees);
        state.initialBalances = new uint256[](numPayees);

        for (uint256 i = 0; i < numPayees; i++) {
            state.fuzzPayees[i] = vm.addr(i + addrOffset);
            state.fuzzShares[i] = (i % 100) + 1;
            state.totalSharesSum += state.fuzzShares[i];
        }

        state.fuzzSplitter = new FeeVaultSplitter(state.fuzzPayees, state.fuzzShares);

        for (uint256 i = 0; i < numPayees; i++) {
            state.initialBalances[i] = state.fuzzPayees[i].balance;
        }
    }

    function _sendPaymentAndUpdateState(FuzzTestState memory state, uint256 paymentAmount)
        internal
    {
        state.cumulativeTotalPaid += paymentAmount;
        vm.deal(address(this), paymentAmount);
        (bool success,) = address(state.fuzzSplitter).call{value: paymentAmount}("");
        assertTrue(success);
    }

    function _verifyPayeeBalances(FuzzTestState memory state, uint8 numPayees) internal view {
        for (uint256 i = 0; i < numPayees; i++) {
            uint256 actualReceived = state.fuzzPayees[i].balance - state.initialBalances[i];
            uint256 expectedReceived =
                (state.cumulativeTotalPaid * state.fuzzShares[i]) / state.totalSharesSum;
            assertEq(actualReceived, expectedReceived);
        }
    }

    address[] public payees = new address[](3);
    uint256[] public shares = new uint256[](3);

    uint256 private _deployerKey = 1;

    uint256 private _payee1Key = 2;
    uint256 private _payee2Key = 3;
    uint256 private _payee3Key = 4;

    address private deployer = vm.addr(_deployerKey);

    address private payee1 = vm.addr(_payee1Key);
    address private payee2 = vm.addr(_payee2Key);
    address private payee3 = vm.addr(_payee3Key);

    uint256 public shares1 = 48;
    uint256 public shares2 = 42;
    uint256 public shares3 = 10;

    function setUp() public {
        payees[0] = payee1;
        payees[1] = payee2;
        payees[2] = payee3;

        shares[0] = shares1;
        shares[1] = shares2;
        shares[2] = shares3;

        splitter = new FeeVaultSplitter(payees, shares);
    }

    function test_read_public_variables() public {
        assertEq(splitter.externalPayees(0), payee1);
        assertEq(splitter.externalPayees(1), payee2);
        assertEq(splitter.externalPayees(2), payee3);
        assertEq(splitter.totalShares(), 100);
        assertEq(splitter.shares(payee1), shares1);
        assertEq(splitter.shares(payee2), shares2);
        assertEq(splitter.shares(payee3), shares3);
        assertEq(splitter.payee(0), payee1);
        assertEq(splitter.payee(1), payee2);
        assertEq(splitter.payee(2), payee3);
    }

    function test_externalPayees_length_matches_payee_count() public {
        splitter = _deployDefaultSplitter();

        // Regression guard for the constructor double-fill bug: externalPayees must have exactly
        // one entry per payee (length N), not 2N with leading zero-address slots.
        assertEq(splitter.externalPayees(0), payee1);
        assertEq(splitter.externalPayees(1), payee2);
        assertEq(splitter.externalPayees(2), payee3);
        vm.expectRevert(); // index 3 is out of bounds => length is exactly 3
        splitter.externalPayees(3);
    }

    function test_balances_after_payment() public {
        uint256 paymentAmount = 10 ether;

        // Record balances before
        uint256 balanceBefore1 = payee1.balance;
        uint256 balanceBefore2 = payee2.balance;
        uint256 balanceBefore3 = payee3.balance;

        // Send ETH to the splitter (triggers receive() which releases to all payees)
        vm.deal(address(this), paymentAmount);
        (bool success,) = address(splitter).call{value: paymentAmount}("");
        assertTrue(success, "Payment to splitter failed");

        // Record balances after
        uint256 balanceAfter1 = payee1.balance;
        uint256 balanceAfter2 = payee2.balance;
        uint256 balanceAfter3 = payee3.balance;

        // Calculate expected amounts based on shares
        uint256 totalShares = splitter.totalShares();
        uint256 expectedPayment1 = (paymentAmount * shares1) / totalShares;
        uint256 expectedPayment2 = (paymentAmount * shares2) / totalShares;
        uint256 expectedPayment3 = (paymentAmount * shares3) / totalShares;

        // Verify balance changes match expected payments
        assertEq(
            balanceAfter1 - balanceBefore1, expectedPayment1, "Payee1 received incorrect amount"
        );
        assertEq(
            balanceAfter2 - balanceBefore2, expectedPayment2, "Payee2 received incorrect amount"
        );
        assertEq(
            balanceAfter3 - balanceBefore3, expectedPayment3, "Payee3 received incorrect amount"
        );

        // Verify the exact amounts (48%, 42%, 10% of 10 ether)
        assertEq(balanceAfter1 - balanceBefore1, 4.8 ether, "Payee1 should receive 4.8 ether");
        assertEq(balanceAfter2 - balanceBefore2, 4.2 ether, "Payee2 should receive 4.2 ether");
        assertEq(balanceAfter3 - balanceBefore3, 1 ether, "Payee3 should receive 1 ether");
        assertEq(address(splitter).balance, 0);
    }

    function test_receive_emits_payment_received() public {
        splitter = _deployDefaultSplitter();

        uint256 paymentAmount = 10 ether;

        vm.deal(address(this), paymentAmount);
        // receive() emits PaymentReceived first, then PaymentReleased per payee during _distribute.
        vm.expectEmit(true, true, true, true, address(splitter));
        emit PaymentReceived(address(this), paymentAmount);
        vm.expectEmit(true, true, true, true, address(splitter));
        emit PaymentReleased(payee1, 4.8 ether);
        vm.expectEmit(true, true, true, true, address(splitter));
        emit PaymentReleased(payee2, 4.2 ether);
        vm.expectEmit(true, true, true, true, address(splitter));
        emit PaymentReleased(payee3, 1 ether);

        (bool success,) = address(splitter).call{value: paymentAmount}("");
        assertTrue(success, "Payment to splitter failed");
    }

    function test_receive_allows_small_payment() public {
        uint256 paymentAmount = 1 wei;

        uint256 balanceBefore1 = payee1.balance;
        uint256 balanceBefore2 = payee2.balance;
        uint256 balanceBefore3 = payee3.balance;

        vm.deal(address(this), paymentAmount);
        (bool success,) = address(splitter).call{value: paymentAmount}("");
        assertTrue(success, "Payment to splitter failed");

        assertEq(payee1.balance, balanceBefore1);
        assertEq(payee2.balance, balanceBefore2);
        assertEq(payee3.balance, balanceBefore3);
        assertEq(address(splitter).balance, paymentAmount);
    }

    function test_receive_skips_failed_payee_emits_failure() public {
        RejectingPayee rejecter = new RejectingPayee();

        address[] memory localPayees = new address[](2);
        localPayees[0] = address(rejecter);
        localPayees[1] = payee1;

        uint256[] memory localShares = new uint256[](2);
        localShares[0] = 50;
        localShares[1] = 50;

        FeeVaultSplitter localSplitter = new FeeVaultSplitter(localPayees, localShares);

        uint256 paymentAmount = 1 ether;
        uint256 payee1Before = payee1.balance;

        vm.deal(address(this), paymentAmount);
        vm.expectEmit(true, true, true, true);
        emit PaymentFailed(address(rejecter), 0.5 ether, _addressSendValueRevertReason());

        (bool success,) = address(localSplitter).call{value: paymentAmount}("");
        assertTrue(success, "Payment to splitter failed");

        assertEq(payee1.balance - payee1Before, 0.5 ether);
        assertEq(address(localSplitter).balance, 0.5 ether);
    }

    function test_distribute_noop_start_gte_end() public {
        uint256 paymentAmount = 1 ether;

        uint256 balanceBefore1 = payee1.balance;
        uint256 balanceBefore2 = payee2.balance;
        uint256 balanceBefore3 = payee3.balance;

        vm.deal(address(splitter), paymentAmount);
        splitter.distribute(2, 2);

        assertEq(payee1.balance, balanceBefore1);
        assertEq(payee2.balance, balanceBefore2);
        assertEq(payee3.balance, balanceBefore3);
        assertEq(address(splitter).balance, paymentAmount);
    }

    function test_distribute_clamps_end_to_payees_length() public {
        uint256 paymentAmount = 1 ether;

        uint256 balanceBefore1 = payee1.balance;
        uint256 balanceBefore2 = payee2.balance;
        uint256 balanceBefore3 = payee3.balance;

        vm.deal(address(splitter), paymentAmount);
        splitter.distribute(0, 10);

        uint256 totalShares = splitter.totalShares();
        uint256 expectedPayment1 = (paymentAmount * shares1) / totalShares;
        uint256 expectedPayment2 = (paymentAmount * shares2) / totalShares;
        uint256 expectedPayment3 = (paymentAmount * shares3) / totalShares;

        assertEq(payee1.balance - balanceBefore1, expectedPayment1);
        assertEq(payee2.balance - balanceBefore2, expectedPayment2);
        assertEq(payee3.balance - balanceBefore3, expectedPayment3);
        assertEq(address(splitter).balance, 0);
    }

    function test_distribute_invariants_with_failed_payee() public {
        RejectingPayee rejecter = new RejectingPayee();

        address[] memory localPayees = new address[](2);
        localPayees[0] = address(rejecter);
        localPayees[1] = payee1;

        uint256[] memory localShares = new uint256[](2);
        localShares[0] = 50;
        localShares[1] = 50;

        FeeVaultSplitter localSplitter = new FeeVaultSplitter(localPayees, localShares);

        uint256 paymentAmount = 1 ether;
        uint256 payee1Before = payee1.balance;

        vm.deal(address(localSplitter), paymentAmount);
        localSplitter.distribute(0, 2);

        assertEq(payee1.balance - payee1Before, 0.5 ether);
        assertEq(localSplitter.released(payee1), 0.5 ether);
        assertEq(localSplitter.released(address(rejecter)), 0);
        assertEq(localSplitter.totalReleased(), 0.5 ether);
        assertEq(address(localSplitter).balance, 0.5 ether);
        assertEq(localSplitter.releasable(address(rejecter)), 0.5 ether);
        assertEq(localSplitter.releasable(payee1), 0);
    }

    function testFuzz_balances_after_payment(uint8 numPayees, uint256 paymentAmount) public {
        numPayees = uint8(bound(numPayees, 1, 50));
        paymentAmount = bound(paymentAmount, 1 ether, 1000 ether);

        FuzzTestState memory state = _createFuzzTestState(numPayees, 100);

        _sendPaymentAndUpdateState(state, paymentAmount);
        _verifyPayeeBalances(state, numPayees);

        assertLe(address(state.fuzzSplitter).balance, uint256(numPayees));
    }

    function testFuzz_balances_after_multiple_payments(
        uint8 numPayees,
        uint256[9] memory paymentAmounts
    ) public {
        numPayees = uint8(bound(numPayees, 1, 50));

        FuzzTestState memory state = _createFuzzTestState(numPayees, 200);

        for (uint256 p = 0; p < 9; p++) {
            uint256 paymentAmount = bound(paymentAmounts[p], 0.1 ether, 10 ether);
            _sendPaymentAndUpdateState(state, paymentAmount);
            _verifyPayeeBalances(state, numPayees);
        }

        assertLe(address(state.fuzzSplitter).balance, uint256(numPayees) * 9);
    }

    /// @dev deployment revert tests

    function test_revert_deploy_empty_payees() public {
        address[] memory emptyPayees = new address[](0);
        uint256[] memory emptyShares = new uint256[](0);

        vm.expectRevert("PaymentSplitter: no payees");
        new FeeVaultSplitter(emptyPayees, emptyShares);
    }

    function test_revert_deploy_length_mismatch_more_payees() public {
        address[] memory morePayees = new address[](3);
        morePayees[0] = payee1;
        morePayees[1] = payee2;
        morePayees[2] = payee3;

        uint256[] memory fewerShares = new uint256[](2);
        fewerShares[0] = 50;
        fewerShares[1] = 50;

        vm.expectRevert("PaymentSplitter: payees and shares length mismatch");
        new FeeVaultSplitter(morePayees, fewerShares);
    }

    function test_revert_deploy_length_mismatch_more_shares() public {
        address[] memory fewerPayees = new address[](2);
        fewerPayees[0] = payee1;
        fewerPayees[1] = payee2;

        uint256[] memory moreShares = new uint256[](3);
        moreShares[0] = 40;
        moreShares[1] = 40;
        moreShares[2] = 20;

        vm.expectRevert("PaymentSplitter: payees and shares length mismatch");
        new FeeVaultSplitter(fewerPayees, moreShares);
    }

    function test_revert_deploy_zero_address_payee() public {
        address[] memory badPayees = new address[](2);
        badPayees[0] = payee1;
        badPayees[1] = address(0);

        uint256[] memory validShares = new uint256[](2);
        validShares[0] = 50;
        validShares[1] = 50;

        vm.expectRevert("PaymentSplitter: account is the zero address");
        new FeeVaultSplitter(badPayees, validShares);
    }

    function test_revert_deploy_zero_shares() public {
        address[] memory validPayees = new address[](2);
        validPayees[0] = payee1;
        validPayees[1] = payee2;

        uint256[] memory badShares = new uint256[](2);
        badShares[0] = 100;
        badShares[1] = 0;

        vm.expectRevert("PaymentSplitter: shares are 0");
        new FeeVaultSplitter(validPayees, badShares);
    }

    function test_revert_deploy_duplicate_payee() public {
        address[] memory duplicatePayees = new address[](3);
        duplicatePayees[0] = payee1;
        duplicatePayees[1] = payee2;
        duplicatePayees[2] = payee1; // duplicate

        uint256[] memory validShares = new uint256[](3);
        validShares[0] = 40;
        validShares[1] = 40;
        validShares[2] = 20;

        vm.expectRevert("PaymentSplitter: account already has shares");
        new FeeVaultSplitter(duplicatePayees, validShares);
    }

    function test_revert_release_account_has_no_shares() public {
        address nonPayee = vm.addr(999);

        vm.expectRevert("PaymentSplitter: account has no shares");
        splitter.release(payable(nonPayee));
    }

    function test_revert_release_account_not_due_payment() public {
        // No ETH sent to splitter, so payee1 has 0 releasable
        vm.expectRevert("PaymentSplitter: account is not due payment");
        splitter.release(payable(payee1));
    }

    function test_revert_release_insufficient_balance() public {
        // Manipulate storage to create an impossible state where totalReleased > 0 but balance = 0
        // _totalReleased is at storage slot 1
        vm.store(address(splitter), bytes32(uint256(1)), bytes32(uint256(100 ether)));

        // Now releasable(payee1) = (0 + 100 ether) * 48 / 100 - 0 = 48 ether
        // But balance is 0, so _sendValue will revert
        vm.expectRevert("Address: insufficient balance");
        splitter.release(payable(payee1));
    }

    function test_revert_release_failed_to_send_value() public {
        // Create a contract that rejects ETH
        RejectingPayee rejecter = new RejectingPayee();

        address[] memory rejectorPayees = new address[](1);
        rejectorPayees[0] = address(rejecter);

        uint256[] memory rejectorShares = new uint256[](1);
        rejectorShares[0] = 100;

        FeeVaultSplitter rejectorSplitter = new FeeVaultSplitter(rejectorPayees, rejectorShares);

        // Send ETH to the splitter - it should emit a failure but not revert
        vm.deal(address(this), 1 ether);
        (bool success,) = address(rejectorSplitter).call{value: 1 ether}("");
        assertTrue(success);

        // Direct release should still revert since the payee rejects ETH
        vm.expectRevert("Address: unable to send value, recipient may have reverted");
        rejectorSplitter.release(payable(address(rejecter)));
    }

    function test_receive_reverts_on_reentrant_payee() public {
        ReentrantPayee reentrant = new ReentrantPayee();

        address[] memory localPayees = new address[](2);
        localPayees[0] = address(reentrant);
        localPayees[1] = payee1;

        uint256[] memory localShares = new uint256[](2);
        localShares[0] = 1;
        localShares[1] = 1;

        FeeVaultSplitter localSplitter = new FeeVaultSplitter(localPayees, localShares);
        reentrant.setSplitter(localSplitter);

        uint256 paymentAmount = 1 ether;
        uint256 payee1Before = payee1.balance;

        vm.deal(address(this), paymentAmount);
        vm.expectEmit(true, true, true, true, address(localSplitter));
        emit PaymentFailed(address(reentrant), 0.5 ether, _addressSendValueRevertReason());

        (bool success,) = address(localSplitter).call{value: paymentAmount}("");
        assertTrue(success, "Payment to splitter failed");

        assertEq(address(reentrant).balance, 0);
        assertEq(payee1.balance - payee1Before, 0.5 ether);
        assertEq(localSplitter.released(address(reentrant)), 0);
        assertEq(localSplitter.released(payee1), 0.5 ether);
        assertEq(localSplitter.totalReleased(), 0.5 ether);
        assertEq(address(localSplitter).balance, 0.5 ether);
        assertEq(localSplitter.releasable(address(reentrant)), 0.5 ether);
    }

    function test_release_after_dust_payment() public {
        vm.deal(address(this), 1 wei);
        (bool success,) = address(splitter).call{value: 1 wei}("");
        assertTrue(success, "Payment to splitter failed");

        uint256 payee1Before = payee1.balance;
        vm.deal(address(splitter), 3 wei);

        splitter.release(payable(payee1));

        assertEq(payee1.balance - payee1Before, 1 wei);
        assertEq(splitter.released(payee1), 1 wei);
        assertEq(address(splitter).balance, 2 wei);
    }

    function test_failed_payee_accounting_invariants() public {
        RejectingPayee rejecter = new RejectingPayee();

        address[] memory localPayees = new address[](2);
        localPayees[0] = address(rejecter);
        localPayees[1] = payee1;

        uint256[] memory localShares = new uint256[](2);
        localShares[0] = 50;
        localShares[1] = 50;

        FeeVaultSplitter localSplitter = new FeeVaultSplitter(localPayees, localShares);

        uint256 paymentAmount = 1 ether;
        uint256 payee1Before = payee1.balance;

        vm.deal(address(this), paymentAmount);
        (bool success,) = address(localSplitter).call{value: paymentAmount}("");
        assertTrue(success, "Payment to splitter failed");

        assertEq(payee1.balance - payee1Before, 0.5 ether);
        assertEq(localSplitter.released(payee1), 0.5 ether);
        assertEq(localSplitter.released(address(rejecter)), 0);
        assertEq(localSplitter.totalReleased(), 0.5 ether);
        assertEq(address(localSplitter).balance, 0.5 ether);
        assertEq(localSplitter.releasable(address(rejecter)), 0.5 ether);
        assertEq(localSplitter.releasable(payee1), 0);
    }

    function test_multiple_payments_accounting_is_cumulative() public {
        uint256 balanceBefore1 = payee1.balance;
        uint256 balanceBefore2 = payee2.balance;
        uint256 balanceBefore3 = payee3.balance;

        vm.deal(address(this), 1 ether);
        (bool success1,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success1, "First payment to splitter failed");

        vm.deal(address(this), 2 ether);
        (bool success2,) = address(splitter).call{value: 2 ether}("");
        assertTrue(success2, "Second payment to splitter failed");

        uint256 cumulativePayment = 3 ether;
        uint256 totalShares = splitter.totalShares();
        uint256 expectedPayment1 = (cumulativePayment * shares1) / totalShares;
        uint256 expectedPayment2 = (cumulativePayment * shares2) / totalShares;
        uint256 expectedPayment3 = (cumulativePayment * shares3) / totalShares;

        assertEq(payee1.balance - balanceBefore1, expectedPayment1);
        assertEq(payee2.balance - balanceBefore2, expectedPayment2);
        assertEq(payee3.balance - balanceBefore3, expectedPayment3);
        assertEq(splitter.released(payee1), expectedPayment1);
        assertEq(splitter.released(payee2), expectedPayment2);
        assertEq(splitter.released(payee3), expectedPayment3);
        assertEq(splitter.totalReleased(), cumulativePayment);
        assertEq(address(splitter).balance, 0);
    }
}

