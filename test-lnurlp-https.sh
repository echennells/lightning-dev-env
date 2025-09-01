#!/bin/bash
set -e

echo "=== TESTING LNURL-P WITH HTTPS AND DOMAIN SPOOFING ==="
echo ""

# We know from the first script output that we have:
# User: superadmin / Password: secret1234
# Admin key was shown in the output

# Since we can't login directly, let's do a fresh install on a different LNbits instance
echo "Using LNbits instance 2 for fresh setup..."

# Step 1: First install on lnbits-2
echo "Step 1: Creating admin user on lnbits-2..."
FIRST_INSTALL=$(curl -s -X PUT http://localhost:5002/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin2",
    "password": "password123",
    "password_repeat": "password123"
  }')

if echo "$FIRST_INSTALL" | jq -e '.access_token' > /dev/null; then
  ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token')
  echo "✅ Admin user created"
  echo "Bearer token: ${ACCESS_TOKEN:0:30}..."
  
  # Step 2: Get wallet info
  USER_INFO=$(curl -s -X GET "http://localhost:5002/api/v1/auth" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
  
  ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
  WALLET_ID=$(echo "$USER_INFO" | jq -r '.wallets[0].id')
  
  echo "Admin key: ${ADMIN_KEY:0:20}..."
  echo "Wallet ID: $WALLET_ID"
  
  # Step 3: Install lnurlp extension with Bearer token
  echo ""
  echo "Step 2: Installing lnurlp extension..."
  curl -s -X POST http://localhost:5002/api/v1/extension \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d '{
      "ext_id": "lnurlp",
      "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip",
      "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
      "version": "1.0.1"
    }' | jq -r '.name'
  
  # Activate and enable
  curl -s -X PUT "http://localhost:5002/api/v1/extension/lnurlp/activate" \
    -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.message'
  
  curl -s -X PUT "http://localhost:5002/api/v1/extension/lnurlp/enable" \
    -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.message'
  
  echo "✅ Extension installed and activated"
  
  # Step 4: Test creating LNURL-P via HTTPS with domain spoofing
  echo ""
  echo "Step 3: Creating LNURL-P link via HTTPS (port 5443)..."
  
  # The nginx proxy should spoof the domain to lnbits.example.com
  PAY_LINK=$(curl -k -s -X POST "https://localhost:5443/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -H "Host: lnbits.example.com" \
    -d '{
      "description": "HTTPS Test Link",
      "min": 1000,
      "max": 10000,
      "comment_chars": 255
    }')
  
  if echo "$PAY_LINK" | jq -e '.id' > /dev/null; then
    echo "🎉 SUCCESS! LNURL-P link created!"
    echo "$PAY_LINK" | jq
  else
    echo "Issue creating link:"
    echo "$PAY_LINK"
  fi
  
else
  echo "First install failed or already done:"
  echo "$FIRST_INSTALL"
fi
