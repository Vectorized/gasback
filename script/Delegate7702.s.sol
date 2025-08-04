// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Script} from "forge-std/Script.sol";
import "../src/Gasback.sol";

contract Delegate7702Script is Script {
    function run() external {
        uint256 privateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        address nicks = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        address gasbackImplementation =
            _predictDeterministicAddress(keccak256(type(Gasback).creationCode), 0, nicks);
        if (gasbackImplementation.code.length == 0) {
            vm.startBroadcast(privateKey);
            gasbackImplementation = address(new Gasback{salt: 0}());
            vm.stopBroadcast();
        }

        address deployer = vm.addr(privateKey);

        vm.signAndAttachDelegation(gasbackImplementation, privateKey);

        vm.startBroadcast(privateKey);
        Gasback(payable(deployer)).noop();
        Gasback(payable(deployer)).setGasbackRatioNumerator(900000000000000000);
        Gasback(payable(deployer)).setGasbackMaxBaseFee(type(uint256).max);
        Gasback(payable(deployer)).setBaseFeeVault(0x4200000000000000000000000000000000000019);
        vm.stopBroadcast();
    }

    /// @dev Returns the address when a contract with initialization code hash,
    /// `hash`, is deployed with `salt`, by `deployer`.
    /// Note: The returned result has dirty upper 96 bits. Please clean if used in assembly.
    function _predictDeterministicAddress(bytes32 hash, bytes32 salt, address deployer)
        internal
        pure
        returns (address predicted)
    {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute and store the bytecode hash.
            mstore8(0x00, 0xff) // Write the prefix.
            mstore(0x35, hash)
            mstore(0x01, shl(96, deployer))
            mstore(0x15, salt)
            predicted := keccak256(0x00, 0x55)
            mstore(0x35, 0) // Restore the overwritten part of the free memory pointer.
        }
    }
}
