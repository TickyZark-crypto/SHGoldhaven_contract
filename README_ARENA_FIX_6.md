# Goldhaven Arena Fix 6

This build addresses the latest arena issues:

1. Finished arenas now clear current/next round queues, so remaining count is 0 after finish.
2. Arena rewards are split into battle rewards and validator rewards:
   - `pendingBattleRewards(user)` / `claimBattleReward()`
   - `pendingValidatorRewards(user)` / `claimValidatorReward()`
   - `pendingRewards(user)` / `claimReward()` remain as compatibility helpers.
3. NFT arena stake is consumed by exactly one arena.
   - `markArenaOpened()` removes participants from the pending queue and assigns `arenaOfToken[tokenId]`.
   - After `markArenaFinished()`, the NFT can be redeemed, but it is not automatically re-entered into the next arena.
   - To join another arena, the user must unstake and stake again.
4. Concurrent verification is supported.
   - Validators can call `verifyMatch(matchIndex)` for different match indexes in the same round.
   - `verifyNextMatch()` remains for compatibility, but may race if several validators use it at the same time.
5. `GoldhavenArenaFactory` now tracks:
   - `activeArena`
   - `latestArena`
   - `latestFinishedArena`
   - `arenaCount`
   - `arenaOfId(arenaId)`
6. For repeated same-day testing, owner can call:
   - `setDailyLimitEnabled(false)`

Production should keep `dailyLimitEnabled = true`.
