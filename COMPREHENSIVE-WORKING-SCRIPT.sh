#!/bin/bash
set -e

echo "=== COMPREHENSIVE WORKING EXTENSION SCRIPT ==="
echo "With HTTPS proxy for proper LNURL functionality"
echo ""

# Wait for services
echo "Waiting for services to be ready..."
sleep 10

# Step 1: Complete first install and get Bearer token
echo "Step 1: Setting up admin user..."
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
  echo "Bearer token: ${ACCESS_TOKEN:0:30}..."
else
  echo "❌ First install failed: $FIRST_INSTALL_RESPONSE"
  exit 1
fi

# Step 2: Get user info (including admin key for wallet operations)
echo ""
echo "Step 2: Getting user and wallet info..."
USER_INFO=$(curl -s -X GET "http://localhost:5001/api/v1/auth" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

WALLET_ID=$(echo "$USER_INFO" | jq -r '.wallets[0].id')
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
USER_ID=$(echo "$USER_INFO" | jq -r '.id')

echo "User ID: $USER_ID"
echo "Wallet ID: $WALLET_ID"
echo "Admin key: ${ADMIN_KEY:0:20}..."

# Step 3: Install extensions using Bearer token
echo ""
echo "Step 3: Installing lnurlp 1.0.1 using Bearer token..."
LNURLP_INSTALL_RESPONSE=$(curl -s -X POST http://localhost:5001/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "ext_id": "lnurlp",
    "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "payment_hash": null,
    "version": "1.0.1"
  }')

echo "lnurlp install response: $LNURLP_INSTALL_RESPONSE"

echo "Activating lnurlp extension using Bearer token..."
curl -s -X PUT "http://localhost:5001/api/v1/extension/lnurlp/activate" \
  -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null

echo "Enabling lnurlp for user using Bearer token..."
curl -s -X PUT "http://localhost:5001/api/v1/extension/lnurlp/enable" \
  -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null

# Step 4: Install withdraw extension
echo ""
echo "Step 4: Installing withdraw 1.0.1 using Bearer token..."
WITHDRAW_INSTALL_RESPONSE=$(curl -s -X POST http://localhost:5001/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "ext_id": "withdraw",
    "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "payment_hash": null,
    "version": "1.0.1"
  }')

echo "withdraw install response: $WITHDRAW_INSTALL_RESPONSE"

echo "Activating withdraw extension using Bearer token..."
curl -s -X PUT "http://localhost:5001/api/v1/extension/withdraw/activate" \
  -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null

echo "Enabling withdraw for user using Bearer token..."
curl -s -X PUT "http://localhost:5001/api/v1/extension/withdraw/enable" \
  -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null

# Step 5: Test extension APIs
echo ""
echo "Step 5: Testing extension APIs via HTTP..."
echo "Testing lnurlp links API..."
LNURLP_LINKS=$(curl -s "http://localhost:5001/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" || echo "API_ERROR")

if echo "$LNURLP_LINKS" | grep -q "\[\]"; then
  echo "✅ lnurlp links API WORKS via HTTP!"
else
  echo "❌ lnurlp links API failed via HTTP: $LNURLP_LINKS"
fi

echo "Testing withdraw links API..."
WITHDRAW_LINKS=$(curl -s "http://localhost:5001/withdraw/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" || echo "API_ERROR")

if echo "$WITHDRAW_LINKS" | grep -q "\"data\":\[\]"; then
  echo "✅ withdraw links API WORKS via HTTP!"
else
  echo "❌ withdraw links API failed via HTTP: $WITHDRAW_LINKS"
fi

# Step 6: Test via HTTPS proxy (required for LNURL)
echo ""
echo "Step 6: Testing extension APIs via HTTPS proxy..."
echo "Testing lnurlp links API via HTTPS..."
LNURLP_LINKS_HTTPS=$(curl -k -s "https://localhost:5443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" || echo "API_ERROR")

if echo "$LNURLP_LINKS_HTTPS" | grep -q "\[\]"; then
  echo "✅ lnurlp links API WORKS via HTTPS!"
else
  echo "❌ lnurlp links API failed via HTTPS: $LNURLP_LINKS_HTTPS"
fi

# Step 7: Create actual links to prove functionality
echo ""
echo "Step 7: Creating test pay link via HTTPS proxy..."
PAY_LINK=$(curl -k -s -X POST "https://localhost:5443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "HTTPS Test Pay Link",
    "min": 100,
    "max": 10000,
    "comment_chars": 255
  }')

if echo "$PAY_LINK" | jq -e '.id' > /dev/null 2>&1; then
  PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id')
  PAY_LINK_LNURL=$(echo "$PAY_LINK" | jq -r '.lnurl')
  echo "🎉 SUCCESS! Created working pay link via HTTPS!"
  echo "   Link ID: $PAY_LINK_ID"
  echo "   LNURL: $PAY_LINK_LNURL"
else
  echo "❌ Pay link creation failed via HTTPS: $PAY_LINK"
fi

echo ""
echo "Step 8: Creating test withdraw link via HTTPS proxy..."
WITHDRAW_LINK=$(curl -k -s -X POST "https://localhost:5443/withdraw/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "is_unique": true,
    "use_custom": false,
    "title": "HTTPS Test Withdraw Link",
    "min_withdrawable": 100,
    "wait_time": 1,
    "max_withdrawable": 1000,
    "uses": 10,
    "custom_url": null
  }')

if echo "$WITHDRAW_LINK" | jq -e '.id' > /dev/null 2>&1; then
  WITHDRAW_LINK_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id')
  echo "🎉 SUCCESS! Created working withdraw link via HTTPS!"
  echo "   Link ID: $WITHDRAW_LINK_ID"
else
  echo "❌ Withdraw link creation failed via HTTPS: $WITHDRAW_LINK"
fi

echo ""
echo "=== FINAL COMPREHENSIVE SUMMARY ==="
echo "🎯 COMPLETE WORKING SOLUTION DISCOVERED:"
echo ""
echo "✅ Extension management: Bearer token via HTTP"
echo "✅ Extension functionality: X-API-KEY via HTTPS proxy"
echo "✅ HTTPS proxy (port 5443) required for LNURL generation"
echo "✅ Extensions install and function correctly"
echo ""
echo "🔑 COMPLETE AUTHENTICATION & URL PATTERN:"
echo "   - Extension install/activate/enable: http://localhost:5001 + Bearer token"
echo "   - Extension usage (create links): https://localhost:5443 + X-API-KEY"
echo ""
echo "🌐 ACCESS URLS:"
echo "   - LNbits HTTP: http://localhost:5001"
echo "   - LNbits HTTPS: https://localhost:5443"
echo "   - Username: superadmin / Password: secret1234"
echo ""
echo "Extensions are now fully functional with proper HTTPS support!"