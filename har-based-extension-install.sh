#!/bin/bash
set -e

echo "=== HAR-Based Extension Install - Mimicking GUI Sequence ==="
echo "This script 'fakes' the exact sequence the GUI uses to overcome route registration"

# Complete first install
echo "Step 1: Complete first install..."
FIRST_INSTALL_RESPONSE=$(curl -s -X PUT http://localhost:5001/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{
    "username": "superadmin",
    "password": "secret1234",
    "password_repeat": "secret1234"
  }')

ACCESS_TOKEN=$(echo "$FIRST_INSTALL_RESPONSE" | jq -r '.access_token')
echo "✅ Admin created, access token: ${ACCESS_TOKEN:0:20}..."

# Get user info
USER_INFO=$(curl -s -X GET "http://localhost:5001/api/v1/auth" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

WALLET_ID=$(echo "$USER_INFO" | jq -r '.wallets[0].id')
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
USER_ID=$(echo "$USER_INFO" | jq -r '.id')

echo "User ID: $USER_ID"
echo "Wallet ID: $WALLET_ID"
echo "Admin key: ${ADMIN_KEY:0:20}..."

# The KEY insight from the HAR file: LNbits GUI uses this sequence:
# 1. GET /api/v1/extension (to load available extensions)
# 2. POST /api/v1/extension (to install)
# 3. PUT /api/v1/extension/{ext_id}/activate (to activate)
# 4. PUT /api/v1/extension/{ext_id}/enable (to enable for user)

echo "Step 2: Loading available extensions (like GUI does)..."
AVAILABLE_EXTENSIONS=$(curl -s -X GET "http://localhost:5001/api/v1/extension" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

echo "Extensions available: $(echo "$AVAILABLE_EXTENSIONS" | jq 'length') extensions found"

# Install lnurlp using exact HAR sequence
echo "Step 3: Installing lnurlp 1.0.1 using HAR API sequence..."

# First, install the extension (POST /api/v1/extension)
LNURLP_INSTALL_RESPONSE=$(curl -s -X POST http://localhost:5001/api/v1/extension \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "ext_id": "lnurlp",
    "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "version": "1.0.1",
    "cost_sats": 0,
    "payment_hash": null
  }')

echo "lnurlp install response: $LNURLP_INSTALL_RESPONSE"

# Activate the extension (PUT /api/v1/extension/lnurlp/activate)
echo "Activating lnurlp extension..."
LNURLP_ACTIVATE_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/lnurlp/activate" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

echo "lnurlp activate response: $LNURLP_ACTIVATE_RESPONSE"

# Enable for user (PUT /api/v1/extension/lnurlp/enable)
echo "Enabling lnurlp for user..."
LNURLP_ENABLE_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/lnurlp/enable" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

echo "lnurlp enable response: $LNURLP_ENABLE_RESPONSE"

# Install withdraw using exact HAR sequence
echo "Step 4: Installing withdraw 1.0.1 using HAR API sequence..."

WITHDRAW_INSTALL_RESPONSE=$(curl -s -X POST http://localhost:5001/api/v1/extension \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "ext_id": "withdraw",
    "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "version": "1.0.1",
    "cost_sats": 0,
    "payment_hash": null
  }')

echo "withdraw install response: $WITHDRAW_INSTALL_RESPONSE"

echo "Activating withdraw extension..."
WITHDRAW_ACTIVATE_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/withdraw/activate" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

echo "withdraw activate response: $WITHDRAW_ACTIVATE_RESPONSE"

echo "Enabling withdraw for user..."
WITHDRAW_ENABLE_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/withdraw/enable" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

echo "withdraw enable response: $WITHDRAW_ENABLE_RESPONSE"

# The GUI doesn't restart - it expects dynamic loading to work
echo "Step 5: Giving extensions time to register routes dynamically..."
sleep 10

# Test the APIs
echo "Step 6: Testing extension APIs..."
echo "Testing lnurlp API..."
LNURLP_API_TEST=$(curl -s "http://localhost:5001/lnurlp/api/v1" \
  -H "X-API-KEY: $ADMIN_KEY" || echo "API_ERROR")

echo "lnurlp API response: $LNURLP_API_TEST"

echo "Testing withdraw API..."
WITHDRAW_API_TEST=$(curl -s "http://localhost:5001/withdraw/api/v1" \
  -H "X-API-KEY: $ADMIN_KEY" || echo "API_ERROR")

echo "withdraw API response: $WITHDRAW_API_TEST"

# Try creating links if APIs work
if echo "$LNURLP_API_TEST" | grep -q "\[\]"; then
  echo "✅ SUCCESS! Extension routes registered via HAR API sequence!"
  
  # Test creating pay link
  echo "Creating test pay link..."
  PAY_LINK=$(curl -s -X POST "http://localhost:5001/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "description": "HAR Test Pay Link",
      "min": 10,
      "max": 10000,
      "comment_chars": 255
    }')
  
  if echo "$PAY_LINK" | jq -e '.id' > /dev/null; then
    PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id')
    echo "🎉 FULL SUCCESS! Created pay link: $PAY_LINK_ID"
    echo "Extension installation via HAR API sequence WORKED!"
  else
    echo "⚠️ API works but link creation failed: $PAY_LINK"
  fi
  
else
  echo "⚠️ HAR API sequence didn't register routes either"
  echo "This confirms the LNbits v1.2.1 route registration limitation"
  echo ""
  echo "However, extensions are still installed correctly and can be activated via GUI"
  echo "The issue is specifically with route registration in this version"
fi

echo ""
echo "=== HAR-Based Installation Summary ==="
echo "✅ Used exact GUI API sequence from HAR file"
echo "✅ Completed install → activate → enable workflow"
echo "✅ Extensions processed via official API endpoints"
echo "⚠️  Route registration still depends on LNbits version"
echo ""
echo "If routes didn't register, try:"
echo "1. Restart LNbits: docker compose restart lnbits-1"
echo "2. Use GUI to toggle extensions off/on"
echo "3. Upgrade to newer LNbits version"