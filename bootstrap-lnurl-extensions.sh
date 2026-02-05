#!/bin/bash

# Bootstrap script for LNURL extensions (lnurlp, withdraw, lnurlFlip)
# Uses file-copy + SQLite method (works with LNbits v1.4.2+)

set -e

echo "🚀 BOOTSTRAPPING LNURL EXTENSIONS"
echo "=================================="
echo ""
echo "Extensions to install:"
echo "  • lnurlp (pay links)"
echo "  • withdraw (withdraw links)"
echo "  • lnurlFlip (auto-switching between pay/withdraw)"
echo ""

# Configuration - versions compatible with LNbits v1.4.0+
LNURLP_VERSION="${LNURLP_VERSION:-1.2.0}"
WITHDRAW_VERSION="${WITHDRAW_VERSION:-1.2.2}"
LNURLFLIP_VERSION="${LNURLFLIP_VERSION:-main}"

LNURLP_REPO="https://github.com/lnbits/lnurlp"
WITHDRAW_REPO="https://github.com/lnbits/withdraw"
LNURLFLIP_REPO="https://github.com/echennells/lnurlFlip"

# Clone or update extensions
echo "=========================================="
echo "Cloning/updating LNURL extensions..."
echo "=========================================="

# lnurlp - clean clone to ensure correct version
if [ -d "lnurlp" ]; then
  echo "Removing existing lnurlp directory for clean install..."
  rm -rf lnurlp
fi
echo "Cloning lnurlp v${LNURLP_VERSION}..."
git clone --depth 1 --branch "v${LNURLP_VERSION}" "$LNURLP_REPO" lnurlp
echo "✅ lnurlp ready"

# withdraw - clean clone to ensure correct version
if [ -d "withdraw" ]; then
  echo "Removing existing withdraw directory for clean install..."
  rm -rf withdraw
fi
echo "Cloning withdraw v${WITHDRAW_VERSION}..."
git clone --depth 1 --branch "v${WITHDRAW_VERSION}" "$WITHDRAW_REPO" withdraw
echo "✅ withdraw ready"

# lnurlFlip - clean clone
if [ -d "lnurlFlip" ]; then
  echo "Removing existing lnurlFlip directory for clean install..."
  rm -rf lnurlFlip
fi
echo "Cloning lnurlFlip..."
git clone --depth 1 "$LNURLFLIP_REPO" lnurlFlip
echo "✅ lnurlFlip ready"

# Function to setup LNURL extensions for a specific LNbits instance
setup_lnurl_extensions() {
  local LNBITS_CONTAINER=$1
  local LNBITS_URL=$2
  local PROXY_PORT=$3
  local NAME=$4

  echo ""
  echo "=========================================="
  echo "Setting up LNURL extensions on $NAME"
  echo "=========================================="

  # Wait for LNbits to be ready
  echo "Waiting for LNbits to be ready..."
  for i in {1..30}; do
    if curl -s "$LNBITS_URL/api/v1/health" > /dev/null 2>&1; then
      echo "✅ LNbits is ready"
      break
    fi
    if [ $i -eq 30 ]; then
      echo "❌ LNbits not responding after 60 seconds"
      return 1
    fi
    echo "Attempt $i/30..."
    sleep 2
  done

  # Copy extensions to container
  echo "Copying lnurlp extension..."
  docker cp lnurlp "$LNBITS_CONTAINER:/app/lnbits/extensions/"

  echo "Copying withdraw extension..."
  docker cp withdraw "$LNBITS_CONTAINER:/app/lnbits/extensions/"

  echo "Copying lnurlFlip extension..."
  docker cp lnurlFlip "$LNBITS_CONTAINER:/app/lnbits/extensions/"

  echo "✅ Extensions copied"

  # Install Python dependencies for extensions
  echo "Installing Python dependencies for extensions..."
  docker exec "$LNBITS_CONTAINER" pip install secp256k1 --quiet 2>/dev/null || true
  docker exec "$LNBITS_CONTAINER" pip install --upgrade lnurl --quiet 2>/dev/null || true
  echo "✅ Dependencies installed"

  # Restart to load extensions
  echo "Restarting LNbits to load extensions..."
  docker restart "$LNBITS_CONTAINER"
  sleep 15

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

  # Try login first
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
      echo "❌ Failed to create admin user"
      return 1
    fi
    echo "✅ Admin user created"
  else
    echo "✅ Logged in successfully"
  fi

  # Get admin user ID
  USER_INFO=$(curl -s "$LNBITS_URL/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN")
  ADMIN_USER_ID=$(echo "$USER_INFO" | jq -r '.id')
  ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
  WALLET_ID=$(echo "$USER_INFO" | jq -r '.wallets[0].id')

  echo "Admin User ID: $ADMIN_USER_ID"

  # Enable extensions in database
  echo "Enabling extensions in database..."
  docker cp "$LNBITS_CONTAINER:/app/data/database.sqlite3" /tmp/enable-lnurl-extensions.db

  sqlite3 /tmp/enable-lnurl-extensions.db << SQL
-- Install lnurlp extension
INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) VALUES
('lnurlp', '${LNURLP_VERSION}', 'Pay Links', 'Create LNURL-pay links', '/lnurlp/static/image/icon.png', 1, '{"installed_release": {"name": "lnurlp", "version": "${LNURLP_VERSION}", "archive": "local", "source_repo": "local"}}');

-- Install withdraw extension
INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) VALUES
('withdraw', '${WITHDRAW_VERSION}', 'Withdraw Links', 'Create LNURL-withdraw links', '/withdraw/static/image/icon.png', 1, '{"installed_release": {"name": "withdraw", "version": "${WITHDRAW_VERSION}", "archive": "local", "source_repo": "local"}}');

-- Install lnurlFlip extension
INSERT OR REPLACE INTO installed_extensions (id, version, name, short_description, icon, active, meta) VALUES
('lnurlFlip', '0.1.1', 'LNURL Flip', 'Auto-switch between pay and withdraw based on balance', '/lnurlFlip/static/image/icon.png', 1, '{"installed_release": {"name": "lnurlFlip", "version": "0.1.1", "archive": "local", "source_repo": "local"}}');

-- Enable extensions for admin user
INSERT OR REPLACE INTO extensions ("user", extension, active) VALUES
('$ADMIN_USER_ID', 'lnurlp', 1);

INSERT OR REPLACE INTO extensions ("user", extension, active) VALUES
('$ADMIN_USER_ID', 'withdraw', 1);

INSERT OR REPLACE INTO extensions ("user", extension, active) VALUES
('$ADMIN_USER_ID', 'lnurlFlip', 1);
SQL

  docker cp /tmp/enable-lnurl-extensions.db "$LNBITS_CONTAINER:/app/data/database.sqlite3"
  rm /tmp/enable-lnurl-extensions.db
  echo "✅ Extensions enabled in database"

  # Final restart
  echo "Final restart..."
  docker restart "$LNBITS_CONTAINER"
  sleep 15

  # Wait for LNbits to be ready
  for i in {1..30}; do
    if curl -s "$LNBITS_URL/api/v1/health" > /dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  # Get invoice key
  INVOICE_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].inkey')

  # Export keys for use in tests (matching workflow expected format)
  echo "export ${NAME}_ADMIN_KEY=$ADMIN_KEY" >> lnbits_keys.env
  echo "export ${NAME}_INVOICE_KEY=$INVOICE_KEY" >> lnbits_keys.env
  echo "export ${NAME}_WALLET_ID=$WALLET_ID" >> lnbits_keys.env
  echo "export ${NAME}_USER_ID=$ADMIN_USER_ID" >> lnbits_keys.env
  echo "export ${NAME}_ACCESS_TOKEN=$ACCESS_TOKEN" >> lnbits_keys.env

  # Verify extensions are working by creating test links
  echo ""
  echo "Verifying extensions work..."

  # Test lnurlp
  PAY_LINK=$(curl -s -X POST "$LNBITS_URL/lnurlp/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "description": "Test Pay Link",
      "min": 100,
      "max": 10000,
      "comment_chars": 255
    }')

  PAY_ID=$(echo "$PAY_LINK" | jq -r '.id' 2>/dev/null)
  if [ -n "$PAY_ID" ] && [ "$PAY_ID" != "null" ]; then
    echo "✅ lnurlp working - created pay link: $PAY_ID"
    echo "export ${NAME}_PAY_ID=$PAY_ID" >> lnbits_keys.env
  else
    echo "❌ lnurlp failed: $PAY_LINK"
    return 1
  fi

  # Test withdraw
  WITHDRAW_LINK=$(curl -s -X POST "$LNBITS_URL/withdraw/api/v1/links" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "title": "Test Withdraw Link",
      "min_withdrawable": 50,
      "max_withdrawable": 500,
      "uses": 10,
      "wait_time": 1,
      "is_unique": true
    }')

  WITHDRAW_ID=$(echo "$WITHDRAW_LINK" | jq -r '.id' 2>/dev/null)
  WITHDRAW_HASH=$(echo "$WITHDRAW_LINK" | jq -r '.unique_hash' 2>/dev/null)
  WITHDRAW_LNURL=$(echo "$WITHDRAW_LINK" | jq -r '.lnurl' 2>/dev/null)
  if [ -n "$WITHDRAW_ID" ] && [ "$WITHDRAW_ID" != "null" ]; then
    echo "✅ withdraw working - created withdraw link: $WITHDRAW_ID"
    echo "export ${NAME}_WITHDRAW_ID=$WITHDRAW_ID" >> lnbits_keys.env
    echo "export ${NAME}_WITHDRAW_HASH=$WITHDRAW_HASH" >> lnbits_keys.env
    echo "export ${NAME}_WITHDRAW_LNURL=$WITHDRAW_LNURL" >> lnbits_keys.env
  else
    echo "❌ withdraw failed: $WITHDRAW_LINK"
    return 1
  fi

  # Test lnurlFlip (requires both pay and withdraw links)
  FLIP_LINK=$(curl -s -X POST "$LNBITS_URL/lnurlFlip/api/v1/lnurlflip" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"Test Flip Link\",
      \"wallet\": \"$WALLET_ID\",
      \"selectedLnurlp\": \"$PAY_ID\",
      \"selectedLnurlw\": \"$WITHDRAW_ID\"
    }")

  FLIP_ID=$(echo "$FLIP_LINK" | jq -r '.id' 2>/dev/null)
  if [ -n "$FLIP_ID" ] && [ "$FLIP_ID" != "null" ]; then
    echo "✅ lnurlFlip working - created flip link: $FLIP_ID"
    echo "export ${NAME}_FLIP_ID=$FLIP_ID" >> lnbits_keys.env
  else
    echo "❌ lnurlFlip failed: $FLIP_LINK"
    return 1
  fi

  echo ""
  echo "✅ All LNURL extensions setup complete for $NAME!"
}

# Clear previous keys file
rm -f lnbits_keys.env
touch lnbits_keys.env

# Determine which instances to set up based on what's running
echo ""
echo "=========================================="
echo "Detecting running LNbits instances..."
echo "=========================================="

# Check for lnbits-1
if docker ps --format '{{.Names}}' | grep -q "lnbits-1"; then
  setup_lnurl_extensions \
    "lightning-dev-env-lnbits-1-1" \
    "http://localhost:5001" \
    "6443" \
    "LNBITS1"
fi

# Check for lnbits-2
if docker ps --format '{{.Names}}' | grep -q "lnbits-2"; then
  setup_lnurl_extensions \
    "lightning-dev-env-lnbits-2-1" \
    "http://localhost:5002" \
    "7443" \
    "LNBITS2"
fi

# Check for lnbits-3
if docker ps --format '{{.Names}}' | grep -q "lnbits-3"; then
  setup_lnurl_extensions \
    "lightning-dev-env-lnbits-3-1" \
    "http://localhost:5003" \
    "8443" \
    "LNBITS3"
fi

echo ""
echo "=========================================="
echo "✅ LNURL EXTENSIONS BOOTSTRAP COMPLETE"
echo "=========================================="
echo ""
echo "Extensions installed:"
echo "  • lnurlp v${LNURLP_VERSION}"
echo "  • withdraw v${WITHDRAW_VERSION}"
echo "  • lnurlFlip"
echo ""
echo "Keys exported to: lnbits_keys.env"
echo "Source this file to use in tests: source lnbits_keys.env"
echo ""
