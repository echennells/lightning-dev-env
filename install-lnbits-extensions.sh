#!/bin/bash
set -e

echo "=== LNbits Extension Installation Script ==="
echo "This script installs and activates lnurlp and withdraw extensions for LNbits"

# Configuration
LNBITS_SERVICE=${1:-lnbits-1}
case $LNBITS_SERVICE in
  lnbits-1) PORT=5001 ;;
  lnbits-2) PORT=5002 ;;
  lnbits-3) PORT=5003 ;;
  *) echo "Usage: $0 [lnbits-1|lnbits-2|lnbits-3]"; exit 1 ;;
esac

echo "Working with: $LNBITS_SERVICE on port $PORT"

# Helper function for API calls with retries
api_call_with_retry() {
    local url=$1
    local method=${2:-GET}
    local headers=$3
    local data=$4
    local max_retries=5
    
    for i in $(seq 1 $max_retries); do
        if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
            response=$(curl -s -X "$method" "$url" $headers -d "$data" 2>&1 || true)
        else
            response=$(curl -s -X "$method" "$url" $headers 2>&1 || true)
        fi
        
        if ! echo "$response" | grep -q "Connection refused"; then
            echo "$response"
            return 0
        fi
        
        echo "Attempt $i/$max_retries: Connection refused, retrying..." >&2
        sleep 2
    done
    
    echo "Failed after $max_retries attempts" >&2
    return 1
}

echo "1. Checking if LNbits is running..."
if ! docker compose ps $LNBITS_SERVICE | grep -q "Up"; then
    echo "Starting $LNBITS_SERVICE..."
    docker compose up -d $LNBITS_SERVICE
    echo "Waiting for startup..."
    sleep 15
fi

echo "2. Checking LNbits API health..."
for i in {1..30}; do
    HEALTH=$(api_call_with_retry "http://localhost:$PORT/api/v1/health" GET "" "" || echo "")
    
    if echo "$HEALTH" | grep -q "200"; then
        echo "✅ LNbits API is healthy"
        break
    elif echo "$HEALTH" | grep -q "307\|first_install"; then
        echo "⚠️ LNbits requires first install setup"
        
        # Complete first install
        echo "Completing first install..."
        FIRST_INSTALL=$(curl -s -X PUT "http://localhost:$PORT/api/v1/auth/first_install" \
            -H "Content-Type: application/json" \
            -d '{
                "username": "admin",
                "password": "admin1234",
                "password_repeat": "admin1234"
            }')
        
        ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token' 2>/dev/null)
        if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
            echo "✅ First install completed, access token obtained"
            break
        fi
    fi
    
    echo "Attempt $i/30: Waiting for LNbits API..."
    sleep 2
done

echo "3. Getting admin credentials..."
if [ -z "$ACCESS_TOKEN" ]; then
    # Try to get admin key from database
    ADMIN_KEY=$(docker compose exec -T $LNBITS_SERVICE bash -c "
        which sqlite3 >/dev/null 2>&1 || (apt-get update >/dev/null 2>&1 && apt-get install -y sqlite3 >/dev/null 2>&1)
        sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets WHERE adminkey IS NOT NULL LIMIT 1;' 2>/dev/null
    " | tr -d '\r\n' || echo "")
    
    if [ -z "$ADMIN_KEY" ]; then
        echo "❌ No admin key found. Please create a wallet first at http://localhost:$PORT"
        exit 1
    fi
    echo "Admin Key: ${ADMIN_KEY:0:10}..."
else
    echo "Using access token from first install"
    
    # Get user info to get admin key
    USER_INFO=$(curl -s "http://localhost:$PORT/api/v1/auth" \
        -H "Authorization: Bearer $ACCESS_TOKEN")
    ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey' 2>/dev/null)
    USER_ID=$(echo "$USER_INFO" | jq -r '.id' 2>/dev/null)
fi

# Get user ID if not already set
if [ -z "$USER_ID" ]; then
    USER_ID=$(docker compose exec -T $LNBITS_SERVICE bash -c "
        sqlite3 /app/data/database.sqlite3 'SELECT user FROM wallets WHERE adminkey=\"$ADMIN_KEY\" LIMIT 1;' 2>/dev/null
    " | tr -d '\r\n')
fi

echo "User ID: $USER_ID"

echo "4. Installing extension files..."
docker compose exec -T $LNBITS_SERVICE bash -c "
    # Install required packages
    apt-get update >/dev/null 2>&1
    apt-get install -y wget unzip sqlite3 >/dev/null 2>&1
    
    # Clean up old installations
    rm -rf /app/lnbits/extensions/lnurlp /app/lnbits/extensions/withdraw
    
    # Download and extract lnurlp v1.0.1
    echo 'Downloading lnurlp extension...'
    cd /tmp
    wget -q https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip -O lnurlp.zip
    unzip -q lnurlp.zip
    mv lnurlp-1.0.1 /app/lnbits/extensions/lnurlp
    
    # Download and extract withdraw v1.0.1
    echo 'Downloading withdraw extension...'
    wget -q https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip -O withdraw.zip
    unzip -q withdraw.zip
    mv withdraw-1.0.1 /app/lnbits/extensions/withdraw
    
    # Verify installation
    echo 'Verifying extension files...'
    ls -la /app/lnbits/extensions/lnurlp/__init__.py >/dev/null && echo '✅ lnurlp installed'
    ls -la /app/lnbits/extensions/withdraw/__init__.py >/dev/null && echo '✅ withdraw installed'
"

echo "5. Registering extensions in database..."
docker compose exec -T $LNBITS_SERVICE bash -c "
    # Clear old entries
    sqlite3 /app/data/database.sqlite3 'DELETE FROM installed_extensions WHERE id IN (\"lnurlp\", \"withdraw\");'
    sqlite3 /app/data/database.sqlite3 'DELETE FROM extensions WHERE extension IN (\"lnurlp\", \"withdraw\");'
    
    # Insert into installed_extensions
    sqlite3 /app/data/database.sqlite3 \"
        INSERT INTO installed_extensions (id, version, name, short_description, icon, active, meta) 
        VALUES 
            ('lnurlp', '1.0.1', 'Pay Links', 'Make reusable LNURL pay links', '/lnurlp/static/image/lnurl-pay.png', 1, 
             '{\\\"installed_release\\\":{\\\"name\\\":\\\"Pay Links\\\",\\\"version\\\":\\\"1.0.1\\\",\\\"archive\\\":\\\"https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip\\\",\\\"source_repo\\\":\\\"https://github.com/lnbits/lnurlp\\\",\\\"hash\\\":\\\"281cf5b0ebb4289f93c97ff9438abf18e01569508faaf389723144104bba2273\\\",\\\"min_lnbits_version\\\":\\\"1.0.0\\\",\\\"is_version_compatible\\\":true}}'),
            ('withdraw', '1.0.1', 'Withdraw Links', 'Make LNURL withdraw links', '/withdraw/static/image/lnurl-withdraw.png', 1,
             '{\\\"installed_release\\\":{\\\"name\\\":\\\"Withdraw Links\\\",\\\"version\\\":\\\"1.0.1\\\",\\\"archive\\\":\\\"https://github.com/lnbits/withdraw/archive/refs/tags/v1.0.1.zip\\\",\\\"source_repo\\\":\\\"https://github.com/lnbits/withdraw\\\",\\\"hash\\\":\\\"58b3847801efb0dcabd7fa8c9d16c08a2d50cd0e21e96b00b3a0baf88daa9a98\\\",\\\"min_lnbits_version\\\":\\\"1.0.0\\\",\\\"is_version_compatible\\\":true}}');
    \"
    
    # Enable for user
    sqlite3 /app/data/database.sqlite3 \"
        INSERT OR REPLACE INTO extensions (extension, active, \\\"user\\\") 
        VALUES 
            ('lnurlp', 1, '$USER_ID'),
            ('withdraw', 1, '$USER_ID');
    \"
    
    echo 'Extensions registered in database'
"

echo "6. Running Python activation script..."
docker compose exec -T $LNBITS_SERVICE bash -c "cat > /tmp/activate_extensions.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import sys
import os
sys.path.insert(0, '/app')
os.chdir('/app')

# Import LNbits modules
from lnbits.core.models.extensions import Extension
from lnbits.core.services.extensions import activate_extension
from lnbits.core.helpers import migrate_extension_database
from lnbits.core.crud import get_db_version
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def activate_extensions():
    extensions = ['lnurlp', 'withdraw']
    
    for ext_id in extensions:
        try:
            print(f'Activating {ext_id}...')
            
            # Run migrations
            db_version = await get_db_version(ext_id)
            from lnbits.core.models.extensions import InstallableExtension
            ext_info = InstallableExtension(
                id=ext_id,
                name=ext_id,
                version='1.0.1',
                meta={},
                icon='',
                short_description=''
            )
            await migrate_extension_database(ext_info, db_version)
            
            # Create Extension object
            extension = Extension(
                code=ext_id,
                name=ext_id,
                is_installed=True,
                is_admin_only=False,
                hidden=False
            )
            
            # Activate extension - this registers routes!
            await activate_extension(extension)
            print(f'✅ {ext_id} activated')
            
        except Exception as e:
            print(f'❌ Failed to activate {ext_id}: {e}')
            import traceback
            traceback.print_exc()

asyncio.run(activate_extensions())
EOF
python /tmp/activate_extensions.py
"

echo "7. Restarting LNbits to ensure routes are loaded..."
docker compose restart $LNBITS_SERVICE
echo "Waiting for restart..."
sleep 15

echo "8. Verifying installation..."
echo "Database check:"
docker compose exec -T $LNBITS_SERVICE bash -c "
    sqlite3 /app/data/database.sqlite3 'SELECT id, version, active FROM installed_extensions;'
"

echo -e "\nFile system check:"
docker compose exec -T $LNBITS_SERVICE bash -c "ls -la /app/lnbits/extensions/ | grep -E 'lnurlp|withdraw'"

echo "9. Testing extension APIs..."
# Wait for API to be ready after restart
for i in {1..30}; do
    if curl -s "http://localhost:$PORT/api/v1/health" >/dev/null 2>&1; then
        break
    fi
    echo "Waiting for API after restart..."
    sleep 2
done

echo "Testing lnurlp API:"
LNURLP_TEST=$(curl -s "http://localhost:$PORT/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY")
echo "$LNURLP_TEST"

echo -e "\nTesting withdraw API:"
WITHDRAW_TEST=$(curl -s "http://localhost:$PORT/withdraw/api/v1" -H "X-API-KEY: $ADMIN_KEY")
echo "$WITHDRAW_TEST"

# Check if APIs are working
if echo "$LNURLP_TEST" | grep -q "\[\]"; then
    echo -e "\n✅ SUCCESS! Extensions are working!"
    
    # Try to create a test pay link
    echo "Creating test pay link..."
    WALLET_ID=$(docker compose exec -T $LNBITS_SERVICE bash -c "
        sqlite3 /app/data/database.sqlite3 'SELECT id FROM wallets WHERE adminkey=\"$ADMIN_KEY\" LIMIT 1;'
    " | tr -d '\r\n')
    
    PAY_LINK=$(curl -s -X POST "http://localhost:$PORT/lnurlp/api/v1/links" \
        -H "X-API-KEY: $ADMIN_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"description\": \"Test Pay Link\",
            \"min\": 10,
            \"max\": 10000,
            \"comment_chars\": 255
        }")
    
    PAY_LINK_ID=$(echo "$PAY_LINK" | jq -r '.id' 2>/dev/null)
    if [ -n "$PAY_LINK_ID" ] && [ "$PAY_LINK_ID" != "null" ]; then
        echo "🎉 Created pay link: $PAY_LINK_ID"
        echo "Extensions are fully functional!"
    else
        echo "Pay link creation response: $PAY_LINK"
    fi
else
    echo -e "\n⚠️ Extensions may not be fully working"
    echo "Response: $LNURLP_TEST"
    echo ""
    echo "You may need to:"
    echo "1. Restart LNbits again: docker compose restart $LNBITS_SERVICE"
    echo "2. Check logs: docker compose logs --tail=50 $LNBITS_SERVICE"
fi

echo -e "\n=== Installation Complete ==="
echo "LNbits URL: http://localhost:$PORT"
echo "Admin Key: $ADMIN_KEY"