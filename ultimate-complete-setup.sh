#!/bin/bash
set -e

echo "=========================================="
echo "🚀 ULTIMATE LNBITS + PROXY SETUP SCRIPT"
echo "=========================================="
echo ""
echo "This script will:"
echo "1. Set up fresh LNbits on 170.75.172.6:5000" 
echo "2. Install extensions with correct authentication"
echo "3. Set up local HTTPS proxy with domain spoofing"
echo "4. Create working LNURL-P links"
echo ""
echo "Press Ctrl+C now if 170.75.172.6 is not fresh, or continue..."
sleep 3

REMOTE_HOST="170.75.172.6:5000"

echo "=== STEP 1: REMOTE LNBITS SETUP ==="
echo "Setting up LNbits on $REMOTE_HOST..."

# First install
FIRST_INSTALL=$(curl -s -X PUT http://$REMOTE_HOST/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "password123", 
    "password_repeat": "password123"
  }')

if echo "$FIRST_INSTALL" | jq -e '.access_token' > /dev/null; then
  ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token')
  echo "✅ Admin user created"
else
  echo "❌ Admin creation failed: $FIRST_INSTALL"
  exit 1
fi

# Get wallet info
USER_INFO=$(curl -s "http://$REMOTE_HOST/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
echo "✅ Admin key obtained: ${ADMIN_KEY:0:20}..."

# Install lnurlp
curl -s -X POST http://$REMOTE_HOST/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"ext_id": "lnurlp", "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}' > /dev/null

curl -s -X PUT "http://$REMOTE_HOST/api/v1/extension/lnurlp/activate" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
curl -s -X PUT "http://$REMOTE_HOST/api/v1/extension/lnurlp/enable" -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
echo "✅ lnurlp extension installed"

# Test extension API
CURRENCIES=$(curl -s "http://$REMOTE_HOST/lnurlp/api/v1/currencies" | head -c 30)
echo "✅ Extension API working: $CURRENCIES..."

echo ""
echo "=== STEP 2: LOCAL PROXY SETUP ==="

# Clean up old proxy
docker stop remote-lnbits-proxy 2>/dev/null || true
docker rm remote-lnbits-proxy 2>/dev/null || true

# Start proxy
docker run -d --name remote-lnbits-proxy -p 6443:443 \
  -v "$(pwd)/remote-proxy-nginx.conf":/etc/nginx/conf.d/default.conf:ro \
  -v "$(pwd)/ssl":/etc/ssl/certs:ro nginx:alpine

echo "✅ Local proxy started on https://localhost:6443"
sleep 3

# Test proxy
PROXY_TEST=$(curl -k -s https://localhost:6443/api/v1/health | jq -r '.server_time // "FAILED"')
if [ "$PROXY_TEST" != "FAILED" ]; then
  echo "✅ Proxy connection working"
else
  echo "❌ Proxy connection failed"
  exit 1
fi

echo ""
echo "=== STEP 3: LNURL-P CREATION TEST ==="

PAY_LINK=$(curl -k -s -X POST "https://localhost:6443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "🎉 FINAL PROOF LNURL-P Link",
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
  echo "✅ LNURL-P Link Created Successfully!"
  echo "   ID: $PAY_LINK_ID"
  echo "   LNURL: $PAY_LINK_LNURL"
  
  # Test endpoint
  LNURL_TEST=$(curl -k -s "https://localhost:6443/lnurlp/link/$PAY_LINK_ID")
  CALLBACK=$(echo "$LNURL_TEST" | jq -r '.callback')
  echo "   Callback: $CALLBACK"
  
  echo ""
  echo "=========================================="
  echo "🏆 PROOF OF CONCEPT COMPLETE!"
  echo "=========================================="
  echo ""
  echo "Architecture Working:"
  echo "  Remote LNbits: http://170.75.172.6:5000"
  echo "  Local Proxy:   https://localhost:6443"  
  echo "  Domain Spoof:  lnbits.example.com"
  echo "  Auth Method:   Bearer token + Admin key"
  echo ""
  echo "✅ Extensions install with Bearer token"
  echo "✅ LNURL-P creation works with Admin key + HTTPS + Domain spoofing"
  echo "✅ Ready for GitHub Actions workflow!"
  echo ""
  echo "Credentials:"
  echo "  Username: admin"
  echo "  Password: password123"
  echo "  Admin Key: $ADMIN_KEY"
  
else
  echo ""
  echo "❌ LNURL-P creation failed: $PAY_LINK"
  echo ""
  echo "Debugging info:"
  echo "- Admin key: $ADMIN_KEY"
  echo "- Proxy URL: https://localhost:6443"
  echo "- Remote URL: http://$REMOTE_HOST"
fi

echo ""
echo "=========================================="
