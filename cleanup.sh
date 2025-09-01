#!/bin/bash

# Cleanup script for Lightning Dev Environment
echo "=== Cleaning up Lightning Dev Environment ==="

echo "Stopping all containers..."
docker compose down

echo "Removing volumes..."
docker compose down -v

echo "Checking for any remaining processes..."
docker compose ps

echo "Cleaning up Docker system (optional - removes unused images/containers)..."
read -p "Do you want to run 'docker system prune' to clean up unused Docker resources? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker system prune -f
    echo "Docker cleanup complete"
else
    echo "Skipped Docker cleanup"
fi

echo "✅ Cleanup complete!"
echo "You can now start fresh with: ./run-workflow-locally.sh"