# Quick Start Guide - Laravel VPS Automation

Fast reference for common operations with the automation scripts.

## Prerequisites

```bash
# 1. Install dependencies
sudo apt-get install curl jq

# 2. Set your Forge API token
export FORGE_API_TOKEN="your-forge-api-token"

# 3. Navigate to scripts directory
cd /path/to/scripts
```

## 5-Minute Setups

### Setup New VPS (5 min)
```bash
./create-vps-environment.sh \
  --name "my-app" \
  --provider "digitalocean" \
  --region "nyc3" \
  --size "s-2vcpu-4gb"
```

### Check Server Health (2 min)
```bash
./health-check.sh --server-id 12345
```

### Clone Database (10 min)
```bash
./clone-database.sh \
  --source-server 11111 \
  --source-database "prod_db" \
  --target-server 22222 \
  --target-database "stage_db"
```

### Setup Peak Load Test (5 min)
```bash
./setup-saturday-peak.sh \
  --database "test_db" \
  --db-type "mysql" \
  --db-user "root" \
  --db-password "password"
```

### Cleanup Server (3 min)
```bash
./cleanup-environment.sh --server-id 12345
```

## Common Server IDs

Replace these in examples:
- `SOURCE_SERVER` - Origin server ID from Forge
- `TARGET_SERVER` - Destination server ID from Forge
- `DB_NAME` - Database name in server

## Get Server IDs

```bash
# List all servers
curl -s -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/servers | jq '.servers[] | {id, name}'
```

## Useful Aliases

Add to `.bashrc`:
```bash
alias forge-health='./health-check.sh --server-id'
alias forge-clone='./clone-database.sh'
alias forge-clean='./cleanup-environment.sh --server-id'
```

Then use:
```bash
forge-health 12345
forge-clean 12345
```

## Dry Runs (Preview without executing)

Always test with `--dry-run` first:

```bash
./setup-saturday-peak.sh --database "db" --dry-run
./cleanup-environment.sh --server-id 12345 --dry-run
```

## Real-Time Log Monitoring

```bash
# Watch creation progress
tail -f logs/vps-creation-*.log

# Watch all operations
tail -f logs/*.log
```

## Common Workflows

### Full Setup Pipeline
```bash
# 1. Create VPS
SERVER_ID=$(./create-vps-environment.sh \
  --name "prod" \
  --provider "digitalocean" \
  --region "nyc3" \
  --size "s-2vcpu-4gb" \
  --domain "example.com")

# Wait for logs to complete, then:

# 2. Health check
./health-check.sh --server-id $SERVER_ID

# 3. Done!
```

### Clone for Staging
```bash
./clone-database.sh \
  --source-server 111 \
  --source-database "production_db" \
  --create-snapshot \
  --target-server 222 \
  --target-database "staging_db" \
  --verify
```

### Test Peak Load
```bash
# 1. Clone production to test server
./clone-database.sh \
  --source-server 111 \
  --source-database "production_db" \
  --target-server 999 \
  --target-database "test_db"

# 2. Setup Saturday peak
./setup-saturday-peak.sh \
  --database "test_db" \
  --db-type "mysql"

# 3. Run your load tests...

# 4. Check results
./health-check.sh --server-id 999 --output json
```

## Scheduling (Cron)

Add to crontab:
```bash
# Daily health check at 6 AM
0 6 * * * /scripts/health-check.sh --server-id 12345

# Weekly database clone (Sundays at 2 AM)
0 2 * * 0 /scripts/clone-database.sh \
  --source-server 111 \
  --source-database "prod" \
  --create-snapshot \
  --target-server 222 \
  --target-database "stage"
```

## Environment File

Create `.env.forge`:
```bash
export FORGE_API_TOKEN="your-token"
export FORGE_API_URL="https://forge.laravel.com/api/v1"
export LOG_DIR="/logs"
export BACKUP_DIR="/backups"
```

Source it:
```bash
source .env.forge
./create-vps-environment.sh --name "app" ...
```

## Output Format

### Text (Default)
```bash
./health-check.sh --server-id 12345
```

### JSON (For automation)
```bash
./health-check.sh --server-id 12345 --output json | jq '.'
```

## Exit Codes

- `0` - Success / Healthy
- `1` - Warning / Partial failure
- `2` - Critical / Complete failure

Use in scripts:
```bash
./health-check.sh --server-id 12345
if [ $? -eq 0 ]; then
  echo "Server is healthy"
else
  echo "Server has issues"
fi
```

## Troubleshooting

**Error: "FORGE_API_TOKEN not set"**
```bash
export FORGE_API_TOKEN="your-token-here"
```

**Error: "curl/jq not found"**
```bash
sudo apt-get install curl jq
```

**API Errors?**
- Verify token: `echo $FORGE_API_TOKEN`
- Check permissions in Forge dashboard
- Verify server ID exists

**Want verbose output?**
```bash
export VERBOSE=true
./health-check.sh --server-id 12345 --verbose
```

## Getting Help

View full documentation:
```bash
cat README.md

# Or get help for specific script:
./create-vps-environment.sh --help
./clone-database.sh --help
./setup-saturday-peak.sh --help
./health-check.sh --help
./cleanup-environment.sh --help
```

## Tips & Tricks

### Watch multiple operations
```bash
for server in 111 222 333; do
  ./health-check.sh --server-id $server &
done
wait
```

### Export results
```bash
./health-check.sh --server-id 12345 --output json > report.json
cat report.json | jq '.'
```

### Automated alerts
```bash
./health-check.sh --server-id 12345 --alerts
# Sends alerts if critical issues found
```

### Backup before cleanup
```bash
# Automatic backup enabled by default
./cleanup-environment.sh --server-id 12345
# Backups stored in /backups/
```

## Next Steps

1. Read full documentation: `README.md`
2. Run `--help` on any script for details
3. Try a `--dry-run` first
4. Check logs for detailed information
5. Explore error handling in script comments

---

**Pro Tips:**
- Always use `--dry-run` before destructive operations
- Monitor logs in separate terminal: `tail -f logs/*.log`
- Save useful server IDs in notes or scripts
- Test cron jobs manually first before scheduling
- Keep backups in secure location
