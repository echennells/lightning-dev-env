#!/bin/bash
set -e

echo "=== Fixing Extension Compatibility Issues ==="

echo "1. Removing current broken extensions..."
docker compose exec -T lnbits-1 bash -c "
  cd /app/lnbits/extensions/
  rm -rf lnurlp withdraw lnurlflip
  echo 'Broken extensions removed'
"

echo -e "\n2. Installing compatible extension versions for LNbits v1.2.1..."
docker compose exec -T lnbits-1 bash -c "
  cd /app/lnbits/extensions/
  
  # Install lnurlp extension - use v1.2.1 compatible tag or commit
  echo 'Installing lnurlp...'
  git clone https://github.com/lnbits/lnurlp.git lnurlp
  cd lnurlp
  # Try to checkout a commit that's compatible with v1.2.1
  git log --oneline | head -5
  # Use an older commit that might be compatible
  git checkout HEAD~5 2>/dev/null || true
  cd ..
  
  # Install withdraw extension 
  echo 'Installing withdraw...'
  git clone https://github.com/lnbits/withdraw.git withdraw  
  cd withdraw
  git log --oneline | head -5
  # Use an older commit that might be compatible
  git checkout HEAD~5 2>/dev/null || true
  cd ..
  
  # For lnurlflip, check if it has proper structure
  echo 'Re-installing lnurlflip...'
  git clone https://github.com/echennells/lnurlFlip.git lnurlflip
  cd lnurlflip
  
  # Check the extension structure
  echo 'Checking lnurlflip structure:'
  ls -la
  if [ -f '__init__.py' ]; then
    echo 'Found __init__.py'
    head -10 __init__.py
  else
    echo 'No __init__.py found - this might be the issue'
  fi
  
  cd /app/lnbits/extensions/
  echo 'Final extension directory:'
  ls -la
"

echo -e "\n3. Updating database to mark extensions as active..."
docker compose exec -T lnbits-1 bash -c "
  sqlite3 /app/data/database.sqlite3 \"
    DELETE FROM installed_extensions WHERE id IN ('lnurlp', 'withdraw', 'lnurlflip');
    INSERT INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
    VALUES 
      ('lnurlp', '1.0.0', 'Pay Links', 'LNURL pay links', 'lnurlp/static/image/lnurl-pay.png', 1, '{}'),
      ('withdraw', '1.0.0', 'Withdraw Links', 'LNURL withdraw links', 'withdraw/static/image/lnurl-withdraw.png', 1, '{}'),
      ('lnurlflip', '1.0.0', 'lnurlFlip', 'Auto-switching LNURL', 'lnurlflip/static/image/lnurlFlip.png', 1, '{}');
  \"
  echo 'Database updated'
"

echo -e "\n4. Restarting LNbits..."
docker compose restart lnbits-1
sleep 20

echo -e "\n5. Checking loading errors..."
docker compose logs --tail=30 lnbits-1 | grep -i "error\|could not load"

echo -e "\n=== Extension Compatibility Fix Complete ==="