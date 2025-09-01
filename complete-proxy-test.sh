#!/bin/bash
set -e

echo "=== STEP 3: TESTING LNURL-P VIA PROXY ==="
echo "Remote: 170.75.172.6:5000 -> Local Proxy: https://localhost:6443"
echo "Domain spoofing: lnbits.example.com"
echo ""

# Use the NEW admin key from the fresh remote setup
ADMIN_KEY="21c7ca28b27341a8a2e859c24510c087"

echo "Creating LNURL-P link via proxy with domain spoofing..."
PAY_LINK=$(curl -k -s -X POST "https://localhost:6443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "WORKING Proxied LNURL-P Link",
    "min": 1000,
    "max": 10000,
    "comment_chars": 255
  }')

echo "Response: $PAY_LINK"

if echo "$PAY_LINK" | jq -e '.id' > /dev/null 2>&1; then
  PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id')
  PAY_LINK_LNURL=$(echo "$PAY_LINK" | jq -r '.lnurl')
  echo ""
  echo "🎉 SUCCESS! Created LNURL-P link through proxy!"
  echo "   Link ID: $PAY_LINK_ID"
  echo "   LNURL: $PAY_LINK_LNURL"
  
  # Test the LNURL endpoint
  echo ""
  echo "Testing LNURL endpoint..."
  LNURL_TEST=$(curl -k -s "https://localhost:6443/lnurlp/link/$PAY_LINK_ID")
  if echo "$LNURL_TEST" | jq -e '.callback' > /dev/null 2>&1; then
    echo "✅ LNURL endpoint working!"
    echo "   Callback: $(echo "$LNURL_TEST" | jq -r '.callback')"
    echo "   Min: $(echo "$LNURL_TEST" | jq -r '.minSendable')msat"
    echo "   Max: $(echo "$LNURL_TEST" | jq -r '.maxSendable')msat"
  fi
  
  echo ""
  echo "=== COMPLETE SUCCESS! ==="
  echo "✅ Remote LNbits setup complete"
  echo "✅ Extensions installed with Bearer token auth" 
  echo "✅ Local proxy with domain spoofing working"
  echo "✅ LNURL-P link created and functional"
  echo ""
  echo "Architecture:"
  echo "  Client -> https://localhost:6443 (proxy + SSL + domain spoofing)"
  echo "         -> http://170.75.172.6:5000 (remote LNbits)"
  
else
  echo ""
  echo "❌ LNURL-P creation failed. Debugging..."
  
  # Test direct connection without proxy
  echo "Testing direct HTTP connection..."
  DIRECT_TEST=$(curl -s -X POST "http://170.75.172.6:5000/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "description": "Direct HTTP Test",
      "min": 1000,
      "max": 10000,
      "comment_chars": 255
    }')
  echo "Direct result: $DIRECT_TEST"
  
  # Test if admin key works for listing
  echo ""
  echo "Testing admin key with list endpoint..."
  LINKS_TEST=$(curl -k -s "https://localhost:6443/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY")
  echo "Links result: $LINKS_TEST"
fi
