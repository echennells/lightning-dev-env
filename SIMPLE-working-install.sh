#!/bin/bash
set -e

echo "=== SIMPLE Working Extension Install ==="

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

echo "5. Installing lnurlp extension files..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  cd /app/lnbits/extensions/
  wget -q https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip
  unzip -q v1.0.1.zip
  mv lnurlp-1.0.1 lnurlp
  rm v1.0.1.zip
  echo 'lnurlp files installed'
"

echo "6. Installing withdraw extension files..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  cd /app/lnbits/extensions/
  wget -q https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip
  unzip -q v1.0.1.zip
  mv withdraw-1.0.1 withdraw
  rm v1.0.1.zip
  echo 'withdraw files installed'
"

echo "7. Running migrations for lnurlp..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  cd /app
  python -c '
import asyncio
import sys
sys.path.insert(0, \"/app\")

async def run_lnurlp_migrations():
    # Import the extension modules directly
    sys.path.insert(0, \"/app/lnbits/extensions\")
    
    # Import lnurlp migrations
    from lnurlp import migrations as lnurlp_migrations
    from lnurlp import db as lnurlp_db
    
    # Run migrations
    from lnbits.core.helpers import run_migration
    async with lnurlp_db.connect() as conn:
        await run_migration(conn, lnurlp_migrations, \"lnurlp\", None)
    print(\"lnurlp migrations completed\")

asyncio.run(run_lnurlp_migrations())
'
"

echo "8. Running migrations for withdraw..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  cd /app
  python -c '
import asyncio
import sys
sys.path.insert(0, \"/app\")

async def run_withdraw_migrations():
    # Import the extension modules directly
    sys.path.insert(0, \"/app/lnbits/extensions\")
    
    # Import withdraw migrations
    from withdraw import migrations as withdraw_migrations
    from withdraw import db as withdraw_db
    
    # Run migrations
    from lnbits.core.helpers import run_migration
    async with withdraw_db.connect() as conn:
        await run_migration(conn, withdraw_migrations, \"withdraw\", None)
    print(\"withdraw migrations completed\")

asyncio.run(run_withdraw_migrations())
'
"

echo "9. Registering extensions in database with full metadata..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT INTO installed_extensions (id, version, name, short_description, icon, stars, active, meta) 
    VALUES 
      ('lnurlp', '1.0.1', 'Pay Links', 'Make reusable LNURL pay links', 'https://github.com/lnbits/lnurlp/raw/main/static/image/lnurl-pay.png', 0, 1, '{\\\"installed_release\\\": {\\\"name\\\": \\\"Pay Links\\\", \\\"version\\\": \\\"1.0.1\\\", \\\"archive\\\": \\\"https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip\\\", \\\"source_repo\\\": \\\"https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json\\\", \\\"hash\\\": \\\"281cf5b0ebb4289f93c97ff9438abf18e01569508faaf389723144104bba2273\\\", \\\"min_lnbits_version\\\": \\\"1.0.0\\\", \\\"max_lnbits_version\\\": \\\"1.2.2\\\", \\\"is_version_compatible\\\": true, \\\"repo\\\": \\\"https://github.com/lnbits/lnurlp\\\"}}'),
      ('withdraw', '1.0.1', 'Withdraw Links', 'Make LNURL withdraw links', 'https://github.com/lnbits/withdraw/raw/main/static/image/lnurl-withdraw.png', 0, 1, '{\\\"installed_release\\\": {\\\"name\\\": \\\"Withdraw Links\\\", \\\"version\\\": \\\"1.0.1\\\", \\\"archive\\\": \\\"https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip\\\", \\\"source_repo\\\": \\\"https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json\\\", \\\"hash\\\": \\\"58b3847801efb0dcabd7fa8c9d16c08a2d50cd0e21e96b00b3a0baf88daa9a98\\\", \\\"min_lnbits_version\\\": \\\"1.0.0\\\", \\\"max_lnbits_version\\\": \\\"1.3.0\\\", \\\"is_version_compatible\\\": true, \\\"repo\\\": \\\"https://github.com/lnbits/withdraw\\\"}}');
  \"
  echo 'Extensions registered in installed_extensions'
"

echo "10. Enabling extensions for user in extensions table..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT INTO extensions (\\\"user\\\", extension, active, extra) 
    VALUES 
      ('$USER_ID', 'lnurlp', 1, null),
      ('$USER_ID', 'withdraw', 1, null);
  \"
  echo 'Extensions enabled for user: $USER_ID'
"

echo "11. Restarting LNbits - this should register routes on startup..."
docker compose restart $LNBITS_SERVICE
sleep 20

echo "12. Checking logs for extension loading..."
docker compose logs --tail=50 $LNBITS_SERVICE | grep -i "extension\|lnurlp\|withdraw" | tail -15

echo "13. Testing extension APIs..."
echo "lnurlp API test:"
LNURLP_RESULT=$(curl -s "http://localhost:$PORT/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "API call failed")
echo "$LNURLP_RESULT"

echo -e "\nwithdraw API test:"
WITHDRAW_RESULT=$(curl -s "http://localhost:$PORT/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "API call failed")
echo "$WITHDRAW_RESULT"

# Test if extensions actually work
if echo "$LNURLP_RESULT" | grep -q "\[\]"; then
    echo -e "\n✅ SUCCESS! Extensions are working!"
    echo "The complete process worked:"
    echo "  1. Downloaded and extracted extension files"
    echo "  2. Ran migrations directly on extension databases"
    echo "  3. Registered in database tables"
    echo "  4. Restart triggered route registration"
    
    # Try to create a test pay link
    echo -e "\n14. Creating test pay link to verify full functionality..."
    PAY_LINK=$(curl -s -X POST "http://localhost:$PORT/lnurlp/api/v1/links" \
      -H "X-API-KEY: $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "description": "Test Pay Link",
        "min": 10,
        "max": 10000,
        "comment_chars": 255
      }')
    
    PAY_LINK_ID=$(echo "$PAY_LINK" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ]; then
        echo "🎉 FULL SUCCESS! Created pay link: $PAY_LINK_ID"
        echo "Extensions are fully functional!"
    else
        echo "Pay link creation response: $PAY_LINK"
    fi
else
    echo -e "\n❌ Extensions still not working."
    echo "API Response: $LNURLP_RESULT"
    echo ""
    echo "This version of LNbits (v1.2.1) may have issues with extension route registration."
    echo "Consider using manual GUI installation or upgrading LNbits version."
fi

echo -e "\n=== Installation Complete ==="#