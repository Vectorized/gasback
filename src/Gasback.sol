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

    /// @dev Storage struct for the gasback contract.
    struct GasbackStorage {
        // The gasback ratio numerator.
        uint256 gasbackRatioNumerator;
        // If the base fee exceeds this, this contract becomes a pass through.
        uint256 gasbackMaxBaseFee;
        // The base fee vault predeploy on OP stack chains.
        // If this contract used as an EIP-7702 delegated EOA which is also the
        // recipient of the base fee vault, it can be configured to auto-pull
        // funds from the base fee vault when it runs out of ETH.
        address baseFeeVault;
        // The minimum balance of the base fee vault.
        uint256 minVaultBalance;
        // The amount of ETH accrued by taking a cut from the gas burned.
        uint256 accrued;
        // The recipient of the accrued ETH.
        address accruedRecipient;
        // A mapping of addresses authorized to withdraw the accrued ETH.
        mapping(address => bool) accuralWithdrawers;
    }

    /// @dev Returns a pointer to the storage struct.
    function _getGasbackStorage() internal pure returns (GasbackStorage storage $) {
        // Truncate to 9 bytes to reduce bytecode size.
        uint256 s = uint72(bytes9(keccak256("GASBACK_STORAGE")));
        /// @solidity memory-safe-assembly
        assembly {
            $.slot := s
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CONSTRUCTOR                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    constructor() payable {
        GasbackStorage storage $ = _getGasbackStorage();
        $.gasbackRatioNumerator = 0.8 ether;
        $.gasbackMaxBaseFee = type(uint256).max;
        $.baseFeeVault = 0x4200000000000000000000000000000000000019;
        $.minVaultBalance = 0.42 ether;
        $.accruedRecipient = 0x4200000000000000000000000000000000000019;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                       VIEW FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The gasback ratio numerator.
    function gasbackRatioNumerator() public view virtual returns (uint256) {
        return _getGasbackStorage().gasbackRatioNumerator;
    }

    /// @dev If the base fee exceeds this, this contract becomes a pass through.
    function gasbackMaxBaseFee() public view virtual returns (uint256) {
        return _getGasbackStorage().gasbackMaxBaseFee;
    }

    /// @dev The base fee vault on OP stack chains.
    function baseFeeVault() public view virtual returns (address) {
        return _getGasbackStorage().baseFeeVault;
    }

    /// @dev The minimum balance of the base fee vault that allows a pull withdrawal.
    function minVaultBalance() public view virtual returns (uint256) {
        return _getGasbackStorage().minVaultBalance;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     ACCURAL FUNCTIONS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the amount of ETH accrued.
    function accrued() public view virtual returns (uint256) {
        return _getGasbackStorage().accrued;
    }

    /// @dev Withdraws from the accrued amount.
    function withdrawAccrued(address to, uint256 amount) public virtual returns (bool) {
        require(_getGasbackStorage().accuralWithdrawers[msg.sender]);
        // Checked math prevents underflow.
        _getGasbackStorage().accrued -= amount;
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(call(gas(), to, amount, 0x00, 0x00, 0x00, 0x00)) { revert(0x00, 0x00) }
        }
        return true;
    }

    /// @dev Returns whether `addr` is authorized to call `withdrawAccrued`.
    function isAuthorizedAccuralWithdrawer(address addr) public view virtual returns (bool) {
        return _getGasbackStorage().accuralWithdrawers[addr];
    }

    /// @dev Set whether `addr` is authorized to call `withdrawAccrued`.
    function setAccuralWithdrawer(address addr, bool authorized)
        public
        onlySystemOrThis
        returns (bool)
    {
        _getGasbackStorage().accuralWithdrawers[addr] = authorized;
        return true;
    }

    /// @dev Withdraws from the accrued amount to the accrued recipient.
    function withdrawAccruedToAccruedRecipient(uint256 amount) public virtual returns (bool) {
        // Checked math prevents underflow.
        _getGasbackStorage().accrued -= amount;

        address accruedRecipient = _getGasbackStorage().accruedRecipient;
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(call(gas(), accruedRecipient, amount, 0x00, 0x00, 0x00, 0x00)) {
                revert(0x00, 0x00)
            }
        }
        return true;
    }

    /// @dev Sets the accrued recipient.
    function setAccruedRecipient(address value) public onlySystemOrThis returns (bool) {
        _getGasbackStorage().accruedRecipient = value;
        return true;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Withdraws ETH from this contract.
    function withdraw(address to, uint256 amount) public onlySystemOrThis returns (bool) {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(call(gas(), to, amount, 0x00, 0x00, 0x00, 0x00)) { revert(0x00, 0x00) }
        }
        return true;
    }

    /// @dev Sets the numerator for the gasback ratio.
    function setGasbackRatioNumerator(uint256 value) public onlySystemOrThis returns (bool) {
        require(value <= GASBACK_RATIO_DENOMINATOR);
        _getGasbackStorage().gasbackRatioNumerator = value;
        return true;
    }

    /// @dev Sets the max base fee.
    function setGasbackMaxBaseFee(uint256 value) public onlySystemOrThis returns (bool) {
        _getGasbackStorage().gasbackMaxBaseFee = value;
        return true;
    }

    /// @dev Sets the base fee vault.
    function setBaseFeeVault(address value) public onlySystemOrThis returns (bool) {
        _getGasbackStorage().baseFeeVault = value;
        return true;
    }

    /// @dev Sets the minimum balance of the base fee vault.
    function setMinVaultBalance(uint256 value) public onlySystemOrThis returns (bool) {
        _getGasbackStorage().minVaultBalance = value;
        return true;
    }

    /// @dev A noop function.
    function noop() public payable returns (bool) {
        return true;
    }

    /// @dev Guards the function such that it can only be called either by
    /// the system contract, or by the contract itself (as an EIP-7702 delegated EOA).
    modifier onlySystemOrThis() {
        require(msg.sender == _SYSTEM_ADDRESS || msg.sender == address(this));
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
            if iszero(eq(calldatasize(), 0x20)) {
                // Use `invalid` to burn all the gas passed in efficiently via the self-call.
                if eq(caller(), address()) { invalid() }
                revert(0x00, 0x00)
            }
        }

        GasbackStorage storage $ = _getGasbackStorage();

        uint256 ethFromGas = gasToBurn * block.basefee;
        uint256 ethToGive = (ethFromGas * $.gasbackRatioNumerator) / GASBACK_RATIO_DENOMINATOR;
        unchecked {
            $.accrued += ethFromGas - ethToGive;
        }

        uint256 selfBalance = address(this).balance;
        // If the contract has insufficient ETH, try to pull from the base fee vault.
        if (ethToGive > selfBalance) {
            address vault = $.baseFeeVault;
            uint256 minBalance = $.minVaultBalance;
            /// @solidity memory-safe-assembly
            assembly {
                if extcodesize(vault) {
                    // If the vault has sufficient ETH, pull from it.
                    if gt(balance(vault), add(sub(ethToGive, selfBalance), minBalance)) {
                        mstore(0x00, 0x3ccfd60b) // `withdraw()`.
                        pop(call(gas(), vault, 0, 0x1c, 0x04, 0x00, 0x00))
                        // Return ETH to vault to ensure that it has `minBalance`.
                        pop(call(gas(), vault, minBalance, 0x00, 0x00, 0x00, 0x00))
                    }
                }
            }
        }

        // If the contract has insufficient ETH, or if the base fee is too high.
        if (ethToGive > address(this).balance || block.basefee > $.gasbackMaxBaseFee) {
            // Do a pass through.
            ethToGive = 0;
            gasToBurn = 0;
        }

        /// @solidity memory-safe-assembly
        assembly {
            if gasToBurn {
                let gasBefore := gas()
                // Make a self-call to burn `gasToBurn`.
                pop(staticcall(gasToBurn, address(), 0x00, 0x01, 0x00, 0x00))
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
    receive() external payable {}
}
