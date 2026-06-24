# Goldhaven Arena Match Snapshot Fix

This patch fixes the frontend data gap for:

1. Replaying "My battle process / history" without relying on RPC event scans.
2. Showing the finished arena Top 32 with the owner address from that arena, not the current NFT owner after unlock/transfer.

## Contract changes

`contracts/GoldhavenArena.sol` now stores lightweight settlement metadata only. It does **not** store full battle logs.

Added snapshots/getters:

- `entrantCount()`
- `entrantAt(index) -> (tokenId, owner)`
- `entrantOwnerAtOpen(tokenId)`
- `matchCount(round)`
- `matchCountOfRound(round)`
- `getMatch(round, matchIndex) -> (round, matchIndex, tokenA, tokenB, winner, loser, verified, validator)`
- `finalRoundNumber()`
- `top32Count()`
- `top32At(index) -> (rank, tokenId, owner)`

Added events:

- `ArenaEntrantSnapshot(tokenId, owner)`
- `Top32Snapshot(rank, tokenId, owner)`

## Design

The Arena stores only:

- participant token IDs and owner snapshots at open time;
- per-round match pairs;
- winner/loser/validator after verification;
- final Top 32 order after finish.

The frontend still reconstructs detailed battle steps from `GoldhavenNFT.cardOf(tokenId)`.

## Deployment note

This changes the Arena bytecode. Deploy a fresh `GoldhavenArena` implementation, then deploy `GoldhavenArenaDeployer(implementation)`, then deploy a new `GoldhavenArenaFactory` pointing to that deployer for new arenas. Old arenas cannot expose these new getters.
