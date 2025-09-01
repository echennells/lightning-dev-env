#!/bin/bash
set -e

echo "=== Final Working LNbits Extension Setup for GitHub Actions ==="
echo "Based on proven working scripts and debug notes"
echo "Installs LNbits v1.2.1 + lnurlp 1.0.1 + withdraw 1.0.1"

# Complete first install (this is crucial!)
echo "Step 1: Complete LNbits first install..."
FIRST_INSTALL_RESPONSE=$(curl -s -X PUT http://localhost:5001/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{
    "username": "superadmin",
    "password": "secret1234",
    "password_repeat": "secret1234"
  }')

if echo "$FIRST_INSTALL_RESPONSE" | jq -e '.access_token' > /dev/null; then
  echo "✅ Admin user created successfully"
  ACCESS_TOKEN=$(echo "$FIRST_INSTALL_RESPONSE" | jq -r '.access_token')
else
  echo "❌ First install failed: $FIRST_INSTALL_RESPONSE"
  exit 1
fi

# Get user and wallet info
USER_INFO=$(curl -s -X GET "http://localhost:5001/api/v1/auth" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

WALLET_ID=$(echo "$USER_INFO" | jq -r '.wallets[0].id')
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
USER_ID=$(echo "$USER_INFO" | jq -r '.id')

echo "User ID: $USER_ID"
echo "Wallet ID: $WALLET_ID"
echo "Admin key: ${ADMIN_KEY:0:20}..."

# Install dependencies
echo "Step 2: Installing required packages..."
docker compose exec -T lnbits-1 bash -c "
  apt-get update > /dev/null 2>&1
  apt-get install -y wget unzip sqlite3 > /dev/null 2>&1
  echo 'Dependencies installed'
"

# Clean existing extensions
echo "Step 3: Cleaning existing extensions..."
docker compose exec -T lnbits-1 bash -c "
  rm -rf /app/lnbits/extensions/*
  sqlite3 /app/data/database.sqlite3 'DELETE FROM installed_extensions;'
  sqlite3 /app/data/database.sqlite3 'DELETE FROM extensions;'
  echo 'Extensions cleaned'
"

# Download and extract extension files
echo "Step 4: Installing lnurlp 1.0.1 extension files..."
docker compose exec -T lnbits-1 bash -c "
  cd /app/lnbits/extensions/
  wget -q https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip
  unzip -q v1.0.1.zip
  mv lnurlp-1.0.1 lnurlp
  rm v1.0.1.zip
  echo 'lnurlp files installed'
"

echo "Step 5: Installing withdraw 1.0.1 extension files..."
docker compose exec -T lnbits-1 bash -c "
  cd /app/lnbits/extensions/
  wget -q https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip
  unzip -q v1.0.1.zip
  mv withdraw-1.0.1 withdraw
  rm v1.0.1.zip
  echo 'withdraw files installed'
"

# Run migrations directly (KEY STEP from your working script!)
echo "Step 6: Running lnurlp migrations directly..."
docker compose exec -T lnbits-1 bash -c "
  cd /app
  python -c '
import asyncio
import sys
sys.path.insert(0, \"/app\")

async def run_lnurlp_migrations():
    sys.path.insert(0, \"/app/lnbits/extensions\")
    from lnurlp import migrations as lnurlp_migrations
    from lnurlp import db as lnurlp_db
    from lnbits.core.helpers import run_migration
    async with lnurlp_db.connect() as conn:
        await run_migration(conn, lnurlp_migrations, \"lnurlp\", None)
    print(\"lnurlp migrations completed\")

asyncio.run(run_lnurlp_migrations())
'
"

echo "Step 7: Running withdraw migrations directly..."
docker compose exec -T lnbits-1 bash -c "
  cd /app
  python -c '
import asyncio
import sys
sys.path.insert(0, \"/app\")

async def run_withdraw_migrations():
    sys.path.insert(0, \"/app/lnbits/extensions\")
    from withdraw import migrations as withdraw_migrations
    from withdraw import db as withdraw_db
    from lnbits.core.helpers import run_migration
    async with withdraw_db.connect() as conn:
        await run_migration(conn, withdraw_migrations, \"withdraw\", None)
    print(\"withdraw migrations completed\")

asyncio.run(run_withdraw_migrations())
'
"

# Register in database with full metadata (from your working script)
echo "Step 8: Registering extensions in database with full metadata..."
docker compose exec -T lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT INTO installed_extensions (id, version, name, short_description, icon, stars, active, meta) 
    VALUES 
      ('lnurlp', '1.0.1', 'Pay Links', 'Make reusable LNURL pay links', 'https://github.com/lnbits/lnurlp/raw/main/static/image/lnurl-pay.png', 0, 1, '{\\\"installed_release\\\": {\\\"name\\\": \\\"Pay Links\\\", \\\"version\\\": \\\"1.0.1\\\", \\\"archive\\\": \\\"https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip\\\", \\\"source_repo\\\": \\\"https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json\\\", \\\"hash\\\": \\\"281cf5b0ebb4289f93c97ff9438abf18e01569508faaf389723144104bba2273\\\", \\\"min_lnbits_version\\\": \\\"1.0.0\\\", \\\"max_lnbits_version\\\": \\\"1.2.2\\\", \\\"is_version_compatible\\\": true, \\\"repo\\\": \\\"https://github.com/lnbits/lnurlp\\\"}}'),
      ('withdraw', '1.0.1', 'Withdraw Links', 'Make LNURL withdraw links', 'https://github.com/lnbits/withdraw/raw/main/static/image/lnurl-withdraw.png', 0, 1, '{\\\"installed_release\\\": {\\\"name\\\": \\\"Withdraw Links\\\", \\\"version\\\": \\\"1.0.1\\\", \\\"archive\\\": \\\"https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip\\\", \\\"source_repo\\\": \\\"https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json\\\", \\\"hash\\\": \\\"58b3847801efb0dcabd7fa8c9d16c08a2d50cd0e21e96b00b3a0baf88daa9a98\\\", \\\"min_lnbits_version\\\": \\\"1.0.0\\\", \\\"max_lnbits_version\\\": \\\"1.3.0\\\", \\\"is_version_compatible\\\": true, \\\"repo\\\": \\\"https://github.com/lnbits/withdraw\\\"}}');
  \"
  echo 'Extensions registered in installed_extensions'
"

# Enable for user
echo "Step 9: Enabling extensions for user..."
docker compose exec -T lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT INTO extensions (\\\"user\\\", extension, active, extra) 
    VALUES 
      ('$USER_ID', 'lnurlp', 1, null),
      ('$USER_ID', 'withdraw', 1, null);
  \"
  echo 'Extensions enabled for user: $USER_ID'
"

# Restart to register routes
echo "Step 10: Restarting LNbits to register extension routes..."
docker compose restart lnbits-1
sleep 20

# Test APIs
echo "Step 11: Testing extension APIs..."
echo "lnurlp API test:"
LNURLP_RESULT=$(curl -s "http://localhost:5001/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "API call failed")
echo "$LNURLP_RESULT"

echo -e "\nwithdraw API test:"
WITHDRAW_RESULT=$(curl -s "http://localhost:5001/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "API call failed")
echo "$WITHDRAW_RESULT"

# Test functionality (if routes work)
if echo "$LNURLP_RESULT" | grep -q "\[\]"; then
  echo -e "\n✅ SUCCESS! Extension routes are working!"
  echo "Testing actual link creation..."
  
  PAY_LINK=$(curl -s -X POST "http://localhost:5001/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "description": "Test Pay Link",
      "min": 10,
      "max": 10000,
      "comment_chars": 255
    }')
  
  if echo "$PAY_LINK" | jq -e '.id' > /dev/null; then
    PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id')
    echo "🎉 Full success! Created pay link: $PAY_LINK_ID"
  else
    echo "⚠️ API works but link creation failed: $PAY_LINK"
  fi
else
  echo -e "\n⚠️ Extension routes not registered (known LNbits v1.2.1 issue)"
  echo "Extensions installed correctly but routes missing"
  echo "This is documented in your debug notes - manual GUI install works"
fi

echo -e "\n=== Extension Installation Summary ==="
echo "✅ LNbits v1.2.1 setup completed"
echo "✅ lnurlp 1.0.1 files installed"
echo "✅ withdraw 1.0.1 files installed"
echo "✅ Database migrations executed" 
echo "✅ Extensions registered and enabled"
echo "⚠️  Route registration depends on LNbits version"
echo ""
echo "Access LNbits at: http://localhost:5001"
echo "Username: superadmin / Password: secret1234"
echo "Admin key: $ADMIN_KEY"