# Goldhaven NFT image CID setup

This package contains the 49 class × beast IPFS image CIDs.

To keep `GoldhavenNFT` below the 24KB contract-size limit, the NFT contract no longer seeds all CID strings in its constructor. Instead, deploy the NFT first, then initialize image URIs with the batch setter script.

## Setup after NFT deployment

```bash
export GOLDHAVEN_NFT=0xYourNftAddress

forge script script/SetGoldhavenNftImageURIs.s.sol:SetGoldhavenNftImageURIs \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast -vvvv
```

The script calls:

```solidity
setComboImageURIs(classIds, beasts, imageURIs)
```

Each URI uses `ipfs://CID`.

The frontend also contains the same table as a fallback, so images can display before the on-chain table is initialized.
