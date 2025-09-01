#!/bin/bash
set -e

echo "=== Working Extension Fix for LNbits v1.2.1 ==="

echo "Solution found: Extension repos have breaking changes after LNbits v1.2.1"
echo "- lnurlp updated to lnurl v0.8.0 (incompatible)"
echo "- withdraw updated to lnurl v0.8.0 (incompatible)" 
echo "- LNbits v1.2.1 ships with lnurl v0.5.3"
echo ""
echo "Using compatible extension versions:"
echo "- withdraw: commit b42fee9 (before lnurl lib update)"
echo "- lnurlp: commit a8e8658 (before lnurl lib update)"
echo ""

# Get credentials
ADMIN_KEY=$(docker compose exec lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets LIMIT 1;'" | tr -d '\r\n')
USER_ID=$(docker compose exec lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT user FROM wallets LIMIT 1;'" | tr -d '\r\n')

echo "Testing extensions after compatibility fix..."
echo "Admin Key: ${ADMIN_KEY:0:10}..."
echo "User ID: $USER_ID"

echo -e "\n1. Enabling extensions for user:"
docker compose exec -T lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO extensions (extension, active, \\\"user\\\") 
    VALUES 
      ('lnurlp', 1, '$USER_ID'),
      ('withdraw', 1, '$USER_ID'),
      ('lnurlflip', 1, '$USER_ID');
  \"
  echo 'Extensions enabled for user'
"

echo -e "\n2. Testing lnurlp API:"
LNURLP_TEST=$(curl -s "http://localhost:5001/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY" 2>&1 || echo "Request failed")
echo "$LNURLP_TEST"

echo -e "\n3. Testing withdraw API:"
WITHDRAW_TEST=$(curl -s "http://localhost:5001/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY" 2>&1 || echo "Request failed")
echo "$WITHDRAW_TEST"

# Test creating actual links if APIs work
if echo "$LNURLP_TEST" | grep -q "\[\]"; then
    echo -e "\n4. ✅ Extensions working! Creating test pay link:"
    PAY_LINK=$(curl -s -X POST "http://localhost:5001/lnurlp/api/v1/links" \
      -H "X-API-KEY: $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "description": "Test Pay Link",
        "min": 10,
        "max": 10000,
        "comment_chars": 255
      }')
    
    echo "Pay link result: $PAY_LINK"
    
    PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id' 2>/dev/null || echo "")
    if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ]; then
        echo "✅ Successfully created pay link: $PAY_LINK_ID"
        
        # Test withdraw link
        WITHDRAW_LINK=$(curl -s -X POST "http://localhost:5001/withdraw/api/v1/links" \
          -H "X-API-KEY: $ADMIN_KEY" \
          -H "Content-Type: application/json" \
          -d '{
            "title": "Test Withdraw Link",
            "min_withdrawable": 10,
            "max_withdrawable": 10000,
            "uses": 100,
            "wait_time": 1,
            "is_unique": true
          }')
        
        echo "Withdraw link result: $WITHDRAW_LINK"
        WITHDRAW_LINK_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id' 2>/dev/null || echo "")
        if [ -n "$WITHDRAW_LINK_ID" ] && [ "$WITHDRAW_LINK_ID" != "null" ]; then
            echo "✅ Successfully created withdraw link: $WITHDRAW_LINK_ID"
            echo ""
            echo "🎉 ALL EXTENSIONS ARE WORKING!"
            echo "   - Pay Link ID: $PAY_LINK_ID"
            echo "   - Withdraw Link ID: $WITHDRAW_LINK_ID"
        fi
    fi
else
    echo -e "\n4. ❌ Extensions still not working. API response: $LNURLP_TEST"
fi

echo -e "\n=== Extension Fix Complete ==="