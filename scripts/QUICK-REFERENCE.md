# Forge API Monitoring - Quick Reference Card

Fast lookup guide for common tasks and commands.

## Setup (2 minutes)

```bash
# 1. Get API Token
# Visit: https://forge.laravel.com/user/profile#/api-tokens

# 2. Get Server ID
# From: https://forge.laravel.com/servers/{id}

# 3. Set Environment Variables
export FORGE_API_TOKEN="your-token"
export FORGE_SERVER_ID="your-server-id"

# 4. Test
./scripts/forge-api-helpers.sh
# Output: "Forge API Helper Functions Library Loaded"
```

## Core Commands

### Real-Time Monitoring
```bash
# Start dashboard
./scripts/monitor-via-api.sh

# Single check
./scripts/monitor-via-api.sh --once

# JSON output
./scripts/monitor-via-api.sh --once --json

# With Slack alerts
./scripts/monitor-via-api.sh --slack-webhook "URL"

# Verbose logging
./scripts/monitor-via-api.sh --log /var/log/monitor.log
```

### Helper Functions (source first)
```bash
source ./scripts/forge-api-helpers.sh

# Server
forge_get_servers
forge_get_server "12345"
forge_reboot_server "12345"

# Sites
forge_get_sites "12345"
forge_deploy_site "12345" "5"
forge_get_site_deployment_log "12345" "5"

# Databases
forge_get_databases "12345"
forge_create_database "12345" "dbname"

# Workers
forge_get_workers "12345"
forge_restart_all_workers "12345"

# Reports
forge_export_server_config "12345" "backup.json"
```

### Examples
```bash
# List all examples
./scripts/forge-monitoring-examples.sh

# View example 1 (production deployment)
./scripts/forge-monitoring-examples.sh 1

# Extract to standalone script
./scripts/forge-monitoring-examples.sh 3 > worker_monitor.sh
chmod +x worker_monitor.sh
```

## Common Tasks

### Monitor Deployments
```bash
# In one terminal, start monitoring
./scripts/monitor-via-api.sh

# In another terminal, trigger deployment
source ./scripts/forge-api-helpers.sh
forge_deploy_site "12345" "5"
```

### Check SSL Certificates
```bash
./scripts/forge-monitoring-examples.sh 2
```

### Monitor Workers
```bash
./scripts/forge-monitoring-examples.sh 3
```

### Check Database Status
```bash
./scripts/forge-monitoring-examples.sh 4
```

### Generate Cost Report
```bash
./scripts/forge-monitoring-examples.sh 5
```

### Backup Server Config
```bash
./scripts/forge-monitoring-examples.sh 8
```

## Systemd Setup

```bash
# Run setup wizard (requires sudo)
sudo bash scripts/setup-forge-monitoring-systemd.sh

# Manual setup
sudo systemctl start forge-monitor
sudo systemctl enable forge-monitor

# View status
sudo systemctl status forge-monitor

# View logs
sudo journalctl -u forge-monitor -f

# Stop
sudo systemctl stop forge-monitor
```

## Integration Commands

### Nagios/Icinga Check
```bash
/usr/lib/nagios/plugins/check_forge.sh
```

### Prometheus Export
```bash
curl http://localhost:9200/metrics
```

### Manual Nagios Integration
```bash
./scripts/monitor-via-api.sh --once --json | jq '.server.status'
```

## Options Reference

| Option | Purpose | Example |
|--------|---------|---------|
| `--once` | Single check, no continuous | `--once` |
| `--json` | JSON output format | `--json` |
| `--interval N` | API polling seconds | `--interval 60` |
| `--refresh-rate N` | Dashboard update seconds | `--refresh-rate 5` |
| `--log FILE` | Log file path | `--log /var/log/mon.log` |
| `--slack-webhook URL` | Slack integration | `--slack-webhook "URL"` |
| `--no-dashboard` | Disable dashboard | `--no-dashboard` |
| `--help` | Show help | `--help` |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `FORGE_API_TOKEN` | - | API authentication token |
| `FORGE_SERVER_ID` | - | Server to monitor |
| `FORGE_API_BASE` | https://... | API endpoint |
| `MONITOR_THRESHOLD_CPU` | 80 | CPU alert % |
| `MONITOR_THRESHOLD_MEM` | 85 | Memory alert % |
| `MONITOR_THRESHOLD_DISK` | 90 | Disk alert % |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Token invalid" | Regenerate in Forge dashboard |
| "Server not found" | Check server ID in Forge URL |
| "Connection refused" | Verify API endpoint reachable |
| "No data returned" | Check server has resources |
| "Slow response" | Increase polling interval |
| "Too many requests" | Reduce API call frequency |

## Security Checklist

- [ ] Never commit API tokens to git
- [ ] Use environment variables for secrets
- [ ] Protect .env files (chmod 600)
- [ ] Rotate tokens every 90 days
- [ ] Use separate tokens per environment
- [ ] Monitor API usage regularly
- [ ] Secure Slack webhooks

## File Locations

| File | Purpose |
|------|---------|
| `monitor-via-api.sh` | Main monitoring script |
| `forge-api-helpers.sh` | API functions library |
| `forge-monitoring-examples.sh` | Usage examples |
| `setup-forge-monitoring-systemd.sh` | Service setup |
| `FORGE-MONITORING-GUIDE.md` | Full documentation |
| `README-FORGE-API.md` | Overview guide |
| `QUICK-REFERENCE.md` | This file |
| `/etc/systemd/system/forge-monitor.service` | Service definition |
| `/var/log/forge-monitor/` | Log files |
| `.env.forge-monitor` | Configuration secrets |

## Quick Aliases

Add to `.bashrc` or `.zshrc`:

```bash
alias forge-mon='./scripts/monitor-via-api.sh'
alias forge-status='systemctl status forge-monitor'
alias forge-logs='journalctl -u forge-monitor -f'
alias forge-check='./scripts/check-forge-monitor.sh'
alias forge-dash='./scripts/forge-dashboard.sh'

# With API token and server ID
export FORGE_API_TOKEN="your-token"
export FORGE_SERVER_ID="your-server-id"
```

## One-Liners

```bash
# Get all sites
source scripts/forge-api-helpers.sh && forge_get_sites "12345" | jq '.data[].domain'

# Count workers
source scripts/forge-api-helpers.sh && forge_get_workers "12345" | grep -o '"id"' | wc -l

# Export config
source scripts/forge-api-helpers.sh && forge_export_server_config "12345"

# Check status
./scripts/monitor-via-api.sh --once --json | jq '.server'

# Deploy and monitor
source scripts/forge-api-helpers.sh && \
  forge_deploy_site "12345" "5" && \
  ./scripts/monitor-via-api.sh --interval 10

# All sites status
source scripts/forge-api-helpers.sh && \
  forge_list_domains "12345" | while read d; do \
    echo "Testing $d..."; \
    curl -s -o /dev/null -w "%{http_code}" https://$d; \
    echo ""; \
  done
```

## Cron Scheduling

```bash
# In /etc/cron.d/forge-health-check

# Every 5 minutes
*/5 * * * * user /path/to/scripts/monitor-via-api.sh \
  --once --log /var/log/forge_checks.log

# Hourly report
0 * * * * user /path/to/scripts/monitor-via-api.sh \
  --once --json >> /var/log/forge_hourly.json

# Daily SSL check
0 3 * * * user /path/to/scripts/forge-monitoring-examples.sh 2 \
  >> /var/log/forge_ssl_check.log
```

## API Endpoints

```
Core Endpoints:
  GET /servers/{id}
  GET /servers/{id}/sites
  GET /servers/{id}/databases
  GET /servers/{id}/workers
  GET /servers/{id}/firewall-rules

Deployment:
  GET /servers/{id}/sites/{site_id}/deployment-log
  POST /servers/{id}/sites/{site_id}/deployment/deploy

Certificates:
  GET /servers/{id}/sites/{site_id}/certificates

Monitoring:
  Rate limit: 120 requests/min
  Best practice: 30-60s polling interval
```

## Performance Tips

| Optimization | Benefit |
|--------------|---------|
| Increase polling interval | Reduce API calls |
| Disable dashboard | Lower CPU usage |
| Use JSON output | Faster parsing |
| Batch operations | Fewer requests |
| Filter responses | Reduced bandwidth |
| Cache results | Faster retrieval |

## Help & Docs

```bash
# Show script help
./scripts/monitor-via-api.sh --help

# View full guide
cat scripts/FORGE-MONITORING-GUIDE.md

# View examples
cat scripts/forge-monitoring-examples.sh

# API documentation
# https://forge.laravel.com/api-documentation

# Forge status page
# https://status.forge.laravel.com
```

## Support

For issues or questions:
1. Check `FORGE-MONITORING-GUIDE.md` for detailed documentation
2. Review examples in `forge-monitoring-examples.sh`
3. Test API connectivity: `curl -H "Authorization: Bearer $TOKEN" https://forge.laravel.com/api/v1/servers`
4. Enable debug: Add `set -x` to scripts for verbose output
5. Check logs: `journalctl -u forge-monitor -n 50`

---

**Last Updated**: 2024-11-08
**Status**: Production Ready
**API Version**: v1 (stable)
