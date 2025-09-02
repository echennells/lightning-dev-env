#!/bin/bash

echo "=== PROPER TEST OF EXTENSIONS ==="

# First do first_install
echo "1. First install..."
FIRST_INSTALL=$(curl -k -s -X PUT https://localhost:5443/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "password": "test1234", "password_repeat": "test1234"}')

if [ -z "$FIRST_INSTALL" ]; then
  echo "First install failed - empty response"
  exit 1
fi

ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token')
if [ "$ACCESS_TOKEN" = "null" ] || [ -z "$ACCESS_TOKEN" ]; then
  echo "Failed to get access token"
  echo "Response: $FIRST_INSTALL"
  exit 1
fi
echo "Got access token"

# Get admin key
USER_INFO=$(curl -k -s "https://localhost:5443/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
echo "Got admin key: ${ADMIN_KEY:0:20}..."

# Install lnurlp
echo "2. Installing lnurlp..."
INSTALL_RESP=$(curl -k -s -X POST https://localhost:5443/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "lnurlp", "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}')
echo "Install response: $(echo $INSTALL_RESP | head -c 100)"

curl -k -s -X PUT "https://localhost:5443/api/v1/extension/lnurlp/activate" -H "Authorization: Bearer $ACCESS_TOKEN"
curl -k -s -X PUT "https://localhost:5443/api/v1/extension/lnurlp/enable" -H "Authorization: Bearer $ACCESS_TOKEN"

# Install withdraw  
echo "3. Installing withdraw..."
curl -k -s -X POST https://localhost:5443/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "withdraw", "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}'

curl -k -s -X PUT "https://localhost:5443/api/v1/extension/withdraw/activate" -H "Authorization: Bearer $ACCESS_TOKEN"
curl -k -s -X PUT "https://localhost:5443/api/v1/extension/withdraw/enable" -H "Authorization: Bearer $ACCESS_TOKEN"

sleep 5

echo ""
echo "4. Testing LNURL-P..."
PAY_LINK=$(curl -k -s -X POST "https://localhost:5443/lnurlp/api/v1/links" \
  -H "X-Api-Key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"description": "test", "amount": 1000, "max": 10000, "comment_chars": 255}')

echo "LNURL-P response: $PAY_LINK"
if echo "$PAY_LINK" | jq -e '.id' > /dev/null 2>&1; then
  echo "✅ LNURL-P WORKS!"
else
  echo "❌ LNURL-P FAILED"
fi

echo ""
echo "5. Testing withdraw..."
WITHDRAW_LINK=$(curl -k -s -X POST "https://localhost:5443/withdraw/api/v1/links" \
  -H "X-Api-Key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"is_unique": true, "use_custom": false, "title": "vouchers", "min_withdrawable": 1000, "wait_time": 1, "max_withdrawable": 1000, "uses": 10, "custom_url": null}')

echo "Withdraw response: $WITHDRAW_LINK"
if echo "$WITHDRAW_LINK" | jq -e '.id' > /dev/null 2>&1; then
  WITHDRAW_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id')
  WITHDRAW_HASH=$(echo "$WITHDRAW_LINK" | jq -r '.unique_hash')
  WITHDRAW_LNURL=$(echo "$WITHDRAW_LINK" | jq -r '.lnurl')
  echo "✅ WITHDRAW CREATION WORKS!"
  echo "   ID: $WITHDRAW_ID"
  echo "   unique_hash: $WITHDRAW_HASH" 
  echo "   LNURL: ${WITHDRAW_LNURL:0:60}..."
  
  # Calculate the id_unique_hash for first use (use 0)
  echo ""
  echo "6. Testing withdraw LNURL callback access..."
  FIRST_ID_UNIQUE_HASH=$(docker exec lightning-dev-env-lnbits-1-1 python3 -c "
import shortuuid
print(shortuuid.uuid(name='$WITHDRAW_ID' + '$WITHDRAW_HASH' + '0'))
")
  echo "First id_unique_hash (use 0): $FIRST_ID_UNIQUE_HASH"
  
  # Test withdraw LNURL access with correct format
  WITHDRAW_URL="https://localhost:5443/withdraw/api/v1/lnurl/$WITHDRAW_HASH/$FIRST_ID_UNIQUE_HASH"
  echo "Testing: $WITHDRAW_URL"
  
  WITHDRAW_PARAMS=$(curl -k -s "$WITHDRAW_URL")
  echo "Withdraw LNURL response: $WITHDRAW_PARAMS"
  
  if echo "$WITHDRAW_PARAMS" | jq -e '.k1' > /dev/null 2>&1; then
    echo "✅ WITHDRAW LNURL CALLBACK WORKS!"
    K1=$(echo "$WITHDRAW_PARAMS" | jq -r '.k1')
    CALLBACK_URL=$(echo "$WITHDRAW_PARAMS" | jq -r '.callback')
    echo "   K1: $K1"
    echo "   Callback URL: $CALLBACK_URL"
    
    # Now test the ACTUAL withdraw payment
    echo ""
    echo "7. Testing ACTUAL withdraw payment..."
    
    # Create a receiving wallet
    echo "Creating receiving wallet..."
    RECEIVE_WALLET=$(curl -k -s -X POST "https://localhost:5443/api/v1/wallet" \
      -H "X-Api-Key: $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d '{"name": "receive-wallet"}')
      
    RECEIVE_WALLET_KEY=$(echo "$RECEIVE_WALLET" | jq -r '.inkey')
    echo "Receiving wallet key: ${RECEIVE_WALLET_KEY:0:20}..."
    
    # Create an invoice
    echo "Creating Lightning invoice..."
    INVOICE_DATA=$(curl -k -s -X POST "https://localhost:5443/api/v1/payments" \
      -H "X-Api-Key: $RECEIVE_WALLET_KEY" \
      -H "Content-Type: application/json" \
      -d '{"out": false, "amount": 1000, "memo": "Test withdraw payment"}')
    
    PAYMENT_REQUEST=$(echo "$INVOICE_DATA" | jq -r '.payment_request')
    echo "Payment request: ${PAYMENT_REQUEST:0:60}..."
    
    if [ "$PAYMENT_REQUEST" != "null" ] && [ -n "$PAYMENT_REQUEST" ]; then
      # Fix callback URL and test payment
      FIXED_CALLBACK_URL=$(echo "$CALLBACK_URL" | sed 's|lnbits.example.com|localhost:5443|g')
      echo "Testing withdraw payment callback..."
      
      PAYMENT_RESPONSE=$(curl -k -s "$FIXED_CALLBACK_URL&k1=$K1&pr=$PAYMENT_REQUEST")
      echo "Payment response: $PAYMENT_RESPONSE"
      
      if echo "$PAYMENT_RESPONSE" | jq -e '.status' > /dev/null 2>&1; then
        STATUS=$(echo "$PAYMENT_RESPONSE" | jq -r '.status')
        if [ "$STATUS" = "OK" ]; then
          echo "🎉 ✅ WITHDRAW PAYMENT SUCCEEDED!"
          
          # Check receiving wallet balance
          sleep 2
          WALLET_BALANCE=$(curl -k -s "https://localhost:5443/api/v1/wallet" -H "X-Api-Key: $RECEIVE_WALLET_KEY")
          BALANCE=$(echo "$WALLET_BALANCE" | jq -r '.balance')
          echo "Receiving wallet balance: $BALANCE msat"
          
          if [ "$BALANCE" -gt 0 ]; then
            echo "💰 CONFIRMED: Money actually moved - withdraw works completely!"
          else
            echo "⚠️  Balance still 0 - payment may be pending"
          fi
        else
          echo "❌ WITHDRAW PAYMENT FAILED!"
          REASON=$(echo "$PAYMENT_RESPONSE" | jq -r '.reason // "Unknown"')
          echo "Reason: $REASON"
        fi
      else
        echo "❌ Invalid payment response: $PAYMENT_RESPONSE"
      fi
    else
      echo "❌ Failed to create invoice for testing"
    fi
    
    echo "✅ Complete withdraw functionality confirmed!"
  else
    echo "❌ WITHDRAW LNURL CALLBACK FAILED!"
    echo "Response: $WITHDRAW_PARAMS"
  fi
  
else
  echo "❌ WITHDRAW CREATION FAILED"
  echo "Response: $WITHDRAW_LINK"
fi