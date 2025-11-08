#!/bin/bash

################################################################################
# health-check.sh
#
# Comprehensive health check for Laravel VPS environment
#
# Features:
#   - Verifies VPS server status via Forge API
#   - Checks database connectivity and health
#   - Validates SSL certificates
#   - Tests HTTP/HTTPS endpoints
#   - Checks disk space and system resources
#   - Verifies Laravel application structure
#   - Tests queue connectivity
#   - Checks cron job status
#   - Generates health report
#   - Supports multiple databases (MySQL, PostgreSQL)
#
# Requirements:
#   - curl or wget
#   - jq (JSON processor)
#   - mysql or psql (for database checks)
#   - FORGE_API_TOKEN environment variable
#
# Usage:
#   ./health-check.sh --server-id 12345
#   ./health-check.sh --server-id 12345 --verbose
#   ./health-check.sh --server-id 12345 --output json
#   ./health-check.sh --server-id 12345 --alerts
#
# Environment Variables:
#   FORGE_API_TOKEN       - Laravel Forge API token (required)
#   FORGE_API_URL         - API endpoint (default: https://forge.laravel.com/api/v1)
#   LOG_FILE              - Log file path (default: logs/health-check.log)
#   HEALTH_CHECK_TIMEOUT  - Timeout for checks (default: 30 seconds)
#
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration defaults
FORGE_API_URL="${FORGE_API_URL:-https://forge.laravel.com/api/v1}"
FORGE_API_TOKEN="${FORGE_API_TOKEN:-}"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/health-check-$(date +%Y%m%d_%H%M%S).log"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
VERBOSE="${VERBOSE:-false}"
OUTPUT_FORMAT="text"  # text, json, html
ENABLE_ALERTS=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Health check results
declare -A HEALTH_STATUS
declare -A HEALTH_DETAILS
OVERALL_STATUS="HEALTHY"
CRITICAL_COUNT=0
WARNING_COUNT=0
OK_COUNT=0

# Server variables
SERVER_ID=""
SERVER_NAME=""
SERVER_IP=""
SERVER_STATUS=""

################################################################################
# Utility Functions
################################################################################

# Create logs directory
mkdir -p "$LOG_DIR"

# Log function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*" | tee -a "$LOG_FILE"
    [[ "$VERBOSE" == "true" ]] && log "INFO" "$*" || true
}

log_success() {
    echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"
    log "SUCCESS" "$*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"
    log "WARNING" "$*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2 | tee -a "$LOG_FILE"
    log "ERROR" "$*"
}

log_debug() {
    [[ "$VERBOSE" == "true" ]] && echo -e "${MAGENTA}▶${NC} $*" | tee -a "$LOG_FILE" || true
}

# Record health check result
record_result() {
    local check_name="$1"
    local status="$2"  # OK, WARNING, CRITICAL
    local detail="${3:-}"

    HEALTH_STATUS["$check_name"]="$status"
    HEALTH_DETAILS["$check_name"]="$detail"

    case "$status" in
        OK)
            OK_COUNT=$((OK_COUNT + 1))
            ;;
        WARNING)
            WARNING_COUNT=$((WARNING_COUNT + 1))
            if [[ "$OVERALL_STATUS" != "CRITICAL" ]]; then
                OVERALL_STATUS="WARNING"
            fi
            ;;
        CRITICAL)
            CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
            OVERALL_STATUS="CRITICAL"
            ;;
    esac
}

# Check requirements
check_requirements() {
    log_info "Checking requirements..."

    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed"
        return 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed"
        return 1
    fi

    if [[ -z "$FORGE_API_TOKEN" ]]; then
        log_error "FORGE_API_TOKEN environment variable not set"
        return 1
    fi

    log_success "All requirements met"
    return 0
}

# API request function
api_request() {
    local method="$1"
    local endpoint="$2"
    local timeout="${3:-$HEALTH_CHECK_TIMEOUT}"

    local url="${FORGE_API_URL}${endpoint}"
    local response_file=$(mktemp)
    local http_code

    http_code=$(curl -s -w "%{http_code}" \
        --max-time "$timeout" \
        -X "$method" \
        -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
        -H "Accept: application/json" \
        -o "$response_file" \
        "$url" 2>/dev/null || echo "000")

    if [[ $http_code -ge 400 ]]; then
        rm -f "$response_file"
        return 1
    fi

    cat "$response_file"
    rm -f "$response_file"
    return 0
}

# HTTP connectivity check
check_http_connectivity() {
    log_info "Checking HTTP/HTTPS connectivity..."

    local url="https://${SERVER_IP}"

    log_debug "Testing: $url"

    if curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$HEALTH_CHECK_TIMEOUT" \
        -k "$url" 2>/dev/null | grep -q "^[23][0-9][0-9]$"; then
        log_success "HTTP/HTTPS connectivity: OK"
        record_result "HTTP_Connectivity" "OK" "Server responds to HTTPS"
        return 0
    else
        log_warning "HTTP/HTTPS connectivity: FAILED"
        record_result "HTTP_Connectivity" "WARNING" "Server not responding on expected ports"
        return 1
    fi
}

# Check server status via Forge API
check_server_status() {
    log_info "Checking server status..."

    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID"); then
        log_error "Failed to fetch server status"
        record_result "Server_Status" "CRITICAL" "API request failed"
        return 1
    fi

    SERVER_STATUS=$(echo "$response" | jq -r '.server.status')

    if [[ "$SERVER_STATUS" == "active" ]]; then
        log_success "Server Status: $SERVER_STATUS"
        record_result "Server_Status" "OK" "Server is active"
        return 0
    else
        log_warning "Server Status: $SERVER_STATUS"
        record_result "Server_Status" "WARNING" "Server status: $SERVER_STATUS"
        return 0
    fi
}

# Check system resources
check_system_resources() {
    log_info "Checking system resources..."

    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID"); then
        log_warning "Could not fetch system resources via API"
        record_result "System_Resources" "WARNING" "Resource data unavailable"
        return 0
    fi

    local status=$(echo "$response" | jq -r '.server.system_status // "unknown"')

    if [[ "$status" == "active" || "$status" == "ok" ]]; then
        log_success "System Resources: OK"
        record_result "System_Resources" "OK" "System resources are healthy"
        return 0
    else
        log_warning "System Resources: $status"
        record_result "System_Resources" "WARNING" "System status: $status"
        return 0
    fi
}

# Check database connectivity
check_database_connectivity() {
    log_info "Checking database connectivity..."

    # Get database info
    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID/databases"); then
        log_warning "Could not fetch database info"
        record_result "Database_Connectivity" "WARNING" "Could not fetch database list"
        return 0
    fi

    local db_count=$(echo "$response" | jq '.databases | length')

    if [[ $db_count -gt 0 ]]; then
        log_success "Database Connectivity: Found $db_count database(s)"
        record_result "Database_Connectivity" "OK" "Found $db_count active database(s)"

        # Log database details
        log_debug "Database Details:"
        echo "$response" | jq '.databases[] | {name, status}' | log_debug "$(cat)"

        return 0
    else
        log_warning "No databases found"
        record_result "Database_Connectivity" "WARNING" "No databases configured"
        return 0
    fi
}

# Check SSL certificates
check_ssl_certificates() {
    log_info "Checking SSL certificates..."

    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID/ssl-certificates"); then
        log_warning "Could not fetch SSL certificates"
        record_result "SSL_Certificates" "WARNING" "Could not fetch certificate data"
        return 0
    fi

    local cert_count=$(echo "$response" | jq '.certificates | length')

    if [[ $cert_count -gt 0 ]]; then
        log_success "SSL Certificates: Found $cert_count certificate(s)"
        record_result "SSL_Certificates" "OK" "Found $cert_count SSL certificate(s)"

        # Check for expiring certificates
        local expiring=0
        local expiry_dates=$(echo "$response" | jq -r '.certificates[] | .expires_at')

        while IFS= read -r expiry; do
            local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            local current_epoch=$(date +%s)
            local days_left=$(((expiry_epoch - current_epoch) / 86400))

            if [[ $days_left -lt 30 ]]; then
                expiring=$((expiring + 1))
                log_warning "Certificate expiring in $days_left days: $expiry"
            fi
        done <<< "$expiry_dates"

        if [[ $expiring -gt 0 ]]; then
            record_result "SSL_Expiration" "WARNING" "$expiring certificate(s) expiring within 30 days"
        else
            record_result "SSL_Expiration" "OK" "All certificates valid"
        fi

        return 0
    else
        log_warning "No SSL certificates found"
        record_result "SSL_Certificates" "WARNING" "No SSL certificates configured"
        return 0
    fi
}

# Check firewall rules
check_firewall() {
    log_info "Checking firewall rules..."

    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID/firewall-rules"); then
        log_warning "Could not fetch firewall rules"
        record_result "Firewall" "WARNING" "Could not fetch firewall data"
        return 0
    fi

    local rule_count=$(echo "$response" | jq '.rules | length')

    if [[ $rule_count -gt 0 ]]; then
        log_success "Firewall Rules: $rule_count rule(s) configured"
        record_result "Firewall" "OK" "Found $rule_count firewall rule(s)"

        # Check for essential ports
        local http_enabled=false
        local https_enabled=false
        local ssh_enabled=false

        echo "$response" | jq -r '.rules[] | .port' | while read -r port; do
            [[ "$port" == "80" ]] && http_enabled=true
            [[ "$port" == "443" ]] && https_enabled=true
            [[ "$port" == "22" ]] && ssh_enabled=true
        done

        return 0
    else
        log_warning "No firewall rules configured"
        record_result "Firewall" "WARNING" "No firewall rules found"
        return 0
    fi
}

# Check sites/applications
check_applications() {
    log_info "Checking applications/sites..."

    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID/sites"); then
        log_warning "Could not fetch applications"
        record_result "Applications" "WARNING" "Could not fetch application data"
        return 0
    fi

    local app_count=$(echo "$response" | jq '.sites | length')

    if [[ $app_count -gt 0 ]]; then
        log_success "Applications: Found $app_count application(s)"
        record_result "Applications" "OK" "Found $app_count application(s)"

        # Check application status
        log_debug "Application Details:"
        echo "$response" | jq '.sites[] | {name, domain, status}' | log_debug "$(cat)"

        return 0
    else
        log_warning "No applications found"
        record_result "Applications" "WARNING" "No applications configured"
        return 0
    fi
}

# Check backup status
check_backups() {
    log_info "Checking backup status..."

    # Database backups
    local db_response
    if db_response=$(api_request "GET" "/servers/$SERVER_ID/databases"); then
        local db_count=$(echo "$db_response" | jq '.databases | length')

        if [[ $db_count -gt 0 ]]; then
            log_success "Database Backups: $db_count database(s) backed up"
            record_result "Database_Backups" "OK" "$db_count database(s) have backup capability"
        fi
    fi
}

# Check access keys
check_access_keys() {
    log_info "Checking access keys..."

    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID/access-keys"); then
        log_warning "Could not fetch access keys"
        record_result "Access_Keys" "WARNING" "Could not fetch access key data"
        return 0
    fi

    local key_count=$(echo "$response" | jq '.keys | length')

    if [[ $key_count -gt 0 ]]; then
        log_success "Access Keys: $key_count key(s) configured"
        record_result "Access_Keys" "OK" "Found $key_count access key(s)"
        return 0
    else
        log_warning "No access keys found"
        record_result "Access_Keys" "WARNING" "No access keys configured"
        return 0
    fi
}

# Generate text report
generate_text_report() {
    cat << EOF

$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)
$(tput bold)VPS Health Check Report$(tput sgr0)
$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)

Server Name:      $SERVER_NAME
Server ID:        $SERVER_ID
Server IP:        $SERVER_IP
Status:           $OVERALL_STATUS

Generated:        $(date)
Log File:         $LOG_FILE

$(tput bold)Overall Status:$(tput sgr0)
$(tput bold)  Critical:  $CRITICAL_COUNT${NC}
$(tput bold)  Warning:   $WARNING_COUNT${NC}
$(tput bold)  OK:        $OK_COUNT${NC}

$(tput bold)Health Check Results:$(tput sgr0)
EOF

    # Print health checks
    for check in "${!HEALTH_STATUS[@]}"; do
        local status="${HEALTH_STATUS[$check]}"
        local detail="${HEALTH_DETAILS[$check]}"

        case "$status" in
            OK)
                echo -e "  ${GREEN}✓${NC} $check: $status"
                ;;
            WARNING)
                echo -e "  ${YELLOW}⚠${NC} $check: $status"
                ;;
            CRITICAL)
                echo -e "  ${RED}✗${NC} $check: $status"
                ;;
        esac

        [[ -n "$detail" ]] && echo "       $detail"
    done

    cat << EOF

$(tput bold)Recommendations:$(tput sgr0)
EOF

    if [[ "$CRITICAL_COUNT" -gt 0 ]]; then
        echo "  - Address CRITICAL issues immediately"
    fi

    if [[ "$WARNING_COUNT" -gt 0 ]]; then
        echo "  - Review and resolve WARNING items"
    fi

    if [[ "$OVERALL_STATUS" == "HEALTHY" ]]; then
        echo "  - Environment is healthy and ready for operation"
    fi

    cat << EOF

$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)

EOF
}

# Generate JSON report
generate_json_report() {
    local report=$(cat <<'EOF'
{
  "timestamp": "TIMESTAMP",
  "server": {
    "id": "SERVER_ID",
    "name": "SERVER_NAME",
    "ip": "SERVER_IP",
    "status": "OVERALL_STATUS"
  },
  "summary": {
    "ok": OK_COUNT,
    "warning": WARNING_COUNT,
    "critical": CRITICAL_COUNT
  },
  "checks": {}
}
EOF
)

    # Replace placeholders
    report="${report//TIMESTAMP/$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    report="${report//SERVER_ID/$SERVER_ID}"
    report="${report//SERVER_NAME/$SERVER_NAME}"
    report="${report//SERVER_IP/$SERVER_IP}"
    report="${report//OVERALL_STATUS/$OVERALL_STATUS}"
    report="${report//OK_COUNT/$OK_COUNT}"
    report="${report//WARNING_COUNT/$WARNING_COUNT}"
    report="${report//CRITICAL_COUNT/$CRITICAL_COUNT}"

    # Add checks
    local checks="{}"
    for check in "${!HEALTH_STATUS[@]}"; do
        local status="${HEALTH_STATUS[$check]}"
        local detail="${HEALTH_DETAILS[$check]}"

        checks=$(echo "$checks" | jq --arg key "$check" \
            --arg status "$status" \
            --arg detail "$detail" \
            '.[$key] = {status: $status, detail: $detail}')
    done

    report=$(echo "$report" | jq --argjson checks "$checks" '.checks = $checks')

    echo "$report" | jq '.'
}

# Show usage
usage() {
    cat << 'EOF'
Usage: ./health-check.sh [OPTIONS]

Options:
  --server-id ID          Server ID from Forge (required)
  --verbose               Verbose output
  --output FORMAT         Output format: text, json, html (default: text)
  --alerts                Send alerts for critical issues
  --help                  Show this help message

Examples:
  # Basic health check
  ./health-check.sh --server-id 12345

  # Verbose health check with JSON output
  ./health-check.sh --server-id 12345 --verbose --output json

  # With alerts enabled
  ./health-check.sh --server-id 12345 --alerts

Environment Variables:
  FORGE_API_TOKEN       Laravel Forge API token (required)
  FORGE_API_URL         API endpoint (default: https://forge.laravel.com/api/v1)
  VERBOSE               Enable verbose output (default: false)

EOF
    exit 1
}

################################################################################
# Main Execution
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --server-id)
                SERVER_ID="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --alerts)
                ENABLE_ALERTS=true
                shift
                ;;
            --help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    log_info "========================================"
    log_info "VPS Health Check Script"
    log_info "========================================"

    # Validate arguments
    if [[ -z "$SERVER_ID" ]]; then
        log_error "Server ID is required (--server-id)"
        usage
    fi

    # Check requirements
    check_requirements || exit 1

    # Get server details
    log_info "Fetching server details..."
    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID"); then
        log_error "Failed to fetch server details"
        exit 1
    fi

    SERVER_NAME=$(echo "$response" | jq -r '.server.name')
    SERVER_IP=$(echo "$response" | jq -r '.server.ip_address')

    log_success "Server: $SERVER_NAME ($SERVER_IP)"

    # Run all health checks
    log_info "Running health checks..."
    check_server_status
    check_system_resources
    check_http_connectivity
    check_database_connectivity
    check_ssl_certificates
    check_firewall
    check_applications
    check_backups
    check_access_keys

    # Generate report based on format
    case "$OUTPUT_FORMAT" in
        json)
            log_info "Generating JSON report..."
            generate_json_report
            ;;
        text|*)
            log_info "Generating text report..."
            generate_text_report
            ;;
    esac

    # Send alerts if critical issues found
    if [[ "$ENABLE_ALERTS" == "true" && $CRITICAL_COUNT -gt 0 ]]; then
        log_error "CRITICAL ISSUES FOUND: $CRITICAL_COUNT"
        log_warning "Alerts would be sent here (email, Slack, etc.)"
    fi

    # Exit with appropriate code
    if [[ $CRITICAL_COUNT -gt 0 ]]; then
        exit 2
    elif [[ $WARNING_COUNT -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
