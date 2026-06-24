# Goldhaven permission model update

This package applies the one-time permission-lock model requested for the Goldhaven contracts.

## One-time locked permissions

### GoldhavenNFT

- `setHook(address)` can be called exactly once by the owner.
- `hook` cannot be changed after it is set.
- `mintFromHook(...)` is callable only by this locked Hook.
- `setVault(address)` is also locked exactly once, so only the configured Vault can update arena stake metadata.

### GoldhavenChainlinkEthCurveGhvOracle

- Constructor no longer receives a Hook address.
- `setGhvHook(address)` can be called exactly once by the owner after `GHVHook` is deployed.
- `ghvToUsdWad(...)` / `ghvUsdWad()` revert with `HookNotSet()` until this is configured.
- `ethToUsdWad(...)` works immediately after deployment because it only depends on Chainlink ETH/USD.

### GoldhavenVault

- Constructor no longer receives a Hook / arena fee receiver address.
- `setHook(IArenaFeeReceiver)` can be called exactly once by the owner after `GHVHook` is deployed.
- `setArenaFeeReceiver(...)` remains as a backwards-compatible alias, but it is also one-time only.
- NFT arena entry fees are sent to this locked Hook through `depositArenaFee()`.

### GHVHook

- `setArenaController(...)` has been removed.
- `ARENA_CONTROLLER` is immutable and locked at Hook deployment.
- Pass the `GoldhavenArenaFactory` address as the Hook constructor's `arenaController_` parameter.
- `pullArenaFunding(...)` can only be called by the locked `ARENA_CONTROLLER`.
- A backwards-compatible `arenaController()` getter is included for frontends.

### GoldhavenArenaFactory

- Constructor no longer receives a Hook address.
- `setHook(IGoldhavenHookArenaFunding)` can be called exactly once by the owner after `GHVHook` is deployed.
- `openDailyArena(...)` reverts with `HookNotSet()` until Hook is configured.

## Updated deployment order

1. Deploy `GHVToken`.
2. Deploy `GoldhavenNFT(initialOwner)`.
3. Deploy `GoldhavenChainlinkEthCurveGhvOracle(ethUsdFeed, maxStaleSeconds, initialOwner)`.
4. Deploy `GoldhavenVault(initialOwner, ghvToken, goldhavenNFT, priceOracle)`.
5. Deploy `GoldhavenBattleEngine`.
6. Deploy `GoldhavenArenaFactory(initialOwner, goldhavenNFT, goldhavenVault, battleEngine)`.
7. Mine and deploy `GHVHook` through `GHVHookDeployer`, passing:
   - `poolManager`
   - `ghvToken`
   - `goldhavenNFT`
   - `goldhavenVault`
   - `priceOracle`
   - `50e18`
   - `arenaFactory` as `arenaController_`
8. Run the one-time locks:
   - `GHVToken.setMinter(hook)`
   - `GoldhavenNFT.setHook(hook)`
   - `GoldhavenNFT.setVault(vault)`
   - `GoldhavenVault.setHook(hook)`
   - `GoldhavenChainlinkEthCurveGhvOracle.setGhvHook(hook)`
   - `GoldhavenArenaFactory.setHook(hook)`
9. Deploy `GoldhavenNFTMarketplace(ghvToken, goldhavenNFT)` if needed.
10. Initialize the Uniswap v4 pool.

## Important

After the one-time setters are called, these addresses are intentionally immutable at the contract level. If a wrong address is locked, the affected contracts must be redeployed.

## Security fix batch: arena queue, pending rewards, reentrancy

This package also applies the requested direct fixes for review items 1, 2, 4, and 6.

### GoldhavenVault participant queue

- `GoldhavenVault` now inherits `ReentrancyGuard`.
- `stakeNftForArena`, `unstakeNftFromArena`, `stakeToken`, `unstakeToken`, `depositDividendForLast24h`, `claimDividend`, and `claimDividends` are protected with `nonReentrant`.
- Vault now maintains the canonical active arena participant queue:
  - `arenaParticipantCount()`
  - `arenaParticipantAt(index)`
  - `getArenaParticipants()`
  - `isArenaParticipant(tokenId)`
- `stakeNftForArena()` adds the NFT to the queue.
- `unstakeNftFromArena()` removes the NFT from the queue by swap-and-pop.
- The queue is capped at `MAX_ARENA_PARTICIPANTS = 32`.

### GoldhavenArenaFactory no longer trusts validator-supplied participant lists

- New canonical entry point:

```solidity
openDailyArena()
```

- The factory now pulls participants from `vault.getArenaParticipants()`.
- The backwards-compatible overload remains:

```solidity
openDailyArena(uint256[] calldata)
```

but the calldata list is intentionally ignored.

### GoldhavenArena participant validation

- Arena constructor now validates every participant:
  - `vault.stakeOwnerOfToken(tokenId) != address(0)`
  - no duplicate token IDs
  - participant count is still `1..32`

### GoldhavenArena pending reward model

- Arena no longer pushes rank and validator rewards with immediate ETH transfers during `_finish()`.
- Rewards are credited to:

```solidity
mapping(address => uint256) public pendingRewards;
```

- Users claim with:

```solidity
claimReward()
```

- This prevents a rejecting recipient contract from DoSing arena settlement.
- `totalPendingRewards` is tracked so unallocated dust can still roll over to the Hook without stealing pending rewards.

### Frontend impact

- Arena opening should call `GoldhavenArenaFactory.openDailyArena()` with no participant list.
- Old calls to `openDailyArena([...])` still work, but the array is ignored.
- Arena reward UI should show `GoldhavenArena.pendingRewards(user)` and call `claimReward()`.
- Token staking dividends still use Vault `claimDividend()` / `claimDividends()`.
