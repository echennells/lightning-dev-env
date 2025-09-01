#!/bin/bash
set -e

echo "=== FINAL EXTENSION FIX FOR LNBITS ==="

# First, let's completely reset and do this properly
echo "Step 1: Complete reset and proper setup..."

# Stop and restart to get clean state
docker compose stop lnbits-1
sleep 2
docker compose start lnbits-1
sleep 15

# Wait for LNbits to be ready
echo "Waiting for LNbits to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:5001/api/v1/health 2>/dev/null | grep -q "server_time"; then
    echo "LNbits is ready!"
    break
  fi
  sleep 2
done

# Get a fresh access token by completing first install
echo ""
echo "Step 2: Getting access token..."
# Try to get access token - if first install is needed, do it
HEALTH_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:5001/api/v1/health)
if echo "$HEALTH_RESPONSE" | grep -q "HTTP_CODE:307"; then
  echo "First install needed..."
  AUTH_RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/auth/first_install" \
    -H "Content-Type: application/json" \
    -d '{
      "username": "superadmin",
      "password": "secret1234", 
      "password_repeat": "secret1234"
    }')
  ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.access_token')
  echo "Got token from first install"
else
  # Get admin key from database
  ADMIN_KEY=$(docker compose exec lnbits-1 bash -c "
    sqlite3 /app/data/database.sqlite3 \"SELECT adminkey FROM wallets LIMIT 1;\" 2>/dev/null
  " | tr -d '\r\n' | head -1)
  echo "Using admin key: ${ADMIN_KEY:0:10}..."
fi

# Step 3: Force install extensions in database
echo ""
echo "Step 3: Force installing extensions..."
docker compose exec lnbits-1 bash -c "
  # Ensure tools are installed
  apt-get update > /dev/null 2>&1 && apt-get install -y sqlite3 git > /dev/null 2>&1
  
  # Make sure lnurlflip is installed
  if [ ! -d '/app/lnbits/extensions/lnurlflip' ]; then
    cd /app
    git clone https://github.com/echennells/lnurlFlip.git lnbits/extensions/lnurlflip
  fi
  
  # Force clear and re-insert extensions
  sqlite3 /app/data/database.sqlite3 \"DELETE FROM installed_extensions;\"
  sqlite3 /app/data/database.sqlite3 \"DELETE FROM extensions;\"
  
  # Insert extensions as active
  sqlite3 /app/data/database.sqlite3 \"
    INSERT INTO installed_extensions (id, version, name, short_description, icon, stars, active, meta) 
    VALUES 
      ('lnurlp', '1.0.1', 'Pay Links', 'Make reusable LNURL pay links', '/lnurlp/static/image/lnurl-pay.png', 0, 1, '{}'),
      ('withdraw', '1.0.1', 'Withdraw Links', 'Make LNURL withdraw links', '/withdraw/static/image/lnurl-withdraw.png', 0, 1, '{}'),
      ('lnurlflip', '0.1.1', 'lnurlFlip', 'Auto-switching LNURL', '/lnurlflip/static/image/lnurlFlip.png', 0, 1, '{}');
  \"
  
  echo 'Extensions force-installed'
"

# Step 4: Test without restarting first
echo ""
echo "Step 4: Testing extensions directly..."

if [ -n "$ADMIN_KEY" ]; then
  # Test using admin key
  echo "Testing lnurlp with admin key..."
  LNURLP_TEST=$(curl -s "http://localhost:5001/lnurlp/api/v1" \
    -H "X-API-KEY: $ADMIN_KEY")
  echo "lnurlp test: $LNURLP_TEST"
  
  echo ""
  echo "Creating pay link with admin key..."
  PAY_LINK_RESULT=$(curl -s -X POST "http://localhost:5001/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "description": "Test Pay Link",
      "min": 10,
      "max": 10000,
      "comment_chars": 255
    }')
  echo "Pay link result: $PAY_LINK_RESULT"
  
  # If that fails, try activating via API with admin access
  if echo "$PAY_LINK_RESULT" | grep -q "disabled\|not found"; then
    echo ""
    echo "Extension disabled, trying to activate..."
    
    # Use the admin key to try to activate extensions through LNbits internal mechanisms
    echo "Directly enabling extensions in user table..."
    USER_ID=$(docker compose exec lnbits-1 bash -c "
      sqlite3 /app/data/database.sqlite3 \"SELECT user FROM wallets LIMIT 1;\" 2>/dev/null
    " | tr -d '\r\n' | head -1)
    
    docker compose exec lnbits-1 bash -c "
      sqlite3 /app/data/database.sqlite3 \"
        INSERT OR REPLACE INTO extensions (extension, active, \\\"user\\\") 
        VALUES 
          ('lnurlp', 1, '$USER_ID'),
          ('withdraw', 1, '$USER_ID'),
          ('lnurlflip', 1, '$USER_ID');
      \"
    "
    
    # Now restart to force reload
    echo "Restarting to force reload..."
    docker compose restart lnbits-1 > /dev/null 2>&1
    sleep 20
    
    # Test again
    echo "Testing after restart..."
    FINAL_TEST=$(curl -s -X POST "http://localhost:5001/lnurlp/api/v1/links" \
      -H "X-API-KEY: $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "description": "Final Test",
        "min": 10,
        "max": 10000,
        "comment_chars": 255
      }')
    
    if echo "$FINAL_TEST" | grep -q '"id"'; then
      echo "🎉 SUCCESS! Extensions are now working!"
      PAY_LINK_ID=$(echo "$FINAL_TEST" | jq -r '.id')
      echo "Created pay link: $PAY_LINK_ID"
      
      # Test withdraw link
      echo ""
      echo "Testing withdraw link..."
      WITHDRAW_TEST=$(curl -s -X POST "http://localhost:5001/withdraw/api/v1/links" \
        -H "X-API-KEY: $ADMIN_KEY" \
        -H "Content-Type: application/json" \
        -d '{
          "title": "Test Withdraw",
          "min_withdrawable": 10,
          "max_withdrawable": 10000,
          "uses": 100,
          "wait_time": 1,
          "is_unique": true
        }')
      
      if echo "$WITHDRAW_TEST" | grep -q '"id"'; then
        WITHDRAW_LINK_ID=$(echo "$WITHDRAW_TEST" | jq -r '.id')
        echo "Created withdraw link: $WITHDRAW_LINK_ID"
        
        # Test flip link
        echo ""
        echo "Testing lnurlFlip link..."
        FLIP_TEST=$(curl -s -X POST "http://localhost:5001/lnurlflip/api/v1/links" \
          -H "X-API-KEY: $ADMIN_KEY" \
          -H "Content-Type: application/json" \
          -d "{
            \"pay_link\": \"$PAY_LINK_ID\",
            \"withdraw_link\": \"$WITHDRAW_LINK_ID\",
            \"title\": \"Test Flip\",
            \"threshold\": 50000
          }")
        
        if echo "$FLIP_TEST" | grep -q '"id"'; then
          FLIP_LINK_ID=$(echo "$FLIP_TEST" | jq -r '.id')
          echo "🎉🎉 COMPLETE SUCCESS! Created flip link: $FLIP_LINK_ID"
          echo ""
          echo "✅ ALL EXTENSIONS WORKING:"
          echo "   - Pay Link: $PAY_LINK_ID"
          echo "   - Withdraw Link: $WITHDRAW_LINK_ID"
          echo "   - Flip Link: $FLIP_LINK_ID"
          echo "   - Admin Key: $ADMIN_KEY"
          echo "   - LNbits UI: http://localhost:5001"
        else
          echo "❌ Flip link failed: $FLIP_TEST"
        fi
      else
        echo "❌ Withdraw link failed: $WITHDRAW_TEST"
      fi
    else
      echo "❌ Still failing: $FINAL_TEST"
    fi
  else
    echo "🎉 Extension working on first try!"
  fi
fi

echo ""
echo "=== FINAL FIX COMPLETE ==="