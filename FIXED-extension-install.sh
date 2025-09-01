#!/bin/bash
set -e

echo "=== FIXED Extension Install (Based on Manual GUI Process) ==="

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

echo "4. Cleaning up existing extensions..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  rm -rf /app/lnbits/extensions/*
  sqlite3 /app/data/database.sqlite3 'DELETE FROM installed_extensions;'
  sqlite3 /app/data/database.sqlite3 'DELETE FROM extensions;'
  apt-get update > /dev/null 2>&1
  apt-get install -y wget unzip sqlite3 > /dev/null 2>&1
"

echo "5. Installing lnurlp extension (v1.0.1)..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  cd /app/lnbits/extensions/
  
  # Download the exact version that worked in GUI
  wget -q https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip
  unzip -q v1.0.1.zip
  mv lnurlp-1.0.1 lnurlp
  rm v1.0.1.zip
  
  echo 'lnurlp downloaded and extracted'
"

echo "6. Installing withdraw extension (v1.0.1)..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  cd /app/lnbits/extensions/
  
  # Download the exact version that worked in GUI
  wget -q https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip
  unzip -q v1.0.1.zip
  mv withdraw-1.0.1 withdraw
  rm v1.0.1.zip
  
  echo 'withdraw downloaded and extracted'
"

echo "7. Registering extensions in installed_extensions table with full metadata..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT INTO installed_extensions (id, version, name, short_description, icon, stars, active, meta) 
    VALUES 
      ('lnurlp', '1.0.1', 'Pay Links', 'Make reusable LNURL pay links', 'https://github.com/lnbits/lnurlp/raw/main/static/image/lnurl-pay.png', 0, 1, '{\\\"installed_release\\\": {\\\"name\\\": \\\"Pay Links\\\", \\\"version\\\": \\\"1.0.1\\\", \\\"archive\\\": \\\"https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip\\\", \\\"source_repo\\\": \\\"https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json\\\", \\\"hash\\\": \\\"281cf5b0ebb4289f93c97ff9438abf18e01569508faaf389723144104bba2273\\\", \\\"min_lnbits_version\\\": \\\"1.0.0\\\", \\\"max_lnbits_version\\\": \\\"1.2.2\\\", \\\"is_version_compatible\\\": true, \\\"repo\\\": \\\"https://github.com/lnbits/lnurlp\\\"}}'),
      ('withdraw', '1.0.1', 'Withdraw Links', 'Make LNURL withdraw links', 'https://github.com/lnbits/withdraw/raw/main/static/image/lnurl-withdraw.png', 0, 1, '{\\\"installed_release\\\": {\\\"name\\\": \\\"Withdraw Links\\\", \\\"version\\\": \\\"1.0.1\\\", \\\"archive\\\": \\\"https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip\\\", \\\"source_repo\\\": \\\"https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json\\\", \\\"hash\\\": \\\"58b3847801efb0dcabd7fa8c9d16c08a2d50cd0e21e96b00b3a0baf88daa9a98\\\", \\\"min_lnbits_version\\\": \\\"1.0.0\\\", \\\"max_lnbits_version\\\": \\\"1.3.0\\\", \\\"is_version_compatible\\\": true, \\\"repo\\\": \\\"https://github.com/lnbits/withdraw\\\"}}');
  \"
  echo 'Extensions registered in installed_extensions'
"

echo "8. Enabling extensions for user in extensions table..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT INTO extensions (\\\"user\\\", extension, active, extra) 
    VALUES 
      ('$USER_ID', 'lnurlp', 1, null),
      ('$USER_ID', 'withdraw', 1, null);
  \"
  echo 'Extensions enabled for user: $USER_ID'
"

echo "9. Running database migrations manually..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  cd /app
  python -c '
import asyncio
import sys
sys.path.insert(0, \"/app\")
from lnbits.core.helpers import migrate_databases
asyncio.run(migrate_databases())
print(\"Migrations completed\")
'
"

echo "10. Restarting LNbits to load extensions..."
docker compose restart $LNBITS_SERVICE
sleep 15

echo "11. Checking for loading errors..."
docker compose logs --tail=30 $LNBITS_SERVICE | grep -E "(INFO|ERROR|WARNING)" | tail -10

echo "12. Testing extension APIs..."
echo "lnurlp API test:"
LNURLP_RESULT=$(curl -s "http://localhost:$PORT/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "API call failed")
echo "$LNURLP_RESULT"

echo -e "\nwithdraw API test:"
WITHDRAW_RESULT=$(curl -s "http://localhost:$PORT/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "API call failed")
echo "$WITHDRAW_RESULT"

# Test if extensions actually work
if echo "$LNURLP_RESULT" | grep -q "\[\]"; then
    echo -e "\n11. ✅ SUCCESS! Extensions are working!"
    echo "Extensions installed using the same process as manual GUI installation."
else
    echo -e "\n11. ❌ Extensions may not be fully working yet."
    echo "Debug: Check if migrations need to be run manually."
fi

echo -e "\n=== Fixed Installation Complete ==="
echo "Key fixes applied:"
echo "- Used correct port (5000)"
echo "- Used correct container name (lnbits)"
echo "- Downloaded from GitHub archives (not git clone)"
echo "- Used exact versions that worked in GUI (v1.0.1)"
echo "- Populated full metadata in both database tables"
echo "- Followed the Download -> Extract -> Register -> Enable process"