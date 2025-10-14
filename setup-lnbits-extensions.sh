#!/bin/bash
set -e

echo "=== Setting up LNbits Extensions ==="

# Function to setup extensions for a specific LNbits instance
setup_lnbits_instance() {
  local LNBITS_CONTAINER=$1
  local LNBITS_URL=$2
  local LITD_CONTAINER=$3
  local LITD_NAME=$4
  local LITD_PORT=$5

  echo ""
  echo "=========================================="
  echo "Setting up $LNBITS_CONTAINER (connected to $LITD_NAME)"
  echo "=========================================="

  # Wait for LNbits to be ready
  echo "Waiting for LNbits to be ready..."
  for i in {1..30}; do
    if curl -s "$LNBITS_URL/api/v1/health" > /dev/null 2>&1; then
      echo "✅ LNbits is ready"
      break
    fi
    if [ $i -eq 30 ]; then
      echo "⚠️  LNbits not responding, skipping..."
      return
    fi
    sleep 2
  done

  # Copy extensions to container
  echo "Copying Taproot Assets extension..."
  docker cp taproot_assets "$LNBITS_CONTAINER:/app/lnbits/extensions/"

  if [ -d "../bitcoinswitch" ]; then
    echo "Copying Bitcoin Switch extension..."
    docker cp ../bitcoinswitch "$LNBITS_CONTAINER:/app/lnbits/extensions/"
  else
    echo "⚠️  Bitcoin Switch extension not found, skipping..."
  fi

  # Extract gRPC files
  echo "Extracting gRPC files..."
  docker exec "$LNBITS_CONTAINER" bash -c "cd /app && tar -xzf /app/lnbits/extensions/taproot_assets/lnd_grpc_files.tar.gz"
  docker exec "$LNBITS_CONTAINER" bash -c "cd /app && tar -xzf /app/lnbits/extensions/taproot_assets/tapd_grpc_files.tar.gz"

  # Update config to point to the correct litd instance
  echo "Updating config for $LITD_NAME..."
  docker exec "$LNBITS_CONTAINER" bash -c "sed -i 's|TAPD_HOST=.*|TAPD_HOST=$LITD_NAME:$LITD_PORT|' /app/lnbits/extensions/taproot_assets/taproot_assets.conf"
  docker exec "$LNBITS_CONTAINER" bash -c "sed -i 's|TAPD_TLS_CERT_PATH=.*|TAPD_TLS_CERT_PATH=/app/data/${LITD_NAME}-tls.cert|' /app/lnbits/extensions/taproot_assets/taproot_assets.conf"
  docker exec "$LNBITS_CONTAINER" bash -c "sed -i 's|TAPD_MACAROON_PATH=.*|TAPD_MACAROON_PATH=/app/data/${LITD_NAME}-admin.macaroon|' /app/lnbits/extensions/taproot_assets/taproot_assets.conf"
  docker exec "$LNBITS_CONTAINER" bash -c "sed -i 's|LND_REST_MACAROON=.*|LND_REST_MACAROON=/app/data/${LITD_NAME}-lnd-admin.macaroon|' /app/lnbits/extensions/taproot_assets/taproot_assets.conf"

  # Copy TLS certificates and macaroons from litd to LNbits
  echo "Copying TLS certificates and macaroons from $LITD_NAME..."

  # Create temp directory for certificates
  mkdir -p /tmp/lnbits-certs-$LITD_NAME

  # Copy files from litd container to temp location
  docker cp "$LITD_CONTAINER:/root/.lnd/tls.cert" /tmp/lnbits-certs-$LITD_NAME/${LITD_NAME}-tls.cert
  docker cp "$LITD_CONTAINER:/root/.tapd/data/regtest/admin.macaroon" /tmp/lnbits-certs-$LITD_NAME/${LITD_NAME}-admin.macaroon
  docker cp "$LITD_CONTAINER:/root/.lnd/data/chain/bitcoin/regtest/admin.macaroon" /tmp/lnbits-certs-$LITD_NAME/${LITD_NAME}-lnd-admin.macaroon

  # Copy from temp to LNbits container
  docker cp /tmp/lnbits-certs-$LITD_NAME/${LITD_NAME}-tls.cert "$LNBITS_CONTAINER:/app/data/"
  docker cp /tmp/lnbits-certs-$LITD_NAME/${LITD_NAME}-admin.macaroon "$LNBITS_CONTAINER:/app/data/"
  docker cp /tmp/lnbits-certs-$LITD_NAME/${LITD_NAME}-lnd-admin.macaroon "$LNBITS_CONTAINER:/app/data/"

  # Clean up temp directory
  rm -rf /tmp/lnbits-certs-$LITD_NAME

  echo "✅ Extensions copied and gRPC files extracted"
  echo "✅ Certificates and macaroons copied"

  # Restart to load extensions
  echo "Restarting LNbits..."
  docker restart "$LNBITS_CONTAINER"
  sleep 25

  # Wait for LNbits to be ready again
  echo "Waiting for LNbits to restart..."
  for i in {1..30}; do
    if curl -s "$LNBITS_URL/api/v1/health" > /dev/null 2>&1; then
      echo "✅ LNbits restarted"
      break
    fi
    sleep 2
  done

  # Login or create admin user
  echo "Logging in to get admin user ID..."
  LOGIN_RESP=$(curl -s -X POST "$LNBITS_URL/api/v1/auth" \
    -H "Content-Type: application/json" \
    -d '{"username": "admin", "password": "password123"}')

  ACCESS_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.access_token')

  # If login failed, try to create first install user
  if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo "Admin user doesn't exist, creating first install..."
    FIRST_INSTALL=$(curl -s -X PUT "$LNBITS_URL/api/v1/auth/first_install" \
      -H "Content-Type: application/json" \
      -d '{
        "username": "admin",
        "password": "password123",
        "password_repeat": "password123"
      }')

    ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token')

    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
      echo "⚠️  Failed to create admin user, skipping extension enablement"
      return
    fi
    echo "✅ Admin user created"
  fi

  # Get admin user ID
  USER_INFO=$(curl -s "$LNBITS_URL/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
  ADMIN_USER_ID=$(echo "$USER_INFO" | jq -r '.id')

  echo "Admin User ID: $ADMIN_USER_ID"

  # Enable extensions in database
  echo "Enabling extensions in database..."
  docker cp "$LNBITS_CONTAINER:/app/data/database.sqlite3" /tmp/enable-extensions-$LITD_NAME.db

  # Always install taproot_assets
  sqlite3 /tmp/enable-extensions-$LITD_NAME.db << SQL
-- Ensure Taproot Assets extension is installed
INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) VALUES
('taproot_assets', '0.1', 'Taproot Assets', 'Manage Taproot Assets on the Bitcoin network', '/taproot_assets/static/image/icon.png', 1, '{"installed_release": {"name": "taproot_assets", "version": "0.1", "archive": "local", "source_repo": "local"}}');

-- Enable Taproot Assets for admin user
INSERT OR REPLACE INTO extensions ("user", extension, active) VALUES
('$ADMIN_USER_ID', 'taproot_assets', 1);
SQL

  # Install bitcoinswitch if it exists
  if [ -d "../bitcoinswitch" ]; then
    sqlite3 /tmp/enable-extensions-$LITD_NAME.db << SQL
-- Ensure Bitcoin Switch extension is installed
INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) VALUES
('bitcoinswitch', '1.1.1', 'Bitcoin Switch', 'Turn things on with bitcoin - now with Taproot Assets support', '/bitcoinswitch/static/image/icon.png', 1, '{"installed_release": {"name": "bitcoinswitch", "version": "1.1.1", "archive": "local", "source_repo": "local"}}');

-- Enable Bitcoin Switch for admin user
INSERT OR REPLACE INTO extensions ("user", extension, active) VALUES
('$ADMIN_USER_ID', 'bitcoinswitch', 1);
SQL
  fi

  docker cp /tmp/enable-extensions-$LITD_NAME.db "$LNBITS_CONTAINER:/app/data/database.sqlite3"
  rm /tmp/enable-extensions-$LITD_NAME.db
  echo "✅ Extensions enabled in database"

  # Final restart
  echo "Final restart..."
  docker restart "$LNBITS_CONTAINER"
  sleep 25

  echo "✅ Extensions setup complete for $LNBITS_CONTAINER!"
}

# Setup extensions for lnbits-1 (connected to litd-1)
setup_lnbits_instance \
  "lightning-dev-env-lnbits-1-1" \
  "http://localhost:5001" \
  "lightning-dev-env-litd-1-1" \
  "litd-1" \
  "10009"

# Setup extensions for lnbits-2 (connected to litd-2)
setup_lnbits_instance \
  "lightning-dev-env-lnbits-2-1" \
  "http://localhost:5002" \
  "lightning-dev-env-litd-2-1" \
  "litd-2" \
  "10010"

echo ""
echo "=========================================="
echo "✅ All Extensions Setup Complete!"
echo "=========================================="
echo "- LNbits 1 (litd-1): http://localhost:5001"
echo "  • Taproot Assets: http://localhost:5001/taproot_assets"
echo "  • Bitcoin Switch: http://localhost:5001/bitcoinswitch"
echo ""
echo "- LNbits 2 (litd-2): http://localhost:5002"
echo "  • Taproot Assets: http://localhost:5002/taproot_assets"
echo "  • Bitcoin Switch: http://localhost:5002/bitcoinswitch"
