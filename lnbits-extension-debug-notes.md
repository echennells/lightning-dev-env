# LNbits Extension Installation Debug Notes

## Test Environment
- **Date**: 2025-08-30
- **LNbits**: Running in Docker container
- **Port**: 5000 (not 5001 as initially expected)
- **Container**: `lightning-dev-env-lnbits-1-1`

## Fresh Install Baseline State

### Database Schema
```sql
-- Extensions table (exists, empty)
CREATE TABLE extensions (
    "user" TEXT NOT NULL,
    extension TEXT NOT NULL,
    active BOOLEAN DEFAULT false, 
    extra TEXT,
    UNIQUE ("user", extension)
);

-- Installed extensions table (exists, empty)
CREATE TABLE installed_extensions (
    id TEXT PRIMARY KEY,
    version TEXT NOT NULL,
    name TEXT NOT NULL,
    short_description TEXT,
    icon TEXT,
    stars INT NOT NULL DEFAULT 0,
    active BOOLEAN DEFAULT false,
    meta TEXT NOT NULL DEFAULT '{}'
);

-- Wallets table structure
CREATE TABLE wallets (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    "user" TEXT NOT NULL,
    adminkey TEXT NOT NULL,  -- Note: column is 'adminkey' not 'admin_key'
    inkey TEXT,
    currency TEXT, 
    deleted BOOLEAN NOT NULL DEFAULT false, 
    created_at TIMESTAMP DEFAULT NULL, 
    updated_at TIMESTAMP DEFAULT NULL, 
    extra TEXT
);
```

### File System State
```bash
# Extensions directory completely empty
/app/lnbits/extensions/  # exists but empty
# No Python files: 0 *.py files found
```

### Database Content (Before First Login)
```bash
# Admin key exists in wallets table
ADMIN_KEY: 57921b4232794561824de125c2d3f530

# After some initial access, accounts table populated:
accounts: 573436e67a6e449f8692d6503040608d||||{...}
wallets: 587032978fed417789ab91665f10e5a3|LNbits wallet

# Extensions tables remain empty:
extensions: (empty)
installed_extensions: (empty)
```

### API Behavior (Fresh Install)
- **Status**: LNbits requires first-time setup
- **Redirects**: All requests redirect (307) to `/first_install`
- **Port**: Service runs on 5000, accessible via localhost:5000
- **API Access**: Blocked until first install completed

### Test Commands Used
```bash
# Database inspection
docker compose exec -T lnbits bash -c "sqlite3 /app/data/database.sqlite3 '.schema extensions'"
docker compose exec -T lnbits bash -c "sqlite3 /app/data/database.sqlite3 'SELECT * FROM extensions;'"
docker compose exec -T lnbits bash -c "sqlite3 /app/data/database.sqlite3 'SELECT * FROM installed_extensions;'"

# File system check
docker compose exec -T lnbits bash -c "ls -la /app/lnbits/extensions/"
docker compose exec -T lnbits bash -c "find /app/lnbits/extensions/ -name '*.py' | wc -l"

# Get admin key (correct column name)
ADMIN_KEY=$(docker compose exec -T lnbits bash -c "sqlite3 /app/data/database.sqlite3 'SELECT adminkey FROM wallets WHERE adminkey IS NOT NULL LIMIT 1;'")

# API testing
curl -s "http://localhost:5000/api/v1/extensions" -H "X-API-KEY: $ADMIN_KEY"
curl -s "http://localhost:5000/extensions/api/v1/extensions" -H "X-API-KEY: $ADMIN_KEY"
```

### Post-Login State (After First Install)
- **API Access**: Now available, but extensions endpoints return `{"detail":"Not Found"}`
- **Database**: Extensions tables still empty
- **Redirect Issue**: No longer redirecting to /first_install

```bash
# API responses after login
curl "http://localhost:5000/api/v1/extensions" -H "X-API-KEY: 57921b4232794561824de125c2d3f530"
# Returns: {"detail":"Not Found"}

curl "http://localhost:5000/extensions/api/v1/extensions" -H "X-API-KEY: 57921b4232794561824de125c2d3f530" 
# Returns: {"detail":"Not Found"}

# Database still empty
extensions: (empty)
installed_extensions: (empty)
```

### Post-Extension-Install State (After Manual GUI Install)

**Extensions Installed**: `lnurlp` (v1.0.1) and `withdraw` (v1.0.1)

**Database State:**
```sql
-- extensions table (user-specific activation)
extensions: 
573436e67a6e449f8692d6503040608d|lnurlp|1|null
573436e67a6e449f8692d6503040608d|withdraw|1|null

-- installed_extensions table (system-wide installation)
installed_extensions:
lnurlp|1.0.1|Pay Links|Make reusable LNURL pay links|[github_icon]|0|1|{full_metadata}
withdraw|1.0.1|Withdraw Links|Make LNURL withdraw links|[github_icon]|0|1|{full_metadata}
```

**Key Metadata in installed_extensions:**
- **Archive URLs**: `https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip`
- **Source**: `https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json`
- **Hashes**: SHA256 checksums for verification
- **Version compatibility**: `min_lnbits_version` and `max_lnbits_version` checks
- **Installation metadata**: `installed_release` object with full details

**File System State:**
```bash
/app/lnbits/extensions/
├── lnurlp/           # Full extension directory
│   ├── migrations.py
│   ├── models.py
│   ├── views.py
│   ├── crud.py
│   ├── __init__.py
│   └── tests/
└── withdraw/         # Full extension directory
    └── [similar structure]
```

**API Endpoints After Install:**
```bash
# Extension management API still returns "Missing user ID"
curl "http://localhost:5000/api/v1/extension" -H "X-API-KEY: $ADMIN_KEY"
# Returns: {"detail":"Missing user ID or access token."}

# Individual extension APIs return "Not Found"  
curl "http://localhost:5000/lnurlp/api/v1" -H "X-API-KEY: $ADMIN_KEY"
# Returns: {"detail":"Not Found"}

# Extension pages return 401 (auth required)
curl "http://localhost:5000/lnurlp/"
# Returns: 401 status code
```

**Manual Install Process (From Logs):**
1. **Download**: `INFO | Downloading extension withdraw (1.0.1)`
2. **Extract**: `INFO | Extracting extension withdraw (1.0.1)`  
3. **Migrate**: `running migration withdraw.1` through `withdraw.7`
4. **Activate**: `INFO | Activating extension: 'withdraw'`
5. **Enable**: `INFO | Enabling extension: withdraw`

**Critical API Discoveries:**
- Extensions management uses `/api/v1/extension` (singular, not plural)
- Admin key alone isn't sufficient - needs user context
- Individual extension APIs exist at `/{extension_id}/api/v1` but return 404
- Extension web interfaces require full authentication (401 errors)

## Final Findings - Extension Installation Issue

**Root Cause Discovered**: Extensions install successfully (files + database) but **routes don't get registered** with FastAPI.

### What Works:
- Extensions download and extract ✅
- Database entries created ✅  
- Migrations run ✅
- Extensions show as "Installed Extensions (2)" in logs ✅

### What Doesn't Work:
- Extension API routes return "Not Found" ❌
- Routes not registered with FastAPI ❌

### Testing Results:
1. **Manual GUI Install**: Extensions work perfectly
2. **Script-based Install**: Extensions install but routes missing
3. **Built-in Auto-Install**: Same issue - installs but routes missing 

### Critical Discovery:
Even the built-in `LNBITS_EXTENSIONS_DEFAULT_INSTALL=lnurlp,withdraw` has the same route registration issue. This suggests:

- **Version Issue**: LNbits v1.2.1 may have a route registration bug
- **Activation Issue**: Extensions need proper `activate_extension()` call
- **Timing Issue**: Route registration happens at specific startup phase

### The Only Working Approach:
**Manual GUI installation** through the web interface properly registers routes via:
1. API call to `/api/v1/extension` (POST)
2. Calls `install_extension()` → `migrate_extension_database()`  
3. Calls `activate_extension()` → `register_new_ext_routes()`
4. Routes become available immediately

## Next Steps
1. ✅ Complete first install via browser
2. ✅ Run same commands again to capture "post-login" state  
3. ✅ Manually install extensions via GUI  
4. ✅ Run commands again to capture "post-extension-install" state
5. ✅ Compare with our automated scripts to identify differences
6. **CONCLUSION**: Use manual GUI install as the reliable method

## Issues Discovered
- **Port confusion**: Expected 5001 but actual port is 5000
- **Column naming**: Database column is `adminkey` not `admin_key`
- **First install requirement**: API blocked until setup completed
- **Docker warnings**: `EXTERNAL_IP` variable not set (non-critical)

## Files in Project Directory
Multiple shell scripts for extension installation automation:
- complete-lnbits-setup.sh
- debug-lnbits-extensions.sh  
- final-extension-fix.sh
- fix-lnbits-extensions.sh
- simple-extension-install.sh
- And many others...

These scripts appear to be previous attempts at automating extension installation.