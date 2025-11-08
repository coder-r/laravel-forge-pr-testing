# Laravel VPS Automation Scripts

Complete automation toolkit for managing Laravel VPS environments via Laravel Forge API.

## Overview

This collection of bash scripts provides comprehensive automation for:
- Creating and provisioning VPS servers
- Cloning databases between environments
- Simulating peak traffic scenarios
- Monitoring environment health
- Clean environment teardown

## Scripts

### 1. create-vps-environment.sh
**Creates a new Laravel VPS server via Forge API**

Creates and configures a complete VPS environment with database, firewall rules, and SSL certificates.

#### Features
- ✅ Multi-provider support (DigitalOcean, AWS, Linode, Vultr, Hetzner)
- ✅ Automatic firewall configuration
- ✅ SSL certificate provisioning
- ✅ Database creation
- ✅ State management (resumable)
- ✅ Comprehensive logging
- ✅ Idempotent operations

#### Requirements
```bash
# Install dependencies
sudo apt-get install curl jq

# Set Forge API token
export FORGE_API_TOKEN="your-api-token-here"
```

#### Usage

**Basic VPS creation:**
```bash
./create-vps-environment.sh \
  --name "production-app" \
  --provider "digitalocean" \
  --region "nyc3" \
  --size "s-2vcpu-4gb"
```

**With domain and database:**
```bash
./create-vps-environment.sh \
  --name "staging-app" \
  --provider "linode" \
  --region "us-east" \
  --size "linode/4GB" \
  --domain "staging.example.com" \
  --database "app_staging"
```

**Load from environment file:**
```bash
source .env.forge
./create-vps-environment.sh --env-file config/vps.env
```

#### Output
- Creates VPS server on specified provider
- Configures firewall rules (SSH, HTTP, HTTPS)
- Provisions SSL certificate if domain provided
- Creates database if specified
- Logs all operations to `logs/vps-creation-TIMESTAMP.log`
- Saves state for resumption in `logs/.vps-creation-state`

#### Environment Variables
```bash
FORGE_API_TOKEN       # Laravel Forge API token (required)
FORGE_API_URL         # API endpoint (default: https://forge.laravel.com/api/v1)
MAX_WAIT_TIME         # Max wait for provisioning (default: 3600s)
RETRY_INTERVAL        # Retry wait time (default: 30s)
```

---

### 2. clone-database.sh
**Clones database snapshots to new environments**

Manages database snapshots and restores them to different servers.

#### Features
- ✅ List available snapshots
- ✅ Create database snapshots
- ✅ Clone snapshots to target servers
- ✅ Clone verification
- ✅ State tracking for resumption
- ✅ Automatic rollback on failure
- ✅ Support for MySQL and PostgreSQL

#### Usage

**Clone database to another server:**
```bash
./clone-database.sh \
  --source-server 12345 \
  --source-database "production_db" \
  --target-server 54321 \
  --target-database "staging_db"
```

**Create snapshot then clone:**
```bash
./clone-database.sh \
  --source-server 12345 \
  --source-database "production_db" \
  --create-snapshot \
  --target-server 54321 \
  --target-database "staging_db" \
  --verify
```

**List available snapshots:**
```bash
./clone-database.sh \
  --source-server 12345 \
  --source-database "production_db" \
  --list-snapshots
```

#### Output
- Creates/uses database snapshot
- Clones data to target server
- Verifies clone integrity
- Logs all operations
- Generates summary report

#### Environment Variables
```bash
FORGE_API_TOKEN         # Laravel Forge API token (required)
ENABLE_VERIFICATION    # Enable verification (default: true)
ENABLE_ROLLBACK        # Enable auto-rollback (default: true)
```

---

### 3. setup-saturday-peak.sh
**Shifts timestamps for Saturday peak traffic testing**

Modifies database timestamps to simulate weekend peak hour activity.

#### Features
- ✅ Automatic Saturday date detection
- ✅ Peak hour selection (8 AM - 11 PM configurable)
- ✅ Database backup before modification
- ✅ Support for MySQL and PostgreSQL
- ✅ Automatic timestamp column detection
- ✅ Dry-run mode for preview
- ✅ Rollback capability
- ✅ Comprehensive logging

#### Usage

**Setup Saturday peak for MySQL:**
```bash
./setup-saturday-peak.sh \
  --database "app_db" \
  --db-type "mysql" \
  --db-host "localhost" \
  --db-user "root" \
  --db-password "secret"
```

**With custom target date:**
```bash
./setup-saturday-peak.sh \
  --database "app_db" \
  --target-date "2024-11-02" \
  --peak-hours "08 09 10 19 20 21" \
  --db-user "root" \
  --db-password "secret"
```

**Dry run to preview changes:**
```bash
./setup-saturday-peak.sh \
  --database "app_db" \
  --db-user "root" \
  --db-password "secret" \
  --dry-run
```

**PostgreSQL database:**
```bash
./setup-saturday-peak.sh \
  --database "app_db" \
  --db-type "postgres" \
  --db-host "localhost" \
  --db-user "postgres" \
  --db-password "secret"
```

#### Output
- Backs up database to `backups/`
- Shifts all timestamp columns to Saturday
- Randomizes peak hours within specified range
- Preserves data relationships
- Logs all changes
- Enables rollback via backup

#### Environment Variables
```bash
DB_TYPE              # mysql or postgres (default: mysql)
DB_HOST              # Database host (default: localhost)
DB_USER              # Database user
DB_PASSWORD          # Database password
DB_NAME              # Database name
```

---

### 4. health-check.sh
**Comprehensive environment health monitoring**

Verifies all components of VPS environment are operational.

#### Features
- ✅ Server status verification
- ✅ HTTP/HTTPS connectivity
- ✅ Database health checks
- ✅ SSL certificate validation
- ✅ Firewall rule verification
- ✅ Application status monitoring
- ✅ Backup status tracking
- ✅ System resource monitoring
- ✅ Multiple output formats (text, JSON)
- ✅ Alert capability for critical issues

#### Usage

**Basic health check:**
```bash
./health-check.sh --server-id 12345
```

**Verbose with JSON output:**
```bash
./health-check.sh --server-id 12345 --verbose --output json
```

**With alerts enabled:**
```bash
./health-check.sh --server-id 12345 --alerts
```

#### Output
- Detailed health report
- Status summary (OK, WARNING, CRITICAL)
- Component-by-component verification
- Optional JSON export for automation
- Exit codes: 0 (healthy), 1 (warning), 2 (critical)

#### Health Checks Performed
1. Server Status - VPS operational status
2. System Resources - CPU, memory, disk availability
3. HTTP Connectivity - Web server responsiveness
4. Database Connectivity - Database availability
5. SSL Certificates - Certificate validity and expiration
6. Firewall Rules - Firewall configuration
7. Applications - Deployed site status
8. Backups - Backup capability
9. Access Keys - Authentication keys

#### Environment Variables
```bash
FORGE_API_TOKEN       # Laravel Forge API token (required)
VERBOSE               # Enable verbose output (default: false)
```

---

### 5. cleanup-environment.sh
**Destroys VPS and performs cleanup**

Safely removes VPS servers and associated resources with confirmation prompts.

#### Features
- ✅ Full server termination
- ✅ Selective component deletion
- ✅ Automatic data backup before deletion
- ✅ Multiple confirmation prompts
- ✅ Dry-run mode for preview
- ✅ Force mode (requires explicit confirmation)
- ✅ Detailed operation logging
- ✅ Rollback-capable backups

#### Usage

**Interactive cleanup with confirmations:**
```bash
./cleanup-environment.sh --server-id 12345
```

**Preview changes without executing:**
```bash
./cleanup-environment.sh --server-id 12345 --dry-run
```

**Delete only databases:**
```bash
./cleanup-environment.sh --server-id 12345 --databases
```

**Force deletion without prompts (REQUIRES EXPLICIT CONFIRMATION):**
```bash
./cleanup-environment.sh --server-id 12345 --force --no-backup
```

#### Cleanup Scope
- `--databases` - Delete all databases only
- `--backups` - Delete all backups only
- `--certificates` - Delete SSL certificates only
- `--firewall` - Delete firewall rules only
- (default) - Delete all of the above plus server

#### Safety Features
- ✅ Automatic backups before deletion
- ✅ Multiple confirmation prompts
- ✅ Dry-run mode for verification
- ✅ Detailed logging of all operations
- ✅ Backup IDs for easy restoration

#### Environment Variables
```bash
FORGE_API_TOKEN       # Laravel Forge API token (required)
FORGE_API_URL         # API endpoint (default: https://forge.laravel.com/api/v1)
```

---

## Common Workflows

### Complete Environment Setup
```bash
# 1. Create VPS
./create-vps-environment.sh \
  --name "prod-app" \
  --provider "digitalocean" \
  --region "nyc3" \
  --size "s-2vcpu-4gb" \
  --domain "app.example.com" \
  --database "production_db"

# 2. Wait for provisioning (check logs)
tail -f logs/vps-creation-*.log

# 3. Health check
./health-check.sh --server-id <ID-from-step-1>
```

### Production to Staging Clone
```bash
# 1. Create snapshot of production
./clone-database.sh \
  --source-server 12345 \
  --source-database "production_db" \
  --create-snapshot \
  --target-server 54321 \
  --target-database "staging_db" \
  --verify

# 2. Verify clone
./health-check.sh --server-id 54321
```

### Peak Load Testing
```bash
# 1. Clone production database to test server
./clone-database.sh \
  --source-server 12345 \
  --source-database "production_db" \
  --target-server 99999 \
  --target-database "load_test_db"

# 2. Setup Saturday peak timestamps
./setup-saturday-peak.sh \
  --database "load_test_db" \
  --db-type "mysql" \
  --target-date "2024-11-02"

# 3. Run load tests
# ... your load testing tools here ...

# 4. Verify results
./health-check.sh --server-id 99999 --output json
```

### Scheduled Backups and Cloning
```bash
# Add to crontab for weekly clone
0 2 * * 0 /path/to/clone-database.sh \
  --source-server 12345 \
  --source-database "production_db" \
  --create-snapshot \
  --target-server 54321 \
  --target-database "staging_db"

# Add to crontab for daily health checks
0 6 * * * /path/to/health-check.sh --server-id 12345
```

---

## Configuration Files

### Environment File Example (.env.forge)
```bash
#!/bin/bash
# Forge Configuration

export FORGE_API_TOKEN="your-api-token-here"
export FORGE_API_URL="https://forge.laravel.com/api/v1"
export LOG_DIR="/var/log/forge-automation"
export BACKUP_DIR="/backups/forge"
export MAX_WAIT_TIME=1800
export RETRY_INTERVAL=30
```

### VPS Configuration File (config/vps.env)
```bash
#!/bin/bash
# VPS Configuration

VPS_NAME="production-app"
VPS_PROVIDER="digitalocean"
VPS_REGION="nyc3"
VPS_SIZE="s-2vcpu-4gb"
VPS_IP_ADDRESS="192.0.2.100"
DOMAIN="app.example.com"
DATABASE="production_db"
```

---

## Logging

All scripts create detailed logs in `logs/` directory:

```
logs/
├── vps-creation-20241108_191622.log
├── database-clone-20241108_191623.log
├── saturday-peak-20241108_191624.log
├── health-check-20241108_191625.log
├── cleanup-20241108_191626.log
└── .vps-creation-state  (state file for resumption)
```

View logs in real-time:
```bash
tail -f logs/vps-creation-*.log
```

---

## Error Handling

All scripts include:
- ✅ Pre-execution requirement checks
- ✅ API error handling with detailed messages
- ✅ Network timeout handling
- ✅ Graceful degradation
- ✅ Automatic rollback on failure
- ✅ Comprehensive error logging
- ✅ State persistence for resumption

### Common Issues

**"FORGE_API_TOKEN not set"**
```bash
export FORGE_API_TOKEN="your-token-here"
```

**"curl/jq not found"**
```bash
sudo apt-get install curl jq
```

**"API request failed with status: 401"**
- Check your API token is valid
- Verify token has proper permissions in Forge dashboard

**"Connection timeout"**
- Check network connectivity
- Increase `HEALTH_CHECK_TIMEOUT` environment variable
- Verify API endpoint is accessible

---

## API Documentation

Scripts use Laravel Forge API v1. For detailed API documentation:
- https://forge.laravel.com/api-documentation

Key endpoints used:
- `GET /servers` - List servers
- `POST /servers` - Create server
- `GET /servers/{id}` - Get server details
- `GET /servers/{id}/databases` - List databases
- `POST /servers/{id}/databases` - Create database
- `GET /servers/{id}/ssl-certificates` - List SSL certificates
- `GET /servers/{id}/firewall-rules` - List firewall rules

---

## Security Considerations

1. **API Token Protection**
   - Never commit `.env` files with tokens
   - Use environment variables for credentials
   - Rotate tokens regularly
   - Use `.gitignore` for sensitive files

2. **Backup Safety**
   - Backups stored in secured `backups/` directory
   - Ensure proper file permissions
   - Test restore procedures regularly
   - Keep backups in multiple locations

3. **Access Control**
   - Scripts require Forge API token with proper permissions
   - Restrict script access to authorized users only
   - Audit all environment modifications
   - Log all automation activities

4. **Data Protection**
   - Database cloning includes full data
   - Mask sensitive data in staging environments
   - Use encryption for backups
   - Verify data integrity after operations

---

## Advanced Usage

### Custom API Endpoints
```bash
export FORGE_API_URL="https://custom-api.example.com/v1"
./create-vps-environment.sh --name "app" --provider "custom" ...
```

### Extended Logging
```bash
export VERBOSE=true
./health-check.sh --server-id 12345 --verbose
```

### Parallel Execution
```bash
# Run multiple operations in parallel
./health-check.sh --server-id 12345 &
./health-check.sh --server-id 54321 &
wait
```

### Integration with CI/CD
```bash
# In your CI/CD pipeline
set -e
source .env.forge
./health-check.sh --server-id $PRODUCTION_SERVER_ID
if [[ $? -ne 0 ]]; then
  echo "Production server health check failed!"
  exit 1
fi
```

---

## Troubleshooting

### Enable Verbose Logging
```bash
bash -x ./create-vps-environment.sh --name "app" ...
```

### Check API Connectivity
```bash
curl -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/servers
```

### View Log Details
```bash
# View last 100 lines
tail -100 logs/health-check-*.log

# Search for errors
grep "ERROR" logs/*.log

# Monitor in real-time
tail -f logs/*.log
```

---

## Support

For issues or questions:
1. Check script logs in `logs/` directory
2. Review Laravel Forge API documentation
3. Verify API token and permissions
4. Test with `--dry-run` mode first
5. Review script comments for implementation details

---

## License

These automation scripts are provided as part of the Laravel VPS management toolkit.

## Changelog

### v1.0.0 (2024-11-08)
- ✅ Initial release
- ✅ All 5 core scripts implemented
- ✅ Comprehensive error handling
- ✅ Full logging and state management
- ✅ Complete documentation
