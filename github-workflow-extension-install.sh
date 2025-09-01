#!/bin/bash
set -e

echo "=== GitHub Workflow Extension Installation ==="

LNBITS_SERVICE=${1:-lnbits-1}
PORT=${2:-5001}
BASE_URL="http://localhost:$PORT"

echo "Installing extensions for $LNBITS_SERVICE on $BASE_URL"

# Wait for LNbits to be ready
echo "1. Waiting for LNbits to be ready..."
for i in {1..60}; do
    HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null "$BASE_URL/api/v1/health" 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ LNbits is ready"
        break
    elif [ "$HTTP_CODE" = "307" ]; then
        echo "⚠️ First install needed, completing..."
        
        # Complete first install
        FIRST_INSTALL=$(curl -s -X PUT "$BASE_URL/api/v1/auth/first_install" \
            -H "Content-Type: application/json" \
            -d '{"username": "superadmin", "password": "secret1234", "password_repeat": "secret1234"}')
        
        # Wait a moment then check again
        sleep 3
        continue
    fi
    
    echo "Attempt $i/60: Waiting for LNbits (HTTP $HTTP_CODE)..."
    sleep 2
done

# Get admin key from the configured super user
echo "2. Getting admin key from super user account..."
ADMIN_KEY=$(docker compose exec -T $LNBITS_SERVICE bash -c "
    sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets WHERE adminkey IS NOT NULL LIMIT 1;' 2>/dev/null
" | tr -d '\r\n')

if [ -z "$ADMIN_KEY" ]; then
    echo "❌ Could not get admin key"
    exit 1
fi

echo "✅ Got admin key: ${ADMIN_KEY:0:10}..."

# Extension installation using the exact sequence from HAR
echo "3. Installing extensions using HAR sequence..."

# Install lnurlp
echo "Installing lnurlp extension..."
LNURLP_INSTALL=$(curl -s -X POST "$BASE_URL/api/v1/extension" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{
        "ext_id": "lnurlp",
        "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip",
        "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
        "payment_hash": null,
        "version": "1.0.1"
    }')

echo "lnurlp install result: $LNURLP_INSTALL"

# Activate lnurlp
echo "Activating lnurlp extension..."
LNURLP_ACTIVATE=$(curl -s -X PUT "$BASE_URL/api/v1/extension/lnurlp/activate" \
    -H "X-API-Key: $ADMIN_KEY")

echo "lnurlp activate result: $LNURLP_ACTIVATE"

# Enable lnurlp
echo "Enabling lnurlp extension..."
LNURLP_ENABLE=$(curl -s -X PUT "$BASE_URL/api/v1/extension/lnurlp/enable" \
    -H "X-API-Key: $ADMIN_KEY")

echo "lnurlp enable result: $LNURLP_ENABLE"

# Install withdraw
echo "Installing withdraw extension..."
WITHDRAW_INSTALL=$(curl -s -X POST "$BASE_URL/api/v1/extension" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $ADMIN_KEY" \
    -d '{
        "ext_id": "withdraw",
        "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip",
        "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
        "payment_hash": null,
        "version": "1.0.1"
    }')

echo "withdraw install result: $WITHDRAW_INSTALL"

# Activate withdraw
echo "Activating withdraw extension..."
WITHDRAW_ACTIVATE=$(curl -s -X PUT "$BASE_URL/api/v1/extension/withdraw/activate" \
    -H "X-API-Key: $ADMIN_KEY")

echo "withdraw activate result: $WITHDRAW_ACTIVATE"

# Enable withdraw
echo "Enabling withdraw extension..."
WITHDRAW_ENABLE=$(curl -s -X PUT "$BASE_URL/api/v1/extension/withdraw/enable" \
    -H "X-API-Key: $ADMIN_KEY")

echo "withdraw enable result: $WITHDRAW_ENABLE"

# Test the extensions
echo "4. Testing extension APIs..."
sleep 3

echo "Testing lnurlp API..."
LNURLP_TEST=$(curl -s "$BASE_URL/lnurlp/api/v1" -H "X-API-Key: $ADMIN_KEY")
echo "lnurlp API response: $LNURLP_TEST"

echo "Testing withdraw API..."
WITHDRAW_TEST=$(curl -s "$BASE_URL/withdraw/api/v1" -H "X-API-Key: $ADMIN_KEY")
echo "withdraw API response: $WITHDRAW_TEST"

# Check if both APIs work
if echo "$LNURLP_TEST" | grep -q "\[\]" && echo "$WITHDRAW_TEST" | grep -q "\[\]"; then
    echo "🎉 SUCCESS! Both extensions are working!"
    
    # Test creating a pay link
    echo "5. Creating test pay link..."
    PAY_LINK=$(curl -s -X POST "$BASE_URL/lnurlp/api/v1/links" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $ADMIN_KEY" \
        -d '{
            "description": "GitHub Workflow Test Link",
            "min": 10,
            "max": 10000,
            "comment_chars": 255
        }')
    
    PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id' 2>/dev/null || echo "null")
    if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ]; then
        echo "🎉 FULL SUCCESS! Created pay link: $PAY_LINK_ID"
    else
        echo "⚠️ Extension APIs work but link creation failed: $PAY_LINK"
    fi
else
    echo "❌ Extension APIs not working properly"
    echo "lnurlp response: $LNURLP_TEST"
    echo "withdraw response: $WITHDRAW_TEST"
fi

echo "=== Extension installation complete ==="