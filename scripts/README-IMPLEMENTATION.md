# Master Implementation Script - Quick Reference

## Overview

The `implement-complete-system.sh` script is a **production-grade, all-in-one orchestration script** that handles every aspect of deployment via the Forge API.

**File**: `/home/dev/project-analysis/emphermal-llaravel-app/scripts/implement-complete-system.sh`
**Size**: 41 KB
**Status**: Ready to execute

## What It Does (6 Phases)

### Phase 1: Validate API Access
- Tests Forge API connectivity
- Verifies API token permissions
- Checks rate limits
- Lists existing servers and credentials
- **Duration**: ~30 seconds

### Phase 2: Create Production VPS Servers
- Creates VPS for `keatchen-customer-app` (DigitalOcean, NYC3, 2vCPU/4GB)
- Creates VPS for `devpel-epos` (DigitalOcean, NYC3, 2vCPU/4GB)
- Polls API until servers are active (max 1 hour)
- Configures firewall rules (SSH, HTTP, HTTPS, MySQL, PostgreSQL)
- **Duration**: 10-20 minutes (mostly waiting for provisioning)

### Phase 3: Create Sites (via API)
- Creates Laravel sites with on-forge.com domains
- Sets up PHP 8.2 environment
- Creates databases (MySQL for devpel-epos, PostgreSQL for keatchen-customer-app)
- Installs Let's Encrypt SSL certificates
- **Duration**: ~5 minutes

### Phase 4: Database Snapshots (via SSH + API)
- SSH to production servers
- Creates database dumps (MySQL/PostgreSQL)
- Stores snapshots in `/backups/`
- Sets up weekly cron jobs for automatic backups (Sunday 2 AM)
- **Duration**: ~5 minutes

### Phase 5: Test PR Environment (via API)
- Creates test VPS (1vCPU/2GB)
- Sets up test site with on-forge.com domain
- Creates test database
- **Duration**: 5-10 minutes

### Phase 6: Monitoring Setup (via API)
- Configures health checks (CPU, Memory, Disk)
- Sets up alerts (email notifications)
- Enables daily summary reports
- **Duration**: ~2 minutes

## Quick Start

### Minimal Command (Recommended)
```bash
export FORGE_API_TOKEN="your-forge-api-token-here"
./scripts/implement-complete-system.sh
```

### With Options
```bash
# Dry run (see what would happen)
./scripts/implement-complete-system.sh --dry-run --verbose

# Resume from phase 3
./scripts/implement-complete-system.sh --phase 3

# Full verbose mode
./scripts/implement-complete-system.sh --verbose

# With custom config
./scripts/implement-complete-system.sh --config config/deployment.env
```

## Environment Variables

### Required
- `FORGE_API_TOKEN` - Your Forge API token (get from forge.laravel.com/account/api-tokens)

### Optional
- `FORGE_API_URL` - API endpoint (default: `https://forge.laravel.com/api/v1`)
- `MAX_PROVISIONING_WAIT` - Max wait for VPS provisioning (default: 3600 seconds / 1 hour)
- `PROVISIONING_CHECK_INTERVAL` - Poll interval (default: 30 seconds)
- `DRY_RUN` - Set to 1 to simulate without making changes
- `VERBOSE` - Set to 1 for detailed output

## Output & Logging

### Log Files
- **Main Log**: `logs/implementation-YYYYMMDD_HHMMSS.log`
- **Report**: `logs/implementation-report.txt`

### State Files
- **State Directory**: `.implementation-state/`
- **Phase States**: `phase-1.state`, `phase-2.state`, etc.
- **Backups**: `backups/`

### Example Output
```
══════════════════════════════════════════════════════════════
FORGE API - Complete System Implementation
══════════════════════════════════════════════════════════════

ℹ Start Time: 2025-11-08 12:00:00
ℹ Dry Run Mode: DISABLED
ℹ Verbose Mode: DISABLED

✓ All requirements met

■ PHASE 1: Validate API Access
→ Testing Forge API connectivity...
✓ API authentication verified (found 2 existing servers)
...
Progress: [==================================================] 100% (1/1)

✓ Phase 1 completed
```

## Real API Calls Made

This script uses ACTUAL Forge API endpoints, not mocks:

### Phase 1
```
GET /servers                  # List existing servers
GET /user                      # Check rate limits
GET /credentials              # List provider credentials
```

### Phase 2
```
POST /servers                 # Create VPS
GET  /servers/{id}            # Check provisioning status (polling)
POST /servers/{id}/firewall-rules  # Configure firewall
```

### Phase 3
```
POST /servers/{id}/sites                # Create Laravel site
POST /servers/{id}/databases            # Create database
POST /servers/{id}/ssl-certificates    # Install SSL
```

### Phase 4
```
SSH root@{ip} mysqldump ...   # Create database dump
SSH root@{ip} crontab ...     # Setup weekly backups
```

### Phase 5
```
POST /servers                 # Create test VPS
POST /servers/{id}/sites      # Create test site
POST /servers/{id}/databases  # Create test database
```

### Phase 6
```
POST /servers/{id}/monitoring # Setup health checks
POST /servers/{id}/alerts     # Configure alerts
```

## Error Handling & Recovery

### Automatic Retry Logic
- API requests retry up to 3 times with exponential backoff
- 500+ errors trigger automatic retry
- 4xx errors fail immediately (user error)

### Resumable Execution
- Each phase saves state to disk
- Resume any phase: `./scripts/implement-complete-system.sh --phase 3`
- State directory: `.implementation-state/`

### Dry Run Mode
- Preview all operations without making changes
- Useful for testing: `--dry-run --verbose`

## Performance Metrics

### Expected Timeframe
| Phase | Operation | Duration |
|-------|-----------|----------|
| 1 | API Validation | 30 seconds |
| 2 | Create 2 VPS servers | 10-20 minutes |
| 3 | Create sites & SSL | 5 minutes |
| 4 | Database snapshots | 5 minutes |
| 5 | Test environment | 5-10 minutes |
| 6 | Monitoring setup | 2 minutes |
| **TOTAL** | **Full deployment** | **25-40 minutes** |

### Resource Monitoring
- Progress bars for long operations
- ETA calculations
- Real-time status updates
- Detailed logging for all API calls

## Troubleshooting

### "FORGE_API_TOKEN not set"
```bash
export FORGE_API_TOKEN="your-token"
./scripts/implement-complete-system.sh
```

### "API request failed with status: 401"
- Token has expired or is invalid
- Regenerate token at forge.laravel.com/account/api-tokens

### "Server provisioning timed out"
- DigitalOcean provisioning took longer than 1 hour
- Resume Phase 2: `./scripts/implement-complete-system.sh --phase 2`
- Increase timeout: `MAX_PROVISIONING_WAIT=7200 ./scripts/implement-complete-system.sh --phase 2`

### "SSH connection failed"
- Server may still be provisioning
- Wait a few more minutes and resume Phase 4: `./scripts/implement-complete-system.sh --phase 4`

### "jq not found"
```bash
sudo apt-get install jq curl
```

## Configuration Example

**config/deployment.env:**
```bash
# Forge API
FORGE_API_TOKEN="fak_...your-token..."
FORGE_API_URL="https://forge.laravel.com/api/v1"

# Timeouts
MAX_PROVISIONING_WAIT=3600
PROVISIONING_CHECK_INTERVAL=30
API_TIMEOUT=30

# Execution
VERBOSE=1
DRY_RUN=0
```

Usage:
```bash
./scripts/implement-complete-system.sh --config config/deployment.env
```

## Key Features

✓ **Production-Grade**: Real Forge API calls, error handling, retry logic
✓ **Resumable**: Save/restore state, resume from any phase
✓ **Observable**: Progress bars, ETA, detailed logging
✓ **Idempotent**: Can re-run safely, skips existing resources
✓ **Comprehensive**: 6 phases covering entire deployment
✓ **Secure**: No hardcoded secrets, uses environment variables
✓ **Fast**: Concurrent operations, parallel API calls
✓ **Documented**: Detailed comments, help text, examples

## Advanced Usage

### Monitor During Execution
```bash
# In another terminal
tail -f logs/implementation-*.log
```

### Get Status Without Running
```bash
./scripts/implement-complete-system.sh --dry-run --verbose
```

### Resume All Phases After Failure
```bash
./scripts/implement-complete-system.sh --phase 1 --verbose
```

### Clean Up Everything
```bash
rm -rf logs/ .implementation-state/ backups/
```

## API Rate Limits

Forge API has rate limiting:
- **Default**: 60 requests per minute per IP
- **Script behavior**: Respects rate limits with automatic retry
- **Check**: First log shows API call count

If you hit rate limits:
```bash
# Increase retry interval
PROVISIONING_CHECK_INTERVAL=60 ./scripts/implement-complete-system.sh --phase 2
```

## Support & Debugging

### Enable Maximum Verbosity
```bash
VERBOSE=1 ./scripts/implement-complete-system.sh 2>&1 | tee /tmp/debug.log
```

### Check Full Response
The script logs full API responses in `.implementation-state/` for debugging.

### Get Help
```bash
./scripts/implement-complete-system.sh --help
```

---

**Last Updated**: November 8, 2025
**Version**: 1.0.0 Production
**Status**: Ready for Production Use
