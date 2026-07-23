// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {PaymentSplitter} from "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title FeeVaultSplitter
 * @dev This contract, implements OpenZeppelin's PaymentSplitter, supports splitting Ether payments among a group of accounts.
 *
 * FeeVaultSplitter follows a _push payment_ model. Incoming Ether triggers an attempt to release funds to all payees.
 */
contract FeeVaultSplitter is PaymentSplitter, ReentrancyGuard {
    event PaymentFailed(address to, uint256 amount, bytes reason);

    address[] public externalPayees;

    /**
     * @dev Creates an instance of `PaymentSplitter` where each account in `payees` is assigned the number of shares at
     * the matching position in the `shares` array.
     *
     * All addresses in `payees` must be non-zero. Both arrays must have the same non-zero length, and there must be no
     * duplicates in `payees`.
     */
    constructor(address[] memory payees_, uint256[] memory shares_)
        payable
        PaymentSplitter(payees_, shares_)
    {
        for (uint256 i = 0; i < payees_.length; i++) {
            externalPayees.push(payees_[i]);
        }
    }

    /**
     * @dev The Ether received will be logged with {PaymentReceived} events. Note that these events are not fully
     * reliable: it's possible for a contract to receive Ether without triggering this function. This only affects the
     * reliability of the events, and not the actual splitting of Ether.
     *
     * To learn more about this see the Solidity documentation for
     * https://solidity.readthedocs.io/en/latest/contracts.html#fallback-function[fallback
     * functions].
     *
     * SECURITY / DoS NOTE (push-payment model): this function attempts to release to every payee in `externalPayees`
     * in a single call. Its gas cost therefore scales with the payee count, and a payee whose `receive`/fallback
     * consumes a large amount of gas (rather than cheaply reverting, which is caught and skipped) can push this call
     * out of gas and make it revert. Because the OP base fee vault's `withdraw()` sends fees to this contract
     * (triggering `receive`), such a revert would block that withdrawal and strand base fees in the vault until resolved.
     * Additionally, a malicious payee ordered after the Gasback contract in `payees_` can re-enter the Gasback contract
     * during distribution and use up the ETH just released to it, leaving no ETH for the original caller so their call is skipped.
     * To bound this risk: keep the payee set small and trusted (it is fixed at deployment).
     * If a deposit's auto-distribution is ever blocked, funds are not lost — anyone can call {distribute} with a
     * bounded `[start, end)` slice to release payees in chunks and recover.
     */
    receive() external payable override(PaymentSplitter) nonReentrant {
        emit PaymentReceived(_msgSender(), msg.value);

        _distribute(0, externalPayees.length);
    }

    /**
     * @dev Attempts to release payments for a slice of payees, skipping zero-due payees and emitting failures instead of
     * reverting on send failures.
     */
    function distribute(uint256 start, uint256 end) public nonReentrant {
        _distribute(start, end);
    }

    /**
     * @dev Attempt to pay a slice of payees without reverting the whole call.
     * Skips zero-due accounts and emits failures for accounts that revert on receive.
     */
    function _distribute(uint256 start, uint256 end) private {
        uint256 payeesLength = externalPayees.length;
        if (end > payeesLength) {
            end = payeesLength;
        }
        if (start >= end) {
            return;
        }

        for (uint256 i = start; i < end; i++) {
            address payable account = payable(externalPayees[i]);
            uint256 payment = releasable(account);
            if (payment == 0) {
                continue;
            }

            try this.release(account) {}
            catch (bytes memory reason) {
                emit PaymentFailed(account, payment, reason);
            }
        }
    }
}
