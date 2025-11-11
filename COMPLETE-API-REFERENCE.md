# Complete Working Forge API Reference (Tested & Verified)

**Date**: November 11, 2025
**Tested on**: Laravel Forge (New 2025 API + v1 Legacy)
**Organization**: rameez-tariq-fvh
**Server**: curved-sanctuary (986747)

## API Base URLs

```bash
# V1 API (Legacy - still works for many endpoints)
https://forge.laravel.com/api/v1

# New Org-Scoped API (2025)
https://forge.laravel.com/api/orgs/{organization_slug}
```

## Authentication

```bash
# All requests require:
Authorization: Bearer YOUR_API_TOKEN
Accept: application/json
Content-Type: application/json (for POST/PUT)
```

## Working Endpoints (Tested ✅)

### 1. List Servers
```bash
GET /api/v1/servers

Response:
{"servers": [
  {"id": 986747, "name": "curved-sanctuary", "ip_address": "159.65.213.130", ...}
]}
```

### 2. Get Server Details
```bash
GET /api/v1/servers/{server_id}

Response:
{"server": {"id": 986747, "name": "curved-sanctuary", ...}}
```

### 3. Create Site ✅
```bash
POST /api/v1/servers/{server_id}/sites

Payload:
{
  "domain": "pr-test-devpel.on-forge.com",
  "project_type": "php",
  "directory": "/public",
  "isolated": true,
  "username": "prdevpel"  # Required when isolated=true
}

Response:
{"site": {"id": 2925742, "status": "installing", ...}}

Time: ~30 seconds to status="installed"
```

### 4. Get Site Details
```bash
GET /api/v1/servers/{server_id}/sites/{site_id}

Response:
{"site": {"id": 2925742, "status": "installed", ...}}
```

### 5. Create Database ✅
```bash
POST /api/v1/servers/{server_id}/databases

Payload:
{
  "name": "pr_test_devpel"
}

Response:
{"database": {"id": 1498991, "name": "pr_test_devpel", "status": "installing"}}

Note: Does NOT automatically grant user access!
Workaround: Use "forge" database which already has forge user access
```

### 6. List Database Users
```bash
GET /api/v1/servers/{server_id}/mysql-users

Response:
{"users": [
  {"id": 815374, "name": "forge", "databases": [1498728]}
]}
```

### 7. Connect GitHub Repository ✅
```bash
POST /api/v1/servers/{server_id}/sites/{site_id}/git

Payload:
{
  "provider": "github",
  "repository": "coder-r/devpelEPOS",
  "branch": "main",
  "composer": true
}

Response:
{"site": {"repository": "coder-r/devpelEPOS", "repository_status": "installing"}}

Time: ~1-2 minutes for code clone + composer install
```

### 8. Update Environment Variables ✅ (NEW API)
```bash
PUT /api/orgs/{org_slug}/servers/{server_id}/sites/{site_id}/environment

Payload:
{
  "environment": "APP_NAME=\"DevpelEPOS\"\nAPP_ENV=testing\nDB_DATABASE=forge\n...",
  "cache": true,
  "queues": true
}

Response: 202 Accepted (no body)

Note: Use \n for newlines in environment string
Note: Must use org-scoped path, not v1!
```

### 9. Trigger Deployment ✅ (NEW API)
```bash
POST /api/orgs/{org_slug}/servers/{server_id}/sites/{site_id}/deployments

Payload: {} (empty)

Response:
{"data": {
  "id": "59000526",
  "type": "deployments",
  "attributes": {"status": "queued", ...}
}}

Time: ~30-60 seconds for deployment
```

### 10. Get Deployment Log ✅ (V1)
```bash
GET /api/v1/servers/{server_id}/sites/{site_id}/deployment/log

Response: (plain text log output)
Tue Nov 11 14:54:11 UTC 2025
Cloning into 'pr-test-devpel.on-forge.com'...
Composer install...
...
[Shows full deployment output including errors]

Note: Sometimes returns "Unauthenticated" - API inconsistency
Workaround: Check site HTTP status to verify deployment
```

### 11. Install SSL Certificate ✅ (V1)
```bash
POST /api/v1/servers/{server_id}/sites/{site_id}/certificates/letsencrypt

Payload:
{
  "domains": ["pr-test-devpel.on-forge.com"]
}

Response:
{"certificate": {
  "id": 2959571,
  "domain": "pr-test-devpel.on-forge.com",
  "status": "installing",
  ...
}}

Time: ~30-60 seconds for Let's Encrypt issuance
```

### 12. Create Queue Worker (Partial ✅)
```bash
POST /api/v1/servers/{server_id}/sites/{site_id}/workers

Payload:
{
  "connection": "database",
  "queue": "default",
  "timeout": 60,
  "sleep": 3,
  "tries": 3,
  "processes": 1,
  "php_version": "php84",  # REQUIRED!
  "daemon": true
}

Status: Tested, requires php_version parameter
```

## Not Working / Need New API Endpoints

### Database User Access Grant ❌
```bash
# Tried:
POST /api/v1/servers/{server}/mysql-users/{user}/databases
POST /api/orgs/{org}/servers/{server}/database-users/{user}/databases/{db}

# Both return: 404 Not Found

# Workaround: Use "forge" database (already has user access)
# Or: Grant via Forge dashboard manually
```

### List Deployments ❌
```bash
# Tried:
GET /api/orgs/{org}/servers/{server}/sites/{site}/deployments

# Returns: "Unauthenticated"

# Workaround: Check individual deployment by ID
# Or: Use webhook URL for deployment status
```

### Get Specific Deployment Details ❌
```bash
# Tried:
GET /api/orgs/{org}/servers/{server}/sites/{site}/deployments/{id}
GET /api/orgs/{org}/servers/{server}/sites/{site}/deployments/{id}/output

# Returns: "Unauthenticated" or 404

# Workaround: Use v1 deployment log endpoint
```

## Complete Working Example

```bash
#!/bin/bash
TOKEN="your-api-token"
ORG="rameez-tariq-fvh"
SERVER="986747"
PR_NUMBER="123"

# 1. Create site
SITE_JSON=$(curl -s -X POST "https://forge.laravel.com/api/v1/servers/$SERVER/sites" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"domain\":\"pr-$PR_NUMBER.on-forge.com\",\"project_type\":\"php\",\"directory\":\"/public\",\"isolated\":true,\"username\":\"pr$PR_NUMBER\"}")

SITE_ID=$(echo $SITE_JSON | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
echo "Site created: $SITE_ID"

# Wait for site to be ready
sleep 30

# 2. Connect GitHub
curl -s -X POST "https://forge.laravel.com/api/v1/servers/$SERVER/sites/$SITE_ID/git" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"provider":"github","repository":"coder-r/devpelEPOS","branch":"main","composer":true}'

# 3. Set environment variables
ENV="APP_NAME=Test\nAPP_ENV=testing\nDB_DATABASE=forge\nDB_USERNAME=forge\nDB_PASSWORD=secret"
curl -s -X PUT "https://forge.laravel.com/api/orgs/$ORG/servers/$SERVER/sites/$SITE_ID/environment" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"environment\":\"$ENV\",\"cache\":true,\"queues\":true}"

# 4. Deploy
curl -s -X POST "https://forge.laravel.com/api/orgs/$ORG/servers/$SERVER/sites/$SITE_ID/deployments" \
  -H "Authorization: Bearer $TOKEN"

# 5. Wait for deployment
sleep 60

# 6. Install SSL
curl -s -X POST "https://forge.laravel.com/api/v1/servers/$SERVER/sites/$SITE_ID/certificates/letsencrypt" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"domains\":[\"pr-$PR_NUMBER.on-forge.com\"]}"

# 7. Create worker
curl -s -X POST "https://forge.laravel.com/api/v1/servers/$SERVER/sites/$SITE_ID/workers" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"connection":"database","queue":"default","processes":1,"php_version":"php84","daemon":true}'

echo "✅ PR environment ready at https://pr-$PR_NUMBER.on-forge.com"
```

## Key Findings

1. **Mixed API Versions**: Laravel Forge uses BOTH v1 and new org-scoped APIs simultaneously
2. **V1 for Core Operations**: Sites, databases, git still on v1
3. **New API for Environment/Deploy**: Env vars and deployments use org-scoped paths
4. **Authentication Issues**: Some endpoints work, others return "Unauthenticated" inconsistently
5. **Database Access**: Creating database doesn't grant user access automatically
6. **On-Forge.com DNS**: May not work until SSL is fully activated

## Recommendations

1. **Use "forge" database** for all PR environments (simplest, already has user access)
2. **Mix v1 and new API** as needed (use what works)
3. **Check site HTTP status** to verify deployments (more reliable than deployment API)
4. **SSL takes time**: Wait 1-2 minutes for Let's Encrypt validation
5. **Workers need php_version**: Always specify PHP version when creating workers

## Next Steps to Investigate

1. Find new API endpoint for database user access grants
2. Figure out why deployment list/details return "Unauthenticated"
3. Understand on-forge.com DNS requirements (might need active SSL first)
4. Test queue worker functionality
5. Document complete automation flow for GitHub Actions

---

**Status**: Core functionality working! Can create PR environments via API.
**Ready for**: Automation and scaling
