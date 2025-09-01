#!/bin/bash
set -e

echo "=== HONEST VERIFICATION SCRIPT ==="
echo "This will prove step by step if extensions actually work"
echo "Timestamp: $(date)"
echo ""

# Start services
echo "1. Starting fresh services..."
docker compose up -d lnbits-1 lnbits-https-proxy
echo "Waiting 30 seconds for services to fully start..."
sleep 30

# Verify services are running
echo ""
echo "2. Verifying services are running..."
echo "LNbits HTTP health check:"
HTTP_HEALTH=$(curl -s "http://localhost:5001/api/v1/health" || echo "FAILED")
echo "$HTTP_HEALTH"

echo "HTTPS proxy check:"
HTTPS_CHECK=$(curl -k -s "https://localhost:5443/api/v1/health" || echo "FAILED")
echo "$HTTPS_CHECK"

if [[ "$HTTP_HEALTH" == "FAILED" ]] || [[ "$HTTPS_CHECK" == "FAILED" ]]; then
    echo "❌ Services failed to start properly"
    exit 1
fi

# Step 1: First install
echo ""
echo "3. Setting up admin user..."
FIRST_INSTALL_RESPONSE=$(curl -s -X PUT http://localhost:5001/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testadmin",
    "password": "test1234",
    "password_repeat": "test1234"
  }')

echo "First install response:"
echo "$FIRST_INSTALL_RESPONSE"

ACCESS_TOKEN=$(echo "$FIRST_INSTALL_RESPONSE" | jq -r '.access_token // empty')
if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
    echo "❌ Failed to get access token"
    exit 1
fi
echo "✅ Got access token: ${ACCESS_TOKEN:0:30}..."

# Step 2: Get wallet info
echo ""
echo "4. Getting wallet information..."
USER_INFO=$(curl -s -X GET "http://localhost:5001/api/v1/auth" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

echo "User info response:"
echo "$USER_INFO" | jq .

ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey // empty')
if [[ -z "$ADMIN_KEY" || "$ADMIN_KEY" == "null" ]]; then
    echo "❌ Failed to get admin key"
    exit 1
fi
echo "✅ Got admin key: ${ADMIN_KEY:0:20}..."

# Step 3: Install lnurlp extension
echo ""
echo "5. Installing lnurlp extension..."
LNURLP_INSTALL=$(curl -s -X POST http://localhost:5001/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "ext_id": "lnurlp",
    "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "payment_hash": null,
    "version": "1.0.1"
  }')

echo "lnurlp install response:"
echo "$LNURLP_INSTALL" | jq .

# Activate and enable
echo ""
echo "6. Activating lnurlp extension..."
ACTIVATE_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/lnurlp/activate" \
  -H "Authorization: Bearer $ACCESS_TOKEN")
echo "Activate response: $ACTIVATE_RESPONSE"

ENABLE_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/lnurlp/enable" \
  -H "Authorization: Bearer $ACCESS_TOKEN")
echo "Enable response: $ENABLE_RESPONSE"

# Step 4: Test if extension API is accessible
echo ""
echo "7. Testing if lnurlp API is accessible..."
echo "Testing via HTTP with X-API-KEY:"
HTTP_API_TEST=$(curl -s "http://localhost:5001/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" 2>&1)
echo "HTTP API Response: $HTTP_API_TEST"

echo "Testing via HTTPS with X-API-KEY:"
HTTPS_API_TEST=$(curl -k -s "https://localhost:5443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" 2>&1)
echo "HTTPS API Response: $HTTPS_API_TEST"

# Step 5: Try to create a pay link
echo ""
echo "8. Attempting to create a pay link via HTTPS..."
CREATE_LINK_RESPONSE=$(curl -k -s -X POST "https://localhost:5443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Honest Test Pay Link",
    "min": 100,
    "max": 10000,
    "comment_chars": 255
  }' 2>&1)

echo "Create link response:"
echo "$CREATE_LINK_RESPONSE" | jq . 2>/dev/null || echo "$CREATE_LINK_RESPONSE"

# Step 6: Verify the link was actually created
echo ""
echo "9. Verifying if the link was actually created..."
VERIFY_LINKS=$(curl -k -s "https://localhost:5443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" 2>&1)

echo "Links verification response:"
echo "$VERIFY_LINKS" | jq . 2>/dev/null || echo "$VERIFY_LINKS"

# Final verdict
echo ""
echo "=== HONEST VERDICT ==="
if echo "$CREATE_LINK_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    LINK_ID=$(echo "$CREATE_LINK_RESPONSE" | jq -r '.id')
    LINK_LNURL=$(echo "$CREATE_LINK_RESPONSE" | jq -r '.lnurl // "NO_LNURL"')
    echo "✅ SUCCESS: Pay link actually created!"
    echo "   Link ID: $LINK_ID"
    echo "   LNURL: $LINK_LNURL"
    
    # Double check it exists
    if echo "$VERIFY_LINKS" | jq -e '.[0].id' > /dev/null 2>&1; then
        echo "✅ VERIFIED: Link exists in database"
        echo "🎉 EXTENSIONS ARE ACTUALLY WORKING!"
    else
        echo "❌ FAILED: Link not found in database"
    fi
else
    echo "❌ FAILED: Could not create pay link"
    echo "❌ EXTENSIONS ARE NOT WORKING"
    echo ""
    echo "Error details:"
    echo "$CREATE_LINK_RESPONSE"
fi

echo ""
echo "Timestamp: $(date)"
echo "=== END HONEST VERIFICATION ==="