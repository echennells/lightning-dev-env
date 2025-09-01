#!/bin/bash
set -e

echo "=== TESTING LNURL-P CREATION VIA LOCAL PROXY ==="
echo "Local proxy (https://localhost:6443) -> Remote LNbits (170.75.172.6:5000)"
echo "With domain spoofing: lnbits.example.com"
echo ""

# Use the admin key from the remote setup
ADMIN_KEY="8aec86f9bc314a7286ea59c24510c087"

echo "Creating LNURL-P link via local proxy with domain spoofing..."
PAY_LINK=$(curl -k -s -X POST "https://localhost:6443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Proxied LNURL-P Link with Domain Spoofing",
    "min": 1000,
    "max": 10000,
    "comment_chars": 255
  }')

if echo "$PAY_LINK" | jq -e '.id' > /dev/null 2>&1; then
  PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id')
  PAY_LINK_LNURL=$(echo "$PAY_LINK" | jq -r '.lnurl')
  echo "🎉 SUCCESS! Created LNURL-P link through proxy!"
  echo "   Link ID: $PAY_LINK_ID"
  echo "   LNURL: $PAY_LINK_LNURL"
  
  # Test the LNURL endpoint
  echo ""
  echo "Testing LNURL endpoint..."
  LNURL_TEST=$(curl -k -s "https://localhost:6443/lnurlp/link/$PAY_LINK_ID")
  if echo "$LNURL_TEST" | jq -e '.callback' > /dev/null 2>&1; then
    echo "✅ LNURL endpoint responds correctly!"
    echo "   Callback: $(echo "$LNURL_TEST" | jq -r '.callback')"
    echo "   Min: $(echo "$LNURL_TEST" | jq -r '.minSendable')msat"
    echo "   Max: $(echo "$LNURL_TEST" | jq -r '.maxSendable')msat"
  else
    echo "LNURL endpoint response: $LNURL_TEST"
  fi
  
  # List all links to confirm
  echo ""
  echo "All LNURL-P links on remote instance:"
  curl -k -s "https://localhost:6443/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" | jq -r '.[] | "ID: " + .id + " | " + .description'
    
else
  echo "❌ LNURL-P creation failed:"
  echo "$PAY_LINK"
fi

echo ""
echo "=== PROXY TEST COMPLETE ==="
echo "Local proxy with domain spoofing: https://localhost:6443"
echo "Remote LNbits instance: 170.75.172.6:5000"
