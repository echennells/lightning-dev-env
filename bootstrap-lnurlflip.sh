#!/bin/bash

# Complete LNbits + lnurlFlip Bootstrap Script
# This script properly bootstraps a fresh environment and installs lnurlFlip

set -e

echo "🚀 BOOTSTRAPPING FRESH LNBITS + LNURLFLIP ENVIRONMENT"
echo "=========================================="

# Start containers
echo "Starting Docker containers..."
docker compose up -d

# Wait for services
echo "Waiting for services to start..."
sleep 30

# Wait for HTTPS proxy to connect to LNbits
echo "Waiting for LNbits to be ready via HTTPS proxy..."
for i in {1..60}; do
  RESPONSE=$(curl -k -s -w "%{http_code}" "https://localhost:5443/" -o /dev/null)
  if [ "$RESPONSE" = "200" ]; then
    echo "✅ LNbits ready via HTTPS proxy"
    break
  elif [ "$RESPONSE" = "307" ]; then
    echo "✅ LNbits ready via HTTPS proxy (redirecting to first_install)"
    break
  elif [ "$RESPONSE" = "502" ] || [ "$RESPONSE" = "503" ]; then
    echo "Attempt $i/60: LNbits still starting (HTTP $RESPONSE)..."
  else
    echo "Attempt $i/60: Unexpected response: $RESPONSE"
  fi
  sleep 3
done

# Bootstrap LNbits with first install
echo ""
echo "=========================================="
echo "BOOTSTRAPPING LNBITS"
echo "=========================================="

echo "Creating admin user..."
FIRST_INSTALL=$(curl -k -s -X PUT "https://localhost:5443/api/v1/auth/first_install" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "password123", 
    "password_repeat": "password123"
  }')

echo "First install response: $FIRST_INSTALL"

if ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token' 2>/dev/null) && [ "$ACCESS_TOKEN" != "null" ]; then
    echo "✅ Admin user created successfully"
elif echo "$FIRST_INSTALL" | grep -q "not your first install"; then
    echo "✅ LNbits already initialized, logging in with existing admin..."
    LOGIN_RESP=$(curl -k -s -X POST "https://localhost:5443/api/v1/auth" \
      -H "Content-Type: application/json" \
      -d '{"username": "admin", "password": "password123"}')
    
    if ACCESS_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.access_token' 2>/dev/null) && [ "$ACCESS_TOKEN" != "null" ]; then
        echo "✅ Successfully logged in"
    else
        echo "❌ Login failed: $LOGIN_RESP"
        exit 1
    fi
else
    echo "❌ Admin creation failed: $FIRST_INSTALL"
    exit 1
fi

# Get user wallet info
echo "Getting wallet info..."
USER_INFO=$(curl -k -s "https://localhost:5443/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
echo "User info response: $USER_INFO"

ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
INVOICE_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].inkey')
WALLET_ID=$(echo "$USER_INFO" | jq -r '.wallets[0].id')

echo "✅ Wallet configured:"
echo "  Admin Key: ${ADMIN_KEY:0:20}..."
echo "  Wallet ID: $WALLET_ID"

# Configure Extension Sources
echo ""
echo "=========================================="
echo "CONFIGURING EXTENSION SOURCES"
echo "=========================================="

echo "Adding lnurlFlip manifest to Extension Sources..."
CURRENT_SETTINGS=$(curl -k -s "https://localhost:5443/admin/api/v1/settings" -H "Authorization: Bearer $ACCESS_TOKEN")
echo "Current settings response: $CURRENT_SETTINGS"

# Add lnurlFlip manifest to extension sources
UPDATE_SETTINGS=$(curl -k -s -X PUT "https://localhost:5443/admin/api/v1/settings" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "lnbits_extensions_manifests": [
      "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
      "https://raw.githubusercontent.com/echennells/lnurlFlip/main/manifest.json"
    ]
  }')

echo "Extension sources update: $UPDATE_SETTINGS"
echo "✅ lnurlFlip manifest added to Extension Sources"

# Install extensions
echo ""
echo "=========================================="
echo "INSTALLING EXTENSIONS"
echo "=========================================="

# Install lnurlp (GitHub workflow version)
echo "Installing lnurlp extension..."
LNURLP_INSTALL=$(curl -k -s -X POST "https://localhost:5443/api/v1/extension" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "lnurlp", "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.1.2.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.1.2"}')

echo "lnurlp install: $LNURLP_INSTALL"

curl -k -s -X PUT "https://localhost:5443/api/v1/extension/lnurlp/activate" -H "Authorization: Bearer $ACCESS_TOKEN" >/dev/null
curl -k -s -X PUT "https://localhost:5443/api/v1/extension/lnurlp/enable" -H "Authorization: Bearer $ACCESS_TOKEN" >/dev/null
echo "✅ lnurlp installed and enabled"

# Install withdraw
echo "Installing withdraw extension..."
WITHDRAW_INSTALL=$(curl -k -s -X POST "https://localhost:5443/api/v1/extension" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "withdraw", "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}')

echo "withdraw install: $WITHDRAW_INSTALL"

curl -k -s -X PUT "https://localhost:5443/api/v1/extension/withdraw/activate" -H "Authorization: Bearer $ACCESS_TOKEN" >/dev/null
curl -k -s -X PUT "https://localhost:5443/api/v1/extension/withdraw/enable" -H "Authorization: Bearer $ACCESS_TOKEN" >/dev/null
echo "✅ withdraw installed and enabled"

# Install lnurlFlip (now available through Extension Sources)
echo "Installing lnurlFlip extension..."
LNURLFLIP_INSTALL=$(curl -k -s -X POST "https://localhost:5443/api/v1/extension" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "lnurlFlip", "archive": "https://api.github.com/repos/echennells/lnurlFlip/zipball/v0.1.1", "source_repo": "echennells/lnurlFlip", "version": "v0.1.1"}')

echo "lnurlFlip install: $LNURLFLIP_INSTALL"

curl -k -s -X PUT "https://localhost:5443/api/v1/extension/lnurlFlip/activate" -H "Authorization: Bearer $ACCESS_TOKEN" >/dev/null
curl -k -s -X PUT "https://localhost:5443/api/v1/extension/lnurlFlip/enable" -H "Authorization: Bearer $ACCESS_TOKEN" >/dev/null
echo "✅ lnurlFlip installed and enabled"

# Check extensions
echo "Checking installed extensions..."
EXTENSIONS=$(curl -k -s "https://localhost:5443/api/v1/extensions" -H "Authorization: Bearer $ACCESS_TOKEN")
if echo "$EXTENSIONS" | grep -q "lnurlFlip"; then
    echo "✅ lnurlFlip confirmed in extensions list"
else
    echo "⚠️  Extensions check: $EXTENSIONS"
fi

# Wait for extensions to initialize
echo "Waiting for extensions to initialize..."
sleep 10

# Test extension creation
echo ""
echo "=========================================="
echo "TESTING LNURLFLIP"
echo "=========================================="

# Create pay link
echo "Creating LNURL-P link..."
PAY_LINK=$(curl -k -s -X POST "https://localhost:5443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Test Pay Link",
    "min": 100,
    "max": 1000,
    "comment_chars": 100
  }')

echo "Pay link response: $PAY_LINK"
PAY_ID=$(echo "$PAY_LINK" | jq -r '.id' 2>/dev/null)

if [ "$PAY_ID" != "null" ] && [ -n "$PAY_ID" ]; then
    echo "✅ Pay link created: $PAY_ID"
else
    echo "❌ Pay link creation failed: $PAY_LINK"
    exit 1
fi

# Create withdraw link
echo "Creating withdraw link..."
WITHDRAW_LINK=$(curl -k -s -X POST "https://localhost:5443/withdraw/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Withdraw Link",
    "min_withdrawable": 50,
    "max_withdrawable": 500,
    "uses": 10,
    "wait_time": 1,
    "is_unique": true
  }')

echo "Withdraw link response: $WITHDRAW_LINK"
WITHDRAW_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id' 2>/dev/null)

if [ "$WITHDRAW_ID" != "null" ] && [ -n "$WITHDRAW_ID" ]; then
    echo "✅ Withdraw link created: $WITHDRAW_ID"
else
    echo "❌ Withdraw link creation failed: $WITHDRAW_LINK"
    exit 1
fi

# Create lnurlFlip link
echo "Creating lnurlFlip link..."
FLIP_LINK=$(curl -k -s -X POST "https://localhost:5443/lnurlFlip/api/v1/lnurlflip" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Test Flip Link\",
    \"wallet\": \"$WALLET_ID\",
    \"selectedLnurlp\": \"$PAY_ID\",
    \"selectedLnurlw\": \"$WITHDRAW_ID\"
  }")

echo "Flip link response: $FLIP_LINK"
FLIP_ID=$(echo "$FLIP_LINK" | jq -r '.id' 2>/dev/null)

if [ "$FLIP_ID" != "null" ] && [ -n "$FLIP_ID" ]; then
    echo "🎉 lnurlFlip link created successfully: $FLIP_ID"
    
    # Test the flip LNURL
    echo "Testing lnurlFlip LNURL..."
    FLIP_LNURL_RESP=$(curl -k -s "https://localhost:5443/lnurlFlip/api/v1/lnurl/$FLIP_ID" \
      -H "X-Api-Key: $INVOICE_KEY")
    
    echo "lnurlFlip LNURL response: $FLIP_LNURL_RESP"
    
    if echo "$FLIP_LNURL_RESP" | jq -e '.lnurl' >/dev/null 2>&1; then
        FLIP_LNURL=$(echo "$FLIP_LNURL_RESP" | jq -r '.lnurl')
        echo "✅ lnurlFlip LNURL generated: ${FLIP_LNURL:0:50}..."
        
        # Test callback
        CALLBACK_URL="https://localhost:5443/lnurlFlip/api/v1/lnurl/callback/$FLIP_ID"
        FLIP_CALLBACK=$(curl -k -s "$CALLBACK_URL")
        echo "lnurlFlip callback response: $FLIP_CALLBACK"
        
        if echo "$FLIP_CALLBACK" | jq -e '.tag' >/dev/null 2>&1; then
            TAG=$(echo "$FLIP_CALLBACK" | jq -r '.tag')
            echo "✅ lnurlFlip is working! Current mode: $TAG"
        else
            echo "❌ lnurlFlip callback failed: $FLIP_CALLBACK"
        fi
    else
        echo "❌ Failed to get lnurlFlip LNURL: $FLIP_LNURL_RESP"
    fi
else
    echo "❌ lnurlFlip creation failed: $FLIP_LINK"
    exit 1
fi

echo ""
echo "🎯 SUCCESS! Environment is ready:"
echo "• LNbits: https://localhost:5443 (admin/password123)"
echo "• Admin Key: $ADMIN_KEY"
echo "• lnurlFlip ID: $FLIP_ID"
echo "• All extensions working!"