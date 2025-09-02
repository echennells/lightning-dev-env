#!/bin/bash
set -e

echo "=== TESTING BOTH EXTENSIONS ==="

# Setup via HTTPS
echo "Setting up..."
FIRST_INSTALL=$(curl -k -s -X PUT https://localhost:5443/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "password": "test123", "password_repeat": "test123"}')

ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token')
USER_INFO=$(curl -k -s "https://localhost:5443/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
echo "Got admin key: ${ADMIN_KEY:0:20}..."

# Install both extensions
echo "Installing lnurlp extension..."
curl -k -s -X POST https://localhost:5443/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "lnurlp", "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}' > /dev/null

curl -k -s -X PUT "https://localhost:5443/api/v1/extension/lnurlp/activate" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
curl -k -s -X PUT "https://localhost:5443/api/v1/extension/lnurlp/enable" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null

echo "Installing withdraw extension..."
curl -k -s -X POST https://localhost:5443/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "withdraw", "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}' > /dev/null

curl -k -s -X PUT "https://localhost:5443/api/v1/extension/withdraw/activate" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
curl -k -s -X PUT "https://localhost:5443/api/v1/extension/withdraw/enable" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null

sleep 3

# Test LNURL-P
echo ""
echo "Testing LNURL-P..."
PAY_LINK=$(curl -k -s -X POST "https://localhost:5443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"description": "Local Test Pay Link", "amount": 1000, "max": 10000, "comment_chars": 255}')

if echo "$PAY_LINK" | jq -e '.id' > /dev/null 2>&1; then
  echo "✅ LNURL-P works!"
  echo "   Created: $(echo "$PAY_LINK" | jq -r '.id')"
else
  echo "❌ LNURL-P failed: $PAY_LINK"
fi

# Test withdraw
echo ""
echo "Testing withdraw..."
WITHDRAW_LINK=$(curl -k -s -X POST "https://localhost:5443/withdraw/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"is_unique": true, "use_custom": false, "title": "vouchers", "min_withdrawable": 1000, "wait_time": 1, "max_withdrawable": 1000, "uses": 10, "custom_url": null}')

if echo "$WITHDRAW_LINK" | jq -e '.id' > /dev/null 2>&1; then
  echo "✅ Withdraw works!"
  echo "   Created: $(echo "$WITHDRAW_LINK" | jq -r '.id')"
else
  echo "❌ Withdraw failed: $(echo "$WITHDRAW_LINK" | head -c 200)"
fi