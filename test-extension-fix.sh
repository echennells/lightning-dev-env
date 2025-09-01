#!/bin/bash
set -e

echo "=== Testing Extension Fix ==="

# Get admin credentials from database
ADMIN_KEY=$(docker compose exec lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets LIMIT 1;'" | tr -d '\r\n')
WALLET_ID=$(docker compose exec lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT id FROM wallets LIMIT 1;'" | tr -d '\r\n')
USER_ID=$(docker compose exec lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT user FROM wallets LIMIT 1;'" | tr -d '\r\n')

echo "Admin Key: ${ADMIN_KEY:0:10}..."
echo "Wallet ID: $WALLET_ID"
echo "User ID: $USER_ID"

echo -e "\n1. Testing extension APIs before activation:"
echo "lnurlp API:"
curl -s "http://localhost:5001/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "Failed"

echo -e "\nwithdraw API:"
curl -s "http://localhost:5001/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "Failed"

echo -e "\n\n2. Enabling extensions for user in database:"
docker compose exec lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO extensions (extension, active, \\\"user\\\") 
    VALUES 
      ('lnurlp', 1, '$USER_ID'),
      ('withdraw', 1, '$USER_ID'),
      ('lnurlflip', 1, '$USER_ID');
  \"
  echo 'Extensions enabled in database'
"

echo -e "\n3. Testing extension APIs after database update:"
echo "lnurlp API:"
LNURLP_RESPONSE=$(curl -s "http://localhost:5001/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY")
echo "$LNURLP_RESPONSE"

echo -e "\nwithdraw API:"
WITHDRAW_RESPONSE=$(curl -s "http://localhost:5001/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY")
echo "$WITHDRAW_RESPONSE"

echo -e "\nlnurlflip API:"
FLIP_RESPONSE=$(curl -s "http://localhost:5001/lnurlflip/api/v1" -H "X-API-KEY: $ADMIN_KEY")
echo "$FLIP_RESPONSE"

if echo "$LNURLP_RESPONSE" | grep -q "[]"; then
  echo -e "\n4. Creating test LNURL pay link:"
  PAY_LINK=$(curl -s -X POST "http://localhost:5001/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "description": "Test Pay Link",
      "min": 10,
      "max": 10000,
      "comment_chars": 255
    }')
  
  PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id' 2>/dev/null || echo "")
  if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ]; then
    echo "✅ Created pay link: $PAY_LINK_ID"
  else
    echo "❌ Failed to create pay link: $PAY_LINK"
  fi
fi

echo -e "\n=== Extension Fix Test Complete ==="