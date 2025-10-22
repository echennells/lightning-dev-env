#!/bin/bash

# Fund LNbits wallets so they can send payments (not just receive)
set -e

echo "💰 Funding LNbits Wallets for Outbound Payments"
echo "================================================"
echo ""

# Get Asset ID
ASSET_ID=$(docker compose exec -T litd-1 tapcli --network=regtest --rpcserver=localhost:10009 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.tapd/data/regtest/admin.macaroon assets list | jq -r '.assets[0].asset_genesis.asset_id' 2>/dev/null || echo "")

if [ -z "$ASSET_ID" ] || [ "$ASSET_ID" = "null" ]; then
  echo "❌ No Taproot Assets found"
  exit 1
fi

echo "Asset ID: $ASSET_ID"
echo ""

# Fund LNbits-1 via container network
echo "📍 Funding LNbits-1..."
docker cp lightning-dev-env-lnbits-1-1:/app/data/database.sqlite3 /tmp/lb1.db 2>/dev/null
LNB1_KEY=$(sqlite3 /tmp/lb1.db "SELECT adminkey FROM wallets ORDER BY id LIMIT 1;" 2>/dev/null)
rm -f /tmp/lb1.db

if [ -z "$LNB1_KEY" ]; then
  echo "❌ Could not get LNbits-1 admin key"
  exit 1
fi

# Bitcoin funding
echo "  💵 Funding with 100,000 sats..."
BTC_INV=$(docker compose exec -T lnbits-1 curl -s -X POST "http://localhost:5000/api/v1/payments" \
  -H "X-Api-Key: $LNB1_KEY" \
  -H "Content-Type: application/json" \
  -d '{"out": false, "amount": 100000, "memo": "Fund wallet"}' | jq -r '.bolt11')

if [ -n "$BTC_INV" ] && [ "$BTC_INV" != "null" ]; then
  # Pay from litd-2 to avoid self-payment (LNbits-1 is connected to litd-1)
  docker compose exec -T litd-2 lncli --network=regtest --rpcserver=localhost:10010 --tlscertpath=/root/.lnd/tls.cert --macaroonpath=/root/.lnd/data/chain/bitcoin/regtest/admin.macaroon payinvoice --force "$BTC_INV" > /dev/null 2>&1
  sleep 2
  echo "  ✅ Bitcoin funded"
else
  echo "  ⚠️  Bitcoin invoice failed, skipping"
fi

# Taproot Asset funding - Skip for LNbits-1 (would be self-payment from litd-1)
echo "  🎨 Skipping Taproot Asset funding for LNbits-1 (self-payment issue)"
echo "     LNbits-1 will need to receive assets from LNbits-2 or other sources"

echo ""

# Fund LNbits-2 (already has some from TEST 3, but add more)
echo "📍 Funding LNbits-2..."
docker cp lightning-dev-env-lnbits-2-1:/app/data/database.sqlite3 /tmp/lb2.db 2>/dev/null
LNB2_KEY=$(sqlite3 /tmp/lb2.db "SELECT adminkey FROM wallets ORDER BY id LIMIT 1;" 2>/dev/null)
rm -f /tmp/lb2.db

if [ -z "$LNB2_KEY" ]; then
  echo "❌ Could not get LNbits-2 admin key"
  exit 1
fi

# Bitcoin funding
echo "  💵 Funding with 100,000 sats..."
BTC_INV=$(docker compose exec -T lnbits-2 curl -s -X POST "http://localhost:5000/api/v1/payments" \
  -H "X-Api-Key: $LNB2_KEY" \
  -H "Content-Type: application/json" \
  -d '{"out": false, "amount": 100000, "memo": "Fund wallet"}' | jq -r '.bolt11')

if [ -n "$BTC_INV" ] && [ "$BTC_INV" != "null" ]; then
  docker compose exec -T litd-1 lncli --network=regtest payinvoice --force "$BTC_INV" > /dev/null 2>&1
  sleep 2
  echo "  ✅ Bitcoin funded"
else
  echo "  ⚠️  Bitcoin invoice failed, skipping"
fi

# Taproot Asset funding
echo "  🎨 Funding with 10,000 Taproot Assets..."
ASSET_INV=$(docker compose exec -T lnbits-2 curl -s -X POST "http://localhost:5000/taproot_assets/api/v1/taproot/invoice" \
  -H "X-Api-Key: $LNB2_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"asset_id\": \"$ASSET_ID\", \"amount\": 10000, \"memo\": \"Fund wallet\"}" | jq -r '.payment_request')

if [ -n "$ASSET_INV" ] && [ "$ASSET_INV" != "null" ]; then
  docker compose exec -T litd-1 litcli \
    --rpcserver localhost:8443 \
    --tlscertpath /root/.lit/tls.cert \
    --macaroonpath /root/.lit/regtest/lit.macaroon \
    --network=regtest ln payinvoice \
    --pay_req "$ASSET_INV" \
    --asset_id "$ASSET_ID" \
    --force > /dev/null 2>&1
  sleep 3
  echo "  ✅ Taproot Assets funded"
else
  echo "  ⚠️  Asset invoice failed, skipping"
fi

echo ""
echo "✅ LNbits wallets funded!"
echo ""
echo "Balances:"
echo "---------"

LNB1_BTC=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/api/v1/wallet" -H "X-Api-Key: $LNB1_KEY" | jq -r '.balance // 0')
LNB1_ASSET=$(docker compose exec -T lnbits-1 curl -s "http://localhost:5000/taproot_assets/api/v1/taproot/listassets" -H "X-Api-Key: $LNB1_KEY" | jq -r '.[0].user_balance // 0')

LNB2_BTC=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/api/v1/wallet" -H "X-Api-Key: $LNB2_KEY" | jq -r '.balance // 0')
LNB2_ASSET=$(docker compose exec -T lnbits-2 curl -s "http://localhost:5000/taproot_assets/api/v1/taproot/listassets" -H "X-Api-Key: $LNB2_KEY" | jq -r '.[0].user_balance // 0')

echo "LNbits-1: $((LNB1_BTC / 1000)) sats, $LNB1_ASSET asset units"
echo "LNbits-2: $((LNB2_BTC / 1000)) sats, $LNB2_ASSET asset units"
echo ""
