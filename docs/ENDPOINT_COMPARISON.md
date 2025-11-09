# Forge API v1 Endpoint Comparison

## Quick Reference: Before vs After

| Operation | ❌ Incorrect Endpoint | ✅ Correct Endpoint | HTTP Method |
|-----------|---------------------|-------------------|-------------|
| **Git Installation** | `/servers/{id}/git-projects` | `/servers/{id}/sites/{site}/git` | POST |
| **Environment Variables** | `POST /servers/{id}/sites/{site}/env` | `PUT /servers/{id}/sites/{site}/env` | PUT |
| **Queue Workers** | `/servers/{id}/workers` | `/servers/{id}/sites/{site}/workers` | POST |
| **SSL Certificate** | `/servers/{id}/ssl-certificates` | `/servers/{id}/sites/{site}/certificates/letsencrypt` | POST |
| **Deploy Code** | With repo/branch payload | Empty payload (pre-configured) | POST |

---

## Detailed Endpoint Specifications

### 1. Git Repository Installation

**Endpoint**: `POST /servers/{server}/sites/{site}/git`

**Request Body**:
```json
{
    "provider": "github",
    "repository": "owner/repo",
    "branch": "main",
    "composer": false
}
```

**Response**:
```json
{
    "git": {
        "id": 1,
        "provider": "github",
        "repository": "owner/repo",
        "branch": "main",
        "status": "installing"
    }
}
```

**Common Errors**:
- `404`: Site not found
- `422`: Invalid repository or provider
- `409`: Git already configured

---

### 2. Environment Variables

**Endpoint**: `PUT /servers/{server}/sites/{site}/env`

**Request Body**:
```json
{
    "content": "APP_ENV=production\nAPP_DEBUG=false\nDB_DATABASE=myapp\n..."
}
```

**Important Notes**:
- Use `PUT`, not `POST`
- Content must be `.env` file format (KEY=VALUE)
- Newlines should be literal `\n` in JSON string
- Use `jq -Rs` to properly escape content

**Response**:
```json
{
    "env": {
        "id": 1,
        "status": "updated"
    }
}
```

---

### 3. Queue Workers

**Endpoint**: `POST /servers/{server}/sites/{site}/workers`

**Request Body**:
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

**Response**:
```json
{
    "worker": {
        "id": 1,
        "connection": "database",
        "queue": "default",
        "processes": 1,
        "status": "running"
    }
}
```

**Worker Options**:
- `connection`: "database", "redis", "sqs", "beanstalkd"
- `queue`: Queue name (default: "default")
- `processes`: Number of worker processes (1-10)
- `daemon`: Use daemon mode (true/false)

---

### 4. SSL Certificate (Let's Encrypt)

**Endpoint**: `POST /servers/{server}/sites/{site}/certificates/letsencrypt`

**Request Body**:
```json
{
    "domains": ["example.com", "www.example.com"]
}
```

**Response**:
```json
{
    "certificate": {
        "id": 1,
        "domains": ["example.com", "www.example.com"],
        "status": "installing",
        "type": "letsencrypt"
    }
}
```

**Other Certificate Types**:
- Let's Encrypt: `/certificates/letsencrypt` (automatic, free)
- Clone from existing: `/certificates/{cert}/clone`
- Custom certificate: `/certificates` (requires cert/key files)

---

### 5. Deployment

**Endpoint**: `POST /servers/{server}/sites/{site}/deployment/deploy`

**Request Body**: Empty or `{}` (no payload needed)

**Prerequisites**:
- Git repository must be configured first
- Deployment script should be set
- Site must be in "installed" status

**Response**:
```json
{
    "deployment": {
        "id": 123,
        "status": "running",
        "started_at": "2025-11-09T10:00:00Z"
    }
}
```

**Deployment Workflow**:
1. Configure git: `POST /servers/{id}/sites/{site}/git`
2. (Optional) Update deployment script: `PUT /servers/{id}/sites/{site}/deployment-script`
3. Trigger deployment: `POST /servers/{id}/sites/{site}/deployment/deploy`
4. Check status: `GET /servers/{id}/sites/{site}/deployments/{deployment}`

---

## API Response Codes

| Code | Meaning | Common Causes |
|------|---------|---------------|
| `200` | Success | Request completed successfully |
| `201` | Created | Resource created successfully |
| `204` | No Content | Successful deletion or update with no response body |
| `401` | Unauthorized | Invalid API token |
| `403` | Forbidden | Insufficient permissions |
| `404` | Not Found | Server, site, or resource doesn't exist |
| `409` | Conflict | Resource already exists or state conflict |
| `422` | Unprocessable Entity | Validation error (check response for details) |
| `429` | Too Many Requests | Rate limit exceeded (60 req/min) |
| `500` | Server Error | Internal Forge API error |

---

## Best Practices

### 1. Error Handling
```bash
response=$(api_request "POST" "/servers/$SERVER_ID/sites/$SITE_ID/git" "$payload")
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    log_error "Failed to install git repository"
    # Parse error response
    error_msg=$(echo "$response" | jq -r '.message // .error // empty')
    log_error "API Error: $error_msg"
    return 1
fi
```

### 2. Polling for Status
```bash
# Wait for site installation
while true; do
    status=$(curl -s -X GET "$FORGE_API_BASE_URL/servers/$SERVER_ID/sites/$SITE_ID" \
        -H "Authorization: Bearer $TOKEN" | jq -r '.site.status')

    if [[ "$status" == "installed" ]]; then
        break
    fi

    sleep 5
done
```

### 3. Rate Limiting
```bash
# Enforce 1 request per second (60/min limit)
LAST_REQUEST_TIME=0

make_request() {
    local now=$(date +%s)
    local elapsed=$((now - LAST_REQUEST_TIME))

    if [[ $elapsed -lt 1 ]]; then
        sleep $((1 - elapsed))
    fi

    # Make request
    curl ...

    LAST_REQUEST_TIME=$(date +%s)
}
```

### 4. Idempotency
```bash
# Check if resource exists before creating
existing=$(curl -s -X GET "$FORGE_API_BASE_URL/servers/$SERVER_ID/sites" \
    -H "Authorization: Bearer $TOKEN" | \
    jq -r ".sites[] | select(.name == \"$SITE_NAME\") | .id // empty")

if [[ -n "$existing" ]]; then
    echo "Site already exists: $existing"
    SITE_ID="$existing"
else
    # Create new site
    response=$(curl -s -X POST "$FORGE_API_BASE_URL/servers/$SERVER_ID/sites" ...)
    SITE_ID=$(echo "$response" | jq -r '.site.id')
fi
```

---

## Related Documentation

- **Official API Docs**: https://forge.laravel.com/api-documentation
- **API Version**: v1 (current)
- **Base URL**: https://forge.laravel.com/api/v1
- **Authentication**: Bearer token in Authorization header
- **Rate Limit**: 60 requests per minute per token

---

## Testing Endpoints

### Using curl:
```bash
# Set variables
export FORGE_TOKEN="your-token-here"
export SERVER_ID="12345"
export SITE_ID="67890"

# Test git installation
curl -X POST "https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID/git" \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "github",
    "repository": "owner/repo",
    "branch": "main"
  }'

# Test environment update
curl -X PUT "https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID/env" \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "APP_ENV=testing\nAPP_DEBUG=true"
  }'

# Test worker creation
curl -X POST "https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID/workers" \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "connection": "database",
    "queue": "default",
    "processes": 1
  }'

# Test SSL certificate
curl -X POST "https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID/certificates/letsencrypt" \
  -H "Authorization: Bearer $FORGE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domains": ["example.com"]
  }'

# Test deployment
curl -X POST "https://forge.laravel.com/api/v1/servers/$SERVER_ID/sites/$SITE_ID/deployment/deploy" \
  -H "Authorization: Bearer $FORGE_TOKEN"
```

---

**Last Updated**: 2025-11-09
**API Version**: v1
