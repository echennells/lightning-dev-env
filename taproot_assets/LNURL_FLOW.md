# LNURL Payment Flow in Taproot Assets Extension

## Overview

When you paste an LNURL in the Taproot Assets extension, it automatically:

1. Detects that it's an LNURL (not a regular invoice)
2. Checks if the LNURL accepts Taproot Assets
3. Finds which asset you have that the LNURL accepts
4. Fetches a Taproot Asset invoice (not a Lightning invoice)
5. Shows the amount in the specific asset units

## How It Works

### 1. Paste LNURL
When you paste an LNURL and click "Decode":
- The system detects it's an LNURL
- Makes a request to the LNURL endpoint
- Checks if it accepts Taproot Assets

### 2. Automatic Asset Selection
The system automatically:
- Checks which assets the LNURL accepts
- Finds the first asset in your wallet that matches
- Requests an invoice for that specific asset

### 3. Invoice Display
The invoice shows:
- Amount in the **asset units** (not sats)
- The specific asset name
- "LNURL Payment Request" indicator

### 4. Payment
When you click pay:
- It uses the LNURL pay endpoint
- Sends the payment in the selected Taproot Asset
- Shows success with the asset amount and name

## Key Differences from Regular Lightning

- **Asset-specific**: The amount is in asset units, not sats
- **Automatic detection**: It knows which asset to use from the LNURL
- **Direct flow**: No need to manually select assets or convert amounts

## Error Handling

If the LNURL doesn't accept Taproot Assets, you'll see:
"This LNURL does not accept Taproot Assets"

If you don't have any of the accepted assets:
"You don't have any of the assets accepted by this LNURL"