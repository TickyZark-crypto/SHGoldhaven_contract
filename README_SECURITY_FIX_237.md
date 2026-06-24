# Goldhaven Security Fix 2/3/6/7

This package is based on `goldhaven_contracts_arena_security_fix.zip` and applies the requested fixes:

## 2. Arena lifecycle NFT lock

`GoldhavenVault` now tracks an active arena lifecycle:

- `activeArena`
- `arenaInProgress`
- `lockedInActiveArena(tokenId)`
- `activeArenaLockedCount()`
- `activeArenaLockedTokenAt(index)`

Flow:

1. Users lock NFTs through `stakeNftForArena(tokenId)`.
2. `GoldhavenArenaFactory.openDailyArena()` reads `vault.getArenaParticipants()`.
3. After deploying the daily `GoldhavenArena`, the factory calls:

```solidity
vault.markArenaOpened(arena, participantTokenIds);
```

4. Those participant NFTs cannot be unlocked while the arena is in progress.
5. When the arena finishes, `GoldhavenArena._finish()` calls:

```solidity
vault.markArenaFinished();
```

6. After that, users can unlock their NFTs again.

`stakeNftForArena()` also reverts while `arenaInProgress == true`, preventing mixed current/next-day queues.

## 3. BattleEngine synchronized to Balance v3.1

`contracts/GoldhavenBattleEngine.sol` has been replaced with the Balance v3.1 engine.

Key v3.1 adjustments included:

- Huanying/Dijiang extra multiplier: `97%` after best-beast bonus.
- WuXiangDuanXu Huanying bond shield: `3.5%` max HP.
- Balance v3 parameters for Zhanjiang, Fangshi/Xuanwu, Zhenyue/Zhuque, Yuhun/Jiuwei, and related reducers.

## 6. Vault rejects direct NFT transfers

`GoldhavenVault.onERC721Received()` now only accepts the official staking flow.

Direct `safeTransferFrom(user, vault, tokenId)` calls are rejected unless they are inside `stakeNftForArena()`.

This prevents NFTs from being stuck in the Vault without a stake record.

## 7. Direct ETH receive handling

### GHVHook

- ETH received from `POOL_MANAGER` is left for explicit buy accounting.
- Direct ETH donations from other addresses are added to `arenaVaultEth`.
- Added `unaccountedEth()` helper for forced/untracked ETH.

### GoldhavenVault

- Direct ETH is added to `pendingUndistributedDividends`.
- Emits `DirectEthReceived` and `DividendRolledOver`.

### GoldhavenArena

- ETH sent before finish is included in the arena pot.
- ETH sent after finish is immediately rolled over to the Hook arena vault.
- Added `sweepExcessToRollover()` for post-finish excess ETH above `totalPendingRewards`.

## Frontend notes

- `GoldhavenArenaFactory.openDailyArena()` remains the entrypoint; it now locks the Vault lifecycle internally.
- NFT unlock buttons should check `lockedInActiveArena(tokenId)` and/or handle `ArenaInProgress()` revert.
- Arena reward claim remains `GoldhavenArena.claimReward()`.
