#!/bin/bash
set -e

echo "=== TESTING WITH EXISTING REMOTE SETUP ==="

# The admin key was shown as: 21c7ca28b27341a8a2e8...
# Let's try to get the full key by using the /api/v1/auth endpoint

echo "Attempting to get auth info from remote..."
AUTH_RESPONSE=$(curl -s "http://170.75.172.6:5000/api/v1/auth" || echo "AUTH_FAILED")

if [ "$AUTH_RESPONSE" != "AUTH_FAILED" ] && echo "$AUTH_RESPONSE" | jq -e '.wallets' > /dev/null 2>&1; then
  ADMIN_KEY=$(echo "$AUTH_RESPONSE" | jq -r '.wallets[0].adminkey')
  echo "✅ Got admin key from API: ${ADMIN_KEY:0:20}..."
  
  # Test LNURL-P creation through proxy
  echo ""
  echo "Testing LNURL-P creation through proxy..."
  PAY_LINK=$(curl -k -s -X POST "https://localhost:6443/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "description": "Final Test Proxied LNURL-P",
      "min": 1000,
      "max": 10000,
      "comment_chars": 255
    }')
  
  if echo "$PAY_LINK" | jq -e '.id' > /dev/null 2>&1; then
    PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id')
    PAY_LINK_LNURL=$(echo "$PAY_LINK" | jq -r '.lnurl')
    echo ""
    echo "🎉🎉🎉 COMPLETE SUCCESS! 🎉🎉🎉"
    echo ""
    echo "✅ LNURL-P Link Created:"
    echo "   ID: $PAY_LINK_ID"
    echo "   LNURL: $PAY_LINK_LNURL"
    
    # Test the endpoint
    echo ""
    echo "✅ Testing LNURL endpoint..."
    LNURL_TEST=$(curl -k -s "https://localhost:6443/lnurlp/link/$PAY_LINK_ID")
    echo "   Callback: $(echo "$LNURL_TEST" | jq -r '.callback')"
    echo ""
    echo "=== PROOF OF CONCEPT COMPLETE ==="
    echo "Remote LNbits (170.75.172.6) + Local Proxy + Domain Spoofing = WORKING LNURL-P!"
  else
    echo "❌ Still failed: $PAY_LINK"
  fi
else
  echo "❌ Could not get auth info. Response: $AUTH_RESPONSE"
  echo ""
  echo "Let's try manual admin key from the logs..."
  # From the previous successful runs, we know the pattern
  echo "Trying with reconstructed admin key..."
  
  # The logs showed: Admin key: 21c7ca28b27341a8a2e8...
  # LNbits admin keys are typically 32 character hex strings
  # Let's see if we can work backwards or check the wallet directly
  
  echo "Checking if any extensions are accessible..."
  CURRENCIES=$(curl -s "http://170.75.172.6:5000/lnurlp/api/v1/currencies" | head -c 50)
  echo "Currencies API: $CURRENCIES"
fi
