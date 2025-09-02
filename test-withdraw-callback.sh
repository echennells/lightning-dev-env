#!/bin/bash
set -e

echo "=== TESTING ACTUAL WITHDRAW CALLBACK ==="

# Set up system and get admin key
FIRST_INSTALL=$(curl -k -s -X PUT https://localhost:5443/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "password": "test1234", "password_repeat": "test1234"}')

ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token')
USER_INFO=$(curl -k -s "https://localhost:5443/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
echo "Got admin key: ${ADMIN_KEY:0:20}..."

# Install and enable withdraw extension
echo "Installing withdraw extension..."
curl -k -s -X POST https://localhost:5443/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "withdraw", "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}' > /dev/null

curl -k -s -X PUT "https://localhost:5443/api/v1/extension/withdraw/activate" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
curl -k -s -X PUT "https://localhost:5443/api/v1/extension/withdraw/enable" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
sleep 3

# Create withdraw link
echo "Creating withdraw link..."
WITHDRAW_LINK=$(curl -k -s -X POST "https://localhost:5443/withdraw/api/v1/links" \
  -H "X-Api-Key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"is_unique": true, "use_custom": false, "title": "test voucher", "min_withdrawable": 1000, "wait_time": 1, "max_withdrawable": 1000, "uses": 10, "custom_url": null}')

WITHDRAW_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id')
WITHDRAW_HASH=$(echo "$WITHDRAW_LINK" | jq -r '.unique_hash')
echo "Created withdraw link: ID=$WITHDRAW_ID, hash=$WITHDRAW_HASH"

# Calculate id_unique_hash for first use
FIRST_ID_UNIQUE_HASH=$(docker exec lightning-dev-env-lnbits-1-1 python3 -c "
import shortuuid
print(shortuuid.uuid(name='$WITHDRAW_ID' + '$WITHDRAW_HASH' + '0'))
")
echo "First id_unique_hash: $FIRST_ID_UNIQUE_HASH"

# Get withdraw LNURL parameters
WITHDRAW_URL="https://localhost:5443/withdraw/api/v1/lnurl/$WITHDRAW_HASH/$FIRST_ID_UNIQUE_HASH"
WITHDRAW_PARAMS=$(curl -k -s "$WITHDRAW_URL")
K1=$(echo "$WITHDRAW_PARAMS" | jq -r '.k1')
CALLBACK_URL=$(echo "$WITHDRAW_PARAMS" | jq -r '.callback')
echo "Got K1: $K1"
echo "Got callback URL: $CALLBACK_URL"

# Generate a dummy Lightning invoice for testing
# First create a second wallet to pay to
echo ""
echo "Creating second wallet for test invoice..."
SECOND_WALLET=$(curl -k -s -X POST "https://localhost:5443/api/v1/wallet" \
  -H "X-Api-Key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "test-receive-wallet"}')

SECOND_WALLET_KEY=$(echo "$SECOND_WALLET" | jq -r '.inkey')
echo "Created second wallet with inkey: ${SECOND_WALLET_KEY:0:20}..."

echo "Creating test invoice..."
INVOICE_REQUEST=$(curl -k -s -X POST "https://localhost:5443/api/v1/payments" \
  -H "X-Api-Key: $SECOND_WALLET_KEY" \
  -H "Content-Type: application/json" \
  -d '{"out": false, "amount": 1000, "memo": "Test invoice for withdraw callback"}')

echo "Invoice creation response: $INVOICE_REQUEST"
PAYMENT_REQUEST=$(echo "$INVOICE_REQUEST" | jq -r '.payment_request')
echo "Created invoice: ${PAYMENT_REQUEST:0:60}..."

# Test the withdraw callback
echo ""
echo "Testing withdraw callback..."
echo "Calling: $CALLBACK_URL"
echo "With parameters: k1=$K1, pr=$PAYMENT_REQUEST"

CALLBACK_RESPONSE=$(curl -k -s "$CALLBACK_URL&k1=$K1&pr=$PAYMENT_REQUEST")
echo "Callback response: $CALLBACK_RESPONSE"

if echo "$CALLBACK_RESPONSE" | jq -e '.status' > /dev/null 2>&1; then
  STATUS=$(echo "$CALLBACK_RESPONSE" | jq -r '.status')
  if [ "$STATUS" = "OK" ]; then
    echo "✅ WITHDRAW CALLBACK SUCCEEDED!"
  else
    echo "❌ WITHDRAW CALLBACK FAILED!"
    echo "Status: $STATUS"
    REASON=$(echo "$CALLBACK_RESPONSE" | jq -r '.reason // "Unknown"')
    echo "Reason: $REASON"
  fi
else
  echo "❌ INVALID CALLBACK RESPONSE!"
  echo "Response: $CALLBACK_RESPONSE"
fi