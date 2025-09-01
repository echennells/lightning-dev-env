#!/bin/bash
set -e

echo "=== TESTING FIXED GITHUB WORKFLOW EXTENSION SECTION ==="
echo "This tests the specific part we fixed in the GitHub workflow"
echo ""

# Start services including HTTPS proxy
echo "1. Starting services with HTTPS proxy..."
docker compose up -d lnbits-1 lnbits-https-proxy
sleep 30

echo "2. Waiting for services to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:5001/api/v1/health >/dev/null 2>&1; then
    echo "✅ LNbits is ready!"
    break
  fi
  echo "Attempt $i/30: Waiting for LNbits..."
  sleep 2
done

echo "3. Checking HTTPS proxy..."
for i in {1..30}; do
  if curl -k -s https://localhost:5443/api/v1/health >/dev/null 2>&1; then
    echo "✅ HTTPS proxy is ready!"
    break
  fi
  echo "Attempt $i/30: Waiting for HTTPS proxy..."
  sleep 2
done

# Simulate the workflow's extension setup function
echo ""
echo "4. Running fixed workflow extension setup..."

PORT=5001
NAME="LNBITS1" 
PROXY_PORT=5443

# Complete first install (from workflow)
echo "Completing first install for $NAME..."
FIRST_INSTALL=$(curl -s -X PUT http://localhost:$PORT/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin'$PORT'",
    "password": "password123", 
    "password_repeat": "password123"
  }')

if echo "$FIRST_INSTALL" | jq -e '.access_token' > /dev/null; then
  ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token')
  echo "✅ Admin user created for $NAME"
else
  echo "❌ Admin creation failed for $NAME: $FIRST_INSTALL"
  exit 1
fi

# Get wallet info (from workflow)
USER_INFO=$(curl -s "http://localhost:$PORT/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
INVOICE_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].inkey')
WALLET_ID=$(echo "$USER_INFO" | jq -r '.wallets[0].id')
echo "✅ Admin key for $NAME: ${ADMIN_KEY:0:20}..."

# Install lnurlp extension (from workflow with Bearer token)
echo "Installing lnurlp extension on $NAME..."
curl -s -X POST http://localhost:$PORT/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "lnurlp", "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}' > /dev/null

curl -s -X PUT "http://localhost:$PORT/api/v1/extension/lnurlp/activate" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
curl -s -X PUT "http://localhost:$PORT/api/v1/extension/lnurlp/enable" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
echo "✅ lnurlp installed on $NAME"

# Install withdraw extension (from workflow with Bearer token)
echo "Installing withdraw extension on $NAME..."
curl -s -X POST http://localhost:$PORT/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "withdraw", "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}' > /dev/null

curl -s -X PUT "http://localhost:$PORT/api/v1/extension/withdraw/activate" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
curl -s -X PUT "http://localhost:$PORT/api/v1/extension/withdraw/enable" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
echo "✅ withdraw installed on $NAME"

echo ""
echo "5. Testing extensions are working (our FIXED version)..."
sleep 3

# Test lnurlp by creating a pay link via HTTPS proxy (FIXED VERSION)
echo "Creating LNURL-P pay link via HTTPS proxy..."
PAY_LINK=$(curl -k -s -X POST "https://localhost:$PROXY_PORT/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Test Pay Link",
    "min": 100,
    "max": 10000,
    "comment_chars": 255
  }')

if echo "$PAY_LINK" | jq -e '.id' > /dev/null; then
  PAY_ID=$(echo "$PAY_LINK" | jq -r '.id')
  PAY_LNURL=$(echo "$PAY_LINK" | jq -r '.lnurl')
  echo "✅ LNURL-P working! Created pay link: $PAY_ID"
  echo "   LNURL: $PAY_LNURL"
  PAY_SUCCESS=true
else
  echo "❌ LNURL-P link creation failed: $PAY_LINK"
  PAY_SUCCESS=false
fi

# Test withdraw by creating a withdraw link via HTTPS proxy (FIXED VERSION)  
echo "Creating withdraw link via HTTPS proxy..."
WITHDRAW_LINK=$(curl -k -s -X POST "https://localhost:$PROXY_PORT/withdraw/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "is_unique": true,
    "use_custom": false,
    "title": "Test Withdraw Link",
    "min_withdrawable": 10,
    "wait_time": 1,
    "max_withdrawable": 1000,
    "uses": 10,
    "custom_url": null
  }')

if echo "$WITHDRAW_LINK" | jq -e '.id' > /dev/null; then
  WITHDRAW_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id')
  WITHDRAW_HASH=$(echo "$WITHDRAW_LINK" | jq -r '.unique_hash')
  echo "✅ Withdraw extension working! Created link ID: $WITHDRAW_ID"
  echo "   Unique hash: $WITHDRAW_HASH" 
  WITHDRAW_SUCCESS=true
else
  echo "❌ Withdraw link creation failed: $WITHDRAW_LINK"
  WITHDRAW_SUCCESS=false
fi

echo ""
echo "=== FIXED WORKFLOW SECTION TEST RESULTS ==="
if [ "$PAY_SUCCESS" = true ] && [ "$WITHDRAW_SUCCESS" = true ]; then
  echo "🎉 SUCCESS! Both extensions working with FIXED workflow pattern:"
  echo "   ✅ Extension management: Authorization: Bearer <access_token>"  
  echo "   ✅ Extension functionality: X-API-KEY: <admin_key> via HTTPS"
  echo "   ✅ HTTPS proxy required for LNURL generation"
  echo ""
  echo "🔧 GitHub workflow has been SUCCESSFULLY FIXED!"
else
  echo "❌ FAILED: Extensions not working properly"
  echo "   LNURL-P: $PAY_SUCCESS"
  echo "   Withdraw: $WITHDRAW_SUCCESS"
fi