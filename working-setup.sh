#!/bin/bash
set -e

echo "=== Setting up LNbits with lnurlp 1.0.1 and withdraw 1.0.1 ==="

# Start the services
echo "Starting services..."
docker compose up -d bitcoind litd-1 litd-2 lnd

# Wait for Bitcoin to be ready
echo "Waiting for Bitcoin..."
for i in {1..30}; do
  if docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning getblockchaininfo 2>/dev/null; then
    echo "Bitcoin ready!"
    break
  fi
  echo "Attempt $i/30: Bitcoin not ready..."
  sleep 2
done

# Create Bitcoin wallet and mine blocks
echo "Setting up Bitcoin wallet..."
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning createwallet "test" || \
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning loadwallet "test"

ADDR=$(docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning getnewaddress)
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 101 $ADDR > /dev/null

# Setup Lightning nodes
echo "Setting up Lightning nodes..."
for node in "litd-1" "litd-2 --rpcserver=litd-2:10010" "lnd --rpcserver=lnd:10011"; do
  node_name=$(echo $node | cut -d' ' -f1)
  node_args=$(echo $node | cut -d' ' -f2- | sed 's/^[^ ]*//')
  
  echo "Setting up $node_name..."
  
  # Wait for node
  for i in {1..30}; do
    if docker compose exec -T $node_name lncli --network=regtest $node_args getinfo 2>&1 | grep -q "identity_pubkey"; then
      break
    fi
    sleep 2
  done
  
  # Create wallet
  docker compose exec -T $node_name lncli --network=regtest $node_args create <<EOF || true
password12345678
password12345678
n
EOF
  
  # Unlock wallet
  docker compose exec -T $node_name lncli --network=regtest $node_args unlock <<EOF || true
password12345678
EOF
  
  sleep 3
done

# Fund nodes
echo "Funding Lightning nodes..."
LITD1_ADDR=$(docker compose exec -T litd-1 lncli --network=regtest newaddress p2wkh | jq -r .address)
LITD2_ADDR=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 newaddress p2wkh | jq -r .address)
LND_ADDR=$(docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 newaddress p2wkh | jq -r .address)

docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning sendtoaddress $LITD1_ADDR 10
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning sendtoaddress $LITD2_ADDR 10  
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning sendtoaddress $LND_ADDR 10

ADDR=$(docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning getnewaddress)
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 6 $ADDR > /dev/null

# Start LNbits
echo "Starting LNbits..."
docker compose up -d lnbits-1

# Wait for LNbits to start
echo "Waiting for LNbits to start..."
for i in {1..60}; do
  if curl -s http://localhost:5001/api/v1/health 2>/dev/null | grep -q "OK"; then
    echo "LNbits is ready!"
    break
  fi
  echo "Attempt $i/60: Waiting for LNbits..."
  sleep 3
done

# Complete first install
echo "Completing LNbits first install..."
FIRST_INSTALL_RESPONSE=$(curl -s -X PUT http://localhost:5001/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{
    "username": "superadmin",
    "password": "secret1234",
    "password_repeat": "secret1234"
  }')

echo "First install response: $FIRST_INSTALL_RESPONSE"
ACCESS_TOKEN=$(echo "$FIRST_INSTALL_RESPONSE" | jq -r '.access_token')
echo "Got access token: ${ACCESS_TOKEN:0:20}..."

# Get user info with wallet
echo "Getting user wallet info..."
USER_INFO=$(curl -s -X GET "http://localhost:5001/api/v1/auth" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

WALLET_ID=$(echo "$USER_INFO" | jq -r '.wallets[0].id')
ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')

echo "Wallet ID: $WALLET_ID"
echo "Admin key: ${ADMIN_KEY:0:20}..."

# Install extensions by downloading and extracting
echo "Installing lnurlp 1.0.1 extension..."
docker compose exec -T lnbits-1 bash -c "
  cd /tmp
  wget -q https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip
  unzip -q v1.0.1.zip
  cp -r lnurlp-1.0.1/* /app/lnbits/extensions/lnurlp/ 2>/dev/null || mkdir -p /app/lnbits/extensions/lnurlp && cp -r lnurlp-1.0.1/* /app/lnbits/extensions/lnurlp/
  rm -rf v1.0.1.zip lnurlp-1.0.1
  echo 'lnurlp extension files installed'
"

echo "Installing withdraw 1.0.1 extension..."
docker compose exec -T lnbits-1 bash -c "
  cd /tmp
  wget -q https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip
  unzip -q v1.0.1.zip
  cp -r withdraw-1.0.1/* /app/lnbits/extensions/withdraw/ 2>/dev/null || mkdir -p /app/lnbits/extensions/withdraw && cp -r withdraw-1.0.1/* /app/lnbits/extensions/withdraw/
  rm -rf v1.0.1.zip withdraw-1.0.1
  echo 'withdraw extension files installed'
"

# Register extensions in database
echo "Registering extensions in database..."
docker compose exec -T lnbits-1 bash -c "
  apt-get update > /dev/null 2>&1 && apt-get install -y sqlite3 > /dev/null 2>&1
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
    VALUES ('lnurlp', '1.0.1', 'Pay Links', 'Make reusable LNURL pay links', '/lnurlp/static/image/lnurl-pay.png', 1, '{}');
  \"
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
    VALUES ('withdraw', '1.0.1', 'Withdraw Links', 'Make LNURL withdraw links', '/withdraw/static/image/lnurl-withdraw.png', 1, '{}');
  \"
  echo 'Extensions registered in database'
"

# Enable extensions for user
USER_ID=$(echo "$USER_INFO" | jq -r '.id')
echo "Enabling extensions for user $USER_ID..."

docker compose exec -T lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    INSERT OR REPLACE INTO extensions (user, extension, active) VALUES ('$USER_ID', 'lnurlp', 1);
    INSERT OR REPLACE INTO extensions (user, extension, active) VALUES ('$USER_ID', 'withdraw', 1);
  \"
  echo 'Extensions enabled for user'
"

# Restart LNbits to load extensions
echo "Restarting LNbits to load extensions..."
docker compose restart lnbits-1

# Wait for restart
echo "Waiting for LNbits to restart..."
for i in {1..30}; do
  if curl -s http://localhost:5001/api/v1/health 2>/dev/null | grep -q "OK"; then
    echo "LNbits restarted!"
    break
  fi
  sleep 3
done

# Test extensions are working
echo "Testing lnurlp extension..."
PAY_LINK=$(curl -s -X POST http://localhost:5001/lnurlp/api/v1/links \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "wallet": "'$WALLET_ID'",
    "description": "Test Pay Link",
    "min": 10,
    "max": 10000,
    "comment_chars": 255
  }')

PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id' 2>/dev/null || echo "")
if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ]; then
  echo "✅ lnurlp extension working! Pay link ID: $PAY_LINK_ID"
else
  echo "❌ lnurlp extension failed: $PAY_LINK"
fi

echo "Testing withdraw extension..."
WITHDRAW_LINK=$(curl -s -X POST http://localhost:5001/withdraw/api/v1/links \
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
  echo "✅ withdraw extension working! Withdraw link ID: $WITHDRAW_LINK_ID"
else
  echo "❌ withdraw extension failed: $WITHDRAW_LINK"
fi

echo ""
echo "=== Setup Complete! ==="
echo "LNbits URL: http://localhost:5001"
echo "Wallet ID: $WALLET_ID"
echo "Admin Key: $ADMIN_KEY"
echo ""
echo "Extensions installed:"
echo "- lnurlp 1.0.1"
echo "- withdraw 1.0.1"