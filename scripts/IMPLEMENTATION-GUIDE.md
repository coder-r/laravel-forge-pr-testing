# Implementation Guide - Laravel VPS Automation Scripts

Complete technical implementation guide for the VPS automation toolkit.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Forge API Layer                           │
│  https://forge.laravel.com/api/v1                          │
└────┬────────┬──────────┬────────────┬────────────┬──────────┘
     │        │          │            │            │
     ▼        ▼          ▼            ▼            ▼
┌─────────┐┌───────┐┌──────────┐┌──────────┐┌──────────┐
│ Create  ││Clone  ││ Setup    ││ Health   ││Cleanup  │
│   VPS   ││  DB   ││ Saturday ││ Check    ││Environment│
│        ││        ││  Peak    ││          ││         │
└─────────┘└───────┘└──────────┘└──────────┘└──────────┘
     │        │          │            │            │
     └─────────┴──────────┴────────────┴────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Logging & State     │
         │  Management          │
         │                      │
         │ logs/                │
         │ backups/             │
         │ state files          │
         └──────────────────────┘
```

## Core Components

### 1. API Communication Layer

All scripts use the same API request function:

```bash
api_request() {
    local method="$1"          # GET, POST, DELETE
    local endpoint="$2"         # /servers, /databases, etc
    local data="${3:-}"         # JSON payload (optional)
    local url="${FORGE_API_URL}${endpoint}"

    # Execute API call with proper headers
    curl -s -w "%{http_code}" \
        -X "$method" \
        -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$data" \
        -o "$response_file" \
        "$url"

    # Handle response and errors
}
```

**Key Features:**
- Bearer token authentication
- HTTP status validation
- JSON response handling
- Error logging
- Timeout support

### 2. State Management

Each script maintains operation state:

```bash
# State file format: key=value pairs
SERVER_ID="12345"
SERVER_NAME="production-app"
SNAPSHOT_ID="snap-abc123"
TIMESTAMP="2024-11-08T19:16:22Z"
```

**Purposes:**
- Resume interrupted operations
- Track operation progress
- Enable rollback
- Provide audit trail

### 3. Error Handling Pattern

All scripts follow consistent error handling:

```bash
# Requirement checks
if ! command -v curl &> /dev/null; then
    log_error "curl is required"
    return 1
fi

# API calls with error checking
if ! response=$(api_request "GET" "/servers"); then
    log_error "API request failed"
    return 1
fi

# Input validation
if [[ -z "$SERVER_ID" ]]; then
    log_error "Server ID is required"
    return 1
fi

# Graceful degradation
if response=$(api_request "GET" "/servers/$id/databases"); then
    # Process response
else
    log_warning "Could not fetch databases"
    # Continue with other checks
fi
```

### 4. Logging System

Comprehensive logging with multiple levels:

```bash
log "INFO" "Information message"      # INFO level
log_info "User-friendly info"         # Blue ℹ icon
log_success "Operation completed"     # Green ✓ icon
log_warning "Non-fatal issue"         # Yellow ⚠ icon
log_error "Fatal error"               # Red ✗ icon
```

**Log Format:**
```
[2024-11-08 19:16:22] [INFO] Operation started
[2024-11-08 19:16:23] [SUCCESS] Server created
[2024-11-08 19:16:24] [WARNING] Resource limitation detected
[2024-11-08 19:16:25] [ERROR] API request failed with status 403
```

**Locations:**
- `logs/vps-creation-20241108_191622.log`
- `logs/database-clone-20241108_191623.log`
- `logs/cleanup-20241108_191626.log`

## Script Breakdown

### create-vps-environment.sh

**Flow:**
```
1. Parse arguments & load config
2. Check requirements (curl, jq, token)
3. Validate parameters
4. Check if server already exists
5. Create VPS via API
6. Poll until provisioned
7. Configure firewall
8. Install SSL certificate
9. Create database
10. Generate summary
```

**API Calls:**
```
1. GET /servers              - List existing servers
2. POST /servers             - Create new server
3. GET /servers/{id}         - Poll server status
4. POST /firewall-rules      - Add rules
5. POST /ssl-certificates    - Create cert
6. POST /databases           - Create database
```

**State Tracking:**
- `VPS_NAME` - Server name
- `SERVER_ID` - API server ID
- `VPS_PROVIDER` - Cloud provider
- `VPS_REGION` - Deployment region
- `VPS_SIZE` - Server size

**Resumption:**
- If interrupted, run again with same arguments
- Script checks for existing server
- Skips already-completed steps
- Continues from last successful operation

### clone-database.sh

**Flow:**
```
1. Parse arguments
2. Check requirements
3. Get database ID from name
4. Create snapshot (if requested)
5. Create target database
6. Verify clone success
7. Generate summary
```

**API Calls:**
```
1. GET /servers/{id}/databases         - List databases
2. POST /databases/{id}/backups        - Create snapshot
3. POST /servers/{id}/databases        - Create DB
4. GET /databases/{id}/restore         - Restore backup
```

**Data Flow:**
```
Production Server          Target Server
     │                           │
     ├─ Database ──────┐         │
     │                 ▼         │
     │            Snapshot       │
     │                 │         │
     │                 ├─────────┼──> Target Database
     │                           │
     └─ Verify Clone ────────────┘
```

**Key Considerations:**
- Snapshot size affects time
- Network bandwidth usage
- Target server capacity
- Data consistency verification

### setup-saturday-peak.sh

**Flow:**
```
1. Parse arguments
2. Check DB connectivity
3. Create full backup
4. Discover timestamp tables
5. Build dynamic SQL updates
6. Execute timestamp shifts
7. Generate summary
```

**Timestamp Transformation:**
```
Original:  2024-10-15 14:30:45 (Monday, 2:30 PM)
Target:    2024-11-09 19:00:00 (Saturday, 7:00 PM peak)

Columns Updated:
  - created_at
  - updated_at
  - published_at
  - deleted_at
  - Any *_at column
```

**SQL Generation:**
```sql
UPDATE `users` SET
  `created_at` = DATE_ADD(
    STR_TO_DATE('2024-11-09', '%Y-%m-%d'),
    INTERVAL FLOOR(RAND() * 24) HOUR
  ),
  `updated_at` = DATE_ADD(
    STR_TO_DATE('2024-11-09', '%Y-%m-%d'),
    INTERVAL FLOOR(RAND() * 24) HOUR
  )
WHERE 1=1;
```

**Backup Location:**
- `backups/app_db-backup-20241108_191624.sql`
- Full mysqldump/pg_dump output
- Enables complete rollback
- Compressed option available

### health-check.sh

**Health Checks Performed:**
```
┌─ Server Status
├─ System Resources
├─ HTTP Connectivity
├─ Database Status
├─ SSL Certificates
├─ Firewall Rules
├─ Applications
├─ Backups
└─ Access Keys
```

**Status Hierarchy:**
```
OK       - Component functioning normally
WARNING  - Component has issues but operational
CRITICAL - Component non-functional
```

**Overall Status Logic:**
```
If ANY check is CRITICAL  → Overall = CRITICAL
Else if ANY check is WARNING → Overall = WARNING
Else                         → Overall = HEALTHY
```

**Output Formats:**

Text format:
```
Health Check Report
==================
Server: production-app
Status: HEALTHY

✓ Server_Status: OK
✓ HTTP_Connectivity: OK
⚠ SSL_Expiration: WARNING (expires in 14 days)
```

JSON format:
```json
{
  "server": {
    "id": "12345",
    "name": "production-app",
    "status": "HEALTHY"
  },
  "checks": {
    "Server_Status": {"status": "OK"},
    "HTTP_Connectivity": {"status": "OK"}
  }
}
```

### cleanup-environment.sh

**Safety Mechanisms:**
```
1. Create backups first
   ↓
2. Request confirmation (normal mode)
   ↓
3. Request 2nd confirmation for destructive ops
   ↓
4. Type "DELETE" for force mode
   ↓
5. Execute deletion
   ↓
6. Log all changes
```

**Deletion Order:**
```
1. Databases & Backups
   └─ Low impact, easily recreated

2. SSL Certificates
   └─ Can be regenerated

3. Firewall Rules
   └─ Can be recreated

4. VPS Server
   └─ Final step, permanent action
```

**Backup Contents:**
```json
{
  "backup_id": "backup-12345-20241108_191626",
  "timestamp": "2024-11-08T19:16:26Z",
  "components": [
    "databases.json",
    "sites.json",
    "firewall.json",
    "certificates.json"
  ],
  "location": "backups/"
}
```

## Integration Patterns

### Pattern 1: Bash Script Chain

```bash
#!/bin/bash
set -e  # Exit on error

# Load environment
source .env.forge

# Create VPS
echo "Creating VPS..."
./create-vps-environment.sh \
  --name "prod" \
  --provider "digitalocean" \
  --region "nyc3" \
  --size "s-2vcpu-4gb" || exit 1

# Extract server ID from logs
SERVER_ID=$(grep "Server ID:" logs/vps-creation-*.log | tail -1 | awk '{print $NF}')

# Health check
echo "Checking health..."
./health-check.sh --server-id $SERVER_ID || exit 1

echo "Setup complete!"
```

### Pattern 2: Error Recovery

```bash
#!/bin/bash

# Attempt operation with retry
MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if ./clone-database.sh \
    --source-server 111 \
    --target-server 222 \
    --target-database "stage"; then
    echo "Success!"
    exit 0
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "Retry $RETRY_COUNT of $MAX_RETRIES..."
  sleep 10
done

echo "Operation failed after $MAX_RETRIES retries"
exit 1
```

### Pattern 3: Monitoring Loop

```bash
#!/bin/bash

# Continuous health monitoring
INTERVAL=300  # 5 minutes

while true; do
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  ./health-check.sh --server-id 12345 --output json | \
    jq -r ".server.status" > /tmp/health.txt

  status=$(cat /tmp/health.txt)

  if [ "$status" != "HEALTHY" ]; then
    echo "[$timestamp] ALERT: Server unhealthy - $status"
    # Send alert (email, Slack, etc)
  fi

  sleep $INTERVAL
done
```

## API Reference

### Authentication

All requests require Bearer token:
```bash
Authorization: Bearer YOUR_FORGE_API_TOKEN
```

Get token from:
1. Forge Dashboard → Settings → API Token
2. Keep it secure (use environment variable)
3. Rotate regularly

### Rate Limiting

- Forge API: 30 requests per minute per token
- Scripts implement backoff via retry logic
- Health checks: OK to run frequently
- Creation/deletion: Single operations recommended

### Error Codes

```
200-299  ✓ Success
400      ✗ Bad Request (invalid parameters)
401      ✗ Unauthorized (invalid token)
403      ✗ Forbidden (insufficient permissions)
404      ✗ Not Found (resource doesn't exist)
429      ✗ Too Many Requests (rate limited)
500+     ✗ Server Error (Forge API issue)
```

## Database Support Matrix

| Database | Create | Clone | Peak Setup | Verify |
|----------|--------|-------|-----------|---------|
| MySQL    | ✓      | ✓     | ✓         | ✓       |
| PostgreSQL | ✓    | ✓     | ✓         | ✓       |
| MariaDB  | ✓      | ✓     | ✓         | ✓       |

**Connection Examples:**

MySQL:
```bash
mysql -h localhost -u root -p"password" database_name
```

PostgreSQL:
```bash
PGPASSWORD="password" psql -h localhost -U postgres -d database_name
```

## Performance Tuning

### VPS Creation Time
```
Basic provisioning:     5-10 min
Firewall config:        1-2 min
SSL provisioning:       2-5 min
Database creation:      1 min
───────────────────
Total:                  10-20 min
```

### Database Cloning Time
```
Snapshot creation:      1-5 min (size dependent)
Data transfer:          Variable (network dependent)
Verification:           1 min
───────────────────
Total:                  5-15 min (100MB-10GB typical)
```

### Timestamp Shifting
```
Backup creation:        1-3 min
Column discovery:       10-30 sec
SQL generation:         1-5 sec
Execution:              1-30 min (row count dependent)
───────────────────
Total:                  1-40 min
```

### Health Checks
```
Server status:          1 sec
Database check:         2 sec
SSL verification:       1 sec
HTTP test:              2 sec
Other checks:           1 sec
───────────────────
Total:                  2-3 sec (all checks)
```

## Troubleshooting Matrix

| Symptom | Cause | Fix |
|---------|-------|-----|
| "FORGE_API_TOKEN not set" | Missing env var | `export FORGE_API_TOKEN="..."` |
| API 401 Unauthorized | Invalid token | Get new token from Forge |
| API 403 Forbidden | Insufficient perms | Check token permissions |
| API 404 Not Found | Wrong server ID | Verify ID exists |
| Connection timeout | Network issue | Check connectivity, increase timeout |
| "curl: command not found" | Missing dependency | `sudo apt-get install curl` |
| "jq: command not found" | Missing dependency | `sudo apt-get install jq` |
| Database connection failed | Wrong credentials | Verify host, user, password |
| No timestamp columns found | Column naming | Check actual column names in DB |
| Script hangs | API timeout | Check Forge status, increase timeout |

## Testing Checklist

### Unit Tests
- [ ] API connectivity verified
- [ ] Token validation works
- [ ] Requirement checks pass
- [ ] Parameter validation works
- [ ] Error messages are helpful

### Integration Tests
- [ ] Create VPS successfully
- [ ] VPS becomes active
- [ ] Health checks pass
- [ ] Clone database works
- [ ] Peak setup executes
- [ ] Cleanup removes resources

### Deployment Tests
- [ ] Scripts run on target system
- [ ] Dependencies installed
- [ ] Permissions correct
- [ ] Logs generated properly
- [ ] Backups created

### Load Tests
- [ ] Peak timestamp setup works
- [ ] Database handles modified data
- [ ] Application works with new timestamps
- [ ] Health checks still pass
- [ ] Performance acceptable

## Documentation Structure

```
scripts/
├── README.md              ← Main documentation
├── QUICK-START.md         ← 5-min setup guide
├── INDEX.md              ← Complete reference
├── IMPLEMENTATION-GUIDE.md ← This file
└── *.sh                   ← Executable scripts
```

## Best Practices

1. **Always use environment files**
   ```bash
   source .env.forge
   ```

2. **Test with --dry-run first**
   ```bash
   ./setup-saturday-peak.sh --dry-run
   ```

3. **Monitor logs in separate terminal**
   ```bash
   tail -f logs/*.log
   ```

4. **Verify backups exist**
   ```bash
   ls -lah backups/
   ```

5. **Document custom modifications**
   ```bash
   # When modifying scripts, add comments explaining changes
   ```

6. **Rotate API tokens regularly**
   ```bash
   # Every 90 days, generate new token
   ```

7. **Test restore procedures**
   ```bash
   # Regularly verify backups can be restored
   ```

8. **Schedule health checks**
   ```bash
   # Add to crontab for regular monitoring
   ```

## Conclusion

This implementation guide provides the technical foundation for understanding and maintaining the VPS automation toolkit. All scripts follow consistent patterns for reliability, error handling, and logging.

For questions or issues, refer to the comprehensive README.md or specific script help:
```bash
./create-vps-environment.sh --help
./clone-database.sh --help
./setup-saturday-peak.sh --help
./health-check.sh --help
./cleanup-environment.sh --help
```
