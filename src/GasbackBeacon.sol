// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

// solc = 0.8.28, evm = london, optimization = 1000.
contract GasbackBeacon {
    fallback() external payable {
        assembly {
            mstore(0x40, sload(returndatasize()))
            if xor(caller(), 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE) { return(0x40, 0x20) }
            sstore(returndatasize(), calldataload(returndatasize()))
        }
    }
}
