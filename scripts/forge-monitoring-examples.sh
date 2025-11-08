#!/bin/bash

################################################################################
# Forge API Monitoring Examples
#
# Practical examples demonstrating how to use the Forge API monitoring system
# and helper functions for common infrastructure tasks.
#
# Source this file to use the functions:
#   source ./forge-monitoring-examples.sh
#
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

# Source the helper library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Uncomment when helper file exists
# source "${SCRIPT_DIR}/forge-api-helpers.sh"

################################################################################
# EXAMPLE 1: Production Deployment Monitoring
################################################################################

example_production_deployment() {
    cat << 'EOF'
#!/bin/bash
# Monitor production deployment progress

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="your-token"
FORGE_SERVER_ID="12345"
SITE_ID="5"

echo "Starting production deployment monitoring..."

# Get initial deployment log
INITIAL_LOG=$(forge_get_site_deployment_log "$FORGE_SERVER_ID" "$SITE_ID")
LAST_LINES=$(echo "$INITIAL_LOG" | tail -5)

echo "Recent deployment history:"
echo "$LAST_LINES"

# Monitor for completion
echo ""
echo "Waiting for deployment to complete..."

TIMEOUT=600
ELAPSED=0
CHECK_INTERVAL=5

while [ $ELAPSED -lt $TIMEOUT ]; do
    CURRENT_LOG=$(forge_get_site_deployment_log "$FORGE_SERVER_ID" "$SITE_ID")

    # Check if deployment is complete
    if echo "$CURRENT_LOG" | grep -q "Deployment finished\|completed\|success"; then
        echo "Deployment completed successfully!"
        echo "$CURRENT_LOG" | tail -10
        exit 0
    fi

    # Check for failures
    if echo "$CURRENT_LOG" | grep -q "failed\|error"; then
        echo "Deployment failed!"
        echo "$CURRENT_LOG" | tail -20
        exit 1
    fi

    echo "Still deploying... ($ELAPSED/$TIMEOUT seconds)"
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

echo "Deployment monitoring timeout"
exit 2
EOF
}

################################################################################
# EXAMPLE 2: SSL Certificate Renewal Alert System
################################################################################

example_ssl_monitoring() {
    cat << 'EOF'
#!/bin/bash
# Monitor SSL certificates and alert when renewal is needed

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="your-token"
FORGE_SERVER_ID="12345"
ALERT_THRESHOLD_DAYS=30  # Alert 30 days before expiry

echo "SSL Certificate Monitoring Report"
echo "=================================="
echo "Generated: $(date)"
echo ""

# Get all sites
SITES=$(forge_get_sites "$FORGE_SERVER_ID")
SITE_IDS=$(echo "$SITES" | grep -o '"id":[0-9]*' | cut -d':' -f2)

CRITICAL_COUNT=0
WARNING_COUNT=0

echo "$SITE_IDS" | while read -r SITE_ID; do
    SITE_NAME=$(echo "$SITES" | grep -A5 "\"id\":$SITE_ID" | grep -o '"domain":"[^"]*' | cut -d'"' -f4 | head -1)

    # Get certificates
    CERTS=$(forge_get_site_certificates "$FORGE_SERVER_ID" "$SITE_ID" 2>/dev/null || echo "{}")

    if echo "$CERTS" | grep -q "error\|null"; then
        echo "[WARNING] $SITE_NAME - No certificate found"
        WARNING_COUNT=$((WARNING_COUNT + 1))
        continue
    fi

    # Extract expiry date
    EXPIRES=$(echo "$CERTS" | grep -o '"expires_at":"[^"]*' | head -1 | cut -d'"' -f4)

    if [ -z "$EXPIRES" ]; then
        echo "[INFO] $SITE_NAME - Certificate details not available"
        continue
    fi

    # Calculate days until expiry
    EXPIRES_EPOCH=$(date -d "$EXPIRES" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRES_EPOCH - $NOW_EPOCH) / 86400 ))

    # Determine status
    if [ $DAYS_LEFT -lt 0 ]; then
        echo "[CRITICAL] $SITE_NAME - Certificate EXPIRED $((DAYS_LEFT * -1)) days ago!"
        CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
    elif [ $DAYS_LEFT -lt $ALERT_THRESHOLD_DAYS ]; then
        echo "[WARNING] $SITE_NAME - Certificate expires in $DAYS_LEFT days"
        WARNING_COUNT=$((WARNING_COUNT + 1))
    else
        echo "[OK] $SITE_NAME - Certificate valid for $DAYS_LEFT days"
    fi
done

echo ""
echo "Summary:"
echo "--------"
echo "Critical: $CRITICAL_COUNT"
echo "Warnings: $WARNING_COUNT"

# Exit with appropriate code
if [ $CRITICAL_COUNT -gt 0 ]; then
    exit 2
elif [ $WARNING_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi
EOF
}

################################################################################
# EXAMPLE 3: Queue Worker Health Check
################################################################################

example_worker_health_check() {
    cat << 'EOF'
#!/bin/bash
# Monitor queue workers and restart if needed

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="your-token"
FORGE_SERVER_ID="12345"
CHECK_INTERVAL=60  # Check every 60 seconds

echo "Queue Worker Health Monitor"
echo "============================"

while true; do
    WORKERS=$(forge_get_workers "$FORGE_SERVER_ID")
    WORKER_IDS=$(echo "$WORKERS" | grep -o '"id":[0-9]*' | cut -d':' -f2)

    WORKER_COUNT=$(echo "$WORKER_IDS" | wc -l)
    echo "[$( date )] Found $WORKER_COUNT workers"

    if [ $WORKER_COUNT -eq 0 ]; then
        echo "ERROR: No workers found! This might indicate a problem."
        echo "Alerting support team..."
        # Send alert
        break
    fi

    # Check each worker
    echo "$WORKER_IDS" | while read -r WORKER_ID; do
        WORKER=$(forge_get_worker "$FORGE_SERVER_ID" "$WORKER_ID")

        WORKER_NAME=$(echo "$WORKER" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
        WORKER_STATUS=$(echo "$WORKER" | grep -o '"status":"[^"]*' | cut -d'"' -f4)

        echo "  - $WORKER_NAME: $WORKER_STATUS"

        if [ "$WORKER_STATUS" != "active" ]; then
            echo "  ! Restarting worker: $WORKER_NAME"
            forge_restart_worker "$FORGE_SERVER_ID" "$WORKER_ID"
        fi
    done

    echo "Next check in ${CHECK_INTERVAL}s"
    sleep "$CHECK_INTERVAL"
done
EOF
}

################################################################################
# EXAMPLE 4: Database Backup Status Monitor
################################################################################

example_database_monitoring() {
    cat << 'EOF'
#!/bin/bash
# Monitor database status and connectivity

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="your-token"
FORGE_SERVER_ID="12345"

echo "Database Connectivity Check"
echo "==========================="
echo "Server: $FORGE_SERVER_ID"
echo "Time: $(date)"
echo ""

DATABASES=$(forge_get_databases "$FORGE_SERVER_ID")
DB_IDS=$(echo "$DATABASES" | grep -o '"id":[0-9]*' | cut -d':' -f2)

if [ -z "$DB_IDS" ]; then
    echo "No databases found on server"
    exit 1
fi

HEALTHY=0
UNHEALTHY=0

echo "$DB_IDS" | while read -r DB_ID; do
    DB=$(forge_get_database "$FORGE_SERVER_ID" "$DB_ID")

    DB_NAME=$(echo "$DB" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
    DB_STATUS=$(echo "$DB" | grep -o '"status":"[^"]*' | cut -d'"' -f4 || echo "unknown")

    if [ -z "$DB_STATUS" ] || [ "$DB_STATUS" = "unknown" ]; then
        DB_STATUS="connected"
        HEALTHY=$((HEALTHY + 1))
        STATUS_INDICATOR="✓"
    else
        HEALTHY=$((HEALTHY + 1))
        STATUS_INDICATOR="✓"
    fi

    printf "  %s %-30s Status: %s\n" "$STATUS_INDICATOR" "$DB_NAME" "$DB_STATUS"
done

echo ""
echo "Summary:"
echo "  Healthy: $HEALTHY"
echo "  Unhealthy: $UNHEALTHY"

if [ $UNHEALTHY -eq 0 ]; then
    echo "All databases are healthy!"
    exit 0
else
    echo "Warning: Some databases may have issues"
    exit 1
fi
EOF
}

################################################################################
# EXAMPLE 5: Cost Reporting and Analysis
################################################################################

example_cost_analysis() {
    cat << 'EOF'
#!/bin/bash
# Generate cost analysis report for multiple servers

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="your-token"

echo "Forge Infrastructure Cost Report"
echo "================================="
echo "Generated: $(date)"
echo ""

# Get all servers
SERVERS=$(forge_get_servers)
SERVER_IDS=$(echo "$SERVERS" | grep -o '"id":[0-9]*' | cut -d':' -f2)

TOTAL_MONTHLY_COST=0

echo "Server Details:"
echo "---------------"
printf "%-15s %-25s %-10s %-15s\n" "Server ID" "Name" "Size" "Monthly Cost"
printf "%-15s %-25s %-10s %-15s\n" "$(printf '%.0s-' {1..15})" "$(printf '%.0s-' {1..25})" "$(printf '%.0s-' {1..10})" "$(printf '%.0s-' {1..15})"

echo "$SERVER_IDS" | while read -r SERVER_ID; do
    SERVER=$(forge_get_server "$SERVER_ID")

    SERVER_NAME=$(echo "$SERVER" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
    SERVER_SIZE=$(echo "$SERVER" | grep -o '"size":"[^"]*' | cut -d'"' -f4)

    # Map size to cost
    case "$SERVER_SIZE" in
        "512MB")     COST="5.00" ;;
        "1GB")       COST="10.00" ;;
        "2GB")       COST="20.00" ;;
        "4GB")       COST="40.00" ;;
        "8GB")       COST="80.00" ;;
        "16GB")      COST="160.00" ;;
        *)           COST="0.00" ;;
    esac

    printf "%-15s %-25s %-10s \$%-15s\n" "$SERVER_ID" "$SERVER_NAME" "$SERVER_SIZE" "$COST"
    TOTAL_MONTHLY_COST=$(echo "$TOTAL_MONTHLY_COST + $COST" | bc)
done

echo ""
echo "Total Monthly Cost: \$$TOTAL_MONTHLY_COST"
echo "Total Yearly Cost: \$(echo \"$TOTAL_MONTHLY_COST * 12\" | bc)"
echo ""

echo "Recommendations:"
echo "  - Review underutilized servers"
echo "  - Consider reserved instances for long-term deployments"
echo "  - Evaluate auto-scaling for traffic spikes"
EOF
}

################################################################################
# EXAMPLE 6: Automated PHP Version Upgrade
################################################################################

example_php_upgrade() {
    cat << 'EOF'
#!/bin/bash
# Safely upgrade PHP versions across servers

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="your-token"
FORGE_SERVER_ID="12345"
TARGET_PHP_VERSION="8.3"

echo "PHP Version Upgrade Planning"
echo "============================="
echo "Target Version: $TARGET_PHP_VERSION"
echo ""

SITES=$(forge_get_sites "$FORGE_SERVER_ID")
SITE_IDS=$(echo "$SITES" | grep -o '"id":[0-9]*' | cut -d':' -f2)

echo "Sites that need upgrade:"
echo ""

echo "$SITE_IDS" | while read -r SITE_ID; do
    SITE_NAME=$(echo "$SITES" | grep -A5 "\"id\":$SITE_ID" | grep -o '"domain":"[^"]*' | cut -d'"' -f4 | head -1)
    CURRENT_PHP=$(forge_get_site_php_version "$FORGE_SERVER_ID" "$SITE_ID")

    if [ "$CURRENT_PHP" != "$TARGET_PHP_VERSION" ]; then
        echo "  - $SITE_NAME (Current: $CURRENT_PHP → Target: $TARGET_PHP_VERSION)"

        # Uncomment to actually perform upgrade
        # echo "    Upgrading..."
        # forge_update_site_php_version "$FORGE_SERVER_ID" "$SITE_ID" "$TARGET_PHP_VERSION"
        # sleep 5  # Wait for upgrade to complete
    fi
done

echo ""
echo "Review and test each upgrade before running in production!"
EOF
}

################################################################################
# EXAMPLE 7: Firewall Rule Management
################################################################################

example_firewall_management() {
    cat << 'EOF'
#!/bin/bash
# Manage firewall rules across servers

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="your-token"
FORGE_SERVER_ID="12345"

echo "Firewall Rule Management"
echo "========================"
echo ""

# Get current rules
echo "Current Firewall Rules:"
echo "-----------------------"
RULES=$(forge_get_firewall_rules "$FORGE_SERVER_ID")

if [ -z "$RULES" ] || echo "$RULES" | grep -q "null"; then
    echo "No firewall rules defined"
else
    echo "$RULES" | jq .
fi

echo ""
echo "Add new rule:"
echo "  forge_create_firewall_rule \"$FORGE_SERVER_ID\" \"Allow HTTPS\" \"443\""
echo ""
echo "Delete rule:"
echo "  forge_delete_firewall_rule \"$FORGE_SERVER_ID\" \"rule-id\""
EOF
}

################################################################################
# EXAMPLE 8: Server Configuration Backup
################################################################################

example_configuration_backup() {
    cat << 'EOF'
#!/bin/bash
# Backup server configuration to file

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="your-token"
FORGE_SERVER_ID="12345"
BACKUP_DIR="./backups"

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/server_${FORGE_SERVER_ID}_${TIMESTAMP}.json"

echo "Backing up server configuration..."
echo "Server: $FORGE_SERVER_ID"
echo "Output: $BACKUP_FILE"
echo ""

forge_export_server_config "$FORGE_SERVER_ID" "$BACKUP_FILE"

echo ""
echo "Backup size: $(du -h "$BACKUP_FILE" | cut -f1)"
echo "Backup complete!"
echo ""
echo "Backed up:"
echo "  - Server information"
echo "  - All sites and domains"
echo "  - Database configurations"
echo "  - Queue workers"
echo "  - Firewall rules"
EOF
}

################################################################################
# EXAMPLE 9: Multi-Server Monitoring Dashboard
################################################################################

example_multi_server_dashboard() {
    cat << 'EOF'
#!/bin/bash
# Monitor multiple servers in a single dashboard

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="your-token"
SERVERS=("12345" "67890" "11111")  # Add your server IDs

display_server_summary() {
    local server_id=$1

    echo ""
    echo "Server: $server_id"
    echo "----------------------------"

    local server=$(forge_get_server "$server_id")
    echo "Name: $(echo "$server" | grep -o '"name":"[^"]*' | cut -d'"' -f4)"
    echo "Status: $(echo "$server" | grep -o '"status":"[^"]*' | cut -d'"' -f4)"

    # Count resources
    local count=$(forge_count_resources "$server_id")
    echo "Resources: $count"
}

clear
echo "╔════════════════════════════════════════════════════════════╗"
echo "║      FORGE MULTI-SERVER MONITORING DASHBOARD               ║"
echo "║      Last Updated: $(date '+%Y-%m-%d %H:%M:%S')                   ║"
echo "╚════════════════════════════════════════════════════════════╝"

for server_id in "${SERVERS[@]}"; do
    display_server_summary "$server_id"
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Press Enter to refresh, Ctrl+C to exit..."
read -r

# Loop for continuous monitoring
while true; do
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║      FORGE MULTI-SERVER MONITORING DASHBOARD               ║"
    echo "║      Last Updated: $(date '+%Y-%m-%d %H:%M:%S')                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"

    for server_id in "${SERVERS[@]}"; do
        display_server_summary "$server_id"
    done

    echo ""
    echo "Refreshing in 30 seconds... (Ctrl+C to exit)"
    sleep 30
done
EOF
}

################################################################################
# EXAMPLE 10: Alert Integration with Email
################################################################################

example_email_alerts() {
    cat << 'EOF'
#!/bin/bash
# Send email alerts for critical issues

source ./scripts/forge-api-helpers.sh

FORGE_API_TOKEN="your-token"
FORGE_SERVER_ID="12345"
EMAIL_TO="alerts@example.com"
EMAIL_FROM="forge-monitor@example.com"

send_email_alert() {
    local subject="$1"
    local message="$2"

    echo "Subject: $subject

$message

Sent by Forge Monitoring System
$(date)" | mail -s "$subject" -r "$EMAIL_FROM" "$EMAIL_TO"
}

# Check server status
SERVER=$(forge_get_server "$FORGE_SERVER_ID")
STATUS=$(echo "$SERVER" | grep -o '"status":"[^"]*' | cut -d'"' -f4)

if [ "$STATUS" != "active" ]; then
    send_email_alert \
        "ALERT: Server $FORGE_SERVER_ID is not active" \
        "Server status: $STATUS

Please investigate immediately.

Server ID: $FORGE_SERVER_ID"
    exit 1
fi

# Check for offline workers
WORKERS=$(forge_get_workers "$FORGE_SERVER_ID")
OFFLINE_WORKERS=$(echo "$WORKERS" | grep -o '"status":"[^"]*' | grep -v '"status":"active"' | wc -l)

if [ $OFFLINE_WORKERS -gt 0 ]; then
    send_email_alert \
        "WARNING: $OFFLINE_WORKERS queue workers offline" \
        "Found $OFFLINE_WORKERS offline workers on server $FORGE_SERVER_ID

Please restart them or investigate the cause."
fi

echo "Alert check completed"
EOF
}

################################################################################
# Main Menu
################################################################################

show_examples_menu() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════════════════════╗
║                    FORGE API MONITORING EXAMPLES                          ║
╚════════════════════════════════════════════════════════════════════════════╝

Available Examples:

  1. Production Deployment Monitoring
  2. SSL Certificate Renewal Alert System
  3. Queue Worker Health Check
  4. Database Connectivity Monitoring
  5. Cost Analysis and Reporting
  6. Automated PHP Version Upgrade
  7. Firewall Rule Management
  8. Server Configuration Backup
  9. Multi-Server Monitoring Dashboard
 10. Email Alert Integration

To use an example:

  1. View the script:     ./scripts/forge-monitoring-examples.sh <number>
  2. Copy the example:    ./scripts/forge-monitoring-examples.sh <number> > my_script.sh
  3. Configure:           Edit FORGE_API_TOKEN and FORGE_SERVER_ID
  4. Run:                 bash my_script.sh

Example:
  # View example 1
  ./scripts/forge-monitoring-examples.sh 1

  # Create a standalone script from example 3
  ./scripts/forge-monitoring-examples.sh 3 > worker_monitor.sh
  chmod +x worker_monitor.sh
  FORGE_API_TOKEN="token" FORGE_SERVER_ID="12345" ./worker_monitor.sh

EOF
}

# Handle command-line arguments
if [ $# -eq 0 ]; then
    show_examples_menu
else
    case "$1" in
        1)  example_production_deployment ;;
        2)  example_ssl_monitoring ;;
        3)  example_worker_health_check ;;
        4)  example_database_monitoring ;;
        5)  example_cost_analysis ;;
        6)  example_php_upgrade ;;
        7)  example_firewall_management ;;
        8)  example_configuration_backup ;;
        9)  example_multi_server_dashboard ;;
        10) example_email_alerts ;;
        *)  echo "Unknown example: $1"; show_examples_menu ;;
    esac
fi
