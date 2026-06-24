# Arena Factory / Deployer Code Size Fix

Earlier versions moved `new GoldhavenArena(...)` from `GoldhavenArenaFactory` into `GoldhavenArenaDeployer`. That fixed the Factory, but the Deployer still embedded the full `GoldhavenArena` creation bytecode and could exceed the 24KB deployment limit.

## Fix

`GoldhavenArena` is now deployed once as an implementation contract, and `GoldhavenArenaDeployer` creates lightweight EIP-1167 minimal proxy clones.

```text
GoldhavenArena implementation
        ↓
GoldhavenArenaDeployer.clone()
        ↓
GoldhavenArena clone initialize(...)
```

The Deployer runtime no longer contains the Arena creation bytecode.

## Contract changes

- `GoldhavenArena` now has `initialize(...)` instead of constructor arguments.
- `GoldhavenArenaDeployer` has constructor `GoldhavenArenaDeployer(address implementation)`.
- `GoldhavenArenaFactory` still calls `arenaDeployer.deployArena(...)`.

## New deployment order

Deploy these before `GoldhavenArenaFactory`:

```text
1. GoldhavenArena implementation
2. GoldhavenArenaDeployer(implementation)
3. GoldhavenArenaFactory(owner, nft, vault, battleEngine, arenaDeployer)
4. GHVHook(..., arenaFactory)
5. GoldhavenArenaFactory.setHook(GHVHook)
```

The Hook controller remains the Factory address, not the deployer or implementation address.
