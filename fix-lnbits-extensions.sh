#!/bin/bash
set -e

echo "=== FIXING LNBITS EXTENSIONS - COMPLETE SOLUTION ==="
echo ""

# Step 1: Get the admin key directly from the database
echo "Step 1: Getting admin credentials from database..."
ADMIN_KEY=$(docker compose exec lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"SELECT adminkey FROM wallets WHERE name='admin' LIMIT 1;\" 2>/dev/null
" | tr -d '\r\n')

WALLET_ID=$(docker compose exec lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"SELECT id FROM wallets WHERE name='admin' LIMIT 1;\" 2>/dev/null
" | tr -d '\r\n')

USER_ID=$(docker compose exec lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"SELECT user FROM wallets WHERE name='admin' LIMIT 1;\" 2>/dev/null
" | tr -d '\r\n')

echo "Admin Key: ${ADMIN_KEY:0:10}..."
echo "Wallet ID: $WALLET_ID"
echo "User ID: $USER_ID"

# Step 2: Register all extensions in database
echo ""
echo "Step 2: Registering extensions in database..."
docker compose exec lnbits-1 bash -c "
  # Ensure sqlite3 is installed
  apt-get update > /dev/null 2>&1 && apt-get install -y sqlite3 > /dev/null 2>&1
  
  # Register lnurlp
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
    VALUES ('lnurlp', '1.0.1', 'Pay Links', 'Make reusable LNURL pay links', '/lnurlp/static/image/lnurl-pay.png', 1, '{}');
  \"
  
  # Register withdraw
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
    VALUES ('withdraw', '1.0.1', 'Withdraw Links', 'Make LNURL withdraw links', '/withdraw/static/image/lnurl-withdraw.png', 1, '{}');
  \"
  
  # Register lnurlflip
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
    VALUES ('lnurlflip', '0.1.1', 'lnurlFlip', 'LnurlFlip creates a single LNURL that switches between pay and withdraw', '/lnurlflip/static/image/lnurlFlip.png', 1, '{}');
  \"
  
  echo 'Extensions registered in database'
"

# Step 3: Enable extensions for the user
echo ""
echo "Step 3: Enabling extensions for user..."
docker compose exec lnbits-1 bash -c "
  # Enable lnurlp for user
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO extensions (extension, active, \\\"user\\\") 
    VALUES ('lnurlp', 1, '$USER_ID');
  \"
  
  # Enable withdraw for user
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO extensions (extension, active, \\\"user\\\") 
    VALUES ('withdraw', 1, '$USER_ID');
  \"
  
  # Enable lnurlflip for user
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO extensions (extension, active, \\\"user\\\") 
    VALUES ('lnurlflip', 1, '$USER_ID');
  \"
  
  echo 'Extensions enabled for user'
"

# Step 4: Restart LNbits to load extensions
echo ""
echo "Step 4: Restarting LNbits to load extensions..."
docker compose restart lnbits-1
echo "Waiting for LNbits to start..."
sleep 15

# Wait for LNbits to be ready
for i in {1..30}; do
  if curl -s http://localhost:5001/api/v1/health 2>/dev/null | grep -q "server_time"; then
    echo "LNbits is ready!"
    break
  fi
  echo "Waiting for LNbits to start... ($i/30)"
  sleep 2
done

# Step 5: Test that extensions are working
echo ""
echo "Step 5: Testing extension APIs..."

echo "Testing lnurlp extension:"
LNURLP_RESPONSE=$(curl -s "http://localhost:5001/lnurlp/api/v1" \
  -H "X-API-KEY: $ADMIN_KEY")
if echo "$LNURLP_RESPONSE" | grep -q "detail"; then
  echo "❌ lnurlp API error: $LNURLP_RESPONSE"
else
  echo "✅ lnurlp API is accessible"
fi

echo ""
echo "Testing withdraw extension:"
WITHDRAW_RESPONSE=$(curl -s "http://localhost:5001/withdraw/api/v1" \
  -H "X-API-KEY: $ADMIN_KEY")
if echo "$WITHDRAW_RESPONSE" | grep -q "detail"; then
  echo "❌ withdraw API error: $WITHDRAW_RESPONSE"
else
  echo "✅ withdraw API is accessible"
fi

echo ""
echo "Testing lnurlflip extension:"
LNURLFLIP_RESPONSE=$(curl -s "http://localhost:5001/lnurlflip/api/v1" \
  -H "X-API-KEY: $ADMIN_KEY")
if echo "$LNURLFLIP_RESPONSE" | grep -q "detail"; then
  echo "❌ lnurlflip API error: $LNURLFLIP_RESPONSE"
else
  echo "✅ lnurlflip API is accessible"
fi

# Step 6: Create test LNURL links
echo ""
echo "Step 6: Creating test LNURL links..."

# Create pay link
echo "Creating LNURL pay link..."
PAY_LINK=$(curl -s -X POST "http://localhost:5001/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"description\": \"Test Pay Link\",
    \"min\": 10,
    \"max\": 10000,
    \"comment_chars\": 255
  }")

PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id' 2>/dev/null || echo "")
if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ]; then
  echo "✅ Created pay link: $PAY_LINK_ID"
else
  echo "❌ Failed to create pay link: $PAY_LINK"
fi

# Create withdraw link
echo ""
echo "Creating LNURL withdraw link..."
WITHDRAW_LINK=$(curl -s -X POST "http://localhost:5001/withdraw/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"Test Withdraw Link\",
    \"min_withdrawable\": 10,
    \"max_withdrawable\": 10000,
    \"uses\": 100,
    \"wait_time\": 1,
    \"is_unique\": true
  }")

WITHDRAW_LINK_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id' 2>/dev/null || echo "")
if [ -n "$WITHDRAW_LINK_ID" ] && [ "$WITHDRAW_LINK_ID" != "null" ]; then
  echo "✅ Created withdraw link: $WITHDRAW_LINK_ID"
else
  echo "❌ Failed to create withdraw link: $WITHDRAW_LINK"
fi

# Create flip link if both were successful
if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ] && \
   [ -n "$WITHDRAW_LINK_ID" ] && [ "$WITHDRAW_LINK_ID" != "null" ]; then
  
  echo ""
  echo "Creating lnurlFlip link..."
  FLIP_LINK=$(curl -s -X POST "http://localhost:5001/lnurlflip/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"pay_link\": \"$PAY_LINK_ID\",
      \"withdraw_link\": \"$WITHDRAW_LINK_ID\",
      \"title\": \"Test Flip Link\",
      \"threshold\": 50000
    }")
  
  FLIP_ID=$(echo "$FLIP_LINK" | jq -r '.id' 2>/dev/null || echo "")
  
  if [ -n "$FLIP_ID" ] && [ "$FLIP_ID" != "null" ]; then
    echo "✅ Created flip link with ID: $FLIP_ID"
    echo ""
    echo "🎉 SUCCESS! All extensions are working properly!"
    echo ""
    echo "You can access the extensions at:"
    echo "  - LNbits UI: http://localhost:5001"
    echo "  - Admin Key: $ADMIN_KEY"
    echo "  - Wallet ID: $WALLET_ID"
  else
    echo "❌ Failed to create flip link: $FLIP_LINK"
  fi
else
  echo ""
  echo "❌ Could not create flip link because pay or withdraw link creation failed"
fi

echo ""
echo "=== EXTENSION FIX COMPLETE ==="