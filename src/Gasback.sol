// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.7;

/// @dev A contract that converts a portion of the gas burned into ETH.
/// This contract holds ETH deposited by the sequencer, which will be
/// redistributed to callers.
contract Gasback {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The address authorized to configure the contract.
    address internal constant _SYSTEM_ADDRESS = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;

    /// @dev The denominator of the gasback ratio.
    uint256 public constant GASBACK_RATIO_DENOMINATOR = 1 ether;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The gasback ratio numerator.
    uint256 public gasbackRatioNumerator;

    /// @dev If the basefee exceeds this, this contract becomes a pass through.
    uint256 public gasbackMaxBasefee;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CONSTRUCTOR                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    constructor() payable {
        gasbackRatioNumerator = 0.9 ether;
        gasbackMaxBasefee = type(uint256).max;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*               SYSTEM ADDRESS ONLY FUNCTIONS                */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Withdraws ETH from this contract.
    function withdraw(address to, uint256 amount) public onlySystem {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(call(gas(), to, amount, 0x00, 0x00, 0x00, 0x00)) { revert(0x00, 0x00) }
        }
    }

    /// @dev Sets the numerator for the gasback ratio.
    function setGasbackRatioNumerator(uint256 value) public onlySystem {
        require(value <= GASBACK_RATIO_DENOMINATOR);
        gasbackRatioNumerator = value;
    }

    /// @dev Sets the max basefee.
    function setGasbackMaxBasefee(uint256 value) public onlySystem {
        gasbackMaxBasefee = value;
    }

    /// @dev Guards the function such that it can only be called by the system contract.
    modifier onlySystem() {
        require(msg.sender == _SYSTEM_ADDRESS);
        _;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          GASBACK                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev For the gasback logic.
    fallback() external payable {
        uint256 gasToBurn;

        /// @solidity memory-safe-assembly
        assembly {
            gasToBurn := calldataload(0x00)
            // The input must be exactly 32 bytes.
            if iszero(eq(calldatasize(), 0x20)) { revert(0x00, 0x00) }
        }

        uint256 ethToGive =
            (gasToBurn * block.basefee * gasbackRatioNumerator) / GASBACK_RATIO_DENOMINATOR;

        // If the contract has insufficient ETH, or if the basefee is too high.
        if (ethToGive > address(this).balance || block.basefee > gasbackMaxBasefee) {
            // Do a pass through.
            ethToGive = 0;
            gasToBurn = 0;
        }

        /// @solidity memory-safe-assembly
        assembly {
            if gasToBurn {
                let gasBefore := gas()
                // Make a self-call to burn `gasToBurn`.
                pop(staticcall(gasToBurn, address(), 0x00, 0x00, 0x00, 0x00))
                // Require that the amount of gas burned is greater or equal to `gasToBurn`.
                if lt(sub(gasBefore, gas()), gasToBurn) { revert(0x00, 0x00) }
            }

            if ethToGive {
                // First, attempt to send the ETH to the caller via a call.
                if iszero(call(gas(), caller(), ethToGive, 0x00, 0x00, 0x00, 0x00)) {
                    // And if it fails, force send the ETH via a `SELFDESTRUCT` contract.
                    mstore(0x00, caller()) // Store the address in scratch space.
                    mstore8(0x0b, 0x73) // Opcode `PUSH20`.
                    mstore8(0x20, 0xff) // Opcode `SELFDESTRUCT`.
                    if iszero(create(ethToGive, 0x0b, 0x16)) { revert(0x00, 0x00) }
                }
            }

            mstore(0x00, ethToGive)
            return(0x00, 0x20) // Return the `ethToGive`.
        }
    }

    /// @dev For depositing ETH.
    receive() external payable {
        /// @solidity memory-safe-assembly
        assembly {
            // Use `invalid` to burn all the gas passed in efficiently via the self-call.
            if eq(caller(), address()) { invalid() }
        }
    }
}
