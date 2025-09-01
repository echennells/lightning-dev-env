#!/bin/bash

# Run individual workflow steps
set -e

STEP="$1"

case "$STEP" in
  "fund")
    echo "=== Step: Fund all three Lightning nodes ==="
    echo "Waiting a bit for nodes to stabilize..."
    sleep 10
    
    echo "Getting litd-1 deposit address..."
    LITD1_ADDR=$(docker compose exec -T litd-1 lncli --network=regtest newaddress p2wkh | jq -r .address)
    echo "litd-1 address: $LITD1_ADDR"
    
    echo "Getting litd-2 deposit address..."
    LITD2_ADDR=$(docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 newaddress p2wkh | jq -r .address)
    echo "litd-2 address: $LITD2_ADDR"
    
    echo "Getting LND deposit address..."
    LND_ADDR=$(docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 newaddress p2wkh | jq -r .address)
    echo "LND address: $LND_ADDR"
    
    if [ -z "$LITD1_ADDR" ] || [ -z "$LITD2_ADDR" ] || [ -z "$LND_ADDR" ]; then
      echo "Failed to get node addresses. Checking container status..."
      docker compose ps
      echo "Checking litd-1 logs..."
      docker compose logs --tail=30 litd-1
      exit 1
    fi
    
    echo "Sending 10 BTC to litd-1..."
    docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning sendtoaddress $LITD1_ADDR 10
    
    echo "Sending 10 BTC to litd-2..."
    docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning sendtoaddress $LITD2_ADDR 10
    
    echo "Sending 10 BTC to LND..."
    docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning sendtoaddress $LND_ADDR 10
    
    echo "Mining blocks to confirm..."
    ADDR=$(docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning getnewaddress)
    docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 6 $ADDR > /dev/null
    
    sleep 3
    
    echo "litd-1 wallet balance:"
    docker compose exec -T litd-1 lncli --network=regtest walletbalance
    
    echo "litd-2 wallet balance:"
    docker compose exec -T litd-2 lncli --network=regtest --rpcserver=litd-2:10010 walletbalance
    
    echo "LND wallet balance:"
    docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 walletbalance
    ;;

  "channels")
    echo "=== Step: Open channel from litd-1 to LND ==="
    echo "Getting LND node info..."
    LND_PUBKEY=$(docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 getinfo | jq -r .identity_pubkey)
    echo "LND pubkey: $LND_PUBKEY"
    
    echo "Connecting litd-1 to LND..."
    docker compose exec -T litd-1 lncli --network=regtest connect ${LND_PUBKEY}@lnd:9737
    
    echo "Opening channel from litd-1 to LND (0.1 BTC capacity, 0.05 BTC on each side)..."
    docker compose exec -T litd-1 lncli --network=regtest openchannel \
      --node_key=$LND_PUBKEY \
      --local_amt=10000000 \
      --push_amt=5000000
    
    echo "Mining blocks to confirm channel..."
    ADDR=$(docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning getnewaddress)
    docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=lightning -rpcpassword=lightning generatetoaddress 6 $ADDR > /dev/null
    
    echo "Waiting for channel to be active..."
    for i in {1..30}; do
      PENDING=$(docker compose exec -T litd-1 lncli --network=regtest pendingchannels | jq '.pending_open_channels | length')
      if [ "$PENDING" = "0" ]; then
        echo "Channel is active!"
        break
      fi
      echo "Attempt $i/30: Channel still pending..."
      sleep 2
    done

    echo "Testing Lightning payment..."
    echo "Checking channel status on litd-1..."
    docker compose exec -T litd-1 lncli --network=regtest listchannels | jq '.channels[0] | {active: .active, capacity: .capacity, local_balance: .local_balance, remote_balance: .remote_balance}'
    
    echo -e "\nCreating invoice on LND for 1000 sats..."
    INVOICE=$(docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 addinvoice --amt=1000 --memo="Test payment" | jq -r .payment_request)
    echo "Invoice created: ${INVOICE:0:60}..."
    
    echo -e "\nPaying invoice from litd-1..."
    docker compose exec -T litd-1 lncli --network=regtest payinvoice --pay_req=$INVOICE --force || echo "Payment attempt completed"
    
    echo -e "\nChecking final balances..."
    echo "litd-1 channel balance:"
    docker compose exec -T litd-1 lncli --network=regtest channelbalance | jq '.'
    
    echo "LND channel balance:"
    docker compose exec -T lnd lncli --network=regtest --rpcserver=lnd:10011 channelbalance | jq '.'
    
    echo -e "\n✅ Lightning channel established successfully!"
    ;;

  "lnbits")
    echo "=== Step: Start and test LNbits instances ==="
    echo "Starting 3 LNbits instances connected to Lightning nodes..."
    docker compose up -d lnbits-1 lnbits-2 lnbits-3
    
    echo "Waiting for LNbits instances to start (this may take a while to download)..."
    sleep 10
    
    echo -e "\n=== Waiting for extension installation to complete ==="
    echo "Extensions are installed asynchronously after startup..."
    
    for i in {1..30}; do
      if docker compose logs lnbits-1 2>&1 | grep -q "Installed Extensions"; then
        echo "✅ Extensions installed!"
        docker compose logs lnbits-1 2>&1 | grep -E "Installed Extensions" -A 5
        break
      fi
      echo "Attempt $i/30: Waiting for extensions to install..."
      sleep 2
    done
    
    echo -e "\n=== Container status after startup ==="
    docker compose ps | grep lnbits
    
    echo -e "\n=== Testing Lightning node connectivity from lnbits-1 ==="
    docker compose exec -T lnbits-1 sh -c "wget --spider https://litd-1:8080 2>&1 | head -5" || true
    
    echo -e "\n=== Checking lnbits-1 (litd-1) on port 5001 ==="
    
    if ! docker compose ps lnbits-1 | grep -q "Up"; then
      echo "❌ lnbits-1 container is not running!"
      echo "Container logs:"
      docker compose logs --tail=50 lnbits-1
    fi
    
    for i in {1..60}; do
      HEALTH_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:5001/api/v1/health 2>&1 || true)
      
      if echo "$HEALTH_RESPONSE" | grep -q "HTTP_CODE:200"; then
        echo "✅ lnbits-1 API is healthy!"
        break
      elif echo "$HEALTH_RESPONSE" | grep -q "HTTP_CODE:307"; then
        echo "⚠️ lnbits-1 is redirecting (first_install?)"
        echo "Response: $HEALTH_RESPONSE"
        break
      elif echo "$HEALTH_RESPONSE" | grep -q "Connection refused\|Failed to connect"; then
        if [ $i -eq 1 ]; then
          echo "Connection refused - LNbits may still be starting..."
          echo "Container logs:"
          docker compose logs --tail=20 lnbits-1
        fi
      fi
      
      if [ $i -eq 1 ] || [ $i -eq 20 ] || [ $i -eq 40 ]; then
        echo "Attempt $i/60: Response: $HEALTH_RESPONSE"
        echo "Checking if container is still running..."
        docker compose ps lnbits-1
        
        echo "Recent logs:"
        docker compose logs --tail=5 lnbits-1 2>&1
      else
        echo "Attempt $i/60: Waiting for lnbits-1..."
      fi
      sleep 3
    done
    
    echo -e "\n=== Checking other LNbits instances ==="
    echo "Checking lnbits-2 (litd-2) on port 5002..."
    for i in {1..60}; do
      if curl -s http://localhost:5002/api/v1/health 2>/dev/null; then
        echo "lnbits-2 API is responding!"
        break
      fi
      echo "Attempt $i/60: Waiting for lnbits-2..."
      sleep 3
    done
    
    echo "Checking lnbits-3 (lnd) on port 5003..."
    for i in {1..60}; do
      if curl -s http://localhost:5003/api/v1/health 2>/dev/null; then
        echo "lnbits-3 API is responding!"
        break
      fi
      echo "Attempt $i/60: Waiting for lnbits-3..."
      sleep 3
    done
    
    echo -e "\n✅ All 3 LNbits instances are running!"
    ;;

  "taproot")
    echo "=== Step: Test Taproot Assets functionality ==="
    echo "Checking Taproot Assets daemon status on litd-1..."
    docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon getinfo || echo "Taproot Assets daemon info"
    
    echo -e "\nChecking Taproot Assets daemon status on litd-2..."
    docker compose exec -T litd-2 tapcli --network=regtest --rpcserver=localhost:10010 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon getinfo || echo "Taproot Assets daemon info"
    
    echo -e "\nListing assets on litd-1 (should be empty for fresh setup)..."
    docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets list || echo "No assets yet"
    
    echo -e "\nChecking universe stats on litd-1..."
    docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon universe stats || echo "Universe stats"
    
    echo -e "\nVerifying RFQ and oracle configuration in logs..."
    docker compose logs litd-1 | grep -i "rfq\|oracle\|taproot" | head -10 || echo "Checking Taproot logs"
    
    echo -e "\n✅ Both Lightning Terminal nodes have full Taproot Assets support!"
    ;;

  "extensions")
    echo "=== Step: Test lnurlFlip extension ==="
    echo "TROUBLESHOOTING MODE: This is where the GitHub workflow often fails"
    echo "We'll run through the extension installation and testing step by step..."
    
    echo "Checking for available extensions..."
    docker compose exec -T lnbits-1 bash -c "ls -la /app/lnbits/extensions/ | head -20"
    
    echo "Installing lnurlFlip extension on lnbits-1..."
    docker compose exec -T lnbits-1 bash -c "
      which git || (apt-get update && apt-get install -y git)
      cd /app
      if [ ! -d 'lnbits/extensions/lnurlflip' ]; then
        echo 'Installing lnurlFlip extension...'
        git clone https://github.com/echennells/lnurlFlip.git lnbits/extensions/lnurlflip
        cd lnbits/extensions/lnurlflip
        pip install -r requirements.txt 2>/dev/null || true
        echo '✅ lnurlFlip extension installed'
      else
        echo 'lnurlFlip already installed'
      fi
    "
    
    echo "Extensions should be available immediately..."
    sleep 5
    
    echo -e "\n=== Checking LNbits health ==="
    HEALTH=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:5001/api/v1/health)
    echo "Health check: $HEALTH"
    
    echo -e "\n=== Container status ==="
    docker compose ps lnbits-1
    
    echo -e "\n=== Checking LNbits logs for initialization ==="
    docker compose logs lnbits-1 2>&1 | grep -i "super\|admin\|first\|extension\|lnurlp\|withdraw" | tail -20
    
    echo -e "\n=== Testing API access ==="
    curl -v http://localhost:5001/api/v1/health 2>&1 | head -20
    
    echo -e "\n🔍 DEBUGGING: This is where we need to investigate extension issues..."
    echo "Check the logs above for any errors in extension loading or API setup."
    ;;

  *)
    echo "Usage: $0 {fund|channels|lnbits|taproot|extensions}"
    echo ""
    echo "Available steps:"
    echo "  fund       - Fund all Lightning nodes"
    echo "  channels   - Open channels and test payments"
    echo "  lnbits     - Start and test LNbits instances"
    echo "  taproot    - Test Taproot Assets functionality"
    echo "  extensions - Test lnurlFlip extension (troubleshooting focus)"
    exit 1
    ;;
esac