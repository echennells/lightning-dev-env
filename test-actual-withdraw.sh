#!/bin/bash
set -e

echo "=== TESTING ACTUAL WITHDRAW PAYMENT ==="

# Get the admin key from the already-running system
USER_INFO=$(curl -k -s "https://localhost:5443/api/v1/auth")
if echo "$USER_INFO" | grep -q "Missing user ID"; then
    echo "Need to get access token first..."
    FIRST_INSTALL=$(curl -k -s -X PUT https://localhost:5443/api/v1/auth/first_install \
      -H "Content-Type: application/json" \
      -d '{"username": "testuser", "password": "test1234", "password_repeat": "test1234"}')
    
    ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token')
    USER_INFO=$(curl -k -s "https://localhost:5443/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
fi

ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
echo "Got admin key: ${ADMIN_KEY:0:20}..."

# Use the withdraw link we already created from PROPER-TEST.sh
echo "Getting existing withdraw links..."
WITHDRAW_LINKS=$(curl -k -s "https://localhost:5443/withdraw/api/v1/links" -H "X-Api-Key: $ADMIN_KEY")
echo "Withdraw links response: $WITHDRAW_LINKS"

# Get the first withdraw link
WITHDRAW_ID=$(echo "$WITHDRAW_LINKS" | jq -r '.[0].id')
WITHDRAW_HASH=$(echo "$WITHDRAW_LINKS" | jq -r '.[0].unique_hash')
echo "Using withdraw link: ID=$WITHDRAW_ID, hash=$WITHDRAW_HASH"

# Calculate id_unique_hash for first use
FIRST_ID_UNIQUE_HASH=$(docker exec lightning-dev-env-lnbits-1-1 python3 -c "
import shortuuid
print(shortuuid.uuid(name='$WITHDRAW_ID' + '$WITHDRAW_HASH' + '0'))
")
echo "First id_unique_hash: $FIRST_ID_UNIQUE_HASH"

# Get the withdraw LNURL parameters
WITHDRAW_URL="https://localhost:5443/withdraw/api/v1/lnurl/$WITHDRAW_HASH/$FIRST_ID_UNIQUE_HASH"
WITHDRAW_PARAMS=$(curl -k -s "$WITHDRAW_URL")
K1=$(echo "$WITHDRAW_PARAMS" | jq -r '.k1')
CALLBACK_URL=$(echo "$WITHDRAW_PARAMS" | jq -r '.callback')
echo "K1: $K1"
echo "Callback URL: $CALLBACK_URL"

# Create a second wallet to receive the payment
echo ""
echo "Creating receiving wallet..."
RECEIVE_WALLET=$(curl -k -s -X POST "https://localhost:5443/api/v1/wallet" \
  -H "X-Api-Key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "receive-wallet"}')
  
RECEIVE_WALLET_KEY=$(echo "$RECEIVE_WALLET" | jq -r '.inkey')
echo "Receiving wallet inkey: ${RECEIVE_WALLET_KEY:0:20}..."

# Create an invoice in the receiving wallet
echo "Creating invoice..."
INVOICE_DATA=$(curl -k -s -X POST "https://localhost:5443/api/v1/payments" \
  -H "X-Api-Key: $RECEIVE_WALLET_KEY" \
  -H "Content-Type: application/json" \
  -d '{"out": false, "amount": 1000, "memo": "Test withdraw payment"}')

echo "Invoice creation response: $INVOICE_DATA"
PAYMENT_REQUEST=$(echo "$INVOICE_DATA" | jq -r '.payment_request')

if [ "$PAYMENT_REQUEST" = "null" ] || [ -z "$PAYMENT_REQUEST" ]; then
    echo "❌ FAILED TO CREATE INVOICE"
    echo "Response: $INVOICE_DATA"
    exit 1
fi

echo "Created payment request: ${PAYMENT_REQUEST:0:60}..."

# Now test the actual withdraw callback
echo ""
echo "🚀 TESTING ACTUAL WITHDRAW CALLBACK..."
echo "Calling callback URL with invoice..."

# Fix the callback URL format - it returns lnbits.example.com but we need localhost
FIXED_CALLBACK_URL=$(echo "$CALLBACK_URL" | sed 's|lnbits.example.com|localhost:5443|g')
echo "Fixed callback URL: $FIXED_CALLBACK_URL"

CALLBACK_RESPONSE=$(curl -k -s "$FIXED_CALLBACK_URL&k1=$K1&pr=$PAYMENT_REQUEST")
echo "🎯 CALLBACK RESPONSE: $CALLBACK_RESPONSE"

if echo "$CALLBACK_RESPONSE" | jq -e '.status' > /dev/null 2>&1; then
  STATUS=$(echo "$CALLBACK_RESPONSE" | jq -r '.status')
  if [ "$STATUS" = "OK" ]; then
    echo "🎉 ✅ WITHDRAW CALLBACK PAYMENT SUCCEEDED!"
    echo "💰 The withdraw actually paid the Lightning invoice!"
  else
    echo "❌ WITHDRAW CALLBACK FAILED!"
    echo "Status: $STATUS"
    REASON=$(echo "$CALLBACK_RESPONSE" | jq -r '.reason // "Unknown"')
    echo "Reason: $REASON"
  fi
else
  echo "❌ INVALID CALLBACK RESPONSE FORMAT"
  echo "Raw response: $CALLBACK_RESPONSE"
fi

# Check if the receiving wallet got the payment
echo ""
echo "🔍 Checking receiving wallet balance..."
WALLET_BALANCE=$(curl -k -s "https://localhost:5443/api/v1/wallet" -H "X-Api-Key: $RECEIVE_WALLET_KEY")
BALANCE=$(echo "$WALLET_BALANCE" | jq -r '.balance')
echo "Receiving wallet balance: $BALANCE msat"

if [ "$BALANCE" -gt 0 ]; then
    echo "🎉 SUCCESS! Receiving wallet has balance - withdraw payment worked!"
else  
    echo "⚠️  Receiving wallet balance is still 0 - payment may not have completed"
fi