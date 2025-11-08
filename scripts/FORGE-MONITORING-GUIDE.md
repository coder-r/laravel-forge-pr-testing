# Forge API Real-Time Monitoring System

Complete guide for the Laravel Forge API monitoring system with real-time metrics, deployment tracking, SSL certificate monitoring, and cost analysis.

## Overview

The monitoring system provides:
- Real-time server and site status monitoring
- Deployment status and logs tracking
- SSL certificate expiration alerts
- Database connectivity verification
- Queue worker monitoring
- Cost and resource tracking
- Dashboard visualization
- JSON export for integration
- Slack webhook alerts

## Quick Start

### 1. Get Your Forge API Token

1. Log in to [Laravel Forge](https://forge.laravel.com)
2. Go to Settings → API Tokens
3. Create a new API token
4. Copy the token (you'll only see it once!)

### 2. Get Your Server ID

1. Go to your server page
2. The URL will be: `https://forge.laravel.com/servers/{id}`
3. Extract the `{id}` number

### 3. Set Environment Variables

```bash
export FORGE_API_TOKEN="your-api-token-here"
export FORGE_SERVER_ID="your-server-id-here"
```

### 4. Run the Monitor

```bash
# Continuous monitoring with dashboard
./scripts/monitor-via-api.sh

# Single check
./scripts/monitor-via-api.sh --once

# JSON output
./scripts/monitor-via-api.sh --json --once

# With logging
./scripts/monitor-via-api.sh --log /var/log/forge_monitor.log

# With Slack alerts
./scripts/monitor-via-api.sh --slack-webhook "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN"
```

## Command-Line Options

### Basic Usage

```bash
./scripts/monitor-via-api.sh [OPTIONS]
```

### Options

| Option | Description | Example |
|--------|-------------|---------|
| `--server-id ID` | Forge Server ID | `--server-id 12345` |
| `--api-token TOKEN` | Forge API Token | `--api-token abc123...` |
| `--interval N` | API polling interval (seconds) | `--interval 30` |
| `--refresh-rate N` | Dashboard refresh rate (seconds) | `--refresh-rate 5` |
| `--json` | Output as JSON instead of dashboard | `--json` |
| `--log FILE` | Log output to file | `--log /var/log/monitor.log` |
| `--slack-webhook URL` | Send alerts to Slack | `--slack-webhook https://hooks...` |
| `--no-dashboard` | Disable dashboard output | `--no-dashboard` |
| `--once` | Run once and exit | `--once` |
| `--help` | Show help message | `--help` |

## Usage Examples

### Example 1: Continuous Monitoring with Dashboard

```bash
#!/bin/bash
export FORGE_API_TOKEN="your-token"
export FORGE_SERVER_ID="12345"

./scripts/monitor-via-api.sh
```

This displays a real-time dashboard that updates every 5 seconds, showing:
- Server status and information
- Active sites
- Queue workers
- Databases
- SSL certificates

### Example 2: Log Monitoring to File

```bash
#!/bin/bash
./scripts/monitor-via-api.sh \
    --api-token "your-token" \
    --server-id "12345" \
    --log /var/log/forge_monitor.log \
    --interval 60 \
    --refresh-rate 30
```

This runs in the background, polling the API every 60 seconds and updating the dashboard every 30 seconds. All output is logged to `/var/log/forge_monitor.log`.

### Example 3: Single Check with JSON Export

```bash
#!/bin/bash
./scripts/monitor-via-api.sh \
    --api-token "your-token" \
    --server-id "12345" \
    --json \
    --once \
    --log /tmp/forge_metrics.json
```

Output:
```json
{
    "timestamp": "2024-11-08T15:30:45Z",
    "server": {
        "id": "12345",
        "name": "production-server",
        "ip_address": "192.168.1.1",
        "size": "2GB",
        "provider": "digitalocean",
        "status": "active",
        "php_version": "8.3"
    },
    "sites": {
        "count": 5,
        "total": 5
    },
    "workers": {
        "count": 2
    },
    "databases": {
        "count": 2
    }
}
```

### Example 4: Slack Alerts for Critical Issues

```bash
#!/bin/bash
SLACK_WEBHOOK="YOUR_SLACK_WEBHOOK_HERE"

./scripts/monitor-via-api.sh \
    --api-token "your-token" \
    --server-id "12345" \
    --slack-webhook "$SLACK_WEBHOOK" \
    --interval 30
```

When an issue is detected (down server, offline database, etc.), a message is sent to Slack:

```
🚨 Forge Monitor Alert - CRITICAL
Server status is offline
```

### Example 5: Scheduled Monitoring via Cron

```bash
# /etc/cron.d/forge-monitor

# Run monitoring check every 5 minutes
*/5 * * * * /home/user/project/scripts/monitor-via-api.sh \
    --api-token "token" \
    --server-id "12345" \
    --log /var/log/forge_monitor.log \
    --once

# Generate daily report
0 0 * * * /home/user/project/scripts/forge-daily-report.sh
```

## Using Helper Functions

The `forge-api-helpers.sh` library provides utility functions for Forge API operations.

### Source the Library

```bash
#!/bin/bash
source ./scripts/forge-api-helpers.sh

# Validate configuration
forge_validate_token
forge_validate_server
```

### Get Information

```bash
# Get all servers
servers=$(forge_get_servers)

# Get specific server
server=$(forge_get_server "12345")

# List all sites
sites=$(forge_get_sites "12345")

# List all databases
databases=$(forge_get_databases "12345")

# Get workers
workers=$(forge_get_workers "12345")
```

### Manage Sites

```bash
# Deploy a site
forge_deploy_site "12345" "5"

# Update PHP version
forge_update_site_php_version "12345" "5" "8.3"

# Get deployment log
log=$(forge_get_site_deployment_log "12345" "5")

# Create new site
forge_create_site "12345" "example.com" "laravel"
```

### Manage Workers

```bash
# Create new worker
forge_create_worker "12345" "5" "my-worker"

# Restart specific worker
forge_restart_worker "12345" "123"

# Restart all workers
forge_restart_all_workers "12345"

# Delete worker
forge_delete_worker "12345" "123"
```

### Manage Databases

```bash
# Create database
forge_create_database "12345" "myapp_db"

# Create database user
forge_create_database_user "12345" "myapp_user" "secure_password"

# List all database users
users=$(forge_get_database_users "12345")
```

### Firewall Management

```bash
# Get firewall rules
rules=$(forge_get_firewall_rules "12345")

# Create rule
forge_create_firewall_rule "12345" "Allow SSH" "22"

# Delete rule
forge_delete_firewall_rule "12345" "rule-id"
```

### Reports and Analysis

```bash
# Generate server report
forge_generate_server_report "12345" "/tmp/report.txt"

# Export server configuration
forge_export_server_config "12345" "server_backup.json"

# Count resources
forge_count_resources "12345"

# List all domains
forge_list_domains "12345"

# Calculate monthly cost
cost=$(forge_estimate_monthly_cost "2GB")
echo "Estimated cost: \$$cost/month"
```

## API Endpoints Used

The monitoring system uses the following Laravel Forge API endpoints:

### Server Endpoints
- `GET /servers` - List all servers
- `GET /servers/{id}` - Get server details
- `POST /servers/{id}/reboot` - Reboot server

### Site Endpoints
- `GET /servers/{id}/sites` - List sites
- `GET /servers/{id}/sites/{site_id}` - Get site details
- `GET /servers/{id}/sites/{site_id}/deployment-log` - Get deployment log
- `GET /servers/{id}/sites/{site_id}/certificates` - Get SSL certificates
- `GET /servers/{id}/sites/{site_id}/env` - Get environment variables
- `POST /servers/{id}/sites/{site_id}/deployment/deploy` - Deploy site

### Database Endpoints
- `GET /servers/{id}/databases` - List databases
- `GET /servers/{id}/database-users` - List database users
- `POST /servers/{id}/databases` - Create database
- `POST /servers/{id}/database-users` - Create user

### Worker Endpoints
- `GET /servers/{id}/workers` - List workers
- `GET /servers/{id}/workers/{worker_id}` - Get worker details
- `POST /servers/{id}/sites/{site_id}/workers` - Create worker
- `POST /servers/{id}/workers/{worker_id}/restart` - Restart worker
- `DELETE /servers/{id}/workers/{worker_id}` - Delete worker

### Other Endpoints
- `GET /servers/{id}/firewall-rules` - List firewall rules
- `GET /servers/{id}/ssh-keys` - List SSH keys
- `GET /servers/{id}/daemons` - List daemons
- `GET /servers/{id}/cron-jobs` - List cron jobs

## Security Best Practices

### 1. Protect Your API Token

```bash
# NEVER commit tokens to git
echo ".env" >> .gitignore
echo "*.token" >> .gitignore

# Store in environment variable
export FORGE_API_TOKEN="your-token-here"

# Or use a .env file (not committed)
# .env
# FORGE_API_TOKEN=your-token-here
# FORGE_SERVER_ID=your-server-id
```

### 2. Rotate Tokens Regularly

- Change API tokens every 90 days
- Revoke old tokens immediately
- Use separate tokens for different environments (staging, production)

### 3. Limit API Permissions

While Forge API tokens have full access, you should:
- Use minimal polling intervals to reduce API calls
- Implement rate limiting in your monitoring scripts
- Monitor API usage regularly

### 4. Secure Slack Webhooks

```bash
# Don't commit webhooks to git
echo "SLACK_WEBHOOK=..." >> .env

# Read from environment
SLACK_WEBHOOK="${SLACK_WEBHOOK}"
```

## Monitoring Thresholds

Configure alert thresholds via environment variables:

```bash
# CPU alert threshold (default: 80%)
export MONITOR_THRESHOLD_CPU=80

# Memory alert threshold (default: 85%)
export MONITOR_THRESHOLD_MEM=85

# Disk alert threshold (default: 90%)
export MONITOR_THRESHOLD_DISK=90
```

## Troubleshooting

### "Token Invalid" Error

```bash
# Verify token is correct
./scripts/forge-api-helpers.sh
forge_validate_token

# Check token hasn't expired
# Regenerate token in Forge dashboard if needed
```

### "Server ID Invalid" Error

```bash
# Verify server ID
forge_validate_server

# Check server still exists in Forge dashboard
./scripts/forge-api-helpers.sh
forge_get_servers
```

### Network Errors

```bash
# Check API endpoint is reachable
curl -I https://forge.laravel.com/api/v1/servers

# Verify proxy settings
echo $http_proxy
echo $https_proxy

# Check firewall/security group rules
```

### No Data Returned

```bash
# Verify API authentication
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://forge.laravel.com/api/v1/servers

# Check if server has any sites/databases
./scripts/forge-api-helpers.sh
forge_count_resources "your-server-id"
```

## Performance Optimization

### 1. Adjust Polling Intervals

```bash
# Less frequent polling (reduce API calls)
./scripts/monitor-via-api.sh --interval 60 --refresh-rate 10

# More frequent polling (more current data)
./scripts/monitor-via-api.sh --interval 10 --refresh-rate 5
```

### 2. Disable Dashboard for Headless Systems

```bash
./scripts/monitor-via-api.sh --no-dashboard --log /var/log/monitor.log
```

### 3. Run in Background

```bash
nohup ./scripts/monitor-via-api.sh --log /var/log/monitor.log &

# Or use systemd
# Create /etc/systemd/system/forge-monitor.service
```

## Systemd Integration

### Create Service File

```bash
sudo tee /etc/systemd/system/forge-monitor.service > /dev/null <<EOF
[Unit]
Description=Forge API Monitoring Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=forge
WorkingDirectory=/home/forge/project
EnvironmentFile=/home/forge/project/.env
ExecStart=/home/forge/project/scripts/monitor-via-api.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

### Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable forge-monitor
sudo systemctl start forge-monitor

# View logs
sudo journalctl -u forge-monitor -f
```

## Integration Examples

### 1. Nagios/Icinga

```bash
#!/bin/bash
# /usr/local/lib/nagios/plugins/check_forge.sh

METRIC=$(./scripts/monitor-via-api.sh --json --once | jq '.server.status')

if [ "$METRIC" = '"active"' ]; then
    echo "OK: Server is active"
    exit 0
else
    echo "CRITICAL: Server is not active"
    exit 2
fi
```

### 2. Prometheus

```bash
#!/bin/bash
# Export metrics in Prometheus format

METRICS=$(./scripts/monitor-via-api.sh --json --once)

echo "forge_server_active{server_id=\"$FORGE_SERVER_ID\"} $(echo "$METRICS" | jq '.server.status == "active"')"
echo "forge_sites_total{server_id=\"$FORGE_SERVER_ID\"} $(echo "$METRICS" | jq '.sites.count')"
echo "forge_workers_total{server_id=\"$FORGE_SERVER_ID\"} $(echo "$METRICS" | jq '.workers.count')"
echo "forge_databases_total{server_id=\"$FORGE_SERVER_ID\"} $(echo "$METRICS" | jq '.databases.count')"
```

### 3. DataDog

```bash
#!/bin/bash
# Send metrics to DataDog

METRICS=$(./scripts/monitor-via-api.sh --json --once)

curl -X POST "https://api.datadoghq.com/api/v1/series" \
  -H "DD-API-KEY: $DATADOG_API_KEY" \
  -d @- <<EOF
{
  "series": [
    {
      "metric": "forge.server.status",
      "points": [[$(date +%s), 1]],
      "tags": ["server_id:$FORGE_SERVER_ID"]
    }
  ]
}
EOF
```

## Cost Analysis

The system tracks VPS costs:

```bash
# Get server size
SERVER=$(./scripts/forge-api-helpers.sh)
SIZE=$(echo "$SERVER" | jq -r '.size')

# Calculate monthly cost
case "$SIZE" in
    "512")      echo "Monthly Cost: \$5.00" ;;
    "1GB")      echo "Monthly Cost: \$10.00" ;;
    "2GB")      echo "Monthly Cost: \$20.00" ;;
    "4GB")      echo "Monthly Cost: \$40.00" ;;
    "8GB")      echo "Monthly Cost: \$80.00" ;;
esac
```

## Advanced Features

### Custom Alert Rules

Extend the `check_alerts()` function in `monitor-via-api.sh`:

```bash
check_alerts() {
    # ... existing code ...

    # Add custom alert
    if [ "$php_version" != "8.3" ]; then
        alerts+=("PHP version is outdated: $php_version")
    fi

    # Check certificate expiry
    if [ "$days_until_expiry" -lt 30 ]; then
        alerts+=("SSL certificate expires in $days_until_expiry days")
    fi
}
```

### Multi-Server Monitoring

```bash
#!/bin/bash
# Monitor multiple servers

SERVERS=("12345" "67890" "11111")

for server_id in "${SERVERS[@]}"; do
    echo "Monitoring Server $server_id..."
    FORGE_SERVER_ID="$server_id" ./scripts/monitor-via-api.sh --once
done
```

## Logs and Reports

### Alert Log Location

```bash
# View alerts
tail -f /tmp/forge_alerts.log

# Alerts are also logged to your custom log file
tail -f /var/log/forge_monitor.log
```

### Metrics Cache

```bash
# View latest metrics
cat /tmp/forge_metrics_cache.json | jq .

# Export metrics
cp /tmp/forge_metrics_cache.json ~/forge_metrics_backup.json
```

## Support and Issues

For API documentation:
- [Laravel Forge API Docs](https://forge.laravel.com/api-documentation)

For monitoring script issues:
1. Enable debug output: `set -x` in the script
2. Check API token and server ID
3. Verify network connectivity
4. Review `/tmp/forge_alerts.log` for errors

## License

These scripts are provided as-is for use with Laravel Forge infrastructure monitoring.
