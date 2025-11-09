# Forge API Endpoint Fixes - orchestrate-pr-system.sh

## Summary
Fixed all Forge API v1 endpoint mismatches in `/home/dev/project-analysis/laravel-forge-pr-testing/scripts/orchestrate-pr-system.sh` to match the official Laravel Forge API v1 specification.

## Fixes Applied

### 1. Git Installation Endpoint (Line 584)
**Issue**: Used incorrect endpoint for installing Git repository

**BEFORE**:
```bash
POST /servers/$SERVER_ID/git-projects
```

**AFTER**:
```bash
POST /servers/$SERVER_ID/sites/$SITE_ID/git
```

**Payload** (unchanged):
```json
{
    "provider": "github",
    "repository": "$GITHUB_REPOSITORY",
    "branch": "$GITHUB_BRANCH"
}
```

---

### 2. Environment Variables Endpoint (Line 622)
**Issue**: Used wrong HTTP method (POST instead of PUT) and wrong payload format (JSON map instead of string content)

**BEFORE**:
```bash
POST /servers/$SERVER_ID/sites/$SITE_ID/env

Payload:
{
    "variables": {
        "APP_ENV": "testing",
        "APP_DEBUG": "true",
        ...
    }
}
```

**AFTER**:
```bash
PUT /servers/$SERVER_ID/sites/$SITE_ID/env

Payload:
{
    "content": "APP_ENV=testing\nAPP_DEBUG=true\nCACHE_DRIVER=array\n..."
}
```

**Key Changes**:
- Changed from `POST` to `PUT`
- Changed from JSON map of variables to `.env` file content as string
- Content must be escaped as JSON string using `jq -Rs`

---

### 3. Queue Workers Endpoint (Line 649)
**Issue**: Missing site_id in endpoint path

**BEFORE**:
```bash
POST /servers/$SERVER_ID/workers
```

**AFTER**:
```bash
POST /servers/$SERVER_ID/sites/$SITE_ID/workers
```

**Payload** (unchanged):
```json
{
    "connection": "database",
    "queue": "default",
    "timeout": 60,
    "sleep": 3,
    "processes": 1,
    "daemon": false
}
```

---

### 4. SSL Certificates Endpoint (Line 673)
**Issue**: Used generic SSL endpoint instead of Let's Encrypt specific endpoint

**BEFORE**:
```bash
POST /servers/$SERVER_ID/ssl-certificates

Payload:
{
    "domain": "$domain",
    "certificate": "letsencrypt"
}
```

**AFTER**:
```bash
POST /servers/$SERVER_ID/sites/$SITE_ID/certificates/letsencrypt

Payload:
{
    "domains": ["$domain"]
}
```

**Key Changes**:
- Added site_id to endpoint path
- Changed to `/certificates/letsencrypt` specific endpoint
- Changed payload from single `domain` to `domains` array
- Removed `certificate` field (implicit in endpoint)

---

### 5. Deployment Trigger Endpoint (Line 692)
**Issue**: Sent repository/branch in deployment payload (should be pre-configured)

**BEFORE**:
```bash
POST /servers/$SERVER_ID/sites/$SITE_ID/deployment/deploy

Payload:
{
    "repository": "$GITHUB_REPOSITORY",
    "branch": "$GITHUB_BRANCH"
}
```

**AFTER**:
```bash
POST /servers/$SERVER_ID/sites/$SITE_ID/deployment/deploy

Payload: (empty string or no payload)
```

**Key Changes**:
- Removed repository and branch from payload
- Git repository must be configured first via Step 8 (install_git_repository)
- Deployment endpoint just triggers deployment of already-configured repo

---

## Verification

All endpoints now match the correct Forge API v1 specification as documented in:
- Laravel Forge API Documentation: https://forge.laravel.com/api/v1
- Reference implementation: `.github/workflows/pr-testing.yml`
- API library: `scripts/lib/forge-api.sh`

## Testing Recommendations

1. **Test git installation**:
   ```bash
   curl -X POST "https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID/git" \
     -H "Authorization: Bearer $TOKEN" \
     -d '{"provider":"github","repository":"owner/repo","branch":"main"}'
   ```

2. **Test environment update**:
   ```bash
   curl -X PUT "https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID/env" \
     -H "Authorization: Bearer $TOKEN" \
     -d '{"content":"APP_ENV=testing\nAPP_DEBUG=true"}'
   ```

3. **Test worker creation**:
   ```bash
   curl -X POST "https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID/workers" \
     -H "Authorization: Bearer $TOKEN" \
     -d '{"connection":"database","queue":"default","processes":1}'
   ```

4. **Test SSL certificate**:
   ```bash
   curl -X POST "https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID/certificates/letsencrypt" \
     -H "Authorization: Bearer $TOKEN" \
     -d '{"domains":["example.com"]}'
   ```

5. **Test deployment trigger**:
   ```bash
   curl -X POST "https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID/deployment/deploy" \
     -H "Authorization: Bearer $TOKEN"
   ```

## Impact Analysis

### Fixed Issues
✅ Git repository installation will now work correctly
✅ Environment variables will be updated as .env file content
✅ Queue workers will be created under the correct site
✅ SSL certificates will use Let's Encrypt specific endpoint
✅ Deployments will trigger without sending redundant repository info

### No Breaking Changes
- All other API calls remain unchanged
- Error handling and retry logic still intact
- Logging and state management unaffected
- Rollback mechanisms still functional

## Related Files

Files that were **correctly** using these endpoints:
- `.github/workflows/pr-testing.yml` (reference implementation)
- `scripts/lib/forge-api.sh` (API library functions)

Files that needed fixes:
- `scripts/orchestrate-pr-system.sh` (fixed all 5 endpoints)

---

**Date**: 2025-11-09
**Fixed By**: Code Quality Analyzer
**Files Modified**: 1
**Lines Changed**: ~50
**Critical Fixes**: 5
