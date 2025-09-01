#!/bin/bash
set -e

echo "=== Testing LNbits v1.2.1 with Extensions v1.0.1 ==="
echo "This script will:"
echo "- Use LNbits v1.2.1 (already in docker-compose.yml)"
echo "- Install lnurlp v1.0.1"
echo "- Install withdraw v1.0.1"
echo ""

# Step 1: Clean and restart LNbits
echo "Step 1: Cleaning and restarting LNbits..."
docker compose stop lnbits-1
docker compose rm -f lnbits-1
docker volume rm lightning-dev-env_lnbits-1-data 2>/dev/null || true
docker compose up -d lnbits-1

echo "Waiting for LNbits to start (30 seconds)..."
sleep 30

# Check if LNbits is ready
for i in {1..30}; do
  if curl -s http://localhost:5001/api/v1/health 2>/dev/null | grep -q "server_time"; then
    echo "LNbits is ready!"
    break
  fi
  echo "Waiting for LNbits... ($i/30)"
  sleep 2
done

# Step 2: Complete first install if needed
echo ""
echo "Step 2: Completing initial setup..."
HEALTH_CHECK=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:5001/api/v1/health)
if echo "$HEALTH_CHECK" | grep -q "HTTP_CODE:307"; then
  echo "First install needed, setting up super user..."
  curl -s -X PUT "http://localhost:5001/api/v1/auth/first_install" \
    -H "Content-Type: application/json" \
    -d '{
      "username": "superadmin",
      "password": "secret1234", 
      "password_repeat": "secret1234"
    }' > /dev/null
  echo "Super user created"
  sleep 5
else
  echo "First install already done"
fi

# Step 3: Install required packages
echo ""
echo "Step 3: Installing required packages in container..."
docker compose exec -T lnbits-1 bash -c "
  apt-get update > /dev/null 2>&1
  apt-get install -y wget sqlite3 git > /dev/null 2>&1
  echo 'Packages installed'
"

# Step 4: Clean existing extensions
echo ""
echo "Step 4: Cleaning existing extensions..."
docker compose exec -T lnbits-1 bash -c "
  rm -rf /app/lnbits/extensions/*
  sqlite3 /app/data/database.sqlite3 'DELETE FROM installed_extensions;' 2>/dev/null || true
  sqlite3 /app/data/database.sqlite3 'DELETE FROM extensions;' 2>/dev/null || true
  echo 'Extensions cleaned'
"

# Step 5: Install extensions v1.0.1
echo ""
echo "Step 5: Installing lnurlp and withdraw v1.0.1..."
docker compose exec -T lnbits-1 bash -c "
  cd /app/lnbits/extensions/
  
  # Download and extract lnurlp v1.0.1
  echo 'Downloading lnurlp v1.0.1...'
  wget -q https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.tar.gz
  if [ \$? -eq 0 ]; then
    tar xzf v1.0.1.tar.gz
    mv lnurlp-1.0.1 lnurlp
    rm v1.0.1.tar.gz
    echo 'lnurlp v1.0.1 installed'
  else
    echo 'Failed to download lnurlp v1.0.1'
    exit 1
  fi
  
  # Download and extract withdraw v1.0.1
  echo 'Downloading withdraw v1.0.1...'
  wget -q https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.tar.gz
  if [ \$? -eq 0 ]; then
    tar xzf v1.0.1.tar.gz
    mv withdraw-1.0.1 withdraw
    rm v1.0.1.tar.gz
    echo 'withdraw v1.0.1 installed'
  else
    echo 'Failed to download withdraw v1.0.1'
    exit 1
  fi
  
  echo ''
  echo 'Extensions installed:'
  ls -la
  
  echo ''
  echo 'Checking for required files:'
  if [ -f lnurlp/__init__.py ]; then
    echo '✓ lnurlp has __init__.py'
  else
    echo '✗ lnurlp missing __init__.py'
  fi
  
  if [ -f withdraw/__init__.py ]; then
    echo '✓ withdraw has __init__.py'
  else
    echo '✗ withdraw missing __init__.py'
  fi
"

# Step 6: Get credentials and register extensions
echo ""
echo "Step 6: Getting credentials and registering extensions..."
USER_ID=$(docker compose exec -T lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT user FROM wallets LIMIT 1;' 2>/dev/null" | tr -d '\r\n')
ADMIN_KEY=$(docker compose exec -T lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets LIMIT 1;' 2>/dev/null" | tr -d '\r\n')

echo "User ID: $USER_ID"
echo "Admin Key: ${ADMIN_KEY:0:10}..."

# Register extensions in database
docker compose exec -T lnbits-1 bash -c "
  # Register in installed_extensions table
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
    VALUES 
      ('lnurlp', '1.0.1', 'Pay Links', 'LNURL pay links', 'lnurlp/static/image/lnurl-pay.png', 1, '{}'),
      ('withdraw', '1.0.1', 'Withdraw Links', 'LNURL withdraw links', 'withdraw/static/image/lnurl-withdraw.png', 1, '{}');
  \"
  
  # Enable for user
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO extensions (extension, active, \\\"user\\\") 
    VALUES 
      ('lnurlp', 1, '$USER_ID'),
      ('withdraw', 1, '$USER_ID');
  \"
  
  echo 'Extensions registered and enabled'
"

# Step 7: Restart LNbits
echo ""
echo "Step 7: Restarting LNbits..."
docker compose restart lnbits-1
echo "Waiting for LNbits to restart (20 seconds)..."
sleep 20

# Wait for LNbits to be ready
for i in {1..30}; do
  if curl -s http://localhost:5001/api/v1/health 2>/dev/null | grep -q "server_time"; then
    echo "LNbits is ready!"
    break
  fi
  echo "Waiting for LNbits... ($i/30)"
  sleep 2
done

# Step 8: Test extensions
echo ""
echo "Step 8: Testing extension APIs..."

echo "Testing lnurlp API:"
LNURLP_RESULT=$(curl -s "http://localhost:5001/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY" 2>&1)
echo "Response: $LNURLP_RESULT"

echo ""
echo "Testing withdraw API:"
WITHDRAW_RESULT=$(curl -s "http://localhost:5001/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY" 2>&1)
echo "Response: $WITHDRAW_RESULT"

# Step 9: Test creating links if APIs work
echo ""
echo "Step 9: Testing link creation..."

if echo "$LNURLP_RESULT" | grep -q "\[\]"; then
    echo "✅ lnurlp API working! Creating test pay link..."
    PAY_LINK=$(curl -s -X POST "http://localhost:5001/lnurlp/api/v1/links" \
      -H "X-API-KEY: $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "description": "Test Pay Link v1.0.1",
        "min": 10,
        "max": 10000,
        "comment_chars": 255
      }')
    
    PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id' 2>/dev/null || echo "")
    if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ]; then
        echo "✅ Successfully created pay link: $PAY_LINK_ID"
    else
        echo "❌ Failed to create pay link. Response: $PAY_LINK"
    fi
else
    echo "❌ lnurlp API not working"
fi

if echo "$WITHDRAW_RESULT" | grep -q "\[\]"; then
    echo "✅ withdraw API working! Creating test withdraw link..."
    WITHDRAW_LINK=$(curl -s -X POST "http://localhost:5001/withdraw/api/v1/links" \
      -H "X-API-KEY: $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "title": "Test Withdraw Link v1.0.1",
        "min_withdrawable": 10,
        "max_withdrawable": 10000,
        "uses": 100,
        "wait_time": 1,
        "is_unique": true
      }')
    
    WITHDRAW_LINK_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id' 2>/dev/null || echo "")
    if [ -n "$WITHDRAW_LINK_ID" ] && [ "$WITHDRAW_LINK_ID" != "null" ]; then
        echo "✅ Successfully created withdraw link: $WITHDRAW_LINK_ID"
    else
        echo "❌ Failed to create withdraw link. Response: $WITHDRAW_LINK"
    fi
else
    echo "❌ withdraw API not working"
fi

echo ""
echo "=== Test Complete ==="
echo ""
echo "Summary:"
echo "- LNbits version: v1.2.1"
echo "- lnurlp version: 1.0.1"
echo "- withdraw version: 1.0.1"
echo ""
echo "Results:"
if echo "$LNURLP_RESULT" | grep -q "\[\]" && echo "$WITHDRAW_RESULT" | grep -q "\[\]"; then
    echo "🎉 SUCCESS! Both extensions are working with v1.0.1!"
    echo ""
    echo "Access LNbits at: http://localhost:5001"
    echo "Admin Key: $ADMIN_KEY"
else
    echo "❌ FAILURE: Extensions not working properly"
    echo ""
    echo "Debug info:"
    echo "- lnurlp response: $LNURLP_RESULT"
    echo "- withdraw response: $WITHDRAW_RESULT"
fi