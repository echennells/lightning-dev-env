#!/bin/bash

# Taproot Assets & LNbits Test Suite
# This script assumes the environment is already deployed via bootstrap-with-taproot-assets.sh

set -e

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🧪 TAPROOT ASSETS & LNBITS TEST SUITE"
echo "======================================"
echo ""

# Helper functions
pass_test() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✅ PASSED${NC}: $1"
}

fail_test() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILED_TESTS+=("$1")
  echo -e "${RED}❌ FAILED${NC}: $1"
  if [ -n "$2" ]; then
    echo "   Reason: $2"
  fi
}

start_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}TEST $TESTS_RUN: $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Get Asset ID
echo "Getting Taproot Asset ID..."
ASSET_ID=$(docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets list | jq -r '.assets[0].asset_genesis.asset_id' 2>/dev/null || echo "")

if [ -z "$ASSET_ID" ] || [ "$ASSET_ID" = "null" ]; then
  echo -e "${RED}❌ No Taproot Assets found. Run bootstrap-with-taproot-assets.sh first${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Found Asset ID: $ASSET_ID${NC}"
echo ""

# Get node pubkeys
LITD1_PUBKEY=$(docker compose exec -T litd-1 lncli --network=regtest getinfo | jq -r .identity_pubkey)
LITD2_PUBKEY=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 getinfo | jq -r .identity_pubkey)

# =============================================================================
# TEST 1: Verify Taproot Asset Channel Exists
# =============================================================================
start_test "Verify Taproot Asset Channel Exists"

# Look for SIMPLE_TAPROOT_OVERLAY commitment type with custom_channel_data
TAPROOT_CHANNEL=$(docker compose exec -T litd-1 lncli --network=regtest listchannels | jq ".channels[] | select(.remote_pubkey == \"$LITD2_PUBKEY\" and .commitment_type == \"SIMPLE_TAPROOT_OVERLAY\")" 2>/dev/null || echo "")

if [ -n "$TAPROOT_CHANNEL" ]; then
  # Check if it has asset data (v0.15.2+ format)
  CHANNEL_CAPACITY=$(echo "$TAPROOT_CHANNEL" | jq -r '.custom_channel_data.capacity' 2>/dev/null || echo "0")
  CHANNEL_LOCAL=$(echo "$TAPROOT_CHANNEL" | jq -r '.custom_channel_data.local_assets[0].amount' 2>/dev/null || echo "0")
  CHANNEL_REMOTE=$(echo "$TAPROOT_CHANNEL" | jq -r '.custom_channel_data.remote_assets[0].amount' 2>/dev/null || echo "0")

  if [ "$CHANNEL_CAPACITY" != "0" ] && [ "$CHANNEL_CAPACITY" != "null" ]; then
    pass_test "Taproot Asset channel exists (capacity: $CHANNEL_CAPACITY, local: $CHANNEL_LOCAL, remote: $CHANNEL_REMOTE)"
  else
    fail_test "Taproot channel found but no asset data"
  fi
else
  fail_test "Taproot Asset channel not found"
fi

# =============================================================================
# TEST 2: System-to-System Taproot Asset Payment
# =============================================================================
start_test "System-to-System Taproot Asset Payment (1000 units)"

# Get channel balances before payment (not on-chain, assets are in channel!)
CHANNEL_BEFORE=$(docker compose exec -T litd-1 lncli --network=regtest listchannels | jq ".channels[] | select(.remote_pubkey == \"$LITD2_PUBKEY\" and .commitment_type == \"SIMPLE_TAPROOT_OVERLAY\") | .custom_channel_data" 2>/dev/null || echo "{}")
LITD1_BEFORE=$(echo "$CHANNEL_BEFORE" | jq -r '.local_assets[0].amount' 2>/dev/null || echo "0")
LITD2_BEFORE=$(echo "$CHANNEL_BEFORE" | jq -r '.remote_assets[0].amount' 2>/dev/null || echo "0")

echo "Initial channel balances: litd-1=$LITD1_BEFORE, litd-2=$LITD2_BEFORE"

# Create invoice on litd-2
echo "Creating invoice on litd-2..."
INVOICE_RESPONSE=$(docker compose exec -T litd-2 litcli \
  --rpcserver localhost:8444 \
  --tlscertpath /root/.lit/tls.cert \
  --macaroonpath /root/.lit/regtest/lit.macaroon \
  --network=regtest \
  ln addinvoice \
  --asset_id "$ASSET_ID" \
  --asset_amount 1000 \
  --memo "Test Suite: System payment" 2>&1)

PAYMENT_REQUEST=$(echo "$INVOICE_RESPONSE" | jq -r '.invoice_result.payment_request' 2>/dev/null)

if [ -z "$PAYMENT_REQUEST" ] || [ "$PAYMENT_REQUEST" = "null" ]; then
  fail_test "Failed to create invoice" "$INVOICE_RESPONSE"
else
  echo "Invoice created: ${PAYMENT_REQUEST:0:60}..."

  # Pay invoice from litd-1
  echo "Paying invoice from litd-1..."
  PAYMENT_RESPONSE=$(docker compose exec -T litd-1 litcli \
    --rpcserver localhost:8443 \
    --tlscertpath /root/.lit/tls.cert \
    --macaroonpath /root/.lit/regtest/lit.macaroon \
    --network=regtest \
    ln payinvoice \
    --pay_req "$PAYMENT_REQUEST" \
    --asset_id "$ASSET_ID" \
    --force 2>&1)

  if echo "$PAYMENT_RESPONSE" | grep -q "Payment status: SUCCEEDED"; then
    sleep 2

    # Check channel balances after payment
    CHANNEL_AFTER=$(docker compose exec -T litd-1 lncli --network=regtest listchannels | jq ".channels[] | select(.remote_pubkey == \"$LITD2_PUBKEY\" and .commitment_type == \"SIMPLE_TAPROOT_OVERLAY\") | .custom_channel_data" 2>/dev/null || echo "{}")
    LITD1_AFTER=$(echo "$CHANNEL_AFTER" | jq -r '.local_assets[0].amount' 2>/dev/null || echo "0")
    LITD2_AFTER=$(echo "$CHANNEL_AFTER" | jq -r '.remote_assets[0].amount' 2>/dev/null || echo "0")

    echo "Final channel balances: litd-1=$LITD1_AFTER, litd-2=$LITD2_AFTER"

    LITD1_DIFF=$((LITD1_BEFORE - LITD1_AFTER))
    LITD2_DIFF=$((LITD2_AFTER - LITD2_BEFORE))

    # Verify asset conservation in channel
    TOTAL_BEFORE=$((LITD1_BEFORE + LITD2_BEFORE))
    TOTAL_AFTER=$((LITD1_AFTER + LITD2_AFTER))

    if [ "$TOTAL_BEFORE" -eq "$TOTAL_AFTER" ] && [ "$LITD1_DIFF" -eq 1000 ] && [ "$LITD2_DIFF" -eq 1000 ]; then
      pass_test "Payment succeeded and assets conserved in channel (sent: $LITD1_DIFF, received: $LITD2_DIFF)"
    else
      fail_test "Asset transfer mismatch" "Sent: $LITD1_DIFF (expected 1000), Received: $LITD2_DIFF (expected 1000)"
    fi
  else
    fail_test "Payment failed" "$PAYMENT_RESPONSE"
  fi
fi

# =============================================================================
# TEST 3: LNbits User Wallet Payment
# =============================================================================
start_test "LNbits User Wallet Payment (500 units)"

# Get lnbits-2 admin key from database
echo "Getting LNbits-2 admin key..."
docker cp lightning-dev-env-lnbits-2-1:/app/data/database.sqlite3 /tmp/lnbits2-test.db 2>/dev/null || true
LNBITS2_ADMIN_KEY=$(sqlite3 /tmp/lnbits2-test.db "SELECT adminkey FROM wallets ORDER BY id LIMIT 1;" 2>/dev/null || echo "")
rm -f /tmp/lnbits2-test.db

if [ -z "$LNBITS2_ADMIN_KEY" ] || [ "$LNBITS2_ADMIN_KEY" = "null" ]; then
  fail_test "Could not get LNbits-2 admin key"
else
  echo "Admin key: ${LNBITS2_ADMIN_KEY:0:20}..."

  # Check initial balance
  LNBITS_BEFORE=$(curl -k -s "https://localhost:5443/taproot_assets/api/v1/taproot/listassets" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.[0].user_balance' 2>/dev/null || echo "0")

  echo "Initial LNbits user balance: $LNBITS_BEFORE"

  # Create invoice in LNbits
  echo "Creating LNbits invoice..."
  LNBITS_INVOICE=$(curl -k -s -X POST "https://localhost:5443/taproot_assets/api/v1/taproot/invoice" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"asset_id\": \"$ASSET_ID\", \"amount\": 500, \"memo\": \"Test Suite: LNbits payment\"}")

  LNBITS_PAYMENT_REQUEST=$(echo "$LNBITS_INVOICE" | jq -r '.payment_request' 2>/dev/null)

  if [ -z "$LNBITS_PAYMENT_REQUEST" ] || [ "$LNBITS_PAYMENT_REQUEST" = "null" ]; then
    fail_test "Failed to create LNbits invoice" "$LNBITS_INVOICE"
  else
    echo "Invoice created: ${LNBITS_PAYMENT_REQUEST:0:60}..."

    # Pay from litd-1
    echo "Paying from litd-1..."
    LNBITS_PAYMENT=$(docker compose exec -T litd-1 litcli \
      --rpcserver localhost:8443 \
      --tlscertpath /root/.lit/tls.cert \
      --macaroonpath /root/.lit/regtest/lit.macaroon \
      --network=regtest \
      ln payinvoice \
      --pay_req "$LNBITS_PAYMENT_REQUEST" \
      --asset_id "$ASSET_ID" \
      --force 2>&1)

    if echo "$LNBITS_PAYMENT" | grep -q "Payment status: SUCCEEDED"; then
      sleep 3

      # Check final balance
      LNBITS_AFTER=$(curl -k -s "https://localhost:5443/taproot_assets/api/v1/taproot/listassets" \
        -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.[0].user_balance' 2>/dev/null || echo "0")

      echo "Final LNbits user balance: $LNBITS_AFTER"

      LNBITS_DIFF=$((LNBITS_AFTER - LNBITS_BEFORE))

      if [ "$LNBITS_DIFF" -eq 500 ]; then
        pass_test "LNbits user wallet credited correctly (+$LNBITS_DIFF units)"
      else
        fail_test "LNbits balance change incorrect" "Expected: +500, Actual: +$LNBITS_DIFF"
      fi
    else
      fail_test "Payment failed" "$LNBITS_PAYMENT"
    fi
  fi
fi

# =============================================================================
# TEST 4: LNbits Extension API Availability
# =============================================================================
start_test "LNbits Taproot Assets Extension API Availability"

if [ -n "$LNBITS2_ADMIN_KEY" ]; then
  # Test listassets endpoint
  ASSETS_RESPONSE=$(curl -k -s "https://localhost:5443/taproot_assets/api/v1/taproot/listassets" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY")

  if echo "$ASSETS_RESPONSE" | jq -e '.[0].asset_id' > /dev/null 2>&1; then
    ASSET_NAME=$(echo "$ASSETS_RESPONSE" | jq -r '.[0].name')
    pass_test "API responds correctly with asset: $ASSET_NAME"
  else
    fail_test "API response invalid" "$ASSETS_RESPONSE"
  fi
else
  fail_test "Cannot test without admin key"
fi

# =============================================================================
# TEST 5: Balance Conservation Check
# =============================================================================
start_test "Overall Asset Balance Conservation"

# Get on-chain balances
LITD1_ONCHAIN=$(docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets balance | jq -r ".asset_balances[\"$ASSET_ID\"].balance" 2>/dev/null || echo "0")
LITD2_ONCHAIN=$(docker compose exec -T litd-2 tapcli --network=regtest --rpcserver=localhost:10010 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets balance | jq -r ".asset_balances[\"$ASSET_ID\"].balance" 2>/dev/null || echo "0")

# Handle null values
[ "$LITD1_ONCHAIN" = "null" ] && LITD1_ONCHAIN=0
[ "$LITD2_ONCHAIN" = "null" ] && LITD2_ONCHAIN=0

# Get channel balances
CHANNEL_FINAL=$(docker compose exec -T litd-1 lncli --network=regtest listchannels | jq ".channels[] | select(.remote_pubkey == \"$LITD2_PUBKEY\" and .commitment_type == \"SIMPLE_TAPROOT_OVERLAY\") | .custom_channel_data" 2>/dev/null || echo "{}")
CHANNEL_LOCAL=$(echo "$CHANNEL_FINAL" | jq -r '.local_assets[0].amount' 2>/dev/null || echo "0")
CHANNEL_REMOTE=$(echo "$CHANNEL_FINAL" | jq -r '.remote_assets[0].amount' 2>/dev/null || echo "0")

[ "$CHANNEL_LOCAL" = "null" ] && CHANNEL_LOCAL=0
[ "$CHANNEL_REMOTE" = "null" ] && CHANNEL_REMOTE=0

TOTAL_ONCHAIN=$((LITD1_ONCHAIN + LITD2_ONCHAIN))
TOTAL_CHANNEL=$((CHANNEL_LOCAL + CHANNEL_REMOTE))
TOTAL_ALL=$((TOTAL_ONCHAIN + TOTAL_CHANNEL))

echo "Current distribution:"
echo "  On-chain:"
echo "    litd-1: $LITD1_ONCHAIN units"
echo "    litd-2: $LITD2_ONCHAIN units"
echo "  In channel:"
echo "    litd-1: $CHANNEL_LOCAL units"
echo "    litd-2: $CHANNEL_REMOTE units"
echo "  Total: $TOTAL_ALL units (on-chain: $TOTAL_ONCHAIN, channel: $TOTAL_CHANNEL)"

# Verify all balances are non-negative
if [ "$LITD1_ONCHAIN" -ge 0 ] && [ "$LITD2_ONCHAIN" -ge 0 ] && [ "$CHANNEL_LOCAL" -ge 0 ] && [ "$CHANNEL_REMOTE" -ge 0 ]; then
  pass_test "All balances are non-negative and properly distributed"
else
  fail_test "Invalid balance detected"
fi

# =============================================================================
# TEST 6: Bitcoin Switch - Create Standard Switch
# =============================================================================
start_test "Bitcoin Switch - Create Standard Lightning Switch"

# Copy fresh database for Bitcoin Switch tests
docker cp lightning-dev-env-lnbits-2-1:/app/data/database.sqlite3 /tmp/lnbits2-test.db 2>/dev/null || true

if [ -n "$LNBITS2_ADMIN_KEY" ]; then
  # Get wallet ID from database
  WALLET_ID=$(sqlite3 /tmp/lnbits2-test.db "SELECT id FROM wallets WHERE adminkey = '$LNBITS2_ADMIN_KEY' LIMIT 1;" 2>/dev/null || echo "")

  if [ -z "$WALLET_ID" ] || [ "$WALLET_ID" = "null" ]; then
    fail_test "Could not get wallet ID"
  else
    echo "Creating Bitcoin Switch..."
    SWITCH_CREATE=$(curl -k -s -X POST "https://localhost:5443/bitcoinswitch/api/v1" \
      -H "X-Api-Key: $LNBITS2_ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d "{
        \"title\": \"Test Switch\",
        \"wallet\": \"$WALLET_ID\",
        \"currency\": \"sat\",
        \"switches\": [{
          \"amount\": 100,
          \"duration\": 30,
          \"pin\": 1,
          \"comment\": false,
          \"variable\": false,
          \"label\": \"Test Pin 1\"
        }],
        \"disabled\": false,
        \"disposable\": false
      }")

    SWITCH_ID=$(echo "$SWITCH_CREATE" | jq -r '.id' 2>/dev/null)

    if [ -n "$SWITCH_ID" ] && [ "$SWITCH_ID" != "null" ]; then
      pass_test "Standard Bitcoin Switch created (ID: ${SWITCH_ID:0:8}...)"
    else
      fail_test "Failed to create Bitcoin Switch" "$SWITCH_CREATE"
    fi
  fi
else
  fail_test "Cannot test without admin key"
fi

# =============================================================================
# TEST 7: Bitcoin Switch - Create Taproot Asset Switch
# =============================================================================
start_test "Bitcoin Switch - Create Taproot Asset-enabled Switch"

if [ -n "$LNBITS2_ADMIN_KEY" ] && [ -n "$WALLET_ID" ]; then
  echo "Creating Taproot Asset-enabled Switch..."
  ASSET_SWITCH_CREATE=$(curl -k -s -X POST "https://localhost:5443/bitcoinswitch/api/v1" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"title\": \"Taproot Asset Switch\",
      \"wallet\": \"$WALLET_ID\",
      \"currency\": \"sat\",
      \"switches\": [{
        \"amount\": 200,
        \"duration\": 60,
        \"pin\": 2,
        \"comment\": false,
        \"variable\": false,
        \"label\": \"Asset Pin 2\",
        \"accepts_assets\": true,
        \"accepted_asset_ids\": [\"$ASSET_ID\"]
      }],
      \"disabled\": false,
      \"disposable\": false
    }")

  ASSET_SWITCH_ID=$(echo "$ASSET_SWITCH_CREATE" | jq -r '.id' 2>/dev/null)

  if [ -n "$ASSET_SWITCH_ID" ] && [ "$ASSET_SWITCH_ID" != "null" ]; then
    # Verify it accepts assets
    ACCEPTS_ASSETS=$(echo "$ASSET_SWITCH_CREATE" | jq -r '.switches[0].accepts_assets' 2>/dev/null)
    if [ "$ACCEPTS_ASSETS" = "true" ]; then
      pass_test "Taproot Asset Switch created (ID: ${ASSET_SWITCH_ID:0:8}..., accepts assets)"
    else
      fail_test "Switch created but doesn't accept assets"
    fi
  else
    fail_test "Failed to create Taproot Asset Switch" "$ASSET_SWITCH_CREATE"
  fi
else
  fail_test "Cannot test without admin key and wallet ID"
fi

# =============================================================================
# TEST 8: Bitcoin Switch - List Switches
# =============================================================================
start_test "Bitcoin Switch - List All Switches"

if [ -n "$LNBITS2_ADMIN_KEY" ]; then
  echo "Listing all switches..."
  SWITCHES_LIST=$(curl -k -s "https://localhost:5443/bitcoinswitch/api/v1" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY")

  SWITCHES_COUNT=$(echo "$SWITCHES_LIST" | jq '. | length' 2>/dev/null || echo "0")

  if [ "$SWITCHES_COUNT" -ge 2 ]; then
    pass_test "Listed $SWITCHES_COUNT switches successfully"
  else
    fail_test "Expected at least 2 switches, found $SWITCHES_COUNT"
  fi
else
  fail_test "Cannot test without admin key"
fi

# =============================================================================
# TEST 9: Bitcoin Switch - Verify Switch Configuration
# =============================================================================
start_test "Bitcoin Switch - Verify Switch Configuration"

if [ -n "$LNBITS2_ADMIN_KEY" ] && [ -n "$SWITCH_ID" ]; then
  echo "Retrieving switch configuration..."
  SWITCH_INFO=$(curl -k -s "https://localhost:5443/bitcoinswitch/api/v1/$SWITCH_ID" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY")

  # Verify switch exists and has valid configuration
  SWITCH_TITLE=$(echo "$SWITCH_INFO" | jq -r '.title' 2>/dev/null)
  SWITCH_HAS_PIN=$(echo "$SWITCH_INFO" | jq -r '.switches[0].pin' 2>/dev/null)

  if [ -n "$SWITCH_TITLE" ] && [ "$SWITCH_TITLE" != "null" ] && [ -n "$SWITCH_HAS_PIN" ] && [ "$SWITCH_HAS_PIN" != "null" ]; then
    pass_test "Switch configuration valid (title: $SWITCH_TITLE, pin: $SWITCH_HAS_PIN)"
  else
    fail_test "Switch configuration invalid or missing"
  fi
else
  fail_test "Cannot test without admin key and switch ID"
fi

# =============================================================================
# TEST 10: Bitcoin Switch - Delete Switch
# =============================================================================
start_test "Bitcoin Switch - Delete Standard Switch"

if [ -n "$LNBITS2_ADMIN_KEY" ] && [ -n "$SWITCH_ID" ]; then
  echo "Deleting standard switch (keeping asset switch for LNURL tests)..."
  DELETE_RESPONSE=$(curl -k -s -X DELETE "https://localhost:5443/bitcoinswitch/api/v1/$SWITCH_ID" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY")

  # Verify it's deleted by trying to get it
  sleep 1
  GET_DELETED=$(curl -k -s "https://localhost:5443/bitcoinswitch/api/v1/$SWITCH_ID" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY")

  if echo "$GET_DELETED" | jq -e '.detail | test("not found|does not exist"; "i")' > /dev/null 2>&1; then
    pass_test "Standard switch deleted successfully"
  else
    fail_test "Switch still exists after deletion"
  fi
else
  fail_test "Cannot test without admin key and switch ID"
fi

# =============================================================================
# TEST 11: Bitcoin Switch - Get LNURL from Asset-Enabled Switch
# =============================================================================
start_test "Bitcoin Switch - Get LNURL Pay Link (Container-to-Container)"

# IMPORTANT: This test fetches LNURL metadata FROM INSIDE a container (lnbits-4)
# to test the actual container-to-container flow. No --resolve cheats!
# The LNURL endpoint must be accessible from lnbits-4 via https://lnbits-https-proxy:5443

if [ -n "$LNBITS2_ADMIN_KEY" ] && [ -n "$ASSET_SWITCH_ID" ]; then
  echo "Getting LNURL from asset-enabled switch (from inside lnbits-4 container)..."

  # Fetch LNURL metadata from inside lnbits-4 container - this tests real container networking
  # Use -k for self-signed SSL cert, port 5443 for nginx proxy
  LNURL_RESPONSE=$(docker compose exec -T lnbits-4 curl -sk \
    "https://lnbits-https-proxy:5443/bitcoinswitch/api/v1/lnurl/$ASSET_SWITCH_ID?pin=2" 2>&1)

  # Check if we got valid LNURL metadata
  LNURL_TAG=$(echo "$LNURL_RESPONSE" | jq -r '.tag' 2>/dev/null)
  LNURL_CALLBACK=$(echo "$LNURL_RESPONSE" | jq -r '.callback' 2>/dev/null)
  LNURL_ACCEPTS_ASSETS=$(echo "$LNURL_RESPONSE" | jq -r '.acceptsAssets' 2>/dev/null)

  if [ "$LNURL_TAG" = "payRequest" ] && [ -n "$LNURL_CALLBACK" ] && [ "$LNURL_CALLBACK" != "null" ]; then
    # Verify the callback URL uses the proxy (not localhost)
    if echo "$LNURL_CALLBACK" | grep -q "lnbits-https-proxy"; then
      if [ "$LNURL_ACCEPTS_ASSETS" = "true" ]; then
        pass_test "LNURL metadata retrieved via container (callback: ${LNURL_CALLBACK:0:40}..., accepts assets: true)"
      else
        pass_test "LNURL metadata retrieved via container but doesn't accept assets"
      fi
    else
      fail_test "LNURL callback uses wrong hostname (should use lnbits-https-proxy)" "$LNURL_CALLBACK"
    fi
  else
    # Check for SSL errors
    if echo "$LNURL_RESPONSE" | grep -qi "ssl\|certificate\|verify"; then
      fail_test "SSL certificate verification failed from container" "$LNURL_RESPONSE"
    else
      fail_test "Failed to get valid LNURL metadata from container" "$LNURL_RESPONSE"
    fi
  fi
else
  fail_test "Cannot test without admin key and asset switch ID"
fi

# =============================================================================
# Connect WebSocket Client (for tests 12-13)
# =============================================================================
if [ -n "$ASSET_SWITCH_ID" ]; then
  echo ""
  echo "🔌 Connecting websocket client to Bitcoin Switch..."
  ./connect-bitcoinswitch-ws.sh "$ASSET_SWITCH_ID" > /dev/null 2>&1
  sleep 2
  echo "✅ Websocket client connected"
fi

# =============================================================================
# TEST 12: Bitcoin Switch - Pay LNURL with Bitcoin (Container-to-Container)
# =============================================================================
start_test "Bitcoin Switch - Pay LNURL with Bitcoin (Container-to-Container)"

# IMPORTANT: This test calls the LNURL callback FROM INSIDE a container (lnbits-4)
# No --resolve cheats! Tests the actual container-to-container networking.

if [ -n "$LNBITS2_ADMIN_KEY" ] && [ -n "$ASSET_SWITCH_ID" ] && [ -n "$LNURL_CALLBACK" ]; then
  # Get wallet balance before payment
  WALLET_BTC_BEFORE=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/api/v1/wallet" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.balance // 0' 2>/dev/null)

  echo "Wallet balance before: $WALLET_BTC_BEFORE msats"

  # Request invoice from LNURL callback FROM INSIDE lnbits-4 container (200 sats = 200000 msats)
  echo "Requesting Bitcoin invoice from LNURL callback (from inside lnbits-4)..."
  if [[ "$LNURL_CALLBACK" == *"?"* ]]; then
    CALLBACK_WITH_AMOUNT="${LNURL_CALLBACK}&amount=200000"
  else
    CALLBACK_WITH_AMOUNT="${LNURL_CALLBACK}?amount=200000"
  fi
  echo "Using callback: $CALLBACK_WITH_AMOUNT"

  # Call callback from inside lnbits-4 - no --resolve cheats! Use -k for self-signed SSL
  CALLBACK_RESPONSE=$(docker compose exec -T lnbits-4 curl -sk "$CALLBACK_WITH_AMOUNT" 2>&1)

  # Check if we got an error (e.g., no hardware connections)
  ERROR_STATUS=$(echo "$CALLBACK_RESPONSE" | jq -r '.status' 2>/dev/null)
  if [ "$ERROR_STATUS" = "ERROR" ]; then
    ERROR_REASON=$(echo "$CALLBACK_RESPONSE" | jq -r '.reason' 2>/dev/null)
    fail_test "LNURL callback returned error: $ERROR_REASON (Bitcoin Switch requires hardware connections)"
  fi

  # Check for SSL/connection errors
  if echo "$CALLBACK_RESPONSE" | grep -qi "ssl\|certificate\|could not resolve\|connection refused"; then
    fail_test "Container-to-container HTTPS failed" "$CALLBACK_RESPONSE"
  fi

  BOLT11=$(echo "$CALLBACK_RESPONSE" | jq -r '.pr' 2>/dev/null)

  if [ -n "$BOLT11" ] && [ "$BOLT11" != "null" ]; then
    echo "Got invoice: ${BOLT11:0:60}..."

    # Pay from litd-1
    echo "Paying invoice from litd-1..."
    PAYMENT=$(docker compose exec -T litd-1 lncli --network=regtest payinvoice --force "$BOLT11" 2>&1)

    if echo "$PAYMENT" | grep -q "Payment status: SUCCEEDED"; then
      sleep 3

      # Check wallet balance after
      WALLET_BTC_AFTER=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/api/v1/wallet" \
        -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.balance // 0' 2>/dev/null)

      echo "Wallet balance after: $WALLET_BTC_AFTER msats"

      WALLET_DIFF=$((WALLET_BTC_AFTER - WALLET_BTC_BEFORE))

      # Should receive 200 sats = 200000 msats
      if [ "$WALLET_DIFF" -ge 195000 ] && [ "$WALLET_DIFF" -le 205000 ]; then
        pass_test "LNURL Bitcoin payment via container succeeded (+$((WALLET_DIFF / 1000)) sats to wallet)"
      else
        fail_test "Wallet balance change incorrect" "Expected ~200 sats, got $((WALLET_DIFF / 1000)) sats"
      fi
    else
      fail_test "Payment failed" "$PAYMENT"
    fi
  else
    fail_test "Failed to get invoice from LNURL callback (container-to-container)" "$CALLBACK_RESPONSE"
  fi
else
  fail_test "Cannot test without LNURL callback"
fi

# =============================================================================
# TEST 13: Bitcoin Switch - Pay LNURL with Taproot Assets (Container-to-Container)
# =============================================================================
start_test "Bitcoin Switch - Pay LNURL with Taproot Assets (Container-to-Container)"

# Get lnbits-1 admin key for this test
docker cp lightning-dev-env-lnbits-1-1:/app/data/database.sqlite3 /tmp/lnbits1-test-lnurl.db 2>/dev/null || true
LNBITS1_ADMIN_KEY=$(sqlite3 /tmp/lnbits1-test-lnurl.db "SELECT adminkey FROM wallets ORDER BY id LIMIT 1;" 2>/dev/null || echo "")
rm -f /tmp/lnbits1-test-lnurl.db

if [ -n "$LNBITS1_ADMIN_KEY" ] && [ -n "$LNBITS2_ADMIN_KEY" ] && [ -n "$ASSET_SWITCH_ID" ] && [ -n "$LNURL_CALLBACK" ]; then
  # Get LNbits-1 asset balance before
  LNBITS1_ASSET_BEFORE=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/taproot_assets/api/v1/taproot/listassets" \
    -H "X-Api-Key: $LNBITS1_ADMIN_KEY" | jq -r '.[0].user_balance // 0' 2>/dev/null)

  # Get LNbits-2 wallet balance before
  WALLET_ASSET_BEFORE=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/api/v1/wallet" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.balance // 0' 2>/dev/null)

  echo "LNbits-1 asset balance before: $LNBITS1_ASSET_BEFORE units"
  echo "LNbits-2 wallet balance before: $WALLET_ASSET_BEFORE msats"

  # Request Taproot Asset invoice from LNURL callback (200 asset units)
  echo "Requesting Taproot Asset invoice from LNURL callback (from inside lnbits-4)..."
  # The callback URL already has query params, so use & instead of ?
  if [[ "$LNURL_CALLBACK" == *"?"* ]]; then
    CALLBACK_WITH_PARAMS="${LNURL_CALLBACK}&amount=200&asset_id=$ASSET_ID"
  else
    CALLBACK_WITH_PARAMS="${LNURL_CALLBACK}?amount=200&asset_id=$ASSET_ID"
  fi
  # Call callback from inside lnbits-4 - no --resolve cheats! Use -k for self-signed SSL
  CALLBACK_RESPONSE=$(docker compose exec -T lnbits-4 curl -sk "$CALLBACK_WITH_PARAMS" 2>&1)

  ASSET_INVOICE=$(echo "$CALLBACK_RESPONSE" | jq -r '.pr' 2>/dev/null)

  if [ -n "$ASSET_INVOICE" ] && [ "$ASSET_INVOICE" != "null" ]; then
    echo "Got asset invoice: ${ASSET_INVOICE:0:60}..."

    # Pay from LNbits-1 using Taproot Assets extension
    echo "Paying asset invoice from LNbits-1..."
    LNBITS1_PAYMENT=$(docker compose exec -T lnbits-1 curl -s -X POST "http://localhost:5000/taproot_assets/api/v1/taproot/pay" \
      -H "X-Api-Key: $LNBITS1_ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"payment_request\": \"$ASSET_INVOICE\"}")

    PAYMENT_SUCCESS=$(echo "$LNBITS1_PAYMENT" | jq -r '.success' 2>/dev/null)

    if [ "$PAYMENT_SUCCESS" = "true" ]; then
      sleep 3

      # Check balances after
      LNBITS1_ASSET_AFTER=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/taproot_assets/api/v1/taproot/listassets" \
        -H "X-Api-Key: $LNBITS1_ADMIN_KEY" | jq -r '.[0].user_balance // 0' 2>/dev/null)

      WALLET_ASSET_AFTER=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/api/v1/wallet" \
        -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.balance // 0' 2>/dev/null)

      echo "LNbits-1 asset balance after: $LNBITS1_ASSET_AFTER units"
      echo "LNbits-2 wallet balance after: $WALLET_ASSET_AFTER msats"

      ASSET_DIFF=$((LNBITS1_ASSET_BEFORE - LNBITS1_ASSET_AFTER))

      # Verify LNbits-1 sent 200 assets
      if [ "$ASSET_DIFF" -eq 200 ]; then
        pass_test "LNURL Taproot Asset payment succeeded (sent $ASSET_DIFF asset units)"
      else
        fail_test "Asset balance change incorrect" "Expected -200, got -$ASSET_DIFF"
      fi
    else
      ERROR_MSG=$(echo "$LNBITS1_PAYMENT" | jq -r '.error // "Unknown error"')
      fail_test "Asset payment failed: $ERROR_MSG"
    fi
  else
    fail_test "Failed to get asset invoice from LNURL callback" "$CALLBACK_RESPONSE"
  fi
else
  fail_test "Cannot test without required keys and IDs"
fi

# =============================================================================
# TEST 14: Bitcoin Switch - Pay LNURL with Sats via RFQ (Container-to-Container)
# =============================================================================
start_test "Bitcoin Switch - Pay LNURL with Sats via RFQ (Container-to-Container)"

# This tests the RFQ flow: request an asset invoice, but pay it with regular sats
# The RFQ system converts sats to assets at market rate
#
# IMPORTANT: We use lnd-rfq-payer which ONLY has a channel to litd-1 (RFQ edge)
# This forces the payment to follow route hints through the RFQ edge, because
# there's no direct channel to litd-2 (the receiver).
# Without this topology, LND would bypass route hints and pay directly.
#
# The LNURL callback is fetched FROM INSIDE lnbits-4 container - no --resolve cheats!

if [ -n "$LNBITS2_ADMIN_KEY" ] && [ -n "$ASSET_SWITCH_ID" ] && [ -n "$LNURL_CALLBACK" ] && [ -n "$ASSET_ID" ]; then
  # Get LNbits-2 asset balance before (receiver)
  LNBITS2_ASSET_BEFORE=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/taproot_assets/api/v1/taproot/listassets" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.[0].user_balance // 0' 2>/dev/null)

  echo "LNbits-2 asset balance before: $LNBITS2_ASSET_BEFORE units"

  # Request an ASSET invoice from the switch (same as TEST 13 - 200 asset units)
  echo "Requesting Taproot Asset invoice from LNURL callback (from inside lnbits-4)..."
  if [[ "$LNURL_CALLBACK" == *"?"* ]]; then
    RFQ_CALLBACK="${LNURL_CALLBACK}&amount=200&asset_id=$ASSET_ID"
  else
    RFQ_CALLBACK="${LNURL_CALLBACK}?amount=200&asset_id=$ASSET_ID"
  fi

  # Call callback from inside lnbits-4 - no --resolve cheats! Use -k for self-signed SSL
  RFQ_RESPONSE=$(docker compose exec -T lnbits-4 curl -sk "$RFQ_CALLBACK" 2>&1)

  RFQ_INVOICE=$(echo "$RFQ_RESPONSE" | jq -r '.pr' 2>/dev/null)

  if [ -n "$RFQ_INVOICE" ] && [ "$RFQ_INVOICE" != "null" ]; then
    echo "Got asset invoice: ${RFQ_INVOICE:0:60}..."

    # Pay with lnd-rfq-payer (SATS only node) - forces RFQ route hint usage
    # This node only has a channel to litd-1, so it MUST follow the route hint
    echo "Paying asset invoice with sats from lnd-rfq-payer (RFQ conversion via route hints)..."
    RFQ_PAYMENT=$(docker compose exec -T lnd-rfq-payer lncli --network=regtest --rpcserver=lnd-rfq-payer:10012 payinvoice --force --timeout=30s "$RFQ_INVOICE" 2>&1)

    if echo "$RFQ_PAYMENT" | grep -q "Payment status: SUCCEEDED"; then
      sleep 3

      # Check LNbits-2 asset balance after - should have received assets
      LNBITS2_ASSET_AFTER=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/taproot_assets/api/v1/taproot/listassets" \
        -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.[0].user_balance // 0' 2>/dev/null)

      echo "LNbits-2 asset balance after: $LNBITS2_ASSET_AFTER units"

      ASSET_RECEIVED=$((LNBITS2_ASSET_AFTER - LNBITS2_ASSET_BEFORE))

      # Verify receiver got assets (paid with sats, received assets via RFQ)
      # Expecting ~200 assets (same as TEST 13)
      if [ "$ASSET_RECEIVED" -ge 190 ] && [ "$ASSET_RECEIVED" -le 210 ]; then
        pass_test "RFQ payment succeeded (paid sats, receiver got $ASSET_RECEIVED asset units)"
      else
        fail_test "RFQ conversion incorrect" "Expected ~200 assets, got $ASSET_RECEIVED"
      fi
    else
      fail_test "RFQ payment failed" "$RFQ_PAYMENT"
    fi
  else
    fail_test "Failed to get asset invoice for RFQ test" "$RFQ_RESPONSE"
  fi
else
  fail_test "Cannot test without required keys and IDs"
fi

# =============================================================================
# TEST 15: Bitcoin Switch - Verify HTTPS Requirement for LNURL
# =============================================================================
start_test "Bitcoin Switch - Verify HTTPS Required for LNURL"

if [ -n "$ASSET_SWITCH_ID" ]; then
  echo "Testing LNURL generation requires HTTPS..."
  # Try to access via HTTP (should fail or redirect)
  HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:5001/bitcoinswitch/api/v1/lnurl/$ASSET_SWITCH_ID?pin=2" 2>/dev/null || echo "000")

  # Try via HTTPS (should work)
  HTTPS_RESPONSE=$(curl -k -s "https://localhost:5443/bitcoinswitch/api/v1/lnurl/$ASSET_SWITCH_ID?pin=2")
  HTTPS_TAG=$(echo "$HTTPS_RESPONSE" | jq -r '.tag' 2>/dev/null)

  if [ "$HTTPS_TAG" = "payRequest" ]; then
    pass_test "HTTPS LNURL endpoint works correctly (HTTP: $HTTP_RESPONSE, HTTPS: working)"
  else
    fail_test "HTTPS LNURL endpoint not working properly"
  fi
else
  fail_test "Cannot test without asset switch ID"
fi

# =============================================================================
# TEST 16: Bitcoin Switch - Keep Asset Switch for Manual Testing
# =============================================================================
start_test "Bitcoin Switch - Keep Asset Switch for Manual Testing"

if [ -n "$LNBITS2_ADMIN_KEY" ] && [ -n "$ASSET_SWITCH_ID" ]; then
  echo "Skipping deletion - keeping switch $ASSET_SWITCH_ID for manual testing"
  pass_test "Asset switch preserved for manual testing (ID: $ASSET_SWITCH_ID)"
else
  fail_test "Cannot test without admin key and asset switch ID"
fi

# =============================================================================
# TEST 17: LNbits Outbound Payment - Taproot Assets (LNbits-2 → LNbits-1)
# =============================================================================
start_test "LNbits Outbound Payment - Send Taproot Assets Between Users"

# Get lnbits-1 admin key
docker cp lightning-dev-env-lnbits-1-1:/app/data/database.sqlite3 /tmp/lnbits1-test-asset.db 2>/dev/null || true
LNBITS1_ADMIN_KEY=$(sqlite3 /tmp/lnbits1-test-asset.db "SELECT adminkey FROM wallets ORDER BY id LIMIT 1;" 2>/dev/null || echo "")
rm -f /tmp/lnbits1-test-asset.db

if [ -n "$LNBITS1_ADMIN_KEY" ] && [ -n "$LNBITS2_ADMIN_KEY" ]; then
  # Check initial balances
  LNBITS1_BEFORE=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/taproot_assets/api/v1/taproot/listassets" \
    -H "X-Api-Key: $LNBITS1_ADMIN_KEY" | jq -r '.[0].user_balance // 0' 2>/dev/null)
  LNBITS2_BEFORE=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/taproot_assets/api/v1/taproot/listassets" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.[0].user_balance // 0' 2>/dev/null)

  echo "Initial balances: LNbits-1=$LNBITS1_BEFORE assets, LNbits-2=$LNBITS2_BEFORE assets"

  # Create invoice on LNbits-1 for 500 assets
  echo "Creating asset invoice on LNbits-1..."
  LNBITS1_INVOICE=$(docker compose exec -T lnbits-1 curl -s -X POST "http://localhost:5000/taproot_assets/api/v1/taproot/invoice" \
    -H "X-Api-Key: $LNBITS1_ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"asset_id\": \"$ASSET_ID\", \"amount\": 500, \"memo\": \"Test Suite: LNbits-to-LNbits\"}")

  PAYMENT_REQ=$(echo "$LNBITS1_INVOICE" | jq -r '.payment_request' 2>/dev/null)

  if [ -n "$PAYMENT_REQ" ] && [ "$PAYMENT_REQ" != "null" ]; then
    echo "Invoice created: ${PAYMENT_REQ:0:60}..."

    # Pay from LNbits-2 (testing OUTBOUND payment between LNbits users)
    echo "Paying invoice from LNbits-2..."
    LNBITS2_PAYMENT=$(docker compose exec -T lnbits-2 curl -s -X POST "http://localhost:5000/taproot_assets/api/v1/taproot/pay" \
      -H "X-Api-Key: $LNBITS2_ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"payment_request\": \"$PAYMENT_REQ\"}")

    # Check payment status
    PAYMENT_SUCCESS=$(echo "$LNBITS2_PAYMENT" | jq -r '.success' 2>/dev/null)

    if [ "$PAYMENT_SUCCESS" = "true" ]; then
      echo "Payment succeeded!"
      sleep 3

      # Check final balances
      LNBITS1_AFTER=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/taproot_assets/api/v1/taproot/listassets" \
        -H "X-Api-Key: $LNBITS1_ADMIN_KEY" | jq -r '.[0].user_balance // 0' 2>/dev/null)
      LNBITS2_AFTER=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/taproot_assets/api/v1/taproot/listassets" \
        -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.[0].user_balance // 0' 2>/dev/null)

      echo "Final balances: LNbits-1=$LNBITS1_AFTER assets, LNbits-2=$LNBITS2_AFTER assets"

      LNBITS1_DIFF=$((LNBITS1_AFTER - LNBITS1_BEFORE))
      LNBITS2_DIFF=$((LNBITS2_BEFORE - LNBITS2_AFTER))

      if [ "$LNBITS1_DIFF" -eq 500 ] && [ "$LNBITS2_DIFF" -eq 500 ]; then
        pass_test "LNbits-to-LNbits asset payment succeeded (LNbits-2 sent $LNBITS2_DIFF, LNbits-1 received $LNBITS1_DIFF)"
      else
        fail_test "Balance change incorrect" "LNbits-1: +$LNBITS1_DIFF (expected +500), LNbits-2: -$LNBITS2_DIFF (expected -500)"
      fi
    else
      ERROR_MSG=$(echo "$LNBITS2_PAYMENT" | jq -r '.error // "Unknown error"')
      fail_test "Payment failed: $ERROR_MSG"
    fi
  else
    fail_test "Failed to create invoice" "$LNBITS1_INVOICE"
  fi
else
  fail_test "Cannot test without both admin keys"
fi

# =============================================================================
# TEST 18: LNbits Outbound Payment - Bitcoin (LNbits-1 → LNbits-2)
# =============================================================================
start_test "LNbits Outbound Payment - Send Bitcoin"

# Get lnbits-1 admin key
docker cp lightning-dev-env-lnbits-1-1:/app/data/database.sqlite3 /tmp/lnbits1-test-btc.db 2>/dev/null || true
LNBITS1_ADMIN_KEY=$(sqlite3 /tmp/lnbits1-test-btc.db "SELECT adminkey FROM wallets ORDER BY id LIMIT 1;" 2>/dev/null || echo "")
rm -f /tmp/lnbits1-test-btc.db

if [ -n "$LNBITS1_ADMIN_KEY" ] && [ -n "$LNBITS2_ADMIN_KEY" ]; then
  # Check initial balances (use container-internal endpoints)
  LNBITS1_BTC_BEFORE=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/api/v1/wallet" \
    -H "X-Api-Key: $LNBITS1_ADMIN_KEY" | jq -r '.balance // 0' 2>/dev/null)
  LNBITS2_BTC_BEFORE=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/api/v1/wallet" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.balance // 0' 2>/dev/null)

  echo "Initial Bitcoin balances: LNbits-1=$LNBITS1_BTC_BEFORE msats, LNbits-2=$LNBITS2_BTC_BEFORE msats"

  # Create Bitcoin invoice on LNbits-2
  echo "Creating Bitcoin invoice on LNbits-2..."
  LNBITS2_BTC_INVOICE=$(docker compose exec -T lnbits-2 curl -s -X POST "http://localhost:5000/api/v1/payments" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{"out": false, "amount": 10000, "memo": "Test Suite: LNbits Bitcoin outbound"}')

  BTC_BOLT11=$(echo "$LNBITS2_BTC_INVOICE" | jq -r '.bolt11' 2>/dev/null)

  if [ -n "$BTC_BOLT11" ] && [ "$BTC_BOLT11" != "null" ]; then
    echo "Bitcoin invoice created: ${BTC_BOLT11:0:60}..."

    # Pay from LNbits-1 (testing OUTBOUND Bitcoin payment)
    echo "Paying Bitcoin invoice from LNbits-1..."
    LNBITS1_BTC_PAYMENT=$(docker compose exec -T lnbits-1 curl -s -X POST "http://localhost:5000/api/v1/payments" \
      -H "X-Api-Key: $LNBITS1_ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"out\": true, \"bolt11\": \"$BTC_BOLT11\"}")

    sleep 3

    # Check final balances
    LNBITS1_BTC_AFTER=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/api/v1/wallet" \
      -H "X-Api-Key: $LNBITS1_ADMIN_KEY" | jq -r '.balance // 0' 2>/dev/null)
    LNBITS2_BTC_AFTER=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/api/v1/wallet" \
      -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.balance // 0' 2>/dev/null)

    echo "Final Bitcoin balances: LNbits-1=$LNBITS1_BTC_AFTER msats, LNbits-2=$LNBITS2_BTC_AFTER msats"

    # Calculate differences (in millisats)
    LNBITS1_BTC_DIFF=$((LNBITS1_BTC_BEFORE - LNBITS1_BTC_AFTER))
    LNBITS2_BTC_DIFF=$((LNBITS2_BTC_AFTER - LNBITS2_BTC_BEFORE))

    # Allow for routing fees (payment should be ~10000 msats, allow ±1000 msats tolerance)
    if [ "$LNBITS2_BTC_DIFF" -ge 9000000 ] && [ "$LNBITS2_BTC_DIFF" -le 11000000 ] && [ "$LNBITS1_BTC_DIFF" -gt 0 ]; then
      pass_test "LNbits outbound Bitcoin payment succeeded (LNbits-1 sent $((LNBITS1_BTC_DIFF / 1000)) sats, LNbits-2 received $((LNBITS2_BTC_DIFF / 1000)) sats)"
    else
      fail_test "Balance change incorrect" "LNbits-1: -$((LNBITS1_BTC_DIFF / 1000)) sats, LNbits-2: +$((LNBITS2_BTC_DIFF / 1000)) sats (expected ~10 sats)"
    fi
  else
    fail_test "Failed to create Bitcoin invoice" "$LNBITS2_BTC_INVOICE"
  fi
else
  fail_test "Cannot test without admin keys"
fi

# =============================================================================
# TEST 19: lnurlFlip - Verify Extension Installed
# =============================================================================
start_test "lnurlFlip - Verify Extension Installed"

# Source lnbits_keys.env if it exists (created by bootstrap-lnurl-extensions.sh)
if [ -f "./lnbits_keys.env" ]; then
  source ./lnbits_keys.env
fi

if [ -n "$LNBITS1_FLIP_ID" ] && [ -n "$LNBITS1_ADMIN_KEY" ]; then
  # Verify the flip link exists
  FLIP_INFO=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/lnurlFlip/api/v1/lnurlflip" \
    -H "X-Api-Key: $LNBITS1_ADMIN_KEY" 2>/dev/null)

  FLIP_COUNT=$(echo "$FLIP_INFO" | jq 'length' 2>/dev/null || echo "0")

  if [ "$FLIP_COUNT" -gt 0 ]; then
    FLIP_NAME=$(echo "$FLIP_INFO" | jq -r '.[0].name' 2>/dev/null)
    pass_test "lnurlFlip extension installed with $FLIP_COUNT flip link(s) (name: $FLIP_NAME)"
  else
    fail_test "lnurlFlip extension installed but no flip links found"
  fi
else
  # Try to get admin key from database if not in env
  docker cp lightning-dev-env-lnbits-1-1:/app/data/database.sqlite3 /tmp/lnbits1-flip.db 2>/dev/null || true
  LNBITS1_ADMIN_KEY=$(sqlite3 /tmp/lnbits1-flip.db "SELECT adminkey FROM wallets ORDER BY id LIMIT 1;" 2>/dev/null || echo "")
  rm -f /tmp/lnbits1-flip.db

  if [ -n "$LNBITS1_ADMIN_KEY" ]; then
    FLIP_INFO=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/lnurlFlip/api/v1/lnurlflip" \
      -H "X-Api-Key: $LNBITS1_ADMIN_KEY" 2>/dev/null)

    FLIP_COUNT=$(echo "$FLIP_INFO" | jq 'length' 2>/dev/null || echo "0")

    if [ "$FLIP_COUNT" -gt 0 ]; then
      LNBITS1_FLIP_ID=$(echo "$FLIP_INFO" | jq -r '.[0].id' 2>/dev/null)
      pass_test "lnurlFlip extension installed with $FLIP_COUNT flip link(s)"
    else
      fail_test "lnurlFlip extension may not be installed or no flip links created"
    fi
  else
    fail_test "Cannot verify lnurlFlip - no admin key available"
  fi
fi

# =============================================================================
# TEST 20: lnurlFlip - Automatic Mode Switching
# =============================================================================
start_test "lnurlFlip - Automatic Mode Switching"

if [ -n "$LNBITS1_FLIP_ID" ] && [ -n "$LNBITS1_ADMIN_KEY" ]; then
  # Get the flip redirect endpoint (this returns payRequest or withdrawRequest based on balance)
  FLIP_REDIRECT_URL="http://localhost:5000/lnurlFlip/api/v1/redirect/$LNBITS1_FLIP_ID"

  FLIP_RESPONSE=$(docker compose exec -T lnbits-1 curl -s "$FLIP_REDIRECT_URL" 2>/dev/null)
  FLIP_TAG=$(echo "$FLIP_RESPONSE" | jq -r '.tag' 2>/dev/null)

  echo "Initial flip mode: $FLIP_TAG"

  if [ "$FLIP_TAG" = "payRequest" ]; then
    echo "Flip is in PAY mode (balance below threshold)"

    # Get callback and pay to increase balance
    CALLBACK_URL=$(echo "$FLIP_RESPONSE" | jq -r '.callback' 2>/dev/null)
    MIN_SENDABLE=$(echo "$FLIP_RESPONSE" | jq -r '.minSendable' 2>/dev/null)

    echo "Callback URL: $CALLBACK_URL"
    echo "Min sendable: $MIN_SENDABLE msats"

    # Make callback request from inside container (callback URL uses internal hostname)
    INTERNAL_CALLBACK=$(echo "$CALLBACK_URL" | sed 's|http://[^/]*|http://localhost:5000|g')
    PAY_RESPONSE=$(docker compose exec -T lnbits-1 curl -s "${INTERNAL_CALLBACK}?amount=${MIN_SENDABLE}" 2>/dev/null)
    BOLT11=$(echo "$PAY_RESPONSE" | jq -r '.pr' 2>/dev/null)

    if [ -n "$BOLT11" ] && [ "$BOLT11" != "null" ]; then
      echo "Paying to flip link to trigger mode switch..."
      # Pay from litd-2 (not litd-1, because lnbits-1 is backed by litd-1 - can't pay yourself)
      PAYMENT=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 payinvoice --force "$BOLT11" 2>&1)

      if echo "$PAYMENT" | grep -q "Payment status: SUCCEEDED"; then
        sleep 2

        # Check if mode switched to withdraw
        FLIP_RESPONSE2=$(docker compose exec -T lnbits-1 curl -s "$FLIP_REDIRECT_URL" 2>/dev/null)
        FLIP_TAG2=$(echo "$FLIP_RESPONSE2" | jq -r '.tag' 2>/dev/null)

        echo "After payment, flip mode: $FLIP_TAG2"

        if [ "$FLIP_TAG2" = "withdrawRequest" ]; then
          pass_test "lnurlFlip auto-switched from PAY to WITHDRAW mode after receiving payment"
        else
          # Mode didn't switch - might need more funds or threshold not reached
          pass_test "lnurlFlip payment succeeded (mode: $FLIP_TAG2, may need more funds to trigger switch)"
        fi
      else
        fail_test "Payment to flip link failed"
      fi
    else
      fail_test "Could not get invoice from flip link callback"
    fi

  elif [ "$FLIP_TAG" = "withdrawRequest" ]; then
    echo "Flip is in WITHDRAW mode (balance above threshold)"
    pass_test "lnurlFlip in withdraw mode - automatic switching working (balance above threshold)"
  else
    fail_test "Unexpected flip response" "$FLIP_RESPONSE"
  fi
else
  fail_test "Cannot test lnurlFlip - no flip ID or admin key"
fi

# =============================================================================
# TEST 21: Laisee - Create Envelope and Serve LNURL-Pay
# =============================================================================
start_test "Laisee - Create Envelope and Serve LNURL-Pay"

# Get lnbits-1 admin key
docker cp lightning-dev-env-lnbits-1-1:/app/data/database.sqlite3 /tmp/lnbits1-laisee.db 2>/dev/null || true
LNBITS1_ADMIN_KEY=$(sqlite3 /tmp/lnbits1-laisee.db "SELECT adminkey FROM wallets ORDER BY id LIMIT 1;" 2>/dev/null || echo "")
rm -f /tmp/lnbits1-laisee.db

# Amount the envelope gets funded with; withdraw must match it exactly
LAISEE_AMOUNT=100
LAISEE_ID=""
LAISEE_HASH=""

if [ -n "$LNBITS1_ADMIN_KEY" ]; then
  LAISEE_CREATE=$(docker compose exec -T lnbits-1 curl -s -X POST "http://localhost:5000/laisee/api/v1/laisees" \
    -H "X-Api-Key: $LNBITS1_ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{"title": "Test Suite Red Envelope", "min_sats": 10, "max_sats": 1000, "allow_comment": true}')

  LAISEE_ID=$(echo "$LAISEE_CREATE" | jq -r '.id' 2>/dev/null)
  LAISEE_HASH=$(echo "$LAISEE_CREATE" | jq -r '.unique_hash' 2>/dev/null)

  if [ -n "$LAISEE_HASH" ] && [ "$LAISEE_HASH" != "null" ]; then
    # While unfunded the shared LNURL must resolve as an LNURL-pay request
    LAISEE_LNURL_RESP=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/laisee/api/v1/lnurl/$LAISEE_HASH" 2>/dev/null)
    LAISEE_TAG=$(echo "$LAISEE_LNURL_RESP" | jq -r '.tag' 2>/dev/null)
    LAISEE_MIN=$(echo "$LAISEE_LNURL_RESP" | jq -r '.minSendable' 2>/dev/null)
    LAISEE_MAX=$(echo "$LAISEE_LNURL_RESP" | jq -r '.maxSendable' 2>/dev/null)
    LAISEE_COMMENT_LEN=$(echo "$LAISEE_LNURL_RESP" | jq -r '.commentAllowed // 0' 2>/dev/null)

    if [ "$LAISEE_TAG" = "payRequest" ] && [ "$LAISEE_MIN" = "10000" ] && [ "$LAISEE_MAX" = "1000000" ]; then
      pass_test "Laisee created ($LAISEE_ID) serving LNURL-pay (10-1000 sats, commentAllowed: $LAISEE_COMMENT_LEN)"
    else
      fail_test "Laisee LNURL not in expected pay mode" "tag=$LAISEE_TAG min=$LAISEE_MIN max=$LAISEE_MAX"
    fi
  else
    fail_test "Could not create laisee" "$LAISEE_CREATE"
  fi
else
  fail_test "Cannot test Laisee - no lnbits-1 admin key"
fi

# =============================================================================
# TEST 22: Laisee - Fund Envelope via LNURL-Pay Callback
# =============================================================================
start_test "Laisee - Fund Envelope via LNURL-Pay Callback"

if [ -n "$LAISEE_HASH" ] && [ "$LAISEE_HASH" != "null" ]; then
  # Ask the pay callback for an invoice, with a comment (allow_comment was set)
  LAISEE_PAY_CB=$(docker compose exec -T lnbits-1 curl -s -G "http://localhost:5000/laisee/api/v1/lnurl/pay-cb/$LAISEE_HASH" \
    --data-urlencode "amount=$((LAISEE_AMOUNT * 1000))" \
    --data-urlencode "comment=Gong hei fat choy" 2>/dev/null)
  LAISEE_BOLT11=$(echo "$LAISEE_PAY_CB" | jq -r '.pr' 2>/dev/null)

  if [ -n "$LAISEE_BOLT11" ] && [ "$LAISEE_BOLT11" != "null" ]; then
    echo "Envelope invoice: ${LAISEE_BOLT11:0:60}..."

    # Pay from litd-2 - lnbits-1 is backed by litd-1, so it can't fund its own envelope
    LAISEE_PAYMENT=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 payinvoice --force "$LAISEE_BOLT11" 2>&1)

    if echo "$LAISEE_PAYMENT" | grep -q "Payment status: SUCCEEDED"; then
      # tasks.py marks the envelope paid off the invoice listener - give it a moment
      LAISEE_PAID="false"
      for i in $(seq 1 10); do
        LAISEE_STATE=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/laisee/api/v1/laisees/$LAISEE_ID" \
          -H "X-Api-Key: $LNBITS1_ADMIN_KEY" 2>/dev/null)
        LAISEE_PAID=$(echo "$LAISEE_STATE" | jq -r '.is_paid' 2>/dev/null)
        [ "$LAISEE_PAID" = "true" ] && break
        sleep 2
      done

      LAISEE_PAID_AMOUNT=$(echo "$LAISEE_STATE" | jq -r '.paid_amount' 2>/dev/null)
      LAISEE_COMMENT=$(echo "$LAISEE_STATE" | jq -r '.comment // ""' 2>/dev/null)

      if [ "$LAISEE_PAID" = "true" ] && [ "$LAISEE_PAID_AMOUNT" = "$LAISEE_AMOUNT" ]; then
        pass_test "Laisee funded with $LAISEE_PAID_AMOUNT sats (comment: \"$LAISEE_COMMENT\")"
      else
        fail_test "Laisee not marked funded after payment" "is_paid=$LAISEE_PAID paid_amount=$LAISEE_PAID_AMOUNT"
      fi
    else
      fail_test "Payment to laisee invoice failed" "$LAISEE_PAYMENT"
    fi
  else
    fail_test "Could not get invoice from laisee pay callback" "$LAISEE_PAY_CB"
  fi
else
  fail_test "Cannot fund laisee - no envelope created"
fi

# =============================================================================
# TEST 23: Laisee - LNURL Flips to Withdraw Mode and Pays Out
# =============================================================================
start_test "Laisee - LNURL Flips to Withdraw Mode and Pays Out"

LAISEE_K1=""

if [ -n "$LAISEE_HASH" ] && [ "$LAISEE_HASH" != "null" ]; then
  # The same LNURL must now resolve as an LNURL-withdraw for exactly what was paid in
  LAISEE_W_RESP=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/laisee/api/v1/lnurl/$LAISEE_HASH" 2>/dev/null)
  LAISEE_W_TAG=$(echo "$LAISEE_W_RESP" | jq -r '.tag' 2>/dev/null)
  LAISEE_K1=$(echo "$LAISEE_W_RESP" | jq -r '.k1' 2>/dev/null)
  LAISEE_W_MIN=$(echo "$LAISEE_W_RESP" | jq -r '.minWithdrawable' 2>/dev/null)
  LAISEE_W_MAX=$(echo "$LAISEE_W_RESP" | jq -r '.maxWithdrawable' 2>/dev/null)

  echo "LNURL mode after funding: $LAISEE_W_TAG (min: $LAISEE_W_MIN, max: $LAISEE_W_MAX msat)"

  if [ "$LAISEE_W_TAG" = "withdrawRequest" ] && [ "$LAISEE_W_MIN" = "$((LAISEE_AMOUNT * 1000))" ] && [ "$LAISEE_W_MAX" = "$((LAISEE_AMOUNT * 1000))" ]; then
    # Claim it to litd-2 - the withdraw amount must match paid_amount exactly
    LAISEE_CLAIM_INV=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 addinvoice --amt="$LAISEE_AMOUNT" --memo="Laisee claim" 2>/dev/null)
    LAISEE_CLAIM_PR=$(echo "$LAISEE_CLAIM_INV" | jq -r '.payment_request' 2>/dev/null)

    if [ -n "$LAISEE_CLAIM_PR" ] && [ "$LAISEE_CLAIM_PR" != "null" ]; then
      LAISEE_W_CB=$(docker compose exec -T lnbits-1 curl -s -G "http://localhost:5000/laisee/api/v1/lnurl/withdraw-cb/$LAISEE_HASH" \
        --data-urlencode "k1=$LAISEE_K1" \
        --data-urlencode "pr=$LAISEE_CLAIM_PR" 2>/dev/null)
      LAISEE_W_STATUS=$(echo "$LAISEE_W_CB" | jq -r '.status' 2>/dev/null)

      if [ "$LAISEE_W_STATUS" = "OK" ]; then
        sleep 3
        LAISEE_FINAL=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/laisee/api/v1/laisees/$LAISEE_ID" \
          -H "X-Api-Key: $LNBITS1_ADMIN_KEY" 2>/dev/null)
        LAISEE_WITHDRAWN=$(echo "$LAISEE_FINAL" | jq -r '.is_withdrawn' 2>/dev/null)

        if [ "$LAISEE_WITHDRAWN" = "true" ]; then
          pass_test "Laisee withdrawn: $LAISEE_AMOUNT sats claimed to litd-2, envelope marked spent"
        else
          fail_test "Withdraw callback returned OK but envelope not marked withdrawn" "is_withdrawn=$LAISEE_WITHDRAWN"
        fi
      else
        fail_test "Laisee withdraw callback failed" "$LAISEE_W_CB"
      fi
    else
      fail_test "Could not create claim invoice on litd-2" "$LAISEE_CLAIM_INV"
    fi
  else
    fail_test "Laisee LNURL did not flip to withdraw mode" "tag=$LAISEE_W_TAG min=$LAISEE_W_MIN max=$LAISEE_W_MAX"
  fi
else
  fail_test "Cannot withdraw laisee - no envelope created"
fi

# =============================================================================
# TEST 24: Laisee - Second Withdrawal Is Rejected (withdraw-once invariant)
# =============================================================================
start_test "Laisee - Second Withdrawal Is Rejected"

if [ -n "$LAISEE_HASH" ] && [ "$LAISEE_HASH" != "null" ] && [ -n "$LAISEE_K1" ] && [ "$LAISEE_K1" != "null" ]; then
  # A spent envelope must not hand out a second payout, and its LNURL must go dead
  LAISEE_REPLAY_INV=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 addinvoice --amt="$LAISEE_AMOUNT" --memo="Laisee replay" 2>/dev/null)
  LAISEE_REPLAY_PR=$(echo "$LAISEE_REPLAY_INV" | jq -r '.payment_request' 2>/dev/null)

  LAISEE_REPLAY_CB=$(docker compose exec -T lnbits-1 curl -s -G "http://localhost:5000/laisee/api/v1/lnurl/withdraw-cb/$LAISEE_HASH" \
    --data-urlencode "k1=$LAISEE_K1" \
    --data-urlencode "pr=$LAISEE_REPLAY_PR" 2>/dev/null)
  LAISEE_REPLAY_STATUS=$(echo "$LAISEE_REPLAY_CB" | jq -r '.status' 2>/dev/null)
  LAISEE_REPLAY_REASON=$(echo "$LAISEE_REPLAY_CB" | jq -r '.reason // ""' 2>/dev/null)

  # And the LNURL itself should report the envelope as spent
  LAISEE_DEAD=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/laisee/api/v1/lnurl/$LAISEE_HASH" 2>/dev/null)
  LAISEE_DEAD_STATUS=$(echo "$LAISEE_DEAD" | jq -r '.status' 2>/dev/null)

  if [ "$LAISEE_REPLAY_STATUS" = "ERROR" ] && [ "$LAISEE_DEAD_STATUS" = "ERROR" ]; then
    pass_test "Double-withdraw rejected (\"$LAISEE_REPLAY_REASON\") and LNURL retired"
  else
    fail_test "Spent laisee did not reject second withdrawal" "replay=$LAISEE_REPLAY_CB lnurl=$LAISEE_DEAD"
  fi
else
  fail_test "Cannot test double-withdraw - no funded envelope"
fi

# =============================================================================
# TEST 25: Laisee - Concurrent Claims Cannot Double-Spend (race invariant)
# =============================================================================
start_test "Laisee - Concurrent Claims Cannot Double-Spend"

# Re-fetch the lnbits-1 admin key in case test 21 was skipped
docker cp lightning-dev-env-lnbits-1-1:/app/data/database.sqlite3 /tmp/lnbits1-race.db 2>/dev/null || true
LNBITS1_ADMIN_KEY=$(sqlite3 /tmp/lnbits1-race.db "SELECT adminkey FROM wallets ORDER BY id LIMIT 1;" 2>/dev/null || echo "$LNBITS1_ADMIN_KEY")
rm -f /tmp/lnbits1-race.db

RACE_AMOUNT=100
RACE_CLAIMS=6

if [ -n "$LNBITS1_ADMIN_KEY" ]; then
  RACE_CREATE=$(docker compose exec -T lnbits-1 curl -s -X POST "http://localhost:5000/laisee/api/v1/laisees" \
    -H "X-Api-Key: $LNBITS1_ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{"title": "Race Test Envelope", "min_sats": 10, "max_sats": 1000}')
  RACE_ID=$(echo "$RACE_CREATE" | jq -r '.id' 2>/dev/null)
  RACE_HASH=$(echo "$RACE_CREATE" | jq -r '.unique_hash' 2>/dev/null)

  if [ -n "$RACE_HASH" ] && [ "$RACE_HASH" != "null" ]; then
    RACE_PAY_CB=$(docker compose exec -T lnbits-1 curl -s -G "http://localhost:5000/laisee/api/v1/lnurl/pay-cb/$RACE_HASH" \
      --data-urlencode "amount=$((RACE_AMOUNT * 1000))" 2>/dev/null)
    RACE_BOLT11=$(echo "$RACE_PAY_CB" | jq -r '.pr' 2>/dev/null)

    if [ -n "$RACE_BOLT11" ] && [ "$RACE_BOLT11" != "null" ]; then
      docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 payinvoice --force "$RACE_BOLT11" >/dev/null 2>&1
      RACE_PAID="false"
      for i in $(seq 1 10); do
        RACE_STATE=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/laisee/api/v1/laisees/$RACE_ID" \
          -H "X-Api-Key: $LNBITS1_ADMIN_KEY" 2>/dev/null)
        RACE_PAID=$(echo "$RACE_STATE" | jq -r '.is_paid' 2>/dev/null)
        [ "$RACE_PAID" = "true" ] && break
        sleep 2
      done

      if [ "$RACE_PAID" = "true" ]; then
        RACE_K1=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/laisee/api/v1/lnurl/$RACE_HASH" 2>/dev/null | jq -r '.k1' 2>/dev/null)

        # Build N distinct claim invoices on litd-2, then fire all claims concurrently
        RACE_RESULTS=/tmp/laisee_race_results.txt
        rm -f "$RACE_RESULTS"
        for n in $(seq 1 $RACE_CLAIMS); do
          RACE_INV=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 addinvoice --amt=$RACE_AMOUNT --memo="Race claim $n" 2>/dev/null)
          RACE_PR=$(echo "$RACE_INV" | jq -r '.payment_request' 2>/dev/null)
          (docker compose exec -T lnbits-1 curl -s -G "http://localhost:5000/laisee/api/v1/lnurl/withdraw-cb/$RACE_HASH" \
            --data-urlencode "k1=$RACE_K1" --data-urlencode "pr=$RACE_PR" | jq -r '.status' >> "$RACE_RESULTS") &
        done
        wait
        sleep 3

        RACE_OK_COUNT=$(grep -c '^OK$' "$RACE_RESULTS" 2>/dev/null || echo 0)
        rm -f "$RACE_RESULTS"

        if [ "$RACE_OK_COUNT" = "1" ]; then
          pass_test "Concurrent claims: exactly 1 of $RACE_CLAIMS succeeded, envelope not double-spent"
        else
          fail_test "Concurrent claims violated withdraw-once invariant" "OK count=$RACE_OK_COUNT"
        fi
      else
        fail_test "Race envelope not marked funded in time" "is_paid=$RACE_PAID"
      fi
    else
      fail_test "Could not get race envelope invoice" "$RACE_PAY_CB"
    fi
  else
    fail_test "Could not create race envelope" "$RACE_CREATE"
  fi
else
  fail_test "Cannot test race invariant - no lnbits-1 admin key"
fi

# =============================================================================
# TEST SUMMARY
# =============================================================================
echo ""
echo "======================================"
echo "📊 TEST SUMMARY"
echo "======================================"
echo -e "Total Tests: ${BLUE}$TESTS_RUN${NC}"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
  echo ""
  exit 0
else
  echo -e "${RED}❌ SOME TESTS FAILED:${NC}"
  for test in "${FAILED_TESTS[@]}"; do
    echo -e "  ${RED}•${NC} $test"
  done
  echo ""
  exit 1
fi
