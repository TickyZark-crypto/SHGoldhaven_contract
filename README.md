  # Goldhaven Contracts

Goldhaven is an on-chain Web3 game and token economy built around **GHV**, a Uniswap v4 Hook-based buy/sell curve, NFT battle cards, vault staking, daily arena battles, validator verification, ETH reward distribution, and a GHV-denominated NFT marketplace.

This repository contains the Solidity smart contracts for the Goldhaven protocol.

## Overview

Goldhaven combines three core systems:

1. **GHV Token Economy**

   * GHV is minted and burned through a Uniswap v4 Hook.
   * Buy/sell pricing follows the project bonding curve.
   * A 2% arena fee is collected from buy/sell activity.
   * Arena funding is pulled by the Arena Factory when a daily arena opens.

2. **NFT Battle Card System**

   * NFTs are minted by the Hook when eligible buy conditions are met.
   * Each NFT stores deterministic on-chain battle attributes.
   * Card metadata is generated from class, element, beast, fate, and skills.
   * NFT image URIs are mapped by class × beast combination.

3. **Arena + Vault System**

   * Users stake NFTs to enter daily arenas.
   * Users stake GHV tokens to participate in dividend rewards and validator eligibility.
   * Validators verify battle matches on-chain.
   * Arena rewards are credited as claimable ETH instead of being pushed immediately.
   * Arena contracts are deployed as EIP-1167 minimal proxy clones to reduce code size.

## Main Contracts

### `GHVToken.sol`

Plain ERC-20 style GHV token.

Key features:

* Name: `Goldhaven Token`
* Symbol: `Goldhaven`
* Decimals: `18`
* Minting and burning are restricted to one locked minter.
* The minter is intended to be the deployed `GHVHook`.
* `setMinter(address)` can only be called once by the deployer.

### `GHVHook.sol`

Goldhaven Uniswap v4 Hook.

Key features:

* Handles GHV buy and sell logic.
* Uses curve-based custom accounting.
* Collects 2% arena tax from buys and sells.
* Routes arena funds into `arenaVaultEth`.
* Allows the Arena Factory to pull daily arena funding.
* Mints Goldhaven NFTs when buy conditions meet the configured USD threshold.
* Blocks direct liquidity additions.
* Uses an immutable `ARENA_CONTROLLER`, usually the `GoldhavenArenaFactory`.

Important constants:

```solidity
K_SUPPLY = 21_000_000e18
MAX_BUY_WEI = 5 ether
COOLDOWN_BLOCKS = 1
FEE_NUMERATOR = 200
FEE_DENOMINATOR = 10_000
```

### `GHVHookDeployer.sol`

CREATE2 helper for deploying `GHVHook` at a Uniswap v4-compatible Hook address.

Key features:

* Computes Hook deployment address.
* Mines a salt for the required Uniswap v4 Hook permission flags.
* Deploys `GHVHook` with constructor arguments.
* Verifies that the final Hook address matches the required flags.

### `GHVSwapRouter.sol`

Minimal exact-input router for GHV Hook swaps.

Key features:

* `buy(...)`
* `sell(...)`
* `swap(...)`
* Supports native ETH buy flow.
* Supports GHV sell flow.
* Uses Uniswap v4 `PoolManager.unlock(...)`.

### `GoldhavenNFT.sol`

ERC-721 NFT battle card contract.

Key features:

* NFTs are minted only by the locked Hook.
* Vault address is locked once and used for arena stake metadata.
* Each NFT stores a generated `GoldhavenTypes.Card`.
* Card attributes are generated fully on-chain.
* Image URI is resolved through class × beast mapping.
* Batch image URI setup is supported through `setComboImageURIs(...)`.

### `GoldhavenVault.sol`

Vault for NFT arena staking, GHV staking, dividend accounting, and validator eligibility.

Key features:

* NFT arena staking with `0.001 ETH` entry fee.
* GHV token staking for dividend rewards.
* Validator eligibility based on 24h average USD value.
* Maintains the canonical arena participant queue.
* Caps arena participants at 32.
* Locks NFT stake/unstake during arena lifecycle and configured arena window.
* Rejects direct NFT transfers outside the official staking flow.
* Tracks dividend epochs and user token-seconds.

Important constants:

```solidity
NFT_STAKE_FEE = 0.001 ether
VALIDATOR_THRESHOLD_USD_WAD = 150e18
WINDOW = 24 hours
MAX_ARENA_PARTICIPANTS = 32
```

### `GoldhavenArenaFactory.sol`

Factory for opening daily arenas.

Key features:

* Opens one arena per UTC day in production mode.
* Production opening window: UTC 12:00 to 12:10.
* Pulls arena participants from `GoldhavenVault`.
* Pulls 70% of Hook arena funds into the new arena.
* Deploys arenas through `GoldhavenArenaDeployer`.
* Supports owner-controlled `testMode` for development.
* Tracks active, latest, finished, and indexed arenas.

Main entrypoints:

```solidity
openDailyArena()
openArena()
syncArenaStatus()
setTestMode(bool enabled)
```

### `GoldhavenArenaDeployer.sol`

EIP-1167 clone deployer for arena contracts.

Key features:

* Stores one `GoldhavenArena` implementation address.
* Creates lightweight clones.
* Initializes each clone immediately after deployment.
* Avoids embedding full Arena bytecode in the Factory or Deployer runtime.

### `GoldhavenArena.sol`

1v1 elimination arena contract.

Key features:

* Supports 1 to 32 participants.
* Stores entrant snapshots at arena open time.
* Stores lightweight match records for frontend replay.
* Validators verify matches by index.
* Battle settlement is delegated to `GoldhavenBattleEngine`.
* Rewards are credited as pending balances.
* Users claim battle and validator rewards manually.
* Excess ETH rolls over to the Hook arena vault.
* Single-entrant arenas can finish automatically.

Reward helpers:

```solidity
pendingBattleRewards(address)
pendingValidatorRewards(address)
pendingRewards(address)
claimBattleReward()
claimValidatorReward()
claimReward()
```

Frontend/history helpers:

```solidity
entrantCount()
entrantAt(index)
matchCount(round)
getMatch(round, matchIndex)
top32Count()
top32At(index)
finalRoundNumber()
```

### `GoldhavenBattleEngine.sol`

Battle settlement engine.

Key features:

* Deterministic battle result calculation.
* Uses generated NFT card attributes.
* Synchronized with the project battle balance rules.
* No new battle randomness is used after NFT mint.

### `GoldhavenChainlinkEthCurveGhvOracle.sol`

Price oracle for ETH/USD and GHV/USD conversion.

Key features:

* Reads ETH/USD from Chainlink.
* Uses Hook marginal curve price for GHV/ETH.
* Computes GHV/USD from GHV/ETH × ETH/USD.
* Hook address is locked once after deployment.
* Includes stale price protection.

### `GoldhavenNFTMarketplace.sol`

Simple GHV-denominated NFT marketplace.

Key features:

* List unstaked NFTs for GHV.
* Cancel listings.
* Buy listed NFTs with GHV.
* Uses pull-style ERC20 payment and ERC721 transfer.

## Libraries

### `Curve.sol`

Bonding curve math used by the Hook.

### `GoldhavenBattle.sol`

On-chain card generation and battle logic utilities.

### `GoldhavenTypes.sol`

Shared Goldhaven structs and enums:

* Classes
* Elements
* Beasts
* Fates
* Skills
* Card data
* Battle result data

## Repository Structure

```text
contracts/
  GHVHook.sol
  GHVHookDeployer.sol
  GHVSwapRouter.sol
  GHVToken.sol
  GoldhavenArena.sol
  GoldhavenArenaDeployer.sol
  GoldhavenArenaFactory.sol
  GoldhavenBattleEngine.sol
  GoldhavenChainlinkEthCurveGhvOracle.sol
  GoldhavenNFT.sol
  GoldhavenNFTMarketplace.sol
  GoldhavenVault.sol

contracts/interfaces/
  IGoldhavenBattleEngine.sol
  IGoldhavenNFT.sol
  IGoldhavenPriceOracle.sol
  IGoldhavenVault.sol

contracts/lib/
  Curve.sol
  GoldhavenBattle.sol
  GoldhavenTypes.sol

script/
  SetGoldhavenNftImageURIs.s.sol
```

## Requirements

This project is intended for a Foundry-based Solidity workflow.

Required dependencies include:

* Foundry
* OpenZeppelin Contracts
* Uniswap v4 Core
* PRBMath
* forge-std

Example dependency setup:

```bash
forge install OpenZeppelin/openzeppelin-contracts
forge install Uniswap/v4-core
forge install PaulRBerg/prb-math
forge install foundry-rs/forge-std
```

Depending on your local dependency layout, configure remappings for imports such as:

```text
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
@prb/math/=lib/prb-math/
forge-std/=lib/forge-std/src/
v4-core-main/=lib/v4-core/
```

## Build

```bash
forge build
```

## Test

If test files are added to the repository:

```bash
forge test
```

## Deployment Order

Recommended deployment order:

1. Deploy `GHVToken`.
2. Deploy `GoldhavenNFT(initialOwner)`.
3. Deploy `GoldhavenChainlinkEthCurveGhvOracle(ethUsdFeed, maxStaleSeconds, initialOwner)`.
4. Deploy `GoldhavenVault(initialOwner, ghvToken, goldhavenNFT, priceOracle)`.
5. Deploy `GoldhavenBattleEngine`.
6. Deploy `GoldhavenArena` implementation.
7. Deploy `GoldhavenArenaDeployer(arenaImplementation)`.
8. Deploy `GoldhavenArenaFactory(initialOwner, goldhavenNFT, goldhavenVault, battleEngine, arenaDeployer)`.
9. Mine and deploy `GHVHook` through `GHVHookDeployer`, passing:

   * `poolManager`
   * `ghvToken`
   * `goldhavenNFT`
   * `goldhavenVault`
   * `priceOracle`
   * `nftThresholdUsdWad`
   * `arenaFactory` as `arenaController_`
10. Deploy `GHVSwapRouter(poolManager)`.
11. Optionally deploy `GoldhavenNFTMarketplace(ghvToken, goldhavenNFT)`.
12. Initialize the Uniswap v4 pool.

## One-Time Permission Locks

After deployment, run the one-time setup calls:

```solidity
GHVToken.setMinter(hook);

GoldhavenNFT.setHook(hook);
GoldhavenNFT.setVault(vault);

GoldhavenVault.setHook(hook);

GoldhavenChainlinkEthCurveGhvOracle.setGhvHook(hook);

GoldhavenArenaFactory.setHook(hook);
```

These permissions are intentionally locked forever. If a wrong address is set, the affected contracts must be redeployed.

## NFT Image URI Setup

To keep `GoldhavenNFT` under the EIP-170 contract size limit, the 49 class × beast image URI table is not seeded in the constructor.

After NFT deployment, configure image URIs with:

```bash
export GOLDHAVEN_NFT=0xYourNftAddress
export RPC_URL=your_rpc_url
export PRIVATE_KEY=your_private_key

forge script script/SetGoldhavenNftImageURIs.s.sol:SetGoldhavenNftImageURIs \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast -vvvv
```

The script calls:

```solidity
setComboImageURIs(classIds, beasts, imageURIs)
```

Each URI uses the `ipfs://CID` format.

## Arena Flow

1. User buys GHV through the Hook.
2. Hook mints/burns GHV based on the curve.
3. Hook collects arena tax into `arenaVaultEth`.
4. Eligible buys may mint Goldhaven NFTs.
5. User stakes NFT into `GoldhavenVault` to join the arena queue.
6. User stakes GHV into `GoldhavenVault` to participate in dividends and validator eligibility.
7. A validator calls `GoldhavenArenaFactory.openDailyArena()`.
8. Factory pulls participants from the Vault.
9. Factory deploys a new Arena clone.
10. Factory pulls 70% of Hook arena funds into the Arena.
11. Validators verify matches.
12. Arena finishes and credits rewards.
13. Users claim battle, validator, and dividend rewards.

## Arena Reward Distribution

At arena settlement, the pot is distributed across:

* Token staking dividend pool
* Validator rewards
* Champion reward
* Rank-based battle rewards
* Rollover funds

Rewards are credited to pending balances and must be claimed by users.

This prevents failed ETH transfers from blocking arena settlement.

## Production Arena Rules

In production mode:

* Arena can open only during UTC 12:00–12:10.
* Only one arena can open per UTC day.
* NFT stake/unstake is disabled around the arena window.
* NFT stake/unstake is disabled while an arena is active.
* Arena participant NFTs are consumed by one arena.
* To join another arena, users must unstake and stake again.

For development or repeated same-day testing, the owner can enable test mode:

```solidity
GoldhavenArenaFactory.setTestMode(true);
```

Production should keep:

```solidity
testMode == false
```

## Security Notes

The current contracts include the following security-oriented design choices:

* One-time locked permission model.
* Immutable Hook arena controller.
* Canonical participant queue maintained by the Vault.
* Factory no longer trusts validator-supplied participant lists.
* Arena rewards use claimable balances instead of immediate ETH pushes.
* Reentrancy protection on Vault, Arena, and Marketplace flows.
* Vault rejects direct NFT transfers outside official staking.
* Arena clones are initialized once and implementation contract is locked.
* Oracle includes stale Chainlink price protection.
* Direct ETH handling is explicitly routed to arena vault, dividends, or rollover logic.

## Important Notes

* The Hook curve approaches the configured `K_SUPPLY`, but `GHVToken` itself does not enforce a hard cap.
* If an absolute maximum token supply is required, add strict cap enforcement at the token or Hook level.
* `GoldhavenArena` is deployed through EIP-1167 clones. Frontend integrations can use the same Arena ABI for clone instances.
* Old arenas deployed before ABI or storage updates will not expose newer getter functions.
* This repository is not an audit. Use at your own risk and perform independent security review before mainnet deployment.

## License

MIT
