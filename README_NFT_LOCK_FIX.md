# GoldhavenNFT hook/vault lock fix

This package fixes the NFT configuration locks so that Hook and Vault are independent one-time settings.

## Problem

Some earlier versions used a shared or wrong lock condition, so calling `setHook()` could make `setVault()` revert.

## Fix

`GoldhavenNFT.sol` now has independent locks:

```solidity
address public hook;
address public vault;
bool public hookLocked;
bool public vaultLocked;
```

- `setHook(address)` checks only `hookLocked`.
- `setVault(address)` checks only `vaultLocked`.
- Either function can be called first.
- Each can still be called only once.

A convenience function is also included:

```solidity
setHookAndVault(address hook, address vault)
```

Use this in deployment scripts if both addresses are already known.

## Important

If you already deployed a broken `GoldhavenNFT` contract, this cannot be fixed in-place unless that deployed contract has upgradeability. You should redeploy `GoldhavenNFT`, then redeploy/reconfigure dependent contracts.
