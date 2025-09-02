#!/bin/bash
set -e

echo "=== TESTING LOCAL WITHDRAW FUNCTIONALITY SPECIFICALLY ==="

# Setup - ALL HTTPS
echo "1. First install via HTTPS..."
FIRST_INSTALL=$(curl -k -s -X PUT https://localhost:5443/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "password": "test123", "password_repeat": "test123"}')

ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token')
echo "Got access token"

# Get admin key via HTTPS
USER_INFO=$(curl -k -s "https://localhost:5443/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
echo "Got admin key: ${ADMIN_KEY:0:20}..."

# Install withdraw extension via HTTPS
echo "2. Installing withdraw extension..."
curl -k -s -X POST https://localhost:5443/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "withdraw", "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}' > /dev/null

curl -k -s -X PUT "https://localhost:5443/api/v1/extension/withdraw/activate" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
curl -k -s -X PUT "https://localhost:5443/api/v1/extension/withdraw/enable" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
echo "Withdraw extension installed"

sleep 3

# Create withdraw link with correct HAR-discovered format (try HTTP first)
echo "3. Creating withdraw link with HAR-discovered format..."
echo "Using admin key: ${ADMIN_KEY:0:20}..."
echo "Testing connection to withdraw endpoint first:"
curl -k -s "https://localhost:5443/withdraw/api/v1/links" -H "X-API-KEY: $ADMIN_KEY" | head -c 100
echo ""
echo "Now creating withdraw link:"
WITHDRAW_LINK=$(curl -v -X POST "https://localhost:5443/withdraw/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -k \
  -d '{
    "is_unique": true,
    "use_custom": false,
    "title": "vouchers",
    "min_withdrawable": 1000,
    "wait_time": 1,
    "max_withdrawable": 1000,
    "uses": 10,
    "custom_url": null
  }' 2>&1)

echo "Withdraw link response:"
echo "$WITHDRAW_LINK"
echo "Formatted:"
echo "$WITHDRAW_LINK" | jq . 2>/dev/null || echo "Failed to parse as JSON"

if echo "$WITHDRAW_LINK" | jq -e '.id' > /dev/null; then
  WITHDRAW_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id')
  WITHDRAW_HASH=$(echo "$WITHDRAW_LINK" | jq -r '.unique_hash')
  echo "✅ Created withdraw link!"
  echo "   ID: $WITHDRAW_ID"
  echo "   unique_hash: $WITHDRAW_HASH"
else
  echo "❌ Failed to create withdraw link"
  exit 1
fi

# Test withdraw link access (same as GitHub workflow)
echo ""
echo "4. Testing withdraw link access..."
echo "Testing with unique_hash: $WITHDRAW_HASH"
WITHDRAW_PARAMS1=$(curl -k -s "https://localhost:5443/withdraw/api/v1/lnurl/$WITHDRAW_HASH")
echo "Response using unique_hash:"
echo "$WITHDRAW_PARAMS1"

echo ""
echo "Testing with ID: $WITHDRAW_ID"
WITHDRAW_PARAMS2=$(curl -k -s "https://localhost:5443/withdraw/api/v1/lnurl/$WITHDRAW_ID")
echo "Response using ID:"
echo "$WITHDRAW_PARAMS2"

echo ""
echo "=== RESULTS ==="
if echo "$WITHDRAW_PARAMS1" | jq -e '.k1' > /dev/null 2>&1; then
  echo "✅ unique_hash works for LNURL endpoint"
  WORKS_WITH_HASH=true
else
  echo "❌ unique_hash fails: $WITHDRAW_PARAMS1"
  WORKS_WITH_HASH=false
fi

if echo "$WITHDRAW_PARAMS2" | jq -e '.k1' > /dev/null 2>&1; then
  echo "✅ ID works for LNURL endpoint" 
  WORKS_WITH_ID=true
else
  echo "❌ ID fails: $WITHDRAW_PARAMS2"
  WORKS_WITH_ID=false
fi

echo ""
echo "=== FINAL ANSWER ==="
if [ "$WORKS_WITH_HASH" = true ] || [ "$WORKS_WITH_ID" = true ]; then
  echo "✅ YES - Local withdraw functionality WORKS"
  if [ "$WORKS_WITH_HASH" = true ]; then
    echo "   Works with unique_hash"
  fi
  if [ "$WORKS_WITH_ID" = true ]; then
    echo "   Works with ID"
  fi
else
  echo "❌ NO - Local withdraw functionality DOES NOT WORK"
fi