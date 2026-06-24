# NFT codesize fix

`GoldhavenNFT.sol` previously embedded the full 49-entry class × beast IPFS CID table in the constructor. That made the deployed bytecode exceed the 24,576-byte EIP-170 contract size limit.

This package removes the embedded default seeding from `GoldhavenNFT.sol`.

## New flow

1. Deploy `GoldhavenNFT(initialOwner)`.
2. Deploy/configure Hook and Vault as before.
3. Call `setComboImageURIs(classIds, beasts, imageURIs)` once after deployment, or use:

```bash
export GOLDHAVEN_NFT=0xYourNftAddress

forge script script/SetGoldhavenNftImageURIs.s.sol:SetGoldhavenNftImageURIs \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast -vvvv
```

## Why this fixes the warning

The CID strings are no longer part of `GoldhavenNFT` deployed bytecode. They are passed as calldata after deployment and stored in the existing `comboImageURI` mapping.

## Frontend

The main site already has the same CID table as a fallback. Even before the on-chain image table is set, the site can display images from its local mapping. For third-party indexers/marketplaces, run the setter script so `tokenURI()` / `imageURI()` returns the on-chain `ipfs://...` URI.
