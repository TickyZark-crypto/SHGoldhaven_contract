# Goldhaven Arena Clone Code Size Fix

This package fixes the latest warning:

```text
Warning: Contract code size is 25471 bytes and exceeds 24576 bytes
--> contracts/GoldhavenArenaDeployer.sol
```

## Cause

`GoldhavenArenaDeployer` still used:

```solidity
new GoldhavenArena(...)
```

That embeds the full Arena creation bytecode inside the Deployer runtime, so the Deployer itself can exceed the Spurious Dragon 24KB contract-size limit.

## Fix

The Arena is now an implementation contract plus EIP-1167 minimal proxy clones:

- `GoldhavenArena` has an `initialize(...)` function and no constructor arguments.
- `GoldhavenArenaDeployer` stores `implementation` and calls `Clones.clone()`.
- The clone is initialized immediately after creation.

## Deployment order

```text
1. Deploy GoldhavenArena implementation
2. Deploy GoldhavenArenaDeployer(implementation)
3. Deploy GoldhavenArenaFactory(owner, nft, vault, battleEngine, arenaDeployer)
4. Deploy GHVHook(..., arenaFactory)
5. Call GoldhavenArenaFactory.setHook(GHVHook)
```

The Hook arena controller must still be the Factory address. Do not use the Arena implementation or Deployer address as the Hook controller.

## Notes

- Existing old arenas remain unchanged.
- New arenas opened by the new Factory are clones that expose the same Arena ABI.
- The frontend does not need ABI changes for this code-size fix.
