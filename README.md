# Gasback

A barebones implementation of a gasback contract that implements [RIP-7767](https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7767.md).

## Suggested deployment for OP stack chains

1. Deploy the `gasback` contract which will be used as an implementation via EIP-7702.

2. Use EIP-7702 to make the EOA `RECIPIENT` of the `baseFeeVault` delegated to the `gasback` implementation.

3. Put or leave some ETH into the EOA `RECIPIENT`, which will be the actual `gasback` contract. 
   The ETH will act as a buffer that will be temporarily dished out to contracts calling the EOA `RECIPIENT` in the span of a single block.
   The base fees collected in a block will only be accrued into the `baseFeeVault` at the end of a block.
   Try not to empty ETH from the `RECIPIENT` when you are actually taking out ETH from it.

4. For better developer quality of life, deploy the `gasbackBeacon` and use the system address to set the EOA `RECIPIENT`.
