#!/bin/bash
set -e

echo "=== Final Working Extension Install ==="

echo "1. Installing missing packages and cleaning..."
docker compose exec -T lnbits-1 bash -c "
  apt-get update > /dev/null 2>&1
  apt-get install -y wget sqlite3 git > /dev/null 2>&1
  
  rm -rf /app/lnbits/extensions/*
  sqlite3 /app/data/database.sqlite3 'DELETE FROM installed_extensions;'
  sqlite3 /app/data/database.sqlite3 'DELETE FROM extensions;'
"

echo -e "\n2. Installing known working extension versions..."
docker compose exec -T lnbits-1 bash -c "
  cd /app/lnbits/extensions/
  
  # Install lnurlp - use v1.1.1 tag which should be compatible
  git clone https://github.com/lnbits/lnurlp.git
  cd lnurlp
  git checkout v1.1.1 2>/dev/null || git checkout tags/v1.1.1 2>/dev/null || echo 'Using main branch'
  cd ..
  
  # Install withdraw - use v1.1.1 tag which should be compatible
  git clone https://github.com/lnbits/withdraw.git  
  cd withdraw
  git checkout v1.1.1 2>/dev/null || git checkout tags/v1.1.1 2>/dev/null || echo 'Using main branch'
  cd ..
  
  # Install lnurlflip
  git clone https://github.com/echennells/lnurlFlip.git lnurlflip
  
  echo 'Extensions installed:'
  ls -la
  
  echo 'Checking for required files:'
  ls lnurlp/__init__.py 2>/dev/null && echo 'lnurlp OK' || echo 'lnurlp missing __init__.py'
  ls withdraw/__init__.py 2>/dev/null && echo 'withdraw OK' || echo 'withdraw missing __init__.py'
  ls lnurlflip/__init__.py 2>/dev/null && echo 'lnurlflip OK' || echo 'lnurlflip missing __init__.py'
"

echo -e "\n3. Registering extensions in database..."
docker compose exec -T lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
    VALUES 
      ('lnurlp', '1.1.1', 'Pay Links', 'LNURL pay links', '/lnurlp/static/image/lnurl-pay.png', 1, '{}'),
      ('withdraw', '1.1.1', 'Withdraw Links', 'LNURL withdraw links', '/withdraw/static/image/lnurl-withdraw.png', 1, '{}'),
      ('lnurlflip', '1.0.0', 'lnurlFlip', 'Auto-switching LNURL', '/lnurlflip/static/image/lnurlFlip.png', 1, '{}');
  \"
  echo 'Extensions registered as active'
"

echo -e "\n4. Enabling extensions for user..."
USER_ID=$(docker compose exec -T lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT user FROM wallets LIMIT 1;'" | tr -d '\r\n')
docker compose exec -T lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO extensions (extension, active, \\\"user\\\") 
    VALUES 
      ('lnurlp', 1, '$USER_ID'),
      ('withdraw', 1, '$USER_ID'),
      ('lnurlflip', 1, '$USER_ID');
  \"
  echo 'Extensions enabled for user: $USER_ID'
"

echo -e "\n5. Restarting LNbits..."
docker compose restart lnbits-1
sleep 20

echo -e "\n6. Checking for loading errors..."
docker compose logs --tail=20 lnbits-1 | grep -i "error\|could not load" || echo "No errors found!"

echo -e "\n7. Testing extension APIs..."
ADMIN_KEY=$(docker compose exec -T lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets LIMIT 1;'" | tr -d '\r\n')

echo "lnurlp API test:"
LNURLP_RESULT=$(curl -s "http://localhost:5001/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY")
echo "$LNURLP_RESULT"

echo -e "\nwithdraw API test:"
WITHDRAW_RESULT=$(curl -s "http://localhost:5001/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY") 
echo "$WITHDRAW_RESULT"

# Test actual functionality if APIs work
if echo "$LNURLP_RESULT" | grep -q "\[\]"; then
    echo -e "\n8. ✅ EXTENSIONS ARE WORKING! Creating test pay link..."
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
        echo "🎉 SUCCESS! Created pay link: $PAY_LINK_ID"
        echo ""
        echo "Ready to update GitHub workflow with this approach!"
    else
        echo "❌ API works but link creation failed: $PAY_LINK"
    fi
else
    echo -e "\n8. ❌ Extensions still not working. API returned: $LNURLP_RESULT"
fi

echo -e "\n=== Final Install Complete ==="