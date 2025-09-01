#!/bin/bash
set -e

echo "=== Testing HAR-based Extension Installation ==="

# Test with current instance
ADMIN_KEY="e0f0787a249a455f971ee8ed08ddb735"
BASE_URL="http://localhost:5001"

echo "Using admin key: ${ADMIN_KEY:0:10}..."

# Test the HAR sequence
echo "1. Installing lnurlp via POST..."
INSTALL_RESULT=$(curl -s -X POST "$BASE_URL/api/v1/extension" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $ADMIN_KEY" \
  -d '{
    "ext_id": "lnurlp",
    "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "payment_hash": null,
    "version": "1.0.1"
  }')

echo "Install result: $INSTALL_RESULT"

if echo "$INSTALL_RESULT" | jq -e '.code' >/dev/null 2>&1; then
  echo "✅ Install succeeded, activating..."
  
  # Activate
  ACTIVATE_RESULT=$(curl -s -X PUT "$BASE_URL/api/v1/extension/lnurlp/activate" \
    -H "X-API-Key: $ADMIN_KEY")
  echo "Activate result: $ACTIVATE_RESULT"
  
  # Enable
  ENABLE_RESULT=$(curl -s -X PUT "$BASE_URL/api/v1/extension/lnurlp/enable" \
    -H "X-API-Key: $ADMIN_KEY")
  echo "Enable result: $ENABLE_RESULT"
  
  echo -e "\n2. Testing API endpoint..."
  sleep 2
  API_TEST=$(curl -s "$BASE_URL/lnurlp/api/v1" -H "X-API-Key: $ADMIN_KEY")
  echo "API test: $API_TEST"
  
  if echo "$API_TEST" | grep -q "\[\]"; then
    echo "🎉 SUCCESS! Extension API is working!"
  else
    echo "❌ API not working: $API_TEST"
  fi
else
  echo "❌ Install failed: $INSTALL_RESULT"
fi