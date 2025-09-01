#!/bin/bash
set -e

echo "=== Fixed LNbits Extension Installation ==="
echo "Using the exact API sequence the GUI uses"

# Configuration
LNBITS_SERVICE=${1:-lnbits-1}
case $LNBITS_SERVICE in
  lnbits-1) PORT=5001 ;;
  lnbits-2) PORT=5002 ;;
  lnbits-3) PORT=5003 ;;
  *) echo "Usage: $0 [lnbits-1|lnbits-2|lnbits-3]"; exit 1 ;;
esac

BASE_URL="http://localhost:$PORT"
echo "Working with: $LNBITS_SERVICE on port $PORT"

# Helper function for API calls
api_call() {
    local method=$1
    local url=$2
    local headers=$3
    local data=$4
    local max_retries=3
    
    for i in $(seq 1 $max_retries); do
        if [ -n "$data" ]; then
            response=$(curl -s -X "$method" "$url" $headers -d "$data" 2>&1 || echo "")
        else
            response=$(curl -s -X "$method" "$url" $headers 2>&1 || echo "")
        fi
        
        if ! echo "$response" | grep -q "Connection refused"; then
            echo "$response"
            return 0
        fi
        
        echo "Attempt $i/$max_retries: Connection refused, retrying..." >&2
        sleep 2
    done
    
    echo "Failed after $max_retries attempts" >&2
    return 1
}

echo "1. Checking LNbits status..."
# Check if we get a redirect (307) which means first_install needed
HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null "$BASE_URL/api/v1/health" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "307" ]; then
    echo "⚠️ LNbits needs first install setup"
    
    echo "Completing first install..."
    FIRST_INSTALL=$(curl -s -X PUT "$BASE_URL/api/v1/auth/first_install" \
        -H "Content-Type: application/json" \
        -d '{"username": "admin", "password": "admin1234", "password_repeat": "admin1234"}')
    
    ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token' 2>/dev/null)
    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        echo "❌ First install failed: $FIRST_INSTALL"
        exit 1
    fi
    
    echo "✅ First install completed"
else
    echo "✅ LNbits is ready"
    # If already set up, we need to get credentials differently
    echo "❌ Script needs modification to handle existing installations"
    echo "Please provide ACCESS_TOKEN or ADMIN_KEY manually for existing installations"
    exit 1
fi

echo "2. Getting user credentials..."
USER_INFO=$(curl -s -X GET "$BASE_URL/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey' 2>/dev/null)
USER_ID=$(echo "$USER_INFO" | jq -r '.id' 2>/dev/null)

if [ -z "$ADMIN_KEY" ] || [ "$ADMIN_KEY" = "null" ]; then
    echo "❌ Could not get admin key: $USER_INFO"
    exit 1
fi

echo "✅ Got credentials"
echo "Admin Key: ${ADMIN_KEY:0:10}..."
echo "User ID: $USER_ID"

# Extensions to install
EXTENSIONS='[
    {
        "ext_id": "lnurlp",
        "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip",
        "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
        "version": "1.0.1"
    },
    {
        "ext_id": "withdraw", 
        "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip",
        "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
        "version": "1.0.1"
    }
]'

echo "3. Installing extensions using correct API sequence..."

echo "$EXTENSIONS" | jq -c '.[]' | while read -r extension; do
    EXT_ID=$(echo "$extension" | jq -r '.ext_id')
    ARCHIVE=$(echo "$extension" | jq -r '.archive')
    SOURCE_REPO=$(echo "$extension" | jq -r '.source_repo')
    VERSION=$(echo "$extension" | jq -r '.version')
    
    echo -e "\n--- Installing $EXT_ID ---"
    
    # Step 1: POST /api/v1/extension - Install extension
    echo "Step 1: Installing $EXT_ID..."
    INSTALL_DATA=$(cat <<EOF
{
    "ext_id": "$EXT_ID",
    "archive": "$ARCHIVE", 
    "source_repo": "$SOURCE_REPO",
    "payment_hash": null,
    "version": "$VERSION"
}
EOF
)
    
    INSTALL_RESPONSE=$(api_call "POST" "$BASE_URL/api/v1/extension" \
        "-H 'Content-Type: application/json' -H 'X-API-Key: $ADMIN_KEY'" \
        "$INSTALL_DATA")
    
    echo "Install response: $INSTALL_RESPONSE"
    
    if echo "$INSTALL_RESPONSE" | jq -e '.code' >/dev/null 2>&1; then
        echo "✅ $EXT_ID installed"
    else
        echo "⚠️ Install may have failed: $INSTALL_RESPONSE"
        continue
    fi
    
    # Step 2: PUT /api/v1/extension/{ext_id}/activate - Activate extension (registers routes!)
    echo "Step 2: Activating $EXT_ID..."
    ACTIVATE_RESPONSE=$(api_call "PUT" "$BASE_URL/api/v1/extension/$EXT_ID/activate" \
        "-H 'X-API-Key: $ADMIN_KEY'")
    
    echo "Activate response: $ACTIVATE_RESPONSE"
    
    if echo "$ACTIVATE_RESPONSE" | jq -e '.success' >/dev/null 2>&1; then
        echo "✅ $EXT_ID activated"
    else
        echo "⚠️ Activation may have failed: $ACTIVATE_RESPONSE"
    fi
    
    # Step 3: PUT /api/v1/extension/{ext_id}/enable - Enable for user
    echo "Step 3: Enabling $EXT_ID for user..."
    ENABLE_RESPONSE=$(api_call "PUT" "$BASE_URL/api/v1/extension/$EXT_ID/enable" \
        "-H 'X-API-Key: $ADMIN_KEY'")
    
    echo "Enable response: $ENABLE_RESPONSE"
    
    if echo "$ENABLE_RESPONSE" | jq -e '.success' >/dev/null 2>&1; then
        echo "✅ $EXT_ID enabled for user"
    else
        echo "⚠️ Enable may have failed: $ENABLE_RESPONSE"
    fi
    
    echo "✅ $EXT_ID installation complete!"
done

# Wait for everything to be loaded
echo -e "\n4. Waiting for extensions to be fully loaded..."
sleep 5

echo "5. Testing extension APIs..."

echo "Testing lnurlp API:"
LNURLP_TEST=$(api_call "GET" "$BASE_URL/lnurlp/api/v1" "-H 'X-API-Key: $ADMIN_KEY'")
echo "lnurlp response: $LNURLP_TEST"

echo -e "\nTesting withdraw API:"
WITHDRAW_TEST=$(api_call "GET" "$BASE_URL/withdraw/api/v1" "-H 'X-API-Key: $ADMIN_KEY'")
echo "withdraw response: $WITHDRAW_TEST"

# Check if APIs work (should return empty array [] for successful extension API)
if echo "$LNURLP_TEST" | grep -q '\[\]'; then
    echo -e "\n🎉 SUCCESS! Extensions are working!"
    
    # Try creating a test pay link
    echo -e "\n6. Creating test pay link..."
    PAY_LINK=$(api_call "POST" "$BASE_URL/lnurlp/api/v1/links" \
        "-H 'Content-Type: application/json' -H 'X-API-Key: $ADMIN_KEY'" \
        '{
            "description": "Test Pay Link",
            "min": 10,
            "max": 10000,
            "comment_chars": 255
        }')
    
    PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id' 2>/dev/null)
    if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ]; then
        echo "🎉 FULL SUCCESS! Created pay link: $PAY_LINK_ID"
        echo "Extensions are fully functional!"
    else
        echo "Pay link creation response: $PAY_LINK"
        echo "Extensions APIs work but pay link creation had issues"
    fi
else
    echo -e "\n❌ Extension APIs not working properly"
    echo "lnurlp response: $LNURLP_TEST"
    echo "withdraw response: $WITHDRAW_TEST"
    
    # Debug info
    echo -e "\nDebug: Checking what extensions are available..."
    ALL_EXTS=$(api_call "GET" "$BASE_URL/api/v1/extension" "-H 'Authorization: Bearer $ACCESS_TOKEN'")
    echo "Available extensions: $ALL_EXTS"
fi

echo -e "\n=== Installation Complete ==="
echo "LNbits URL: $BASE_URL"
echo "Admin Key: $ADMIN_KEY"
echo ""
echo "This script used the exact API sequence the GUI uses:"
echo "1. POST /api/v1/extension (install)" 
echo "2. PUT /api/v1/extension/{ext}/activate (register routes)"
echo "3. PUT /api/v1/extension/{ext}/enable (enable for user)"