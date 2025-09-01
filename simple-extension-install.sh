#!/bin/bash
set -e

echo "=== Simple Extension Installation ==="

# Clean start - remove everything
echo "1. Cleaning existing extensions..."
docker compose exec -T lnbits-1 bash -c "
  rm -rf /app/lnbits/extensions/*
  sqlite3 /app/data/database.sqlite3 'DELETE FROM installed_extensions;'
  sqlite3 /app/data/database.sqlite3 'DELETE FROM extensions;'
"

# Install the extensions that ship with LNbits v1.2.1 
echo -e "\n2. Installing extensions from LNbits official releases..."
docker compose exec -T lnbits-1 bash -c "
  cd /app/lnbits/extensions/
  
  # Download and extract lnurlp v1.1.1 (compatible with LNbits v1.2.1)
  echo 'Installing lnurlp v1.1.1...'
  wget -q https://github.com/lnbits/lnurlp/archive/refs/tags/v1.1.1.tar.gz
  tar xzf v1.1.1.tar.gz
  mv lnurlp-1.1.1 lnurlp
  rm v1.1.1.tar.gz
  
  # Download and extract withdraw v1.1.1 (compatible with LNbits v1.2.1)  
  echo 'Installing withdraw v1.1.1...'
  wget -q https://github.com/lnbits/withdraw/archive/refs/tags/v1.1.1.tar.gz
  tar xzf v1.1.1.tar.gz
  mv withdraw-1.1.1 withdraw
  rm v1.1.1.tar.gz
  
  # Install lnurlflip from git (should work)
  echo 'Installing lnurlflip...'
  git clone https://github.com/echennells/lnurlFlip.git lnurlflip
  
  echo 'Extensions installed:'
  ls -la
"

echo -e "\n3. Registering extensions in database..."
docker compose exec -T lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
    VALUES 
      ('lnurlp', '1.1.1', 'Pay Links', 'LNURL pay links', 'lnurlp/static/image/lnurl-pay.png', 1, '{}'),
      ('withdraw', '1.1.1', 'Withdraw Links', 'LNURL withdraw links', 'withdraw/static/image/lnurl-withdraw.png', 1, '{}'),
      ('lnurlflip', '1.0.0', 'lnurlFlip', 'Auto-switching LNURL', 'lnurlflip/static/image/lnurlFlip.png', 1, '{}');
  \"
"

# Enable for the user
USER_ID=$(docker compose exec -T lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT user FROM wallets LIMIT 1;'" | tr -d '\r\n')
docker compose exec -T lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT INTO extensions (extension, active, \\\"user\\\") 
    VALUES 
      ('lnurlp', 1, '$USER_ID'),
      ('withdraw', 1, '$USER_ID'),
      ('lnurlflip', 1, '$USER_ID');
  \"
"

echo -e "\n4. Restarting LNbits..."
docker compose restart lnbits-1
sleep 20

echo -e "\n5. Testing extensions..."
ADMIN_KEY=$(docker compose exec -T lnbits-1 bash -c "sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets LIMIT 1;'" | tr -d '\r\n')

echo "Testing lnurlp:"
curl -s "http://localhost:5001/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY"

echo -e "\nTesting withdraw:"
curl -s "http://localhost:5001/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY"

echo -e "\n\nIf you see [] above, extensions are working! If you see 404, they're not."

echo -e "\n=== Simple Installation Complete ==="