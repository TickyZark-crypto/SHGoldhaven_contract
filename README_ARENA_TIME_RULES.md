# Arena time and NFT lock rule update

This package implements the optimized arena timing rules:

1. Production mode: arenas can open only from UTC 12:00 to 12:10.
2. Production mode: only one arena can open per UTC day.
3. NFT stake/unstake is disabled from UTC 11:50 to 12:10 while today's arena has not finished, including the not-yet-opened case.
4. NFT stake/unstake is always disabled while an arena is active.
5. Once the active arena finishes, NFT stake/unstake is open again.
6. Pending staked NFTs remain in the Vault queue across days until an arena opens.
7. When an arena opens, its participant NFTs are consumed for that arena; to join another arena, the user must unstake and stake again.
8. Owner can enable `testMode` on `GoldhavenArenaFactory`; in test mode open time and daily count are ignored, but active arena locking still applies.

## Owner testing calls

```solidity
GoldhavenArenaFactory.setTestMode(true);
GoldhavenArenaFactory.setTestMode(false);
```

Backward-compatible helper:

```solidity
setDailyLimitEnabled(false) // enables testMode
setDailyLimitEnabled(true)  // disables testMode
```

## Important

Production should keep `testMode == false`.
