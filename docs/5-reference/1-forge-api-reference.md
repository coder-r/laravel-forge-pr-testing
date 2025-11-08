# Laravel Forge API Reference

**Quick lookup reference for PR testing automation**

Base URL: `https://forge.laravel.com`

All requests require authentication via Bearer token in the `Authorization` header.

---

## Authentication

```bash
Authorization: Bearer YOUR_FORGE_API_TOKEN
Accept: application/json
Content-Type: application/json
```

**Rate Limiting**: 60 requests per minute per token

---

## 1. Site Management

### Create Site

**Endpoint**: `POST /api/v1/servers/{serverId}/sites`

**Request Parameters**:
```json
{
  "domain": "pr-123.testing.example.com",
  "project_type": "php",
  "directory": "/public",
  "isolated": false,
  "username": "forge",
  "php_version": "php82"
}
```

**Parameter Details**:
- `domain` (required): Site domain name
- `project_type` (required): `php`, `html`, `symfony`, `symfony_dev`
- `directory` (optional): Web directory (default: `/public`)
- `isolated` (optional): Isolate site user (default: `false`)
- `username` (optional): System user (default: `forge`)
- `php_version` (optional): `php81`, `php82`, `php83`

**Response** (201 Created):
```json
{
  "site": {
    "id": 12345,
    "server_id": 67890,
    "name": "pr-123.testing.example.com",
    "directory": "/public",
    "wildcards": false,
    "status": "installing",
    "repository": null,
    "repository_provider": null,
    "repository_branch": null,
    "repository_status": null,
    "quick_deploy": false,
    "project_type": "php",
    "app": null,
    "app_status": null,
    "slack_channel": null,
    "telegram_chat_id": null,
    "telegram_chat_title": null,
    "teams_webhook_url": null,
    "discord_webhook_url": null,
    "created_at": "2025-01-07 12:00:00",
    "deployment_url": null,
    "tags": []
  }
}
```

**cURL Example**:
```bash
curl -X POST https://forge.laravel.com/api/v1/servers/67890/sites \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "pr-123.testing.example.com",
    "project_type": "php",
    "directory": "/public",
    "php_version": "php82"
  }'
```

**Common Errors**:
- `422 Unprocessable Entity`: Invalid parameters or domain already exists
- `404 Not Found`: Server ID not found
- `429 Too Many Requests`: Rate limit exceeded

---

### Get Site Details

**Endpoint**: `GET /api/v1/servers/{serverId}/sites/{siteId}`

**Response** (200 OK):
```json
{
  "site": {
    "id": 12345,
    "server_id": 67890,
    "name": "pr-123.testing.example.com",
    "directory": "/public",
    "status": "installed",
    "repository": "owner/repo",
    "repository_provider": "github",
    "repository_branch": "pr-123",
    "repository_status": "installed",
    "quick_deploy": true,
    "project_type": "php",
    "php_version": "php82",
    "app": "laravel",
    "app_status": "installed",
    "deployment_status": null,
    "is_secured": true,
    "created_at": "2025-01-07 12:00:00"
  }
}
```

**cURL Example**:
```bash
curl https://forge.laravel.com/api/v1/servers/67890/sites/12345 \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json"
```

**Common Errors**:
- `404 Not Found`: Server or site not found

---

### Delete Site

**Endpoint**: `DELETE /api/v1/servers/{serverId}/sites/{siteId}`

**Response** (204 No Content): Empty response body

**cURL Example**:
```bash
curl -X DELETE https://forge.laravel.com/api/v1/servers/67890/sites/12345 \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json"
```

**Common Errors**:
- `404 Not Found`: Server or site not found

---

## 2. Database Management

### Create Database

**Endpoint**: `POST /api/v1/servers/{serverId}/databases`

**Request Parameters**:
```json
{
  "name": "pr_123_testing",
  "user": "pr_123_user",
  "password": "secure_random_password_here"
}
```

**Parameter Details**:
- `name` (required): Database name (alphanumeric, underscores, max 64 chars)
- `user` (optional): Database user (created if provided)
- `password` (optional): User password (required if `user` provided, min 12 chars)

**Response** (201 Created):
```json
{
  "database": {
    "id": 54321,
    "name": "pr_123_testing",
    "status": "installed",
    "created_at": "2025-01-07 12:05:00"
  }
}
```

**cURL Example**:
```bash
curl -X POST https://forge.laravel.com/api/v1/servers/67890/databases \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "pr_123_testing",
    "user": "pr_123_user",
    "password": "secure_random_password_here"
  }'
```

**Common Errors**:
- `422 Unprocessable Entity`: Invalid database name or password too short
- `404 Not Found`: Server not found

---

### Delete Database

**Endpoint**: `DELETE /api/v1/servers/{serverId}/databases/{databaseId}`

**Response** (204 No Content): Empty response body

**cURL Example**:
```bash
curl -X DELETE https://forge.laravel.com/api/v1/servers/67890/databases/54321 \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json"
```

**Common Errors**:
- `404 Not Found`: Server or database not found

---

## 3. Environment Variables

### Update .env File

**Endpoint**: `PUT /api/v1/servers/{serverId}/sites/{siteId}/env`

**Request Parameters**:
```json
{
  "content": "APP_NAME=\"PR Testing\"\nAPP_ENV=testing\nAPP_KEY=base64:...\nAPP_DEBUG=true\nAPP_URL=https://pr-123.testing.example.com\n\nDB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=3306\nDB_DATABASE=pr_123_testing\nDB_USERNAME=pr_123_user\nDB_PASSWORD=secure_password\n\nCACHE_DRIVER=redis\nQUEUE_CONNECTION=redis\nSESSION_DRIVER=redis\n\nREDIS_HOST=127.0.0.1\nREDIS_PASSWORD=null\nREDIS_PORT=6379"
}
```

**Parameter Details**:
- `content` (required): Full .env file content as string (use `\n` for newlines)

**Response** (200 OK):
```json
{
  "message": "Environment file updated."
}
```

**cURL Example**:
```bash
curl -X PUT https://forge.laravel.com/api/v1/servers/67890/sites/12345/env \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "APP_NAME=\"PR Testing\"\nAPP_ENV=testing\nAPP_URL=https://pr-123.testing.example.com"
  }'
```

**Common Errors**:
- `422 Unprocessable Entity`: Invalid content format
- `404 Not Found`: Server or site not found

**Notes**:
- Replaces entire .env file content
- Use proper escaping for special characters
- Restart services after updating environment variables

---

## 4. Git Integration

### Connect Repository

**Endpoint**: `POST /api/v1/servers/{serverId}/sites/{siteId}/git`

**Request Parameters**:
```json
{
  "provider": "github",
  "repository": "owner/repository-name",
  "branch": "pr-123",
  "composer": true
}
```

**Parameter Details**:
- `provider` (required): `github`, `gitlab`, `bitbucket`, `bitbucket-v2`, `custom`
- `repository` (required): Repository identifier (format depends on provider)
- `branch` (optional): Branch name (default: `master`)
- `composer` (optional): Install Composer dependencies (default: `true`)

**Response** (200 OK):
```json
{
  "site": {
    "id": 12345,
    "repository": "owner/repository-name",
    "repository_provider": "github",
    "repository_branch": "pr-123",
    "repository_status": "installing",
    "quick_deploy": false
  }
}
```

**cURL Example**:
```bash
curl -X POST https://forge.laravel.com/api/v1/servers/67890/sites/12345/git \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "github",
    "repository": "owner/repository-name",
    "branch": "pr-123",
    "composer": true
  }'
```

**Common Errors**:
- `422 Unprocessable Entity`: Invalid provider or repository format
- `404 Not Found`: Server or site not found
- `403 Forbidden`: No access to repository (check GitHub integration)

**Notes**:
- Requires GitHub/GitLab/Bitbucket integration configured in Forge
- Repository must be accessible to the connected account

---

## 5. Deployment

### Trigger Deployment

**Endpoint**: `POST /api/v1/servers/{serverId}/sites/{siteId}/deployment/deploy`

**Request Parameters**: None (empty body or `{}`)

**Response** (200 OK):
```json
{
  "message": "Deployment started."
}
```

**cURL Example**:
```bash
curl -X POST https://forge.laravel.com/api/v1/servers/67890/sites/12345/deployment/deploy \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Common Errors**:
- `422 Unprocessable Entity`: Deployment already in progress
- `404 Not Found`: Server or site not found
- `403 Forbidden`: Repository not connected

**Notes**:
- Runs the deployment script configured for the site
- Cannot trigger new deployment while one is in progress
- Use deployment log endpoint to monitor progress

---

### Get Deployment Log

**Endpoint**: `GET /api/v1/servers/{serverId}/sites/{siteId}/deployment/log`

**Response** (200 OK):
```json
{
  "output": "$ cd /home/forge/pr-123.testing.example.com\n$ git pull origin pr-123\nAlready up to date.\n$ composer install --no-interaction --prefer-dist --optimize-autoloader\nInstalling dependencies from lock file\nPackage operations: 0 installs, 0 updates, 0 removals\nGenerating optimized autoload files\n$ php artisan migrate --force\nMigration table created successfully.\nMigrating: 2014_10_12_000000_create_users_table\nMigrated:  2014_10_12_000000_create_users_table (45.23ms)\n$ php artisan config:cache\nConfiguration cache cleared!\nConfiguration cached successfully!\n$ php artisan route:cache\nRoute cache cleared!\nRoutes cached successfully!\n$ php artisan view:cache\nCompiled views cleared!\nBlade templates cached successfully!\n",
  "status": "finished"
}
```

**cURL Example**:
```bash
curl https://forge.laravel.com/api/v1/servers/67890/sites/12345/deployment/log \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json"
```

**Common Errors**:
- `404 Not Found`: Server, site not found, or no deployment log available

**Notes**:
- Returns the most recent deployment log
- `status` values: `running`, `finished`, `failed`
- Poll this endpoint to monitor deployment progress

---

## 6. SSL Certificates

### Create Let's Encrypt Certificate

**Endpoint**: `POST /api/v1/servers/{serverId}/sites/{siteId}/certificates/letsencrypt`

**Request Parameters**:
```json
{
  "domains": ["pr-123.testing.example.com"]
}
```

**Parameter Details**:
- `domains` (required): Array of domain names (must point to server)

**Response** (201 Created):
```json
{
  "certificate": {
    "id": 98765,
    "domain": "pr-123.testing.example.com",
    "request_status": "creating",
    "status": null,
    "type": "letsencrypt",
    "created_at": "2025-01-07 12:30:00",
    "existing": false
  }
}
```

**cURL Example**:
```bash
curl -X POST https://forge.laravel.com/api/v1/servers/67890/sites/12345/certificates/letsencrypt \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "domains": ["pr-123.testing.example.com"]
  }'
```

**Common Errors**:
- `422 Unprocessable Entity`: Domain doesn't point to server or certificate already exists
- `404 Not Found`: Server or site not found
- `429 Too Many Requests`: Rate limit from Let's Encrypt (5 certificates per domain per week)

**Notes**:
- Domain must have DNS pointing to server IP
- Let's Encrypt rate limits apply
- Certificate creation takes 1-3 minutes
- Poll site details to check `is_secured` status

---

## 7. Queue Workers

### Create Queue Worker

**Endpoint**: `POST /api/v1/servers/{serverId}/sites/{siteId}/workers`

**Request Parameters**:
```json
{
  "connection": "redis",
  "timeout": 60,
  "sleep": 3,
  "tries": 3,
  "processes": 1,
  "stopwaitsecs": 600,
  "daemon": true,
  "force": false,
  "php_version": "php82"
}
```

**Parameter Details**:
- `connection` (required): Queue connection name from config/queue.php
- `timeout` (optional): Job timeout in seconds (default: `60`)
- `sleep` (optional): Sleep seconds when no jobs (default: `3`)
- `tries` (optional): Max attempts per job (default: `3`)
- `processes` (optional): Number of worker processes (default: `1`)
- `stopwaitsecs` (optional): Seconds to wait before force kill (default: `600`)
- `daemon` (optional): Run as daemon (default: `true`)
- `force` (optional): Force run in maintenance mode (default: `false`)
- `php_version` (optional): PHP version (default: site's PHP version)

**Response** (201 Created):
```json
{
  "worker": {
    "id": 11111,
    "connection": "redis",
    "timeout": 60,
    "sleep": 3,
    "tries": 3,
    "processes": 1,
    "stopwaitsecs": 600,
    "daemon": true,
    "php_version": "php82",
    "status": "installing",
    "created_at": "2025-01-07 12:45:00"
  }
}
```

**cURL Example**:
```bash
curl -X POST https://forge.laravel.com/api/v1/servers/67890/sites/12345/workers \
  -H "Authorization: Bearer YOUR_FORGE_API_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "connection": "redis",
    "timeout": 60,
    "tries": 3,
    "processes": 1
  }'
```

**Common Errors**:
- `422 Unprocessable Entity`: Invalid parameters or connection name
- `404 Not Found`: Server or site not found

**Notes**:
- Creates Supervisor configuration for queue worker
- Worker automatically restarts on failure
- Uses `php artisan queue:work` command
- Monitor worker status via Forge dashboard

---

## Common Response Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 200 | OK | Request successful |
| 201 | Created | Resource created successfully |
| 204 | No Content | Deletion successful (no response body) |
| 400 | Bad Request | Invalid request format |
| 401 | Unauthorized | Invalid or missing API token |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource not found |
| 422 | Unprocessable Entity | Validation failed |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Server Error | Forge internal error |

---

## Rate Limiting

**Limit**: 60 requests per minute per API token

**Headers** (included in all responses):
```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
```

**When rate limited** (429 response):
```json
{
  "message": "Too Many Attempts."
}
```

**Best Practices**:
- Monitor `X-RateLimit-Remaining` header
- Implement exponential backoff for retries
- Use polling intervals >= 5 seconds
- Batch operations where possible

---

## Polling Best Practices

Many operations are asynchronous. Poll status endpoints to check completion:

**Site Installation**:
```bash
# Poll until status = "installed"
GET /api/v1/servers/{serverId}/sites/{siteId}
# Check: site.status === "installed"
```

**Repository Connection**:
```bash
# Poll until repository_status = "installed"
GET /api/v1/servers/{serverId}/sites/{siteId}
# Check: site.repository_status === "installed"
```

**Deployment**:
```bash
# Poll deployment log until status != "running"
GET /api/v1/servers/{serverId}/sites/{siteId}/deployment/log
# Check: status === "finished" or "failed"
```

**SSL Certificate**:
```bash
# Poll until is_secured = true
GET /api/v1/servers/{serverId}/sites/{siteId}
# Check: site.is_secured === true
```

**Recommended Polling Interval**: 5-10 seconds

---

## Error Handling Example

```bash
#!/bin/bash

response=$(curl -s -w "\n%{http_code}" \
  https://forge.laravel.com/api/v1/servers/67890/sites/12345 \
  -H "Authorization: Bearer $FORGE_API_TOKEN" \
  -H "Accept: application/json")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

case $http_code in
  200|201)
    echo "Success: $body"
    ;;
  404)
    echo "Error: Resource not found"
    exit 1
    ;;
  422)
    echo "Error: Validation failed - $body"
    exit 1
    ;;
  429)
    echo "Error: Rate limit exceeded. Waiting 60 seconds..."
    sleep 60
    # Retry logic here
    ;;
  *)
    echo "Error: HTTP $http_code - $body"
    exit 1
    ;;
esac
```

---

## Additional Resources

- **Official Documentation**: https://forge.laravel.com/api-documentation
- **Forge Dashboard**: https://forge.laravel.com
- **Support**: https://forge.laravel.com/support

---

## Quick Reference Commands

```bash
# List all sites on server
curl https://forge.laravel.com/api/v1/servers/67890/sites \
  -H "Authorization: Bearer $FORGE_API_TOKEN" \
  -H "Accept: application/json"

# List all databases on server
curl https://forge.laravel.com/api/v1/servers/67890/databases \
  -H "Authorization: Bearer $FORGE_API_TOKEN" \
  -H "Accept: application/json"

# Get site deployment script
curl https://forge.laravel.com/api/v1/servers/67890/sites/12345/deployment/script \
  -H "Authorization: Bearer $FORGE_API_TOKEN" \
  -H "Accept: application/json"

# Update deployment script
curl -X PUT https://forge.laravel.com/api/v1/servers/67890/sites/12345/deployment/script \
  -H "Authorization: Bearer $FORGE_API_TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{"content": "cd $FORGE_SITE\ngit pull origin $FORGE_SITE_BRANCH\n..."}'
```

---

**Last Updated**: 2025-01-07
