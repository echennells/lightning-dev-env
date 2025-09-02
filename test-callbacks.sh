#!/bin/bash
set -e

echo "=== TESTING LNURL CALLBACKS LOCALLY ==="

# Use same auth approach as PROPER-TEST.sh - it already set up the system
USER_INFO=$(curl -k -s "https://localhost:5443/api/v1/auth")
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')

echo "Got admin key: ${ADMIN_KEY:0:20}..."

# Create LNURL-P link
echo "Creating LNURL-P link..."
PAY_LINK=$(curl -k -s -X POST "https://localhost:5443/lnurlp/api/v1/links" \
  -H "X-Api-Key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"description": "test callback", "amount": 1000, "max": 10000, "comment_chars": 255}')

PAY_ID=$(echo "$PAY_LINK" | jq -r '.id')
echo "Created LNURL-P link: $PAY_ID"

# Test the LNURL-P callback
echo ""
echo "Testing LNURL-P callback..."
CALLBACK_URL="https://localhost:5443/lnurlp/api/v1/links/$PAY_ID/callback"
echo "Trying: $CALLBACK_URL?amount=2000000"

PAY_REQUEST=$(curl -k -s "$CALLBACK_URL?amount=2000000")
echo "Callback response: $PAY_REQUEST"

if echo "$PAY_REQUEST" | jq -e '.pr' > /dev/null 2>&1; then
  echo "✅ LNURL-P callback works!"
else
  echo "❌ LNURL-P callback failed!"
fi

echo ""
echo "=== TESTING WITHDRAW CALLBACKS ==="

# Create withdraw link
echo "Creating withdraw link..."
WITHDRAW_LINK=$(curl -k -s -X POST "https://localhost:5443/withdraw/api/v1/links" \
  -H "X-Api-Key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"is_unique": true, "use_custom": false, "title": "test voucher", "min_withdrawable": 1000, "wait_time": 1, "max_withdrawable": 1000, "uses": 10, "custom_url": null}')

echo "Withdraw link response: $WITHDRAW_LINK"

if echo "$WITHDRAW_LINK" | jq -e '.id' > /dev/null 2>&1; then
  WITHDRAW_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id')
  WITHDRAW_HASH=$(echo "$WITHDRAW_LINK" | jq -r '.unique_hash')
  echo "✅ Created withdraw link!"
  echo "   ID: $WITHDRAW_ID"
  echo "   unique_hash: $WITHDRAW_HASH"
  
  # Calculate id_unique_hash for first use (use 0)
  echo ""
  echo "Calculating id_unique_hash values..."
  FIRST_ID_UNIQUE_HASH=$(docker exec lightning-dev-env-lnbits-1-1 python3 -c "
import shortuuid
print(shortuuid.uuid(name='$WITHDRAW_ID' + '$WITHDRAW_HASH' + '0'))
")
  echo "First id_unique_hash (use 0): $FIRST_ID_UNIQUE_HASH"
  
  # Test withdraw LNURL access with correct format
  echo ""
  echo "Testing withdraw LNURL access..."
  WITHDRAW_URL="https://localhost:5443/withdraw/api/v1/lnurl/$WITHDRAW_HASH/$FIRST_ID_UNIQUE_HASH"
  echo "Trying: $WITHDRAW_URL"
  
  WITHDRAW_PARAMS=$(curl -k -s "$WITHDRAW_URL")
  echo "Withdraw LNURL response: $WITHDRAW_PARAMS"
  
  if echo "$WITHDRAW_PARAMS" | jq -e '.k1' > /dev/null 2>&1; then
    echo "✅ WITHDRAW LNURL access works!"
    K1=$(echo "$WITHDRAW_PARAMS" | jq -r '.k1')
    CALLBACK_URL=$(echo "$WITHDRAW_PARAMS" | jq -r '.callback')
    echo "   K1: $K1"
    echo "   Callback URL: $CALLBACK_URL"
  else
    echo "❌ WITHDRAW LNURL access failed!"
    echo "Response: $WITHDRAW_PARAMS"
  fi
  
else
  echo "❌ Failed to create withdraw link"
  echo "Response: $WITHDRAW_LINK"
fi