# Forge API Real-Time Monitoring System

Complete suite of tools and scripts for comprehensive Laravel Forge infrastructure monitoring with real-time dashboards, deployment tracking, SSL certificate management, and integrated alerting.

## Overview

This monitoring system provides production-ready tools for:

- Real-time server and site status monitoring
- Deployment progress tracking with automatic alerts
- SSL certificate expiration monitoring and alerts
- Database connectivity verification
- Queue worker health monitoring with auto-restart
- Cost analysis and tracking
- Multi-server dashboard support
- Slack webhook integration
- JSON export for tool integration
- Nagios/Icinga integration
- Prometheus metrics export

## Files Included

### Core Monitoring Script
- **`monitor-via-api.sh`** - Main real-time monitoring dashboard
  - Real-time server metrics
  - Site deployment tracking
  - Worker status monitoring
  - Database connectivity checks
  - SSL certificate tracking
  - ASCII art dashboard
  - JSON export capability
  - Slack webhook alerts

### Helper Library
- **`forge-api-helpers.sh`** - Forge API utility functions
  - Server management functions
  - Site deployment functions
  - Database management
  - Worker lifecycle management
  - Certificate operations
  - Firewall rule management
  - Cost analysis utilities
  - Batch operations

### Examples and Documentation
- **`forge-monitoring-examples.sh`** - 10 real-world usage examples
  - Production deployment monitoring
  - SSL certificate renewal alerts
  - Queue worker health checks
  - Database backup monitoring
  - Cost reporting
  - PHP version upgrades
  - Firewall management
  - Configuration backups
  - Multi-server dashboards
  - Email alert integration

- **`FORGE-MONITORING-GUIDE.md`** - Comprehensive user guide
- **`README-FORGE-API.md`** - This file

## Quick Start

### 1. Setup (2 minutes)

```bash
# Clone/copy the monitoring scripts
cd /path/to/project/scripts

# Get your Forge API token
# Visit: https://forge.laravel.com/user/profile#/api-tokens

# Get your Server ID
# From: https://forge.laravel.com/servers/{id}

# Set environment variables
export FORGE_API_TOKEN="your-api-token-here"
export FORGE_SERVER_ID="your-server-id-here"

# Test the setup
./forge-api-helpers.sh
# Should output: "Forge API Helper Functions Library Loaded"
```

### 2. Run the Monitor (1 minute)

```bash
# Start real-time monitoring
./monitor-via-api.sh

# Or with custom options
./monitor-via-api.sh \
    --interval 30 \
    --refresh-rate 5 \
    --slack-webhook "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN"

# Single check (non-continuous)
./monitor-via-api.sh --once --json
```

### 3. View Results

The dashboard updates in real-time showing:
```
╔════════════════════════════════════════════════════════════════╗
║     🚀 FORGE API REAL-TIME MONITORING SYSTEM                   ║
║     Laravel Forge Infrastructure Dashboard                     ║
╚════════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SERVER STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Name:                 ✓ production-server-1
  IP Address:              192.168.1.1
  Size:                    2GB
  Provider:                digitalocean
  Region:                  us-east-1
  PHP Version:             8.3
  Status:                  active
```

## Core Features

### Real-Time Monitoring Dashboard
```bash
./monitor-via-api.sh
```
- Continuous monitoring with automatic refreshes
- Color-coded status indicators
- Resource utilization display
- Site and worker status
- Database connectivity status
- SSL certificate information

### Single Health Check
```bash
./monitor-via-api.sh --once --json > metrics.json
```
- One-time check for automation
- JSON output for tool integration
- Exit codes for alerting
- Structured data for parsing

### Slack Integration
```bash
./monitor-via-api.sh \
    --slack-webhook "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN..." \
    --interval 30
```
- Real-time alerts on failures
- Deployment notifications
- Certificate expiration warnings
- Worker status changes

### Multi-Server Monitoring
```bash
#!/bin/bash
for server_id in 12345 67890 11111; do
    echo "=== Server $server_id ==="
    FORGE_SERVER_ID="$server_id" ./monitor-via-api.sh --once
done
```

## API Endpoints Monitored

The system actively monitors these Forge API endpoints:

```
Server Information
├── GET /servers/{id}
├── GET /servers/{id}/sites
├── GET /servers/{id}/databases
├── GET /servers/{id}/workers
├── GET /servers/{id}/firewall-rules
└── POST /servers/{id}/reboot

Site Management
├── GET /servers/{id}/sites/{site_id}
├── GET /servers/{id}/sites/{site_id}/deployment-log
├── GET /servers/{id}/sites/{site_id}/certificates
├── GET /servers/{id}/sites/{site_id}/env
└── POST /servers/{id}/sites/{site_id}/deployment/deploy

Database Operations
├── GET /servers/{id}/databases
├── GET /servers/{id}/databases/{db_id}
├── GET /servers/{id}/database-users
├── POST /servers/{id}/databases
└── POST /servers/{id}/database-users

Worker Management
├── GET /servers/{id}/workers
├── GET /servers/{id}/workers/{worker_id}
├── POST /servers/{id}/workers/{worker_id}/restart
└── DELETE /servers/{id}/workers/{worker_id}
```

## Usage Patterns

### Pattern 1: Production Monitoring (Always Running)

```bash
#!/bin/bash
# In systemd service or supervisor

export FORGE_API_TOKEN="prod-token"
export FORGE_SERVER_ID="12345"

./scripts/monitor-via-api.sh \
    --log /var/log/forge_monitor.log \
    --slack-webhook "$SLACK_WEBHOOK_URL" \
    --interval 60 \
    --refresh-rate 30
```

### Pattern 2: Scheduled Health Checks (Cron)

```bash
# In /etc/cron.d/forge-health-check

*/5 * * * * \
  FORGE_API_TOKEN="token" FORGE_SERVER_ID="12345" \
  /path/to/scripts/monitor-via-api.sh \
  --once \
  --json \
  --log /var/log/forge_checks.json
```

### Pattern 3: Deployment Monitoring

```bash
# Monitor during deployments
source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="token"
FORGE_SERVER_ID="12345"
SITE_ID="5"

# Initiate deployment
forge_deploy_site "$FORGE_SERVER_ID" "$SITE_ID"

# Monitor progress
./monitor-via-api.sh --interval 5 --refresh-rate 2
```

### Pattern 4: Cost Analysis Reports

```bash
#!/bin/bash
# Monthly cost report

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="token"

# Generate report
forge_export_server_config "12345" "server_backup.json"

# Analyze costs
for server_id in $(forge_get_servers | grep -o '"id":[0-9]*'); do
    size=$(forge_get_server "$server_id" | grep -o '"size":"[^"]*' | cut -d'"' -f4)
    cost=$(forge_estimate_monthly_cost "$size")
    echo "Server $server_id ($size): \$$cost/month"
done
```

## Integration Examples

### Nagios/Icinga

```bash
#!/bin/bash
# /usr/lib/nagios/plugins/check_forge.sh

export FORGE_API_TOKEN="token"
export FORGE_SERVER_ID="12345"

RESULT=$(/path/to/scripts/monitor-via-api.sh --json --once)
STATUS=$(echo "$RESULT" | jq -r '.server.status')

if [ "$STATUS" = "active" ]; then
    echo "OK: Forge server is active"
    exit 0
else
    echo "CRITICAL: Forge server is not active"
    exit 2
fi
```

### Prometheus Exporter

```bash
#!/bin/bash
# /usr/local/bin/forge_exporter.sh

export FORGE_API_TOKEN="token"
export FORGE_SERVER_ID="12345"

PORT=9200
while true; do
    METRICS=$(/path/to/scripts/monitor-via-api.sh --json --once)

    cat << EOF | nc localhost $PORT
# TYPE forge_server_active gauge
forge_server_active{server_id="$FORGE_SERVER_ID"} $(echo "$METRICS" | jq '.server.status == "active"')

# TYPE forge_sites_total gauge
forge_sites_total{server_id="$FORGE_SERVER_ID"} $(echo "$METRICS" | jq '.sites.count')

# TYPE forge_workers_total gauge
forge_workers_total{server_id="$FORGE_SERVER_ID"} $(echo "$METRICS" | jq '.workers.count')

# TYPE forge_databases_total gauge
forge_databases_total{server_id="$FORGE_SERVER_ID"} $(echo "$METRICS" | jq '.databases.count')
EOF

    sleep 60
done
```

### DataDog Integration

```bash
#!/bin/bash
# Send Forge metrics to DataDog

export FORGE_API_TOKEN="token"
export FORGE_SERVER_ID="12345"
METRICS=$(/path/to/scripts/monitor-via-api.sh --json --once)

curl -X POST "https://api.datadoghq.com/api/v1/series" \
  -H "DD-API-KEY: $DATADOG_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"series\": [
      {
        \"metric\": \"forge.server.active\",
        \"points\": [[$(date +%s), $(echo "$METRICS" | jq '.server.status == "active"')]],
        \"tags\": [\"server_id:$FORGE_SERVER_ID\"]
      }
    ]
  }"
```

## Alert Thresholds

Configure alert sensitivity with environment variables:

```bash
# CPU usage alert at 80%
export MONITOR_THRESHOLD_CPU=80

# Memory usage alert at 85%
export MONITOR_THRESHOLD_MEM=85

# Disk usage alert at 90%
export MONITOR_THRESHOLD_DISK=90

# SSL certificate alert 30 days before expiry
export SSL_ALERT_DAYS=30
```

## Troubleshooting

### "API Token Invalid" Error

```bash
# Verify token
curl -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/servers

# Regenerate token in Forge dashboard if needed
```

### "Server ID Not Found" Error

```bash
# Verify server ID exists
curl -H "Authorization: Bearer $FORGE_API_TOKEN" \
  https://forge.laravel.com/api/v1/servers

# Check current server ID in Forge URL
# https://forge.laravel.com/servers/{id}
```

### Network Connection Issues

```bash
# Test API endpoint connectivity
curl -I https://forge.laravel.com/api/v1/servers

# Check firewall/proxy settings
echo $http_proxy
echo $https_proxy

# Test with verbose output
./scripts/monitor-via-api.sh --once 2>&1 | head -20
```

### No Data Returned

```bash
# Verify authentication works
source ./scripts/forge-api-helpers.sh
forge_validate_token
forge_validate_server

# Check if server has any resources
forge_count_resources "$FORGE_SERVER_ID"
```

## Performance Optimization

### Reduce API Load
```bash
# Increase polling interval
./monitor-via-api.sh --interval 300  # Check every 5 minutes
```

### Headless Monitoring
```bash
# Disable dashboard for background operation
./monitor-via-api.sh --no-dashboard --log /var/log/monitor.log
```

### JSON-Only Output
```bash
# Use JSON for integration without dashboard rendering
./monitor-via-api.sh --json --log metrics.json
```

## Security Best Practices

### 1. Protect API Tokens

```bash
# Add to .gitignore
echo "FORGE_API_TOKEN=*" >> .gitignore
echo ".env" >> .gitignore

# Use environment file (not committed)
cat > .env <<EOF
FORGE_API_TOKEN="your-token"
FORGE_SERVER_ID="your-server-id"
EOF

source .env
```

### 2. Rotate Tokens Regularly

- Change API tokens every 90 days
- Revoke old tokens immediately
- Use separate tokens for different environments

### 3. Secure Slack Webhooks

```bash
# Store in environment, not in scripts
export SLACK_WEBHOOK="YOUR_SLACK_WEBHOOK_HERE"

# Don't commit to version control
echo "SLACK_WEBHOOK=*" >> .gitignore
```

### 4. Limit API Calls

- Use reasonable polling intervals
- Implement rate limiting
- Monitor API usage regularly

## File Organization

```
project/
├── scripts/
│   ├── monitor-via-api.sh           # Main monitoring script
│   ├── forge-api-helpers.sh         # API helper functions
│   ├── forge-monitoring-examples.sh # Usage examples
│   ├── FORGE-MONITORING-GUIDE.md    # Detailed guide
│   └── README-FORGE-API.md          # This file
├── .env                             # API credentials (not committed)
├── logs/
│   ├── forge_monitor.log            # Daily monitoring logs
│   ├── forge_alerts.log             # Alert events
│   └── forge_metrics_*.json         # Historical metrics
└── backups/
    └── server_12345_*.json          # Configuration backups
```

## Command Reference

### Core Monitoring
```bash
# Real-time dashboard
./monitor-via-api.sh

# Single check
./monitor-via-api.sh --once

# JSON output
./monitor-via-api.sh --once --json

# With alerts
./monitor-via-api.sh --slack-webhook "URL"
```

### Helper Functions
```bash
source ./scripts/forge-api-helpers.sh

# Server operations
forge_get_servers
forge_get_server "12345"
forge_reboot_server "12345"

# Site operations
forge_get_sites "12345"
forge_deploy_site "12345" "5"
forge_get_site_deployment_log "12345" "5"

# Database operations
forge_get_databases "12345"
forge_create_database "12345" "dbname"

# Worker operations
forge_get_workers "12345"
forge_restart_all_workers "12345"

# Reports
forge_export_server_config "12345" "backup.json"
forge_generate_server_report "12345"
```

### Examples
```bash
# View example usage
./scripts/forge-monitoring-examples.sh

# Extract specific example
./scripts/forge-monitoring-examples.sh 1 > ssl_monitor.sh
./scripts/forge-monitoring-examples.sh 3 > worker_monitor.sh
```

## API Rate Limits

Forge API rate limits:
- Requests per minute: 120
- Requests per hour: 3,600
- Default retry: 429 responses trigger automatic backoff

Our scripts respect these limits with:
- Configurable polling intervals (default 30s)
- Batch operations where possible
- Efficient endpoint usage

## Support Resources

- **Forge API Documentation**: https://forge.laravel.com/api-documentation
- **Laravel Forge Status**: https://status.forge.laravel.com
- **Issue Reporting**: Create issues in your project repository

## Examples

See `forge-monitoring-examples.sh` for:
1. Production deployment monitoring
2. SSL certificate renewal alerts
3. Queue worker health checks
4. Database backup monitoring
5. Cost analysis and reporting
6. PHP version upgrades
7. Firewall rule management
8. Server configuration backups
9. Multi-server dashboards
10. Email alert integration

## License

These scripts are provided for use with Laravel Forge infrastructure monitoring. See LICENSE file for details.

## Next Steps

1. Set up environment variables
2. Run `./monitor-via-api.sh --once` to test
3. Configure Slack webhook for alerts
4. Set up cron job for scheduled monitoring
5. Integrate with monitoring system (Nagios, Prometheus, etc.)

For detailed usage, see `FORGE-MONITORING-GUIDE.md`
