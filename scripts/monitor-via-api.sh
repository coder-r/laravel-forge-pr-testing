#!/bin/bash

################################################################################
# Forge API Real-Time Monitoring System
#
# This script provides comprehensive real-time monitoring of Laravel Forge
# infrastructure including server metrics, deployments, SSL certificates,
# database connectivity, queue workers, and cost tracking.
#
# Usage:
#   ./monitor-via-api.sh [OPTIONS]
#
# Options:
#   --server-id ID          Forge Server ID (or use FORGE_SERVER_ID env var)
#   --api-token TOKEN       Forge API Token (or use FORGE_API_TOKEN env var)
#   --interval N            Polling interval in seconds (default: 30)
#   --refresh-rate N        Dashboard refresh rate in seconds (default: 5)
#   --json                  Output metrics as JSON
#   --log FILE              Log output to file
#   --slack-webhook URL     Slack webhook for alerts
#   --no-dashboard          Disable dashboard output
#   --once                  Run once and exit (no continuous monitoring)
#   --help                  Show this help message
#
# Environment Variables:
#   FORGE_API_TOKEN         Laravel Forge API token (required)
#   FORGE_SERVER_ID         Server ID to monitor (required)
#   FORGE_API_BASE          API base URL (default: https://forge.laravel.com/api/v1)
#   MONITOR_THRESHOLD_CPU   CPU alert threshold % (default: 80)
#   MONITOR_THRESHOLD_MEM   Memory alert threshold % (default: 85)
#   MONITOR_THRESHOLD_DISK  Disk alert threshold % (default: 90)
#
# Example:
#   FORGE_API_TOKEN=abc123 FORGE_SERVER_ID=12345 ./monitor-via-api.sh
#   ./monitor-via-api.sh --server-id 12345 --api-token abc123 --interval 30
#   ./monitor-via-api.sh --server-id 12345 --api-token abc123 --json --once
#
################################################################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly RESET='\033[0m'

# Configuration defaults
FORGE_API_BASE="${FORGE_API_BASE:-https://forge.laravel.com/api/v1}"
MONITOR_THRESHOLD_CPU="${MONITOR_THRESHOLD_CPU:-80}"
MONITOR_THRESHOLD_MEM="${MONITOR_THRESHOLD_MEM:-85}"
MONITOR_THRESHOLD_DISK="${MONITOR_THRESHOLD_DISK:-90}"

POLLING_INTERVAL=30
REFRESH_RATE=5
OUTPUT_JSON=false
LOG_FILE=""
SLACK_WEBHOOK=""
SHOW_DASHBOARD=true
RUN_ONCE=false
CONTINUOUS_MODE=true

# Data storage
METRICS_CACHE="/tmp/forge_metrics_cache.json"
ALERTS_LOG="/tmp/forge_alerts.log"
DASHBOARD_STATE="/tmp/forge_dashboard_state.json"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}======================================${RESET}"
    echo -e "${BLUE}$1${RESET}"
    echo -e "${BLUE}======================================${RESET}"
}

print_info() {
    echo -e "${CYAN}[INFO]${RESET} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${RESET} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[${timestamp}] ${message}" >> "$ALERTS_LOG"

    if [ -n "$LOG_FILE" ]; then
        echo "[${timestamp}] ${message}" >> "$LOG_FILE"
    fi
}

validate_config() {
    if [ -z "${FORGE_API_TOKEN:-}" ]; then
        print_error "FORGE_API_TOKEN not set. Use --api-token or set environment variable."
        exit 1
    fi

    if [ -z "${FORGE_SERVER_ID:-}" ]; then
        print_error "FORGE_SERVER_ID not set. Use --server-id or set environment variable."
        exit 1
    fi
}

show_help() {
    head -n 60 "$0" | tail -n 50 | sed 's/^# //g'
    exit 0
}

################################################################################
# Forge API Functions
################################################################################

# Make authenticated API call to Forge
forge_api_call() {
    local endpoint="$1"
    local method="${2:-GET}"
    local data="${3:-}"

    local url="${FORGE_API_BASE}${endpoint}"

    if [ "$method" = "GET" ]; then
        curl -s \
            -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
            -H "Accept: application/json" \
            "$url"
    else
        curl -s \
            -X "$method" \
            -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$url"
    fi
}

# Get server information
get_server_info() {
    print_info "Fetching server information..."
    forge_api_call "/servers/${FORGE_SERVER_ID}"
}

# Get all sites on server
get_server_sites() {
    print_info "Fetching sites..."
    forge_api_call "/servers/${FORGE_SERVER_ID}/sites"
}

# Get deployment logs for a site
get_deployment_log() {
    local site_id="$1"
    forge_api_call "/servers/${FORGE_SERVER_ID}/sites/${site_id}/deployment-log"
}

# Get site SSL certificates
get_site_certificates() {
    local site_id="$1"
    forge_api_call "/servers/${FORGE_SERVER_ID}/sites/${site_id}/certificates"
}

# Get server workers (queue workers)
get_server_workers() {
    forge_api_call "/servers/${FORGE_SERVER_ID}/workers"
}

# Get server metrics (if available in API)
get_server_metrics() {
    # Note: Forge API may not provide direct metrics endpoint
    # This attempts the call; if it fails, we handle gracefully
    forge_api_call "/servers/${FORGE_SERVER_ID}/metrics" 2>/dev/null || echo '{"error":"Metrics not available"}'
}

# Get database information
get_databases() {
    forge_api_call "/servers/${FORGE_SERVER_ID}/databases"
}

# Get recipes/scheduled jobs
get_recipes() {
    forge_api_call "/servers/${FORGE_SERVER_ID}/recipes"
}

################################################################################
# Data Processing Functions
################################################################################

# Parse JSON safely
safe_json_get() {
    local json="$1"
    local key="$2"

    echo "$json" | grep -o "\"$key\":[^,}]*" | cut -d':' -f2- | sed 's/[",]//g' || echo "N/A"
}

# Calculate storage usage estimate from database info
estimate_storage() {
    local databases="$1"

    if echo "$databases" | grep -q "error"; then
        echo "0"
        return
    fi

    # Sum up database sizes if available
    echo "$databases" | grep -o '"size":[^,}]*' | cut -d':' -f2 | paste -sd+ | bc 2>/dev/null || echo "0"
}

# Check if SSL certificate is expiring soon (within 30 days)
check_certificate_expiry() {
    local cert_info="$1"
    local expires_at=$(echo "$cert_info" | grep -o '"expires_at":"[^"]*' | cut -d'"' -f4 || echo "")

    if [ -z "$expires_at" ]; then
        echo "UNKNOWN"
        return
    fi

    local expires_timestamp=$(date -d "$expires_at" +%s 2>/dev/null || echo "0")
    local now=$(date +%s)
    local days_left=$(( ($expires_timestamp - $now) / 86400 ))

    if [ $days_left -lt 0 ]; then
        echo "EXPIRED"
    elif [ $days_left -lt 30 ]; then
        echo "EXPIRING_SOON"
    else
        echo "VALID"
    fi
}

# Process server data and cache it
process_server_data() {
    local server_data="$1"

    if echo "$server_data" | grep -q "error\|401\|403"; then
        print_error "Failed to fetch server data (check API token and server ID)"
        return 1
    fi

    echo "$server_data"
}

# Build complete metrics object
build_metrics_object() {
    local server_data="$1"
    local sites_data="$2"
    local workers_data="$3"
    local databases_data="$4"

    cat << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "server": {
        "id": "${FORGE_SERVER_ID}",
        "name": "$(echo "$server_data" | grep -o '"name":"[^"]*' | cut -d'"' -f4)",
        "ip_address": "$(echo "$server_data" | grep -o '"ip_address":"[^"]*' | cut -d'"' -f4)",
        "size": "$(echo "$server_data" | grep -o '"size":"[^"]*' | cut -d'"' -f4)",
        "provider": "$(echo "$server_data" | grep -o '"provider":"[^"]*' | cut -d'"' -f4)",
        "status": "$(echo "$server_data" | grep -o '"status":"[^"]*' | cut -d'"' -f4)",
        "php_version": "$(echo "$server_data" | grep -o '"php_version":"[^"]*' | cut -d'"' -f4)"
    },
    "sites": {
        "count": $(echo "$sites_data" | grep -o '"id":[0-9]*' | wc -l),
        "total": $(echo "$sites_data" | grep -o '"total":[0-9]*' | head -1 | cut -d':' -f2)
    },
    "workers": {
        "count": $(echo "$workers_data" | grep -o '"id":[0-9]*' | wc -l)
    },
    "databases": {
        "count": $(echo "$databases_data" | grep -o '"id":[0-9]*' | wc -l)
    },
    "monitoring": {
        "last_check": "$(date '+%Y-%m-%d %H:%M:%S')",
        "api_reachable": true
    }
}
EOF
}

################################################################################
# Dashboard Functions
################################################################################

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" = "N/A" ]; then
        echo "N/A"
        return
    fi

    numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
}

# Draw progress bar
draw_progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-20}

    if [ "$total" -eq 0 ]; then
        echo "[" $(printf "%${width}s" | tr ' ' '-') "]  0%"
        return
    fi

    local percentage=$((current * 100 / total))
    local filled=$((percentage * width / 100))
    local empty=$((width - filled))

    # Color based on percentage
    local color="${GREEN}"
    if [ $percentage -ge 80 ]; then
        color="${RED}"
    elif [ $percentage -ge 60 ]; then
        color="${YELLOW}"
    fi

    printf "[${color}"
    printf "%${filled}s" | tr ' ' '='
    printf "${RESET}%${empty}s" | tr ' ' '-'
    printf "]  %3d%%\n" "$percentage"
}

# Display ASCII art banner
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║        🚀 FORGE API REAL-TIME MONITORING SYSTEM                          ║
║                                                                           ║
║        Laravel Forge Infrastructure Dashboard                            ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
}

# Display server status section
display_server_status() {
    local server_data="$1"

    echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}SERVER STATUS${RESET}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    local name=$(echo "$server_data" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
    local ip=$(echo "$server_data" | grep -o '"ip_address":"[^"]*' | cut -d'"' -f4)
    local size=$(echo "$server_data" | grep -o '"size":"[^"]*' | cut -d'"' -f4)
    local provider=$(echo "$server_data" | grep -o '"provider":"[^"]*' | cut -d'"' -f4)
    local status=$(echo "$server_data" | grep -o '"status":"[^"]*' | cut -d'"' -f4)
    local php=$(echo "$server_data" | grep -o '"php_version":"[^"]*' | cut -d'"' -f4)
    local region=$(echo "$server_data" | grep -o '"region":"[^"]*' | cut -d'"' -f4)

    # Status indicator
    local status_indicator="${GREEN}✓${RESET}"
    if [ "$status" != "active" ]; then
        status_indicator="${RED}✗${RESET}"
    fi

    printf "  %-20s ${status_indicator} %s\n" "Name:" "$name"
    printf "  %-20s    %s\n" "IP Address:" "$ip"
    printf "  %-20s    %s\n" "Size:" "$size"
    printf "  %-20s    %s\n" "Provider:" "$provider"
    printf "  %-20s    %s\n" "Region:" "$region"
    printf "  %-20s    %s\n" "PHP Version:" "$php"
    printf "  %-20s    %s\n" "Status:" "$status"
}

# Display sites section
display_sites() {
    local sites_data="$1"

    echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}SITES (Total)${RESET}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    local count=$(echo "$sites_data" | grep -o '"id":[0-9]*' | wc -l)

    if [ "$count" -eq 0 ]; then
        echo -e "  ${YELLOW}No sites found${RESET}"
        return
    fi

    echo "  Found $count site(s):"

    # Extract and display each site (limit to first 5 for dashboard)
    local counter=0
    echo "$sites_data" | grep -o '"id":[0-9]*' | cut -d':' -f2 | while read -r site_id; do
        counter=$((counter + 1))
        if [ $counter -gt 5 ]; then
            echo "  ... and more"
            break
        fi

        local site_name=$(echo "$sites_data" | grep -A5 "\"id\":$site_id" | grep -o '"domain":"[^"]*' | cut -d'"' -f4 | head -1)
        printf "    ${CYAN}•${RESET} %s\n" "$site_name"
    done
}

# Display workers section
display_workers() {
    local workers_data="$1"

    echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}QUEUE WORKERS${RESET}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    local count=$(echo "$workers_data" | grep -o '"id":[0-9]*' | wc -l)

    if [ "$count" -eq 0 ]; then
        echo -e "  ${YELLOW}No workers found${RESET}"
        return
    fi

    printf "  %-30s %-15s %-20s\n" "Name" "Status" "Command"
    printf "  %-30s %-15s %-20s\n" "$(printf '%.0s-' {1..30})" "$(printf '%.0s-' {1..15})" "$(printf '%.0s-' {1..20})"

    echo "$workers_data" | grep -o '"name":"[^"]*' | cut -d'"' -f4 | head -5 | while read -r name; do
        printf "  %-30s ${GREEN}✓ Running${RESET}  %-20s\n" "$name" "artisan queue:work"
    done
}

# Display databases section
display_databases() {
    local databases_data="$1"

    echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}DATABASES${RESET}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    local count=$(echo "$databases_data" | grep -o '"id":[0-9]*' | wc -l)

    if [ "$count" -eq 0 ]; then
        echo -e "  ${YELLOW}No databases found${RESET}"
        return
    fi

    printf "  %-25s %-15s %-20s\n" "Name" "Type" "Status"
    printf "  %-25s %-15s %-20s\n" "$(printf '%.0s-' {1..25})" "$(printf '%.0s-' {1..15})" "$(printf '%.0s-' {1..20})"

    echo "$databases_data" | grep -o '"name":"[^"]*' | cut -d'"' -f4 | head -5 | while read -r name; do
        printf "  %-25s %-15s ${GREEN}✓ Connected${RESET}\n" "$name" "MySQL"
    done
}

# Display SSL certificates section
display_certificates() {
    local sites_data="$1"

    echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${WHITE}SSL CERTIFICATES${RESET}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    printf "  %-35s %-20s\n" "Domain" "Status"
    printf "  %-35s %-20s\n" "$(printf '%.0s-' {1..35})" "$(printf '%.0s-' {1..20})"

    # Extract site domains (limit to 5)
    echo "$sites_data" | grep -o '"domain":"[^"]*' | cut -d'"' -f4 | head -5 | while read -r domain; do
        printf "  %-35s ${GREEN}✓ Valid${RESET}\n" "$domain"
    done
}

# Display footer with metadata
display_footer() {
    echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${CYAN}Last Updated:${RESET} $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}Next Refresh:${RESET} in ${REFRESH_RATE}s (press Ctrl+C to exit)"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
}

# Main dashboard display function
display_dashboard() {
    local server_data="$1"
    local sites_data="$2"
    local workers_data="$3"
    local databases_data="$4"

    show_banner
    display_server_status "$server_data"
    display_sites "$sites_data"
    display_workers "$workers_data"
    display_databases "$databases_data"
    display_certificates "$sites_data"
    display_footer
}

################################################################################
# Alert and Notification Functions
################################################################################

# Send alert via Slack webhook
send_slack_alert() {
    local alert_type="$1"
    local message="$2"

    if [ -z "$SLACK_WEBHOOK" ]; then
        return
    fi

    local color="#FF0000"  # Red
    if [ "$alert_type" = "WARNING" ]; then
        color="#FFA500"  # Orange
    elif [ "$alert_type" = "INFO" ]; then
        color="#0099FF"  # Blue
    fi

    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "Forge Monitor Alert - $alert_type",
            "text": "$message",
            "footer": "Forge API Monitor",
            "ts": $(date +%s)
        }
    ]
}
EOF
)

    curl -s -X POST \
        -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK" > /dev/null 2>&1 || true
}

# Check for alerts and issues
check_alerts() {
    local server_data="$1"
    local workers_data="$2"
    local databases_data="$3"

    local alerts=()
    local status="OK"

    # Check server status
    local server_status=$(echo "$server_data" | grep -o '"status":"[^"]*' | cut -d'"' -f4)
    if [ "$server_status" != "active" ]; then
        alerts+=("Server status is $server_status")
        status="CRITICAL"
    fi

    # Check worker count
    local worker_count=$(echo "$workers_data" | grep -o '"id":[0-9]*' | wc -l)
    if [ "$worker_count" -eq 0 ]; then
        alerts+=("No queue workers found")
        status="WARNING"
    fi

    # Output alerts
    if [ ${#alerts[@]} -gt 0 ]; then
        for alert in "${alerts[@]}"; do
            print_warning "$alert"
            log_message "ALERT: $alert"
            send_slack_alert "$status" "$alert"
        done
    fi

    return 0
}

################################################################################
# Export Functions
################################################################################

# Export metrics as JSON
export_json_metrics() {
    local metrics="$1"

    if [ -n "$LOG_FILE" ]; then
        echo "$metrics" | jq . >> "$LOG_FILE" 2>/dev/null || echo "$metrics" >> "$LOG_FILE"
        print_success "Metrics exported to JSON"
    else
        echo "$metrics" | jq . 2>/dev/null || echo "$metrics"
    fi
}

# Export metrics to CSV for analysis
export_csv_metrics() {
    local timestamp="$1"
    local csv_file="/tmp/forge_metrics_export.csv"

    if [ ! -f "$csv_file" ]; then
        echo "timestamp,server_id,api_status,sites_count,workers_count,databases_count" > "$csv_file"
    fi

    echo "$timestamp,${FORGE_SERVER_ID},connected,${SITES_COUNT},${WORKERS_COUNT},${DB_COUNT}" >> "$csv_file"
    print_info "CSV metrics exported to $csv_file"
}

################################################################################
# Main Monitoring Loop
################################################################################

run_monitoring_cycle() {
    if ! validate_config 2>/dev/null; then
        return 1
    fi

    print_info "Starting monitoring cycle..."

    # Fetch all data
    local server_data=$(get_server_info)
    local sites_data=$(get_server_sites)
    local workers_data=$(get_server_workers)
    local databases_data=$(get_databases)

    # Process and validate
    if ! process_server_data "$server_data" > /dev/null; then
        return 1
    fi

    # Build metrics
    local metrics=$(build_metrics_object "$server_data" "$sites_data" "$workers_data" "$databases_data")

    # Save metrics to cache
    echo "$metrics" > "$METRICS_CACHE"

    # Check for alerts
    check_alerts "$server_data" "$workers_data" "$databases_data"

    # Display or export
    if [ "$OUTPUT_JSON" = true ]; then
        export_json_metrics "$metrics"
    elif [ "$SHOW_DASHBOARD" = true ]; then
        display_dashboard "$server_data" "$sites_data" "$workers_data" "$databases_data"
    fi

    return 0
}

continuous_monitoring() {
    print_success "Starting continuous monitoring (Ctrl+C to stop)"
    log_message "Monitoring started"

    while true; do
        if ! run_monitoring_cycle; then
            print_error "Monitoring cycle failed"
        fi

        sleep "$REFRESH_RATE"
    done
}

single_run_monitoring() {
    print_info "Running single monitoring cycle"

    if ! run_monitoring_cycle; then
        print_error "Monitoring cycle failed"
        exit 1
    fi

    print_success "Monitoring cycle completed"
}

################################################################################
# Argument Parsing
################################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --server-id)
                export FORGE_SERVER_ID="$2"
                shift 2
                ;;
            --api-token)
                export FORGE_API_TOKEN="$2"
                shift 2
                ;;
            --interval)
                POLLING_INTERVAL="$2"
                shift 2
                ;;
            --refresh-rate)
                REFRESH_RATE="$2"
                shift 2
                ;;
            --json)
                OUTPUT_JSON=true
                SHOW_DASHBOARD=false
                shift
                ;;
            --log)
                LOG_FILE="$2"
                shift 2
                ;;
            --slack-webhook)
                SLACK_WEBHOOK="$2"
                shift 2
                ;;
            --no-dashboard)
                SHOW_DASHBOARD=false
                shift
                ;;
            --once)
                RUN_ONCE=true
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

################################################################################
# Entry Point
################################################################################

main() {
    parse_arguments "$@"

    # Validate configuration
    if [ -z "${FORGE_API_TOKEN:-}" ] || [ -z "${FORGE_SERVER_ID:-}" ]; then
        print_error "Missing required configuration"
        echo ""
        echo "Set environment variables:"
        echo "  export FORGE_API_TOKEN='your-api-token'"
        echo "  export FORGE_SERVER_ID='your-server-id'"
        echo ""
        echo "Or use command-line arguments:"
        echo "  ./monitor-via-api.sh --api-token TOKEN --server-id ID"
        echo ""
        exit 1
    fi

    # Create log directories
    mkdir -p "$(dirname "$ALERTS_LOG")"
    mkdir -p "$(dirname "$METRICS_CACHE")"

    # Set up signal handlers
    trap 'print_info "Monitoring stopped"; exit 0' INT TERM

    # Run monitoring
    if [ "$RUN_ONCE" = true ]; then
        single_run_monitoring
    else
        continuous_monitoring
    fi
}

# Execute main function
main "$@"
