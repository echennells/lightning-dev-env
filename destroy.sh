#!/bin/bash

# Destroy script for Lightning Dev Environment
# Stops and removes all containers and volumes

set -e

echo "Stopping and removing containers..."
docker compose down -v

echo "Removing extension data..."
rm -rf data/*

echo "✅ Environment destroyed"
