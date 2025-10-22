#!/bin/bash
# Connect websocket client to a Bitcoin Switch

SWITCH_ID=$1

if [ -z "$SWITCH_ID" ]; then
  echo "Usage: $0 <switch_id>"
  exit 1
fi

echo "🔌 Connecting websocket client to Bitcoin Switch: $SWITCH_ID"

# Set environment variable and restart the websocket client
export BITCOIN_SWITCH_ID=$SWITCH_ID

# Restart the websocket client with the new switch ID
docker compose rm -sf bitcoinswitch-ws-client 2>/dev/null || true
BITCOIN_SWITCH_ID=$SWITCH_ID docker compose up -d bitcoinswitch-ws-client

echo "⏳ Waiting for websocket connection..."
sleep 3

# Check if container is running
if docker compose ps bitcoinswitch-ws-client | grep -q "Up"; then
  echo "✅ Websocket client connected to switch $SWITCH_ID"
  docker compose logs --tail 10 bitcoinswitch-ws-client
else
  echo "❌ Failed to start websocket client"
  docker compose logs bitcoinswitch-ws-client
  exit 1
fi
