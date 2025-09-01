#!/bin/bash
set -e

echo "=== ULTIMATE Working Extension Install - Exact HAR Replication ==="
echo "Using X-Api-Key header format discovered from HAR file"

# Complete first install
echo "Step 1: Complete first install..."
FIRST_INSTALL_RESPONSE=$(curl -s -X PUT http://localhost:5001/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{
    "username": "superadmin",
    "password": "secret1234",
    "password_repeat": "secret1234"
  }')

if echo "$FIRST_INSTALL_RESPONSE" | jq -e '.access_token' > /dev/null; then
  echo "✅ Admin user created successfully"
  ACCESS_TOKEN=$(echo "$FIRST_INSTALL_RESPONSE" | jq -r '.access_token')
else
  echo "❌ First install failed: $FIRST_INSTALL_RESPONSE"
  exit 1
fi

# Get user and wallet info 
USER_INFO=$(curl -s -X GET "http://localhost:5001/api/v1/auth" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

WALLET_ID=$(echo "$USER_INFO" | jq -r '.wallets[0].id')
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
USER_ID=$(echo "$USER_INFO" | jq -r '.id')

echo "User ID: $USER_ID"
echo "Wallet ID: $WALLET_ID"
echo "Admin key: ${ADMIN_KEY:0:20}..."

# The KEY DISCOVERY: GUI uses X-Api-Key header, not Authorization Bearer!
# This is the missing piece from the HAR analysis

echo "Step 2: Installing lnurlp using EXACT HAR sequence..."

# 1. Install extension (POST with X-Api-Key)
LNURLP_INSTALL_RESPONSE=$(curl -s -X POST http://localhost:5001/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $ADMIN_KEY" \
  -d '{
    "ext_id": "lnurlp",
    "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "payment_hash": null,
    "version": "1.0.1"
  }')

echo "lnurlp install response: $LNURLP_INSTALL_RESPONSE"

# 2. Activate extension (PUT with X-Api-Key) 
echo "Activating lnurlp extension..."
LNURLP_ACTIVATE_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/lnurlp/activate" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $ADMIN_KEY")

echo "lnurlp activate response: $LNURLP_ACTIVATE_RESPONSE"

# 3. Enable for user (PUT with X-Api-Key)
echo "Enabling lnurlp for user..."
LNURLP_ENABLE_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/lnurlp/enable" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $ADMIN_KEY")

echo "lnurlp enable response: $LNURLP_ENABLE_RESPONSE"

echo "Step 3: Installing withdraw using EXACT HAR sequence..."

# Same sequence for withdraw 
WITHDRAW_INSTALL_RESPONSE=$(curl -s -X POST http://localhost:5001/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $ADMIN_KEY" \
  -d '{
    "ext_id": "withdraw",
    "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "payment_hash": null,
    "version": "1.0.1"
  }')

echo "withdraw install response: $WITHDRAW_INSTALL_RESPONSE"

echo "Activating withdraw extension..."
WITHDRAW_ACTIVATE_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/withdraw/activate" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $ADMIN_KEY")

echo "withdraw activate response: $WITHDRAW_ACTIVATE_RESPONSE"

echo "Enabling withdraw for user..."
WITHDRAW_ENABLE_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/withdraw/enable" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $ADMIN_KEY")

echo "withdraw enable response: $WITHDRAW_ENABLE_RESPONSE"

# GUI doesn't restart - extensions should register routes immediately
echo "Step 4: Testing extension APIs (no restart needed)..."
sleep 5

echo "Testing lnurlp API with X-Api-Key..."
LNURLP_API_TEST=$(curl -s "http://localhost:5001/lnurlp/api/v1" \
  -H "X-API-KEY: $ADMIN_KEY" || echo "API_ERROR")

echo "lnurlp API response: $LNURLP_API_TEST"

echo "Testing withdraw API with X-Api-Key..."
WITHDRAW_API_TEST=$(curl -s "http://localhost:5001/withdraw/api/v1" \
  -H "X-API-KEY: $ADMIN_KEY" || echo "API_ERROR")

echo "withdraw API response: $WITHDRAW_API_TEST"

# Test creating links if APIs work
if echo "$LNURLP_API_TEST" | grep -q "\[\]"; then
  echo "🎉 SUCCESS! Extension routes registered via EXACT HAR API sequence!"
  
  # Test creating pay link
  echo "Creating test pay link..."
  PAY_LINK=$(curl -s -X POST "http://localhost:5001/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "description": "Ultimate Test Pay Link",
      "min": 10,
      "max": 10000,
      "comment_chars": 255
    }')
  
  if echo "$PAY_LINK" | jq -e '.id' > /dev/null; then
    PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id')
    echo "🚀 ULTIMATE SUCCESS! Created pay link: $PAY_LINK_ID"
    echo ""
    echo "🎯 ROUTE REGISTRATION WORKED!"
    echo "✅ Extensions fully functional via HAR replication"
    
    # Test withdraw link too
    echo "Creating test withdraw link..."
    WITHDRAW_LINK=$(curl -s -X POST "http://localhost:5001/withdraw/api/v1/links" \
      -H "X-API-KEY: $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "title": "Ultimate Test Withdraw Link",
        "min_withdrawable": 10,
        "max_withdrawable": 10000,
        "uses": 100,
        "wait_time": 1,
        "is_unique": true
      }')
    
    if echo "$WITHDRAW_LINK" | jq -e '.id' > /dev/null; then
      WITHDRAW_LINK_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id')
      echo "🚀 Created withdraw link: $WITHDRAW_LINK_ID"
      echo ""
      echo "🔥 COMPLETE SUCCESS! Both extensions fully working!"
    else
      echo "Withdraw link creation: $WITHDRAW_LINK"
    fi
    
  else
    echo "Pay link creation failed: $PAY_LINK"
  fi
  
else
  echo "⚠️ Routes still not registered"
  echo "lnurlp API response: $LNURLP_API_TEST"
  echo "withdraw API response: $WITHDRAW_API_TEST"
  
  if echo "$LNURLP_API_TEST" | grep -q "Not Found"; then
    echo "Still getting Not Found - route registration issue persists"
  fi
fi

echo ""
echo "=== Ultimate HAR Replication Summary ==="
echo "✅ Used exact HAR POST data format"
echo "✅ Used exact X-Api-Key header (not Authorization)"
echo "✅ Used exact sequence: install → activate → enable"
echo "✅ No restart needed (like GUI)"
echo ""
echo "If this worked, we've cracked the code!"
echo "If not, the issue is deeper in LNbits v1.2.1 internals"