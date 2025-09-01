#!/bin/bash
set -e

echo "=== AUTO Extension Install (Using LNBITS_EXTENSIONS_DEFAULT_INSTALL) ==="

# Select which LNbits instance to work with (default: lnbits-1)
LNBITS_SERVICE=${1:-lnbits-1}
case $LNBITS_SERVICE in
  lnbits-1) PORT=5001 ;;
  lnbits-2) PORT=5002 ;;  
  lnbits-3) PORT=5003 ;;
  *) echo "Usage: $0 [lnbits-1|lnbits-2|lnbits-3]"; exit 1 ;;
esac

echo "Working with service: $LNBITS_SERVICE on port $PORT"

echo "1. Checking environment variable..."
docker compose exec -T $LNBITS_SERVICE bash -c "env | grep LNBITS_EXTENSIONS"

echo "2. Completely cleaning slate..."
docker compose stop $LNBITS_SERVICE
docker compose exec -T $LNBITS_SERVICE bash -c "
  rm -rf /app/lnbits/extensions/*
  rm -f /app/data/database.sqlite3
" || true

echo "3. Starting fresh - this should auto-install extensions..."
docker compose up -d $LNBITS_SERVICE
echo "Waiting for LNbits to fully start and auto-install extensions..."
sleep 30

echo "4. Getting admin key..."
ADMIN_KEY=$(docker compose exec -T $LNBITS_SERVICE bash -c "sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets WHERE adminkey IS NOT NULL LIMIT 1;'" | tr -d '\r\n' 2>/dev/null || echo "")

if [ -z "$ADMIN_KEY" ]; then
  echo "No admin key found - need to create initial wallet first"
  echo "Go to http://localhost:$PORT and create your first wallet"
  echo "Then the auto-installed extensions should be available"
  exit 0
fi

echo "Admin Key: ${ADMIN_KEY:0:10}..."

echo "5. Checking what got auto-installed..."
echo "Installed extensions:"
docker compose exec -T $LNBITS_SERVICE bash -c "sqlite3 /app/data/database.sqlite3 'SELECT id, version, active FROM installed_extensions;'" 2>/dev/null || echo "No installed extensions table yet"

echo "File system:"
docker compose exec -T $LNBITS_SERVICE bash -c "ls -la /app/lnbits/extensions/" 2>/dev/null || echo "Extensions directory not found"

echo "6. Checking startup logs for auto-install messages..."
docker compose logs --tail=50 $LNBITS_SERVICE | grep -i "extension\|install\|lnurlp\|withdraw" | tail -10

echo "7. Testing extension APIs..."
sleep 5

echo "lnurlp API test:"
LNURLP_RESULT=$(curl -s "http://localhost:$PORT/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY" 2>/dev/null || echo "API call failed")
echo "$LNURLP_RESULT"

echo -e "\nwithdraw API test:"
WITHDRAW_RESULT=$(curl -s "http://localhost:$PORT/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY" 2>/dev/null || echo "API call failed")
echo "$WITHDRAW_RESULT"

# Test if extensions actually work
if echo "$LNURLP_RESULT" | grep -q "\[\]"; then
    echo -e "\n8. ✅ SUCCESS! Auto-install worked!"
    echo "Extensions were automatically installed via LNBITS_EXTENSIONS_DEFAULT_INSTALL"
else
    echo -e "\n8. ❌ Auto-install may need manual wallet creation first."
    echo "Visit http://localhost:$PORT to create initial wallet and trigger extension installation"
fi

echo -e "\n=== Auto Installation Check Complete ==="
echo "The docker-compose.yml already has: LNBITS_EXTENSIONS_DEFAULT_INSTALL=lnurlp,withdraw"
echo "This should automatically install extensions on first run."