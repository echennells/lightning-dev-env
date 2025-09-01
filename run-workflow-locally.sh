#!/bin/bash

# Run Lightning Dev Environment Workflow Locally
# This script simulates the GitHub Actions workflow for troubleshooting
set -e

echo "==================== LIGHTNING DEV ENVIRONMENT WORKFLOW ===================="
echo "Starting workflow simulation at $(date)"
echo "Working directory: $(pwd)"

# Step 1: Start Bitcoin and Lightning nodes
echo ""
echo "=== Step 1: Starting Bitcoin and Lightning nodes ==="
docker compose up -d bitcoind litd-1 litd-2 lnd
echo "Waiting for containers to start..."
sleep 5

# Step 2: Wait for Bitcoin to be ready
echo ""
echo "=== Step 2: Waiting for Bitcoin to be ready ==="
echo "Waiting for Bitcoin node to start..."
for i in {1..30}; do
  if docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning getblockchaininfo 2>/dev/null; then
    echo "Bitcoin node is ready!"
    break
  fi
  echo "Attempt $i/30: Bitcoin not ready yet..."
  sleep 2
done

# Step 3: Create Bitcoin wallet and mine blocks
echo ""
echo "=== Step 3: Creating Bitcoin wallet and mining blocks ==="
echo "Creating Bitcoin wallet..."
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning createwallet "test" || \
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning loadwallet "test"

echo "Getting new address..."
ADDR=$(docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning getnewaddress)
echo "Address: $ADDR"

echo "Mining 101 blocks..."
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 101 $ADDR > /dev/null

echo "Bitcoin balance:"
docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning getbalance

# Step 4: Setup litd-1 wallet
echo ""
echo "=== Step 4: Setting up litd-1 wallet ==="
echo "Waiting for litd-1 to be responsive..."
for i in {1..30}; do
  if docker compose exec -T litd-1 lncli --network=regtest getinfo 2>&1 | grep -q "identity_pubkey"; then
    echo "litd-1 is responding!"
    break
  fi
  echo "Attempt $i/30: litd-1 not ready yet..."
  sleep 2
done

echo "Creating litd-1 wallet..."
docker compose exec -T litd-1 lncli --network=regtest create <<EOF || true
password12345678
password12345678
n
EOF

echo "Unlocking litd-1 wallet..."
docker compose exec -T litd-1 lncli --network=regtest unlock <<EOF || true
password12345678
EOF

sleep 5

# Step 5: Setup litd-2 wallet
echo ""
echo "=== Step 5: Setting up litd-2 wallet ==="
echo "Waiting for litd-2 to be responsive..."
for i in {1..30}; do
  if docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 getinfo 2>&1 | grep -q "identity_pubkey"; then
    echo "litd-2 is responding!"
    break
  fi
  echo "Attempt $i/30: litd-2 not ready yet..."
  sleep 2
done

echo "Creating litd-2 wallet..."
docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 create <<EOF || true
password12345678
password12345678
n
EOF

echo "Unlocking litd-2 wallet..."
docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 unlock <<EOF || true
password12345678
EOF

sleep 5

# Step 6: Setup LND wallet
echo ""
echo "=== Step 6: Setting up LND wallet ==="
echo "Waiting for LND to be responsive..."
for i in {1..30}; do
  if docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 getinfo 2>&1 | grep -q "identity_pubkey"; then
    echo "LND is responding!"
    break
  fi
  echo "Attempt $i/30: LND not ready yet..."
  sleep 2
done

echo "Creating LND wallet..."
docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 create <<EOF || true
password12345678
password12345678
n
EOF

echo "Unlocking LND wallet..."
docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 unlock <<EOF || true
password12345678
EOF

sleep 5

# Step 7: Wait for nodes to sync
echo ""
echo "=== Step 7: Waiting for nodes to sync ==="
echo "Waiting for litd-1 to sync with blockchain..."
for i in {1..30}; do
  INFO=$(docker compose exec -T litd-1 lncli --network=regtest getinfo 2>/dev/null || echo "{}")
  if [ "$i" -eq 1 ]; then
    echo "DEBUG: litd-1 getinfo output (first 500 chars):"
    echo "$INFO" | head -c 500
    echo ""
  fi
  if echo "$INFO" | grep -qE '"synced_to_chain":\s*true|"synced_to_chain": true'; then
    echo "✅ litd-1 is synced!"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "⚠️ litd-1 sync check timed out, but continuing..."
    echo "Last getinfo output:"
    echo "$INFO"
  else
    echo "Attempt $i/30: Waiting for sync..."
  fi
  sleep 2
done

echo -e "\nWaiting for litd-2 to sync with blockchain..."
for i in {1..30}; do
  INFO=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 getinfo 2>/dev/null || echo "{}")
  if [ "$i" -eq 1 ]; then
    echo "DEBUG: litd-2 getinfo output (first 500 chars):"
    echo "$INFO" | head -c 500
    echo ""
  fi
  if echo "$INFO" | grep -qE '"synced_to_chain":\s*true|"synced_to_chain": true'; then
    echo "✅ litd-2 is synced!"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "⚠️ litd-2 sync check timed out, but continuing..."
  else
    echo "Attempt $i/30: Waiting for sync..."
  fi
  sleep 2
done

echo -e "\nWaiting for LND to sync with blockchain..."
for i in {1..30}; do
  INFO=$(docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 getinfo 2>/dev/null || echo "{}")
  if [ "$i" -eq 1 ]; then
    echo "DEBUG: LND getinfo output (first 500 chars):"
    echo "$INFO" | head -c 500
    echo ""
  fi
  if echo "$INFO" | grep -qE '"synced_to_chain":\s*true|"synced_to_chain": true'; then
    echo "✅ LND is synced!"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "⚠️ LND sync check timed out, but continuing..."
  else
    echo "Attempt $i/30: Waiting for sync..."
  fi
  sleep 2
done

echo "All nodes sync check complete, proceeding..."

echo ""
echo "==================== BASIC SETUP COMPLETE ===================="
echo "Bitcoin Core, Lightning Terminal (litd-1, litd-2), and LND are running"
echo "You can now run individual test steps with:"
echo "  ./run-workflow-step.sh fund"
echo "  ./run-workflow-step.sh channels"
echo "  ./run-workflow-step.sh lnbits"
echo "  ./run-workflow-step.sh taproot"
echo "  ./run-workflow-step.sh extensions"
echo ""
echo "Or cleanup with:"
echo "  ./cleanup.sh"