#!/usr/bin/env python3
"""
Simple websocket client to connect to Bitcoin Switch and keep connection alive.
This simulates hardware being connected to the switch.
"""

import asyncio
import websockets
import sys
import ssl
import os

async def connect_to_switch(switch_id, url="ws://lnbits-2:5000/api/v1/ws"):
    """Connect to Bitcoin Switch websocket and keep connection alive."""

    ws_url = f"{url}/{switch_id}"
    print(f"Connecting to {ws_url}...", flush=True)

    retry_count = 0
    max_retries = 10

    while retry_count < max_retries:
        try:
            async with websockets.connect(ws_url) as websocket:
                print(f"✅ Connected to Bitcoin Switch {switch_id}", flush=True)

                # Keep connection alive by listening for messages
                async for message in websocket:
                    print(f"📨 Received: {message}", flush=True)

        except Exception as e:
            retry_count += 1
            print(f"⚠️  Connection failed (attempt {retry_count}/{max_retries}): {e}", flush=True)
            if retry_count < max_retries:
                await asyncio.sleep(5)  # Wait before retry
            else:
                print("❌ Max retries reached, exiting", flush=True)
                sys.exit(1)

async def main():
    # Get switch ID from environment variable
    switch_id = os.getenv("BITCOIN_SWITCH_ID", "")

    if not switch_id:
        print("⚠️  No BITCOIN_SWITCH_ID provided, waiting for it to be set...", flush=True)
        # Wait and retry to get switch_id
        for i in range(30):
            await asyncio.sleep(2)
            switch_id = os.getenv("BITCOIN_SWITCH_ID", "")
            if switch_id:
                break

    if not switch_id:
        print("❌ BITCOIN_SWITCH_ID not set after 60 seconds, exiting", flush=True)
        sys.exit(1)

    print(f"🔌 Bitcoin Switch WebSocket Client", flush=True)
    print(f"   Switch ID: {switch_id}", flush=True)

    await connect_to_switch(switch_id)

if __name__ == "__main__":
    asyncio.run(main())
