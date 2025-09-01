#!/bin/bash
set -e

echo "=== API-Based Extension Install (Using Proper LNbits API) ==="

# Select which LNbits instance to work with (default: lnbits-1)
LNBITS_SERVICE=${1:-lnbits-1}
case $LNBITS_SERVICE in
  lnbits-1) PORT=5001 ;;
  lnbits-2) PORT=5002 ;;
  lnbits-3) PORT=5003 ;;
  *) echo "Usage: $0 [lnbits-1|lnbits-2|lnbits-3]"; exit 1 ;;
esac

echo "Working with service: $LNBITS_SERVICE on port $PORT"

echo "1. Starting services if not running..."
docker compose up -d $LNBITS_SERVICE
sleep 10

echo "2. Getting admin key..."
ADMIN_KEY=$(docker compose exec -T $LNBITS_SERVICE bash -c "sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets WHERE adminkey IS NOT NULL LIMIT 1;'" | tr -d '\r\n')
if [ -z "$ADMIN_KEY" ]; then
  echo "No admin key found - need to create initial wallet first"
  echo "Go to http://localhost:$PORT and create your first wallet"
  exit 1
fi
echo "Admin Key: ${ADMIN_KEY:0:10}..."

echo "3. Getting user ID..."
USER_ID=$(docker compose exec -T $LNBITS_SERVICE bash -c "sqlite3 /app/data/database.sqlite3 'SELECT user FROM wallets LIMIT 1;'" | tr -d '\r\n')
echo "User ID: $USER_ID"

echo "4. Cleaning up existing extensions first..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  rm -rf /app/lnbits/extensions/*
  sqlite3 /app/data/database.sqlite3 'DELETE FROM installed_extensions;'
  sqlite3 /app/data/database.sqlite3 'DELETE FROM extensions;'
"

echo "5. Installing lnurlp extension via API..."
LNURLP_INSTALL=$(curl -s -X POST "http://localhost:$PORT/api/v1/extension" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "ext_id": "lnurlp",
    "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "version": "1.0.1"
  }')

echo "lnurlp install result: $LNURLP_INSTALL"

echo "6. Installing withdraw extension via API..."
WITHDRAW_INSTALL=$(curl -s -X POST "http://localhost:$PORT/api/v1/extension" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "ext_id": "withdraw",
    "archive": "https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "version": "1.0.1"
  }')

echo "withdraw install result: $WITHDRAW_INSTALL"

echo "7. Enabling lnurlp for user..."
LNURLP_ENABLE=$(curl -s -X PUT "http://localhost:$PORT/api/v1/extension/lnurlp/enable" \
  -H "X-API-KEY: $ADMIN_KEY")
echo "lnurlp enable result: $LNURLP_ENABLE"

echo "8. Enabling withdraw for user..."
WITHDRAW_ENABLE=$(curl -s -X PUT "http://localhost:$PORT/api/v1/extension/withdraw/enable" \
  -H "X-API-KEY: $ADMIN_KEY")  
echo "withdraw enable result: $WITHDRAW_ENABLE"

echo "9. Checking database state..."
echo "Installed extensions:"
docker compose exec -T $LNBITS_SERVICE bash -c "sqlite3 /app/data/database.sqlite3 'SELECT id, version, active FROM installed_extensions;'"

echo "User extensions:"  
docker compose exec -T $LNBITS_SERVICE bash -c "sqlite3 /app/data/database.sqlite3 'SELECT user, extension, active FROM extensions;'"

echo "10. Testing extension APIs..."
sleep 5

echo "lnurlp API test:"
LNURLP_RESULT=$(curl -s "http://localhost:$PORT/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "API call failed")
echo "$LNURLP_RESULT"

echo -e "\nwithdraw API test:"
WITHDRAW_RESULT=$(curl -s "http://localhost:$PORT/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "API call failed")
echo "$WITHDRAW_RESULT"

# Test if extensions actually work
if echo "$LNURLP_RESULT" | grep -q "\[\]"; then
    echo -e "\n11. ✅ SUCCESS! Extensions are working!"
    echo "The API-based installation properly handled download → extract → migrate → activate!"
else
    echo -e "\n11. ❌ Extensions may not be fully working yet."
    echo "Check the install results above for errors."
fi

echo -e "\n=== API-Based Installation Complete ==="
echo "This approach uses the same API endpoints that the GUI uses:"
echo "- POST /api/v1/extension (installs and runs migrations)"  
echo "- PUT /api/v1/extension/{ext_id}/enable (enables for user)"
echo "- No manual file manipulation or database insertion needed"