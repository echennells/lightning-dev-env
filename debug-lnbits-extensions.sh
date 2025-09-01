#!/bin/bash

# Debug LNbits Extension Issues
ACCESS_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJzdXBlcmFkbWluIiwidXNyIjoiZDA4YTMzMTMzMjJhNDUxNGFmNzVkNDg4YmNjMjdlZWUiLCJhdXRoX3RpbWUiOjE3NTY0Mjc5MzQsImV4cCI6MTc4Nzk2MzkzNH0.PrVsTwi9aJElAQporreaXpEYEV51FvmjJeJC087SjTk"

echo "=== LNbits Extension Debugging ==="
echo ""

echo "1. Check LNbits health:"
curl -s http://localhost:5001/api/v1/health
echo ""

echo -e "\n2. Check available extensions via API:"
curl -s "http://localhost:5001/api/v1/extension" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
echo ""

echo -e "\n3. Check user extensions:"
curl -s "http://localhost:5001/api/v1/auth" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq '.extensions'
echo ""

echo -e "\n4. Check filesystem extensions:"
docker compose exec lnbits-1 ls -la /app/lnbits/extensions/
echo ""

echo -e "\n5. Check extension manifests:"
echo "lnurlp manifest:"
docker compose exec lnbits-1 cat /app/lnbits/extensions/lnurlp/manifest.json 2>/dev/null || echo "No manifest"
echo -e "\nwithdraw manifest:"
docker compose exec lnbits-1 cat /app/lnbits/extensions/withdraw/manifest.json 2>/dev/null || echo "No manifest"
echo -e "\nlnurlflip manifest:"
docker compose exec lnbits-1 cat /app/lnbits/extensions/lnurlflip/manifest.json 2>/dev/null || echo "No manifest"

echo -e "\n6. Check database (installed_extensions table):"
docker compose exec lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 '.headers on' '.mode column' 'SELECT * FROM installed_extensions;' 2>/dev/null || echo 'Table query failed'
" 2>/dev/null

echo -e "\n7. Try to activate lnurlp manually:"
RESPONSE=$(curl -s -X PUT "http://localhost:5001/api/v1/extension/lnurlp/activate" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")
echo "Activation response: $RESPONSE"

echo -e "\n8. Check extensions after activation attempt:"
curl -s "http://localhost:5001/api/v1/extension" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
echo ""

echo -e "\n9. Check all extension endpoints:"
curl -s "http://localhost:5001/api/v1/extension?all_extensions=true" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
echo ""

echo -e "\n10. Recent container logs:"
docker compose logs --tail=10 lnbits-1

echo -e "\n=== END DEBUG ==="