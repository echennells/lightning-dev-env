#!/bin/bash

# Complete LNbits + lnurlFlip + Taproot Assets Bootstrap Script
# This script includes all the Taproot Assets functionality from the GitHub workflow

set -e

# Configuration: Extensions
TAPROOT_ASSETS_REPO="${TAPROOT_ASSETS_REPO:-https://github.com/echennells/taproot_assets}"
TAPROOT_ASSETS_VERSION="${TAPROOT_ASSETS_VERSION:-main}"  # can be branch, tag, or commit
BITCOINSWITCH_REPO="${BITCOINSWITCH_REPO:-https://github.com/echennells/bitcoinswitch}"
BITCOINSWITCH_VERSION="${BITCOINSWITCH_VERSION:-main}"  # can be branch, tag, or commit

echo "🚀 BOOTSTRAPPING FRESH LNBITS + LNURLFLIP + TAPROOT ASSETS ENVIRONMENT"
echo "=============================================================="
echo ""
echo "📦 Extension Configuration:"
echo "   Taproot Assets Repository: $TAPROOT_ASSETS_REPO"
echo "   Taproot Assets Version: $TAPROOT_ASSETS_VERSION"
echo "   Bitcoin Switch Repository: $BITCOINSWITCH_REPO"
echo "   Bitcoin Switch Version: $BITCOINSWITCH_VERSION"
echo ""

# Clone or update Taproot Assets extension
if [ -d "taproot_assets" ]; then
  echo "Found existing taproot_assets directory. Updating to $TAPROOT_ASSETS_VERSION..."
  cd taproot_assets
  git fetch origin
  git checkout "$TAPROOT_ASSETS_VERSION"
  git pull origin "$TAPROOT_ASSETS_VERSION" 2>/dev/null || echo "Already up to date"
  cd ..
  echo "✅ Taproot Assets extension updated"
else
  echo "Cloning Taproot Assets extension..."
  git clone "$TAPROOT_ASSETS_REPO" taproot_assets
  cd taproot_assets
  git checkout "$TAPROOT_ASSETS_VERSION"
  cd ..
  echo "✅ Taproot Assets extension cloned"
fi

# Clone or update Bitcoin Switch extension
cd ..
if [ -d "bitcoinswitch" ]; then
  echo "Found existing bitcoinswitch directory. Updating to $BITCOINSWITCH_VERSION..."
  cd bitcoinswitch
  git fetch origin
  git checkout "$BITCOINSWITCH_VERSION"
  git pull origin "$BITCOINSWITCH_VERSION" 2>/dev/null || echo "Already up to date"
  cd ../lightning-dev-env
  echo "✅ Bitcoin Switch extension updated"
else
  echo "Cloning Bitcoin Switch extension..."
  git clone "$BITCOINSWITCH_REPO" bitcoinswitch
  cd bitcoinswitch
  git checkout "$BITCOINSWITCH_VERSION"
  cd ../lightning-dev-env
  echo "✅ Bitcoin Switch extension cloned"
fi
echo ""

# Start containers
echo "Starting Docker containers..."
docker compose up -d

# Wait for services
echo "Waiting for services to start..."
sleep 30

# Wait for HTTPS proxy to connect to LNbits
echo "Waiting for LNbits to be ready via HTTPS proxy..."
for i in {1..60}; do
  RESPONSE=$(curl -k -s -w "%{http_code}" "https://localhost:5443/" -o /dev/null)
  if [ "$RESPONSE" = "200" ]; then
    echo "✅ LNbits ready via HTTPS proxy"
    break
  elif [ "$RESPONSE" = "307" ]; then
    echo "✅ LNbits ready via HTTPS proxy (redirecting to first_install)"
    break
  elif [ "$RESPONSE" = "502" ] || [ "$RESPONSE" = "503" ]; then
    echo "Attempt $i/60: LNbits still starting (HTTP $RESPONSE)..."
  else
    echo "Attempt $i/60: Unexpected response: $RESPONSE"
  fi
  sleep 3
done

# Bootstrap LNbits with first install
echo ""
echo "=========================================="
echo "BOOTSTRAPPING LNBITS"
echo "=========================================="

echo "Creating admin user..."
FIRST_INSTALL=$(curl -k -s -X PUT "https://localhost:5443/api/v1/auth/first_install" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "password123",
    "password_repeat": "password123"
  }')

echo "First install response: $FIRST_INSTALL"

if ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token' 2>/dev/null) && [ "$ACCESS_TOKEN" != "null" ]; then
    echo "✅ Admin user created successfully"
elif echo "$FIRST_INSTALL" | grep -q "not your first install"; then
    echo "✅ LNbits already initialized, logging in with existing admin..."
    LOGIN_RESP=$(curl -k -s -X POST "https://localhost:5443/api/v1/auth" \
      -H "Content-Type: application/json" \
      -d '{"username": "admin", "password": "password123"}')

    if ACCESS_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.access_token' 2>/dev/null) && [ "$ACCESS_TOKEN" != "null" ]; then
        echo "✅ Successfully logged in"
    else
        echo "❌ Login failed: $LOGIN_RESP"
        exit 1
    fi
else
    echo "❌ Admin creation failed: $FIRST_INSTALL"
    exit 1
fi

# Get user wallet info
echo "Getting wallet info..."
USER_INFO=$(curl -k -s "https://localhost:5443/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
echo "User info response: $USER_INFO"

ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
INVOICE_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].inkey')
WALLET_ID=$(echo "$USER_INFO" | jq -r '.wallets[0].id')

echo "✅ Wallet configured:"
echo "  Admin Key: ${ADMIN_KEY:0:20}..."
echo "  Wallet ID: $WALLET_ID"

# Skip extension installation - we'll install them manually after Taproot Assets setup
echo ""
echo "⚠️  Skipping LNbits extension installation via API (unreliable)"
echo "    Extensions will be installed after Taproot Assets setup"

echo ""
echo "=========================================="
echo "SETTING UP BITCOIN AND LIGHTNING NETWORK"
echo "=========================================="

# Setup Bitcoin wallets and mine blocks
echo "Creating Bitcoin wallets for all Lightning nodes..."
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning createwallet litd-1 || true
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning createwallet litd-2 || true
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning createwallet lnd || true

echo "Mining initial blocks..."
ADDR=$(docker compose exec -T bitcoind bitcoin-cli -regtest -rpcwallet=litd-1 -rpcuser=lightning -rpcpassword=lightning getnewaddress)
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 101 $ADDR > /dev/null

echo "Funding Lightning nodes..."
LITD1_ADDR=$(docker compose exec -T litd-1 lncli --network=regtest newaddress p2wkh | jq -r .address)
LITD2_ADDR=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 newaddress p2wkh | jq -r .address)
LND_ADDR=$(docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 newaddress p2wkh | jq -r .address)

# Fund each node with 10 BTC (all from litd-1 wallet which has the mining rewards)
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcwallet=litd-1 -rpcuser=lightning -rpcpassword=lightning sendtoaddress $LITD1_ADDR 10
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcwallet=litd-1 -rpcuser=lightning -rpcpassword=lightning sendtoaddress $LITD2_ADDR 10
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcwallet=litd-1 -rpcuser=lightning -rpcpassword=lightning sendtoaddress $LND_ADDR 10

echo "Mining blocks to confirm funding..."
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 6 $ADDR > /dev/null

echo "Waiting for nodes to sync..."
sleep 10

echo ""
echo "=========================================="
echo "MINTING TAPROOT ASSETS"
echo "=========================================="

echo "1. Minting a new Taproot Asset on litd-1 (TestCoin with 1 million units)..."
MINT_RESULT=$(docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets mint \
  --type normal \
  --name TestCoin \
  --supply 1000000 \
  --meta_bytes "546573742041737365740a" || echo "{}")

echo "Mint initiated. Waiting for batch..."
sleep 2

echo -e "\n2. Finalizing the mint batch..."
docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets mint finalize || echo "Finalizing batch"

echo -e "\n3. Mining blocks to confirm the minting..."
ADDR=$(docker compose exec -T bitcoind bitcoin-cli -regtest -rpcwallet=litd-1 -rpcuser=lightning -rpcpassword=lightning getnewaddress)
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 6 $ADDR > /dev/null

echo "Waiting for asset to be confirmed..."
sleep 5

echo -e "\n4. Listing minted assets on litd-1..."
ASSETS=$(docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets list)
echo "$ASSETS"

# Extract asset ID from the list
ASSET_ID=$(echo "$ASSETS" | jq -r '.assets[0].asset_genesis.asset_id' 2>/dev/null || echo "")

if [ -n "$ASSET_ID" ] && [ "$ASSET_ID" != "null" ]; then
  echo -e "\n✅ Successfully minted asset with ID: $ASSET_ID"

  echo -e "\n5. Setting up Lightning channels..."

  # Get node pubkeys
  LITD1_PUBKEY=$(docker compose exec -T litd-1 lncli --network=regtest getinfo | jq -r .identity_pubkey)
  LITD2_PUBKEY=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 getinfo | jq -r .identity_pubkey)
  LND_PUBKEY=$(docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 getinfo | jq -r .identity_pubkey)

  echo "Node pubkeys:"
  echo "  litd-1: $LITD1_PUBKEY"
  echo "  litd-2: $LITD2_PUBKEY"
  echo "  lnd: $LND_PUBKEY"

  # Connect nodes
  echo "Connecting nodes..."
  docker compose exec -T litd-1 lncli --network=regtest connect ${LITD2_PUBKEY}@litd-2:9736 || true
  docker compose exec -T litd-1 lncli --network=regtest connect ${LND_PUBKEY}@lnd:9737 || true
  docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 connect ${LND_PUBKEY}@lnd:9737 || true

  # Open regular Lightning channels first
  echo "Opening regular Lightning channels..."

  # litd-1 -> lnd (10M sats)
  echo "Opening channel: litd-1 -> lnd..."
  docker compose exec -T litd-1 lncli --network=regtest openchannel --node_key $LND_PUBKEY --local_amt 10000000 --push_amt 5000000
  echo "Mining blocks to confirm..."
  docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 6 $ADDR > /dev/null
  sleep 3

  # litd-2 -> lnd (10M sats)
  echo "Opening channel: litd-2 -> lnd..."
  docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 openchannel --node_key $LND_PUBKEY --local_amt 10000000 --push_amt 5000000
  echo "Mining blocks to confirm..."
  docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 6 $ADDR > /dev/null
  sleep 3

  # litd-1 -> litd-2 (10M sats)
  echo "Opening channel: litd-1 -> litd-2..."
  docker compose exec -T litd-1 lncli --network=regtest openchannel --node_key $LITD2_PUBKEY --local_amt 10000000 --push_amt 5000000

  echo "Mining blocks to confirm all channels..."
  docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 6 $ADDR > /dev/null

  echo "Waiting for channels to be active..."
  sleep 10

  echo -e "\n6. Preparing for Taproot Asset channel..."
  echo "Asset balance on litd-1:"
  docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets balance

  # Verify the asset exists and has balance
  echo "Verifying asset exists on litd-1..."
  ASSET_BALANCE=$(docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets balance | jq -r ".asset_balances[\"$ASSET_ID\"].balance" || echo "0")
  echo "Asset balance: $ASSET_BALANCE"

  if [ "$ASSET_BALANCE" -ge "50000" ]; then
    echo "Sufficient balance. Opening Taproot Asset channel..."

    echo "========================================="
    echo "ATTEMPTING TO OPEN TAPROOT ASSET CHANNEL"
    echo "========================================="
    echo "Asset ID: $ASSET_ID"
    echo "litd-2 pubkey: $LITD2_PUBKEY"
    echo "Asset amount: 50000"
    echo "litd-1 balance: $ASSET_BALANCE"

    # First verify litd-2 knows about the asset through universe sync
    echo "Syncing universe to ensure litd-2 knows about the asset..."
    docker compose exec -T litd-2 tapcli --network=regtest --rpcserver=localhost:10010 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon universe federation add --universe_host=litd-1:10009 || true
    sleep 2
    docker compose exec -T litd-2 tapcli --network=regtest --rpcserver=localhost:10010 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon universe sync --universe_host=litd-1:10009 --asset_id="$ASSET_ID" || true
    sleep 3

    echo "Checking if litd-2 knows about the asset..."
    docker compose exec -T litd-2 tapcli --network=regtest --rpcserver=localhost:10010 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon universe roots

    # Open the Taproot Asset channel
    echo -e "\n>>> RUNNING: litcli ln fundchannel --node_key $LITD2_PUBKEY --asset_amount 50000 --asset_id $ASSET_ID --sat_per_vbyte 5"

    docker compose exec -T litd-1 litcli --network=regtest ln fundchannel \
      --node_key "$LITD2_PUBKEY" \
      --asset_amount 50000 \
      --asset_id "$ASSET_ID" \
      --sat_per_vbyte 5 2>&1

    CHANNEL_RESULT=$?

    if [ $CHANNEL_RESULT -ne 0 ]; then
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      echo "TAPROOT ASSET CHANNEL OPENING FAILED!"
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      echo "Debugging info:"
      echo "Checking litd-1 logs for errors..."
      docker compose logs --tail=20 litd-1 | grep -i "error\|fail\|unable" || true
      echo "Checking litd-2 logs for errors..."
      docker compose logs --tail=20 litd-2 | grep -i "error\|fail\|unable" || true
      exit 1
    fi

    echo "✅ Taproot Asset channel opening initiated!"

    echo "Mining blocks to confirm the funding transaction..."
    ADDR=$(docker compose exec -T bitcoind bitcoin-cli -regtest -rpcwallet=litd-1 -rpcuser=lightning -rpcpassword=lightning getnewaddress)
    docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 6 $ADDR > /dev/null

    echo "Waiting for channel to be confirmed..."
    sleep 5
  else
    echo "Insufficient asset balance. Have: $ASSET_BALANCE, Need: 50000"
    exit 1
  fi

  echo -e "\n7. Verifying Taproot Asset channel is active..."
  echo "Checking litd-1 channels:"
  docker compose exec -T litd-1 lncli --network=regtest listchannels

  echo -e "\nChecking for Taproot Asset channel specifically:"
  ASSET_CHANNEL=$(docker compose exec -T litd-1 lncli --network=regtest listchannels | jq ".channels[] | select(.remote_pubkey == \"$LITD2_PUBKEY\")")
  if [ -n "$ASSET_CHANNEL" ]; then
    echo "✅ Found channel with litd-2!"
    echo "$ASSET_CHANNEL" | jq '.'
  else
    echo "❌ No channel found with litd-2!"
    echo "All channels:"
    docker compose exec -T litd-1 lncli --network=regtest listchannels | jq '.channels'
    exit 1
  fi

  echo -e "\n8. Checking asset balances after channel opening..."
  echo "litd-1 assets:"
  docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets balance || echo "No assets"

  echo -e "\nlitd-2 assets:"
  docker compose exec -T litd-2 tapcli --network=regtest --rpcserver=localhost:10010 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets balance || echo "No assets"

  echo -e "\nlitd-1 channels:"
  docker compose exec -T litd-1 lncli --network=regtest listchannels | jq '.channels[] | {remote_pubkey: .remote_pubkey, capacity: .capacity, asset_id: .asset_id}'

  echo -e "\nChecking if asset was synced to litd-2's universe:"
  docker compose exec -T litd-2 tapcli --network=regtest --rpcserver=localhost:10010 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon universe roots || echo "Universe check"

  echo -e "\n✅ Taproot Asset minted and channel opened!"

else
  echo "❌ Failed to mint Taproot Asset: $ASSETS"
  exit 1
fi

# lnurlFlip testing removed - API extension installation is unreliable
# Extensions will be installed via setup-lnbits-extensions.sh after this script completes

echo ""
echo "=========================================="
echo "INSTALLING BITCOIN SWITCH & TAPROOT ASSETS EXTENSIONS"
echo "=========================================="

# Run the automated extension setup
if [ -f "./setup-lnbits-extensions.sh" ]; then
  ./setup-lnbits-extensions.sh
else
  echo "⚠️  setup-lnbits-extensions.sh not found, skipping extension setup"
fi

echo ""
echo "=========================================="
echo "🎯 SUCCESS! ENVIRONMENT READY"
echo "=========================================="
echo ""
echo "✅ LNbits running at: https://localhost:5443"
echo "   Login: admin / password123"
echo "   Admin Key: ${ADMIN_KEY:0:20}..."
echo ""
echo "✅ Taproot Assets:"
echo "   Asset ID: $ASSET_ID"
echo "   Asset: TestCoin (1M units minted)"
echo "   Channel: 50,000 units allocated (litd-1 ↔ litd-2)"
echo ""
echo "✅ Extensions installed:"
echo "   • Bitcoin Switch: http://localhost:5001/bitcoinswitch"
echo "   • Taproot Assets: http://localhost:5001/taproot_assets"
echo ""
echo "📝 To run tests:"
echo "   ./test-suite.sh"
echo ""
echo "Note: Extensions are accessible at port 5001 (direct LNbits)"
echo "      Main LNbits UI is at port 5443 (HTTPS proxy)"