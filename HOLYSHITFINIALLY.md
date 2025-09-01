# HOLY SHIT FINALLY! 🎉

**The Complete Guide to Fixing LNbits Extension Installation & LNURL-P Creation**

*After hours of debugging, HAR file analysis, and authentication detective work, we finally cracked it!*

---

## The Problem That Nearly Drove Us Insane

We were trying to:
1. Install LNbits extensions (lnurlp 1.0.1, withdraw 1.0.1) via API 
2. Get them working in GitHub Actions workflow
3. Create functional LNURL-P links over HTTPS

**What kept failing:**
- Extensions would "install" but APIs returned `{"detail":"Not Found"}`
- Route registration appeared broken in LNbits v1.2.1
- LNURL-P creation failed with "need public domain" errors

## The Breakthrough Discovery 🕵️

**IT WAS ALL ABOUT AUTHENTICATION METHODS!**

The HAR file analysis revealed the truth:
- Browser/GUI uses `Authorization: Bearer <token>` for extension management
- We were using `X-API-KEY: <admin_key>` (WRONG!)
- Different APIs need different auth methods

## The Complete Working Solution ✅

### 1. Authentication Matrix

| Operation | Header | Value |
|-----------|--------|-------|
| First install | `Content-Type: application/json` | Body: `{username, password, password_repeat}` |
| Extension install/activate/enable | `Authorization: Bearer <access_token>` | From first_install response |
| Extension usage (create links) | `X-API-KEY: <admin_key>` | From wallet.adminkey |
| Extension APIs (currencies, etc) | `Authorization: Bearer <access_token>` | From first_install response |

### 2. The Complete API Sequence

```bash
# Step 1: Complete first install and get Bearer token
FIRST_INSTALL=$(curl -s -X PUT https://localhost:5443/api/v1/auth/first_install \
  -H "Content-Type: application/json" \
  -d '{
    "username": "superadmin",
    "password": "secret1234", 
    "password_repeat": "secret1234"
  }')

ACCESS_TOKEN=$(echo "$FIRST_INSTALL" | jq -r '.access_token')

# Step 2: Get wallet admin key for later use
USER_INFO=$(curl -s -X GET "https://localhost:5443/api/v1/auth" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')

# Step 3: Install extension with Bearer token (NOT admin key!)
curl -s -X POST https://localhost:5443/api/v1/extension \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "ext_id": "lnurlp",
    "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip",
    "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json",
    "payment_hash": null,
    "version": "1.0.1"
  }'

# Step 4: Activate extension with Bearer token
curl -s -X PUT "https://localhost:5443/api/v1/extension/lnurlp/activate" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# Step 5: Enable extension for user with Bearer token  
curl -s -X PUT "https://localhost:5443/api/v1/extension/lnurlp/enable" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# Step 6: Now use admin key for wallet operations
curl -s -X POST "https://localhost:5443/lnurlp/api/v1/links" \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Working LNURL-P Link",
    "min": 1000,
    "max": 10000,
    "comment_chars": 255
  }'
```

### 3. HTTPS & Public Domain Requirements

**LNURL-P requires HTTPS and "public" domains.** Here's how to fake it:

#### nginx-lnbits.conf
```nginx
server {
    listen 443 ssl;
    server_name localhost lnbits.example.com;

    ssl_certificate /etc/ssl/certs/lnbits.crt;
    ssl_certificate_key /etc/ssl/certs/lnbits.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://lnbits-1:5000;
        # 🔑 KEY: Fake a public domain to bypass LNURL validation
        proxy_set_header Host lnbits.example.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host lnbits.example.com;
    }
}
```

#### Docker Compose Setup
```yaml
lnbits-https-proxy:
  image: nginx:alpine
  hostname: lnbits-https
  depends_on:
    - lnbits-1
  restart: unless-stopped
  ports:
    - "5443:443"
  volumes:
    - ./nginx-lnbits.conf:/etc/nginx/conf.d/default.conf:ro
    - ./ssl:/etc/ssl/certs:ro
```

## What We Learned 🧠

### The Root Cause
**LNbits v1.2.1 is NOT broken!** We were just using the wrong authentication:
- Extension management APIs expect Bearer tokens (like the GUI uses)
- Wallet operation APIs expect admin keys
- Mixed usage caused route registration failures

### Why the HAR File Was Crucial
- Showed the browser was using Bearer token authentication
- Revealed the exact API sequence that works
- Proved the extension routes DO register when auth is correct

### The LNURL-P Domain Trick
- LNURL spec requires public HTTPS domains
- Nginx can fake the domain via `proxy_set_header Host`
- LNbits extension accepts the spoofed domain
- Results in working LNURL-P links with QR codes

## GitHub Workflow Implementation 🚀

```yaml
- name: Install and test LNbits extensions
  run: |
    # Complete first install
    FIRST_INSTALL_RESPONSE=$(curl -k -s -X PUT https://localhost:5443/api/v1/auth/first_install \
      -H "Content-Type: application/json" \
      -d '{"username": "superadmin", "password": "secret1234", "password_repeat": "secret1234"}')
    
    ACCESS_TOKEN=$(echo "$FIRST_INSTALL_RESPONSE" | jq -r '.access_token')
    
    # Get admin key
    USER_INFO=$(curl -k -s -X GET "https://localhost:5443/api/v1/auth" \
      -H "Authorization: Bearer $ACCESS_TOKEN")
    ADMIN_KEY=$(echo "$USER_INFO" | jq -r '.wallets[0].adminkey')
    
    # Install lnurlp extension
    curl -k -s -X POST https://localhost:5443/api/v1/extension \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"ext_id": "lnurlp", "archive": "https://github.com/lnbits/lnurlp/archive/refs/tags/v1.0.1.zip", "source_repo": "https://raw.githubusercontent.com/lnbits/lnbits-extensions/main/extensions.json", "version": "1.0.1"}'
    
    # Activate and enable
    curl -k -s -X PUT "https://localhost:5443/api/v1/extension/lnurlp/activate" -H "Authorization: Bearer $ACCESS_TOKEN"
    curl -k -s -X PUT "https://localhost:5443/api/v1/extension/lnurlp/enable" -H "Authorization: Bearer $ACCESS_TOKEN"
    
    # Test by creating LNURL-P link
    PAY_LINK=$(curl -k -s -X POST "https://localhost:5443/lnurlp/api/v1/links" \
      -H "X-API-KEY: $ADMIN_KEY" \
      -H "Content-Type: application/json" \
      -d '{"description": "Test Link", "min": 1000, "max": 10000}')
    
    if echo "$PAY_LINK" | jq -e '.id'; then
      echo "✅ LNURL-P extension fully working!"
    else  
      echo "❌ Extension installation failed"
      exit 1
    fi
```

## Files That Actually Work 📁

### FINAL-PROVEN-WORKING-SCRIPT.sh
The definitive script that proves extension installation works with correct auth.

### COMPLETE-WITH-HTTPS-LNURLP.sh  
Shows the complete HTTPS + domain spoofing setup for LNURL-P.

### nginx-lnbits.conf
The nginx config that fakes public domains for LNURL validation.

## Key Takeaways 💡

1. **Read the HAR files carefully** - they contain the exact working API sequences
2. **Authentication matters more than anything** - wrong auth = broken routes
3. **LNbits v1.2.1 works perfectly** when you use the right auth methods  
4. **LNURL-P needs HTTPS + public domains** but nginx can fake both
5. **No restarts needed** - routes register immediately with correct auth
6. **Bearer tokens ≠ Admin keys** - use the right one for each API type

## The Final Test Results ✅

**Extension Installation:** ✅ WORKING  
**Route Registration:** ✅ WORKING  
**LNURL-P Creation:** ✅ WORKING  
**HTTPS Delivery:** ✅ WORKING  
**QR Code Generation:** ✅ WORKING  
**Public Domain Validation:** ✅ BYPASSED  

---

## In Conclusion

After thinking this was a complex LNbits version bug, route registration issue, or HTTPS configuration problem, **the solution was embarrassingly simple**: 

**USE THE RIGHT AUTHENTICATION METHOD FOR EACH API** 

Bearer tokens for extension management, admin keys for wallet operations. That's it. That's the whole secret.

*Sometimes the simplest solutions hide behind the most complex debugging journeys.* 🤦‍♂️

---

*Written after many hours of debugging, several false leads, and one very helpful HAR file analysis. May this save future developers from the same authentication confusion!*

**Date:** August 31, 2025  
**LNbits Version:** 1.2.1  
**Extensions Tested:** lnurlp 1.0.1, withdraw 1.0.1  
**Result:** HOLY SHIT FINALLY IT WORKS! 🎉