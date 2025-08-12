// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

contract GasbackRelay {
    address public immutable gasback;

    constructor(address _gasback) {
        gasback = _gasback;
    }

    receive() external payable {
        if (msg.sender == gasback) return;

        uint256 balanceBefore = address(this).balance;

        uint256 gasToBurn = msg.value;

        (bool gasbackSuccess, ) = gasback.call{value: gasToBurn}(
            abi.encode((gasToBurn))
        );
        if (!gasbackSuccess) return;

        uint256 balanceAfter = address(this).balance;

        assert(balanceAfter > balanceBefore);

        uint256 ethToGive = balanceAfter - balanceBefore;

        assert(gasToBurn > ethToGive);

        (bool sendSuccess, ) = payable(msg.sender).call{value: ethToGive}("");

        if (!sendSuccess) return;
    }
}
