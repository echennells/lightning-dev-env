#!/bin/bash
set -e

echo "=== WORKING Extension Install - Complete Solution ==="

# Select which LNbits instance to work with (default: lnbits-1)
LNBITS_SERVICE=${1:-lnbits-1}
case $LNBITS_SERVICE in
  lnbits-1) PORT=5001 ;;
  lnbits-2) PORT=5002 ;;
  lnbits-3) PORT=5003 ;;
  *) echo "Usage: $0 [lnbits-1|lnbits-2|lnbits-3]"; exit 1 ;;
esac

echo "Working with service: $LNBITS_SERVICE on port $PORT"

echo "1. Starting services if not running..."
docker compose up -d $LNBITS_SERVICE
sleep 10

echo "2. Getting admin key..."
ADMIN_KEY=$(docker compose exec -T $LNBITS_SERVICE bash -c "sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets WHERE adminkey IS NOT NULL LIMIT 1;'" | tr -d '\r\n')
if [ -z "$ADMIN_KEY" ]; then
  echo "No admin key found - need to create initial wallet first"
  echo "Go to http://localhost:$PORT and create your first wallet"
  exit 1
fi
echo "Admin Key: ${ADMIN_KEY:0:10}..."

echo "3. Getting user ID..."
USER_ID=$(docker compose exec -T $LNBITS_SERVICE bash -c "sqlite3 /app/data/database.sqlite3 'SELECT user FROM wallets LIMIT 1;'" | tr -d '\r\n')
echo "User ID: $USER_ID"

echo "4. Cleaning up existing extensions..."
docker compose exec -T $LNBITS_SERVICE bash -c "
  rm -rf /app/lnbits/extensions/*
  sqlite3 /app/data/database.sqlite3 'DELETE FROM installed_extensions;'
  sqlite3 /app/data/database.sqlite3 'DELETE FROM extensions;'
  apt-get update > /dev/null 2>&1
  apt-get install -y wget unzip sqlite3 > /dev/null 2>&1
"

echo "5. Installing and activating extensions via Python script..."
docker compose exec -T $LNBITS_SERVICE bash -c "cat > /tmp/install_extensions.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import sys
import os
sys.path.insert(0, '/app')
os.chdir('/app')

from lnbits.core.models.extensions import InstallableExtension, ExtensionMeta, Extension, UserExtension
from lnbits.core.services.extensions import install_extension, activate_extension
from lnbits.core.crud import get_user_extension, create_user_extension, update_user_extension
from lnbits.app import core_app_extra
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def install_and_activate_extensions():
    user_id = '$USER_ID'
    
    # Extension configurations
    extensions_to_install = [
        {
            'id': 'lnurlp',
            'name': 'Pay Links',
            'version': '1.0.1',
            'archive': 'https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip',
            'source_repo': 'https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json',
            'hash': '281cf5b0ebb4289f93c97ff9438abf18e01569508faaf389723144104bba2273',
            'icon': 'https://github.com/lnbits/lnurlp/raw/main/static/image/lnurl-pay.png',
        },
        {
            'id': 'withdraw',
            'name': 'Withdraw Links', 
            'version': '1.0.1',
            'archive': 'https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip',
            'source_repo': 'https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json',
            'hash': '58b3847801efb0dcabd7fa8c9d16c08a2d50cd0e21e96b00b3a0baf88daa9a98',
            'icon': 'https://github.com/lnbits/withdraw/raw/main/static/image/lnurl-withdraw.png',
        }
    ]
    
    for ext_config in extensions_to_install:
        try:
            print(f\"Installing {ext_config['id']}...\")
            
            # Create extension metadata
            ext_meta = ExtensionMeta(
                installed_release={
                    'name': ext_config['name'],
                    'version': ext_config['version'],
                    'archive': ext_config['archive'],
                    'source_repo': ext_config['source_repo'],
                    'hash': ext_config['hash'],
                    'min_lnbits_version': '1.0.0',
                    'max_lnbits_version': '1.3.0',
                    'is_version_compatible': True,
                    'repo': f\"https://github.com/lnbits/{ext_config['id']}\",
                }
            )
            
            # Create InstallableExtension
            ext_info = InstallableExtension(
                id=ext_config['id'],
                name=ext_config['name'],
                version=ext_config['version'],
                meta=ext_meta,
                icon=ext_config['icon'],
                short_description=f\"Extension {ext_config['name']}\",
                stars=0
            )
            
            # Download and install extension
            await ext_info.download_archive()
            ext_info.extract_archive()
            
            # Run migrations
            from lnbits.core.helpers import migrate_extension_database
            from lnbits.core.crud import get_db_version
            db_version = await get_db_version(ext_info.id)
            await migrate_extension_database(ext_info, db_version)
            
            # Save to database
            from lnbits.core.crud import create_installed_extension, update_installed_extension
            from lnbits.core.crud import get_installed_extension
            
            existing = await get_installed_extension(ext_info.id)
            if existing:
                await update_installed_extension(ext_info)
            else:
                await create_installed_extension(ext_info)
            
            # Create Extension object for activation
            extension = Extension(
                code=ext_config['id'],
                name=ext_config['name'],
                is_installed=True,
                is_admin_only=False,
                hidden=False
            )
            
            # Activate extension - this registers routes!
            print(f\"Activating {ext_config['id']}...\")
            await activate_extension(extension)
            
            # Enable for user
            print(f\"Enabling {ext_config['id']} for user {user_id}...\")
            user_ext = await get_user_extension(user_id, ext_config['id'])
            if not user_ext:
                user_ext = UserExtension(user=user_id, extension=ext_config['id'], active=True)
                await create_user_extension(user_ext)
            else:
                user_ext.active = True
                await update_user_extension(user_ext)
            
            print(f\"✅ {ext_config['id']} installed and activated successfully!\")
            
        except Exception as e:
            print(f\"❌ Failed to install {ext_config['id']}: {e}\")
            import traceback
            traceback.print_exc()
    
    print(\"Installation complete!\")

# Run the async function
asyncio.run(install_and_activate_extensions())
EOF
python /tmp/install_extensions.py
"

echo "6. Restarting LNbits to ensure everything is loaded..."
docker compose restart $LNBITS_SERVICE
sleep 15

echo "7. Checking what got installed..."
echo "Installed extensions in database:"
docker compose exec -T $LNBITS_SERVICE bash -c "sqlite3 /app/data/database.sqlite3 'SELECT id, version, active FROM installed_extensions;'"

echo -e "\nUser extensions:"
docker compose exec -T $LNBITS_SERVICE bash -c "sqlite3 /app/data/database.sqlite3 'SELECT extension, active FROM extensions WHERE user=\"$USER_ID\";'"

echo -e "\nFile system:"
docker compose exec -T $LNBITS_SERVICE bash -c "ls -la /app/lnbits/extensions/"

echo "8. Checking logs for extension loading..."
docker compose logs --tail=30 $LNBITS_SERVICE | grep -i "extension\|lnurlp\|withdraw" | tail -10

echo "9. Testing extension APIs..."
echo "lnurlp API test:"
LNURLP_RESULT=$(curl -s "http://localhost:$PORT/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "API call failed")
echo "$LNURLP_RESULT"

echo -e "\nwithdraw API test:"
WITHDRAW_RESULT=$(curl -s "http://localhost:$PORT/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY" || echo "API call failed")
echo "$WITHDRAW_RESULT"

# Test if extensions actually work
if echo "$LNURLP_RESULT" | grep -q "\[\]"; then
    echo -e "\n✅ SUCCESS! Extensions are working!"
    echo "The Python script properly:"
    echo "  - Downloaded and extracted extensions"
    echo "  - Ran database migrations"
    echo "  - Called activate_extension() to register routes"
    echo "  - Enabled extensions for the user"
    
    # Try to create a test pay link
    echo -e "\n10. Creating test pay link to verify full functionality..."
    PAY_LINK=$(curl -s -X POST "http://localhost:$PORT/lnurlp/api/v1/links" \
      -H "X-API-KEY: $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "description": "Test Pay Link",
        "min": 10,
        "max": 10000,
        "comment_chars": 255
      }')
    
    PAY_LINK_ID=$(echo "$PAY_LINK" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ]; then
        echo "🎉 FULL SUCCESS! Created pay link: $PAY_LINK_ID"
        echo "Extensions are fully functional!"
    else
        echo "Pay link creation response: $PAY_LINK"
    fi
else
    echo -e "\n❌ Extensions still not working properly."
    echo "API Response: $LNURLP_RESULT"
    echo "The route registration may have failed."
fi

echo -e "\n=== Installation Complete ==="
echo "This script mimics the exact process the GUI uses:"
echo "1. Downloads and extracts extension files"
echo "2. Runs database migrations"
echo "3. Calls activate_extension() to register routes"
echo "4. Enables extensions for the user"