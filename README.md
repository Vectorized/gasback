# Gasback

A barebones implementation of a gasback contract that implements [RIP-7767](https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7767.md).

## Suggested setup for OP stack chains

### Requirements

- The `baseFeeVault` is deployed at `0x4200000000000000000000000000000000000019`.
- The `WITHDRAWAL_NETWORK` of the `baseFeeVault` is set to `1`.

### Via script

See `script/Delegate7702.s.sol` for an automated script that can help you deploy.

This script requires you to have the private key of the `baseFeeVault` recipient in your environment.

For more information on how to run a foundry script, see `https://getfoundry.sh/guides/scripting-with-solidity`.

### Manual steps

1. Deploy the `gasback` contract which will be used as an implementation via EIP-7702.

2. Use EIP-7702 to make the EOA `RECIPIENT` of the `baseFeeVault` delegated to the `gasback` implementation.  
   After delegating, use the EOA to call functions on itself to initialize the parameters:
   
   - `setGasbackRatioNumerator(uint256)`  
     `900000000000000000`
   - `setGasbackMaxBaseFee(uint256)`  
     `115792089237316195423570985008687907853269984665640564039457584007913129639935`  
   - `setBaseFeeVault(address)`  
     `0x4200000000000000000000000000000000000019`

4. Put or leave some ETH into the EOA `RECIPIENT`, which will be the actual `gasback` contract. 
   The ETH will act as a buffer that will be temporarily dished out to contracts calling the EOA `RECIPIENT` in the span of a single block.
   The base fees collected in a block will only be accrued into the `baseFeeVault` at the end of a block.
   Try not to empty ETH from the `RECIPIENT` when you are actually taking out ETH from it.

5. For better discoverabiity (for the devX), deploy the `gasbackBeacon` and use the system address to set the EOA `RECIPIENT`.  
   The exact CREATE2 instructions are in [`./deployments.md`](./deployments.md).
