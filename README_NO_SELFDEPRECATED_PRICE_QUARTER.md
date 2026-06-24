# Goldhaven Hook Update: No Self-Deprecation + Quarter Initial Price

This package removes the old 99% curve exhaustion self-deprecation logic from `GHVHook` and lowers the bonding-curve scale parameter `S` to one quarter of the previous value.

## Changes

- Removed `selfDeprecated` state from `GHVHook`.
- Removed `SelfDeprecatedNoBuys` error.
- Removed the buy-side check that reverted after `selfDeprecated == true`.
- Removed the 99% threshold code that set `selfDeprecated = true`.
- Changed `S` in both places:
  - `contracts/GHVHook.sol`
  - `contracts/lib/Curve.sol`

## New S

```solidity
uint256 public constant S = 73_884_348_733_790_717_179;
```

The old value was:

```solidity
295_537_394_935_162_868_716
```

The new value is exactly `old / 4`.

## Effect

The initial marginal mint price changes from approximately:

```text
0.0000140732 ETH / GHV
```

to approximately:

```text
0.0000035183 ETH / GHV
```

The curve still asymptotically approaches `21,000,000 GHV`, but buys no longer permanently stop at 99% fair curve supply.

## Important

`GHVToken` still should have a hard cap if the project requires an absolute 21,000,000 token maximum. Removing `selfDeprecated` means the Hook will not stop buy minting at 99%, so the token contract cap becomes more important for a strict supply guarantee.
