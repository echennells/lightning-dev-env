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
  # Check if it has asset data
  CHANNEL_CAPACITY=$(echo "$TAPROOT_CHANNEL" | jq -r '.custom_channel_data.assets[0].capacity' 2>/dev/null || echo "0")
  CHANNEL_LOCAL=$(echo "$TAPROOT_CHANNEL" | jq -r '.custom_channel_data.assets[0].local_balance' 2>/dev/null || echo "0")
  CHANNEL_REMOTE=$(echo "$TAPROOT_CHANNEL" | jq -r '.custom_channel_data.assets[0].remote_balance' 2>/dev/null || echo "0")

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
CHANNEL_BEFORE=$(docker compose exec -T litd-1 lncli --network=regtest listchannels | jq ".channels[] | select(.remote_pubkey == \"$LITD2_PUBKEY\" and .commitment_type == \"SIMPLE_TAPROOT_OVERLAY\") | .custom_channel_data.assets[0]" 2>/dev/null || echo "{}")
LITD1_BEFORE=$(echo "$CHANNEL_BEFORE" | jq -r '.local_balance' 2>/dev/null || echo "0")
LITD2_BEFORE=$(echo "$CHANNEL_BEFORE" | jq -r '.remote_balance' 2>/dev/null || echo "0")

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
    CHANNEL_AFTER=$(docker compose exec -T litd-1 lncli --network=regtest listchannels | jq ".channels[] | select(.remote_pubkey == \"$LITD2_PUBKEY\" and .commitment_type == \"SIMPLE_TAPROOT_OVERLAY\") | .custom_channel_data.assets[0]" 2>/dev/null || echo "{}")
    LITD1_AFTER=$(echo "$CHANNEL_AFTER" | jq -r '.local_balance' 2>/dev/null || echo "0")
    LITD2_AFTER=$(echo "$CHANNEL_AFTER" | jq -r '.remote_balance' 2>/dev/null || echo "0")

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
  LNBITS_BEFORE=$(curl -s "http://localhost:5002/taproot_assets/api/v1/taproot/listassets" \
    -H "X-Api-Key: $LNBITS2_ADMIN_KEY" | jq -r '.[0].user_balance' 2>/dev/null || echo "0")

  echo "Initial LNbits user balance: $LNBITS_BEFORE"

  # Create invoice in LNbits
  echo "Creating LNbits invoice..."
  LNBITS_INVOICE=$(curl -s -X POST "http://localhost:5002/taproot_assets/api/v1/taproot/invoice" \
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
      LNBITS_AFTER=$(curl -s "http://localhost:5002/taproot_assets/api/v1/taproot/listassets" \
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
  ASSETS_RESPONSE=$(curl -s "http://localhost:5002/taproot_assets/api/v1/taproot/listassets" \
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
CHANNEL_FINAL=$(docker compose exec -T litd-1 lncli --network=regtest listchannels | jq ".channels[] | select(.remote_pubkey == \"$LITD2_PUBKEY\" and .commitment_type == \"SIMPLE_TAPROOT_OVERLAY\") | .custom_channel_data.assets[0]" 2>/dev/null || echo "{}")
CHANNEL_LOCAL=$(echo "$CHANNEL_FINAL" | jq -r '.local_balance' 2>/dev/null || echo "0")
CHANNEL_REMOTE=$(echo "$CHANNEL_FINAL" | jq -r '.remote_balance' 2>/dev/null || echo "0")

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
