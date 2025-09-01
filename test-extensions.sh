#!/bin/bash

cd /home/ubuntu/lightning-dev-env

echo "=== Testing Extensions After Database Fix ==="

# Get fresh access token by logging in
echo "1. Getting fresh access token..."
RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/auth/first_install" \
  -H "Content-Type: application/json" \
  -d '{"username": "superadmin", "password": "secret1234", "password_repeat": "secret1234"}')

ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
echo "Got token: ${ACCESS_TOKEN:0:20}..."

echo -e "\n2. Testing available extensions:"
curl -s "http://localhost:5001/api/v1/extension" -H "Authorization: Bearer $ACCESS_TOKEN"

echo -e "\n\n3. Testing user info:"
curl -s "http://localhost:5001/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN" | jq '.extensions'

echo -e "\n\n4. Testing extension activation:"
curl -s -X PUT "http://localhost:5001/api/v1/extension/lnurlp/enable" -H "Authorization: Bearer $ACCESS_TOKEN"

echo -e "\n\n5. Checking user extensions after enable:"
curl -s "http://localhost:5001/api/v1/auth" -H "Authorization: Bearer $ACCESS_TOKEN" | jq '.extensions'

echo -e "\n\n=== END TEST ==="