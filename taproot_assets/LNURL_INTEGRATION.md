# LNURL Integration for Taproot Assets

This document describes how the Taproot Assets extension integrates with LNURL pay links, particularly those created by the BitcoinSwitch extension.

## Overview

The Taproot Assets extension now supports paying LNURL pay links. When combined with BitcoinSwitch, this enables cross-server payments where:

1. **Server A** (BitcoinSwitch): Creates LNURL pay links that can accept either Lightning sats or Taproot Assets
2. **Server B** (Taproot Assets): Can pay these LNURL links using Taproot Assets

## How It Works

### Creating Asset-Aware LNURL Links (BitcoinSwitch)

When creating a switch in BitcoinSwitch:
1. Enable "Accept Taproot Assets" for the switch
2. Select which asset IDs to accept
3. The generated LNURL will include asset metadata in its response

### Paying LNURL Links (Taproot Assets)

The Taproot Assets extension provides two endpoints:

#### 1. Check LNURL Info
```
POST /taproot_assets/api/v1/taproot/lnurl/info
{
  "lnurl": "LNURL1..."
}
```

This returns information about the LNURL including:
- Whether it supports assets
- Which asset IDs are accepted
- Min/max amounts
- Comment support

#### 2. Pay LNURL
```
POST /taproot_assets/api/v1/taproot/lnurl/pay
{
  "lnurl": "LNURL1...",
  "amount_msat": 1000000,
  "asset_id": "asset_id_here",  // Optional
  "comment": "Payment for coffee",  // Optional
  "fee_limit_sats": 100  // Optional, defaults to 100
}
```

## LNURL Protocol Extensions

The implementation follows the LNURL specification with these extensions for Taproot Assets:

### LNURL Response Extensions
```json
{
  "tag": "payRequest",
  "callback": "https://...",
  "minSendable": 1000,
  "maxSendable": 1000000,
  "metadata": "...",
  "acceptsAssets": true,  // New field
  "acceptedAssetIds": ["asset1", "asset2"],  // New field
  "assetMetadata": {  // New field
    "supportsRfq": true,
    "message": "This switch accepts Taproot Assets"
  }
}
```

### Callback Parameters
When making the callback, include the `asset_id` parameter:
```
GET /callback?amount=1000000&asset_id=asset1
```

## Example Flow

1. **User scans LNURL QR code** from BitcoinSwitch
2. **Taproot Assets extension decodes** the LNURL and checks asset support
3. **User selects** amount and asset to pay with
4. **Extension makes callback** with asset_id parameter
5. **BitcoinSwitch creates** a Taproot Asset invoice
6. **Taproot Assets extension pays** the invoice

## Testing

Use the included test script to verify LNURL flows:
```bash
python test_lnurl_flow.py LNURL1... 1000 [asset_id]
```

## Security Considerations

- LNURL callbacks are validated using LNbits' `check_callback_url` function
- Invoice amounts are verified to match requested amounts
- SSL certificates are validated for HTTPS URLs
- Asset IDs are validated against the accepted list