#!/bin/bash
set -e

echo "=== COMPLETE LNBITS SETUP WITH EXTENSIONS ==="
echo ""

# Step 1: Complete first install if needed
echo "Step 1: Completing initial setup..."
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
  sleep 2
else
  echo "First install already done"
fi

# Step 2: Get credentials from database
echo ""
echo "Step 2: Getting credentials from database..."
ADMIN_KEY=$(docker compose exec lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"SELECT adminkey FROM wallets LIMIT 1;\" 2>/dev/null
" | tr -d '\r\n' | head -1)

WALLET_ID=$(docker compose exec lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"SELECT id FROM wallets LIMIT 1;\" 2>/dev/null
" | tr -d '\r\n' | head -1)

USER_ID=$(docker compose exec lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"SELECT user FROM wallets LIMIT 1;\" 2>/dev/null
" | tr -d '\r\n' | head -1)

echo "Admin Key: ${ADMIN_KEY:0:10}..."
echo "Wallet ID: $WALLET_ID"
echo "User ID: $USER_ID"

# Step 3: Install extensions properly
echo ""
echo "Step 3: Installing and registering extensions..."
docker compose exec lnbits-1 bash -c "
  apt-get update > /dev/null 2>&1 && apt-get install -y sqlite3 git > /dev/null 2>&1
  
  # Install lnurlflip if not present
  if [ ! -d '/app/lnbits/extensions/lnurlflip' ]; then
    cd /app
    git clone https://github.com/echennells/lnurlFlip.git lnbits/extensions/lnurlflip > /dev/null 2>&1
    cd lnbits/extensions/lnurlflip
    pip install -r requirements.txt > /dev/null 2>&1 || true
  fi
  
  # Register extensions in database
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
    VALUES 
      ('lnurlp', '1.0.1', 'Pay Links', 'Make reusable LNURL pay links', '/lnurlp/static/image/lnurl-pay.png', 1, '{}'),
      ('withdraw', '1.0.1', 'Withdraw Links', 'Make LNURL withdraw links', '/withdraw/static/image/lnurl-withdraw.png', 1, '{}'),
      ('lnurlflip', '0.1.1', 'lnurlFlip', 'LnurlFlip creates a single LNURL', '/lnurlflip/static/image/lnurlFlip.png', 1, '{}');
  \"
  
  # Enable extensions for user
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO extensions (extension, active, \\\"user\\\") 
    VALUES 
      ('lnurlp', 1, '$USER_ID'),
      ('withdraw', 1, '$USER_ID'),
      ('lnurlflip', 1, '$USER_ID');
  \"
  
  echo 'Extensions installed and registered'
"

# Step 4: Restart LNbits with a small delay
echo ""
echo "Step 4: Restarting LNbits..."
docker compose restart lnbits-1 > /dev/null 2>&1
echo "Waiting for LNbits to initialize (20 seconds)..."
sleep 20

# Wait for LNbits to be fully ready
for i in {1..30}; do
  if curl -s http://localhost:5001/api/v1/health 2>/dev/null | grep -q "server_time"; then
    echo "LNbits is ready!"
    break
  fi
  echo "Waiting for LNbits... ($i/30)"
  sleep 2
done

# Step 5: Test extensions
echo ""
echo "Step 5: Testing extensions..."

# Create pay link
echo "Creating LNURL pay link..."
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
  PAY_LNURL=$(echo "$PAY_LINK" | jq -r '.lnurl' 2>/dev/null || echo "")
  echo "   LNURL: ${PAY_LNURL:0:50}..."
else
  echo "❌ Failed to create pay link"
  echo "   Response: $PAY_LINK"
fi

# Create withdraw link
echo ""
echo "Creating LNURL withdraw link..."
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

WITHDRAW_LINK_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id' 2>/dev/null || echo "")
if [ -n "$WITHDRAW_LINK_ID" ] && [ "$WITHDRAW_LINK_ID" != "null" ]; then
  echo "✅ Created withdraw link: $WITHDRAW_LINK_ID"
  WITHDRAW_LNURL=$(echo "$WITHDRAW_LINK" | jq -r '.lnurl' 2>/dev/null || echo "")
  echo "   LNURL: ${WITHDRAW_LNURL:0:50}..."
else
  echo "❌ Failed to create withdraw link"
  echo "   Response: $WITHDRAW_LINK"
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
    echo "✅ Created flip link: $FLIP_ID"
    FLIP_LNURL=$(echo "$FLIP_LINK" | jq -r '.lnurl' 2>/dev/null || echo "")
    echo "   LNURL: ${FLIP_LNURL:0:50}..."
    echo ""
    echo "🎉 SUCCESS! All extensions are working!"
    echo ""
    echo "Access Details:"
    echo "  - LNbits UI: http://localhost:5001"
    echo "  - Admin Key: $ADMIN_KEY"
    echo "  - Test Links Created:"
    echo "    - Pay Link ID: $PAY_LINK_ID"
    echo "    - Withdraw Link ID: $WITHDRAW_LINK_ID"
    echo "    - Flip Link ID: $FLIP_ID"
  else
    echo "❌ Failed to create flip link"
    echo "   Response: $FLIP_LINK"
  fi
else
  echo ""
  echo "❌ Could not create flip link - prerequisites failed"
fi

echo ""
echo "=== SETUP COMPLETE ==="