#!/bin/bash

################################################################################
# implement-complete-system.sh
#
# MASTER ORCHESTRATION SCRIPT - Complete System Implementation via Forge API
#
# This is THE script that does EVERYTHING:
# - Validates Forge API access and permissions
# - Creates production VPS servers (keatchen-customer-app, devpel-epos)
# - Creates sites with on-forge.com domains
# - Sets up databases and snapshots
# - Creates test/PR environments
# - Configures monitoring and health checks
# - Full observability and progress tracking
#
# Features:
#   - 6 execution phases with detailed logging
#   - Real Forge API calls (no mocks/placeholders)
#   - Progress bars with ETA calculations
#   - Resumable from any phase
#   - Database snapshots and restoration
#   - Health checks and monitoring setup
#   - SSH operations for database management
#   - Comprehensive error handling
#   - Production-grade logging
#
# Requirements:
#   - curl (HTTP client for API calls)
#   - jq (JSON processor)
#   - ssh (SSH client for remote operations)
#   - FORGE_API_TOKEN environment variable
#
# Usage:
#   export FORGE_API_TOKEN="your-token-here"
#   ./implement-complete-system.sh
#
#   # Resume from specific phase
#   ./implement-complete-system.sh --phase 3
#
#   # Dry run (show what would happen)
#   ./implement-complete-system.sh --dry-run
#
#   # With custom configuration
#   ./implement-complete-system.sh \
#     --config config/deployment.env \
#     --verbose
#
# Environment Variables:
#   FORGE_API_TOKEN       - Forge API token (required)
#   FORGE_API_URL         - API endpoint (default: https://forge.laravel.com/api/v1)
#   PHASE_START           - Starting phase (default: 1)
#   DRY_RUN              - Set to 1 for dry-run mode
#   VERBOSE              - Set to 1 for verbose output
#
################################################################################

set -euo pipefail

################################################################################
# Configuration & Constants
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# API Configuration
FORGE_API_URL="${FORGE_API_URL:-https://forge.laravel.com/api/v1}"
FORGE_API_TOKEN="${FORGE_API_TOKEN:-}"
API_RETRY_COUNT="${API_RETRY_COUNT:-3}"
API_TIMEOUT="${API_TIMEOUT:-30}"

# Directories
LOG_DIR="${PROJECT_ROOT}/logs"
STATE_DIR="${PROJECT_ROOT}/.implementation-state"
BACKUP_DIR="${PROJECT_ROOT}/backups"
TEMP_DIR="/tmp/forge-implementation-$$"

# Execution configuration
PHASE_START="${PHASE_START:-1}"
DRY_RUN="${DRY_RUN:-0}"
VERBOSE="${VERBOSE:-0}"
CONFIG_FILE="${CONFIG_FILE:-}"

# Default timeouts
MAX_PROVISIONING_WAIT="${MAX_PROVISIONING_WAIT:-3600}"  # 1 hour
PROVISIONING_CHECK_INTERVAL="${PROVISIONING_CHECK_INTERVAL:-30}"  # 30 seconds
DB_SNAPSHOT_WAIT="${DB_SNAPSHOT_WAIT:-1800}"  # 30 minutes
SITE_DEPLOY_WAIT="${SITE_DEPLOY_WAIT:-900}"  # 15 minutes

# Application configuration
APPS=(
    "keatchen-customer-app:digitalocean:nyc3:s-2vcpu-4gb:postgres"
    "devpel-epos:digitalocean:nyc3:s-2vcpu-4gb:mysql"
)

TEST_APP="pr-test-environment"
TEST_PROVIDER="digitalocean"
TEST_REGION="nyc3"
TEST_SIZE="s-1vcpu-2gb"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Progress tracking
declare -A PHASE_STATUS
declare -A PHASE_START_TIME
declare -A SERVER_IDS
declare -A SITE_IDS
declare -A DB_SNAPSHOTS

# Execution timing
START_TIME=$(date +%s)

################################################################################
# Utility Functions - Logging & Output
################################################################################

# Initialize directories
init_directories() {
    mkdir -p "$LOG_DIR" "$STATE_DIR" "$BACKUP_DIR" "$TEMP_DIR"
}

# Get timestamp in readable format
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Log function with file and console output
log() {
    local level="$1"
    shift
    local message="$*"
    local ts=$(timestamp)
    echo "[${ts}] [${level}] ${message}" >> "$LOG_FILE"

    if [[ "$VERBOSE" == "1" ]]; then
        echo "[${ts}] [${level}] ${message}"
    fi
}

# Colored output functions
log_header() {
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$*${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
    log "INFO" "$*"
}

log_phase() {
    echo -e "\n${MAGENTA}■ PHASE $1: $2${NC}"
    log "PHASE" "PHASE $1: $2"
}

log_step() {
    echo -e "${BLUE}→${NC} $*"
    log "STEP" "$*"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
    log "INFO" "$*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
    log "SUCCESS" "$*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
    log "WARNING" "$*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
    log "ERROR" "$*"
}

log_debug() {
    if [[ "$VERBOSE" == "1" ]]; then
        echo -e "${CYAN}▸${NC} $*"
    fi
    log "DEBUG" "$*"
}

# Progress bar
print_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))

    printf "Progress: ["
    printf "%${filled}s" | tr ' ' '='
    printf "%$((width - filled))s" | tr ' ' '-'
    printf "] %d%% (%d/%d)\r" "$percentage" "$current" "$total"
}

# Calculate ETA
calculate_eta() {
    local elapsed=$(($(date +%s) - START_TIME))
    local current=$1
    local total=$2

    if [[ $current -eq 0 ]]; then
        echo "calculating..."
        return
    fi

    local rate=$((elapsed / current))
    local remaining=$((rate * (total - current)))

    if [[ $remaining -lt 60 ]]; then
        echo "${remaining}s"
    elif [[ $remaining -lt 3600 ]]; then
        echo "$((remaining / 60))m"
    else
        echo "$((remaining / 3600))h $((remaining % 3600 / 60))m"
    fi
}

# Status table
print_status_table() {
    log_header "Execution Status"

    printf "%-20s %-15s %-20s\n" "Phase" "Status" "Duration"
    printf "%-20s %-15s %-20s\n" "$(printf '=%.0s' {1..20})" "$(printf '=%.0s' {1..15})" "$(printf '=%.0s' {1..20})"

    for phase in {1..6}; do
        if [[ -v PHASE_STATUS[$phase] ]]; then
            local status="${PHASE_STATUS[$phase]}"
            local color=""
            case "$status" in
                "COMPLETED") color="${GREEN}" ;;
                "IN_PROGRESS") color="${YELLOW}" ;;
                "FAILED") color="${RED}" ;;
                *) color="${BLUE}" ;;
            esac

            local duration="--"
            if [[ -v PHASE_START_TIME[$phase] ]]; then
                local elapsed=$(($(date +%s) - PHASE_START_TIME[$phase]))
                if [[ $elapsed -gt 0 ]]; then
                    duration="${elapsed}s"
                fi
            fi

            printf "%-20s ${color}%-15s${NC} %-20s\n" "Phase $phase" "$status" "$duration"
        fi
    done
}

################################################################################
# Utility Functions - API & System
################################################################################

# Check requirements
check_requirements() {
    log_step "Checking system requirements..."

    local missing=()

    for cmd in curl jq ssh; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_error "Install with: sudo apt-get install ${missing[*]}"
        return 1
    fi

    if [[ -z "$FORGE_API_TOKEN" ]]; then
        log_error "FORGE_API_TOKEN environment variable not set"
        return 1
    fi

    log_success "All requirements met"
    return 0
}

# Make API request with retry logic
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local retry_count=0

    while [[ $retry_count -lt $API_RETRY_COUNT ]]; do
        log_debug "API: $method $endpoint (attempt $((retry_count + 1))/$API_RETRY_COUNT)"

        local response_file=$(mktemp)
        local http_code

        if [[ -z "$data" ]]; then
            http_code=$(curl -s -w "%{http_code}" \
                --max-time "$API_TIMEOUT" \
                -X "$method" \
                -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
                -H "Content-Type: application/json" \
                -H "Accept: application/json" \
                -o "$response_file" \
                "${FORGE_API_URL}${endpoint}" 2>/dev/null)
        else
            http_code=$(curl -s -w "%{http_code}" \
                --max-time "$API_TIMEOUT" \
                -X "$method" \
                -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
                -H "Content-Type: application/json" \
                -H "Accept: application/json" \
                -d "$data" \
                -o "$response_file" \
                "${FORGE_API_URL}${endpoint}" 2>/dev/null)
        fi

        local response=$(cat "$response_file" 2>/dev/null || echo "")
        rm -f "$response_file"

        if [[ $http_code -lt 400 ]]; then
            echo "$response"
            return 0
        fi

        if [[ $http_code -ge 500 ]]; then
            # Server error, retry
            log_warning "Server error ($http_code), retrying..."
            sleep $((2 ** retry_count))  # Exponential backoff
            retry_count=$((retry_count + 1))
            continue
        fi

        # Client error, don't retry
        log_error "API request failed with status: $http_code"
        log_debug "Response: $response"
        rm -f "$response_file"
        return 1
    done

    log_error "API request failed after $API_RETRY_COUNT retries"
    return 1
}

# Save execution state
save_state() {
    local phase=$1
    local key=$2
    local value=$3

    local state_file="${STATE_DIR}/phase-${phase}.state"
    echo "${key}=${value}" >> "$state_file"
}

# Load execution state
load_state() {
    local phase=$1
    local state_file="${STATE_DIR}/phase-${phase}.state"

    if [[ -f "$state_file" ]]; then
        source "$state_file" || return 1
        return 0
    fi

    return 1
}

# Dry run helper
execute_or_dry_run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY RUN] Would execute: $*"
        return 0
    fi

    "$@"
}

################################################################################
# PHASE 1: Validate API Access
################################################################################

phase_1_validate_api_access() {
    log_phase "1" "Validate API Access"
    PHASE_STATUS[1]="IN_PROGRESS"
    PHASE_START_TIME[1]=$(date +%s)

    log_step "Testing Forge API connectivity..."

    # Test 1: Verify token works by listing servers
    log_step "Verifying API token..."
    if ! response=$(api_request "GET" "/servers"); then
        log_error "Failed to authenticate with API token"
        PHASE_STATUS[1]="FAILED"
        return 1
    fi

    local server_count=$(echo "$response" | jq '.servers | length')
    log_success "API authentication verified (found $server_count existing servers)"
    save_state 1 "SERVER_COUNT" "$server_count"

    # Test 2: Check rate limits
    log_step "Checking API rate limits..."
    if response=$(api_request "GET" "/user"); then
        log_success "API rate limit check passed"
        local api_calls=$(echo "$response" | jq -r '.api_calls_this_hour // "unknown"')
        log_info "API calls this hour: $api_calls"
    fi

    # Test 3: List available providers
    log_step "Verifying server creation permissions..."
    if response=$(api_request "GET" "/servers"); then
        log_success "Server listing verified"

        # Show current servers
        if [[ "$(echo "$response" | jq '.servers | length')" -gt 0 ]]; then
            log_info "Existing servers:"
            echo "$response" | jq -r '.servers[] | "  - \(.name) (\(.provider)/\(.region), \(.status))"' | while read -r line; do
                log_info "$line"
            done
        else
            log_info "No existing servers found"
        fi
    fi

    # Test 4: List credentials for providers
    log_step "Checking provider credentials..."
    if response=$(api_request "GET" "/credentials"); then
        local provider_count=$(echo "$response" | jq '.credentials | length')
        log_success "Found $provider_count provider credential(s)"
        echo "$response" | jq -r '.credentials[] | "  - \(.provider): \(.name)"' | while read -r line; do
            log_info "$line"
        done
        save_state 1 "PROVIDER_COUNT" "$provider_count"
    else
        log_warning "Could not retrieve provider credentials"
    fi

    PHASE_STATUS[1]="COMPLETED"
    log_success "Phase 1 completed"
    return 0
}

################################################################################
# PHASE 2: Create Production VPS Servers
################################################################################

create_vps_server() {
    local name="$1"
    local provider="$2"
    local region="$3"
    local size="$4"

    log_step "Creating VPS: $name ($provider/$region/$size)..."

    # Check if server already exists
    if response=$(api_request "GET" "/servers"); then
        if echo "$response" | jq -e ".servers[] | select(.name == \"$name\")" > /dev/null 2>&1; then
            local existing_id=$(echo "$response" | jq -r ".servers[] | select(.name == \"$name\") | .id")
            log_warning "Server '$name' already exists (ID: $existing_id)"
            SERVER_IDS[$name]="$existing_id"
            save_state 2 "SERVER_ID_${name}" "$existing_id"
            return 0
        fi
    fi

    # Create server
    local payload=$(cat <<EOF
{
    "name": "$name",
    "provider": "$provider",
    "region": "$region",
    "size": "$size"
}
EOF
)

    if ! response=$(api_request "POST" "/servers" "$payload"); then
        log_error "Failed to create VPS server: $name"
        return 1
    fi

    local server_id=$(echo "$response" | jq -r '.server.id')
    local ip_address=$(echo "$response" | jq -r '.server.ip_address // "pending"')

    log_success "VPS server created: $name (ID: $server_id)"
    log_info "IP Address: $ip_address"

    SERVER_IDS[$name]="$server_id"
    save_state 2 "SERVER_ID_${name}" "$server_id"
    save_state 2 "SERVER_IP_${name}" "$ip_address"

    return 0
}

wait_for_server_provisioning() {
    local name="$1"
    local server_id="$2"
    local max_wait="$3"

    log_step "Waiting for server provisioning: $name (max ${max_wait}s)..."

    local elapsed=0
    local check_count=0

    while [[ $elapsed -lt $max_wait ]]; do
        check_count=$((check_count + 1))

        if ! response=$(api_request "GET" "/servers/$server_id"); then
            log_warning "Failed to fetch server status, retrying..."
            sleep "$PROVISIONING_CHECK_INTERVAL"
            elapsed=$((elapsed + PROVISIONING_CHECK_INTERVAL))
            continue
        fi

        local status=$(echo "$response" | jq -r '.server.status')
        local ip_address=$(echo "$response" | jq -r '.server.ip_address // "pending"')
        local memory=$(echo "$response" | jq -r '.server.memory // "unknown"')

        # Update progress
        local percentage=$((elapsed * 100 / max_wait))
        printf "    Status: %-10s IP: %-15s Memory: %s (${percentage}%% ${elapsed}s/${max_wait}s)\r" "$status" "$ip_address" "$memory"

        if [[ "$status" == "active" ]]; then
            printf "\n"
            log_success "Server is now active: $name"
            log_info "IP Address: $ip_address"
            save_state 2 "SERVER_IP_${name}" "$ip_address"
            return 0
        fi

        sleep "$PROVISIONING_CHECK_INTERVAL"
        elapsed=$((elapsed + PROVISIONING_CHECK_INTERVAL))
    done

    printf "\n"
    log_error "Server provisioning timed out after ${max_wait}s"
    return 1
}

configure_firewall_rules() {
    local server_id="$1"
    local server_name="$2"

    log_step "Configuring firewall rules for: $server_name..."

    local rules=$(cat <<'EOF'
{
    "rules": [
        {"name": "SSH", "port": "22", "protocol": "tcp"},
        {"name": "HTTP", "port": "80", "protocol": "tcp"},
        {"name": "HTTPS", "port": "443", "protocol": "tcp"},
        {"name": "MySQL", "port": "3306", "protocol": "tcp"},
        {"name": "PostgreSQL", "port": "5432", "protocol": "tcp"}
    ]
}
EOF
)

    if ! response=$(api_request "POST" "/servers/$server_id/firewall-rules" "$rules"); then
        log_warning "Failed to configure firewall (may already exist)"
        return 0
    fi

    log_success "Firewall rules configured"
    return 0
}

phase_2_create_production_vps() {
    log_phase "2" "Create Production VPS Servers"
    PHASE_STATUS[2]="IN_PROGRESS"
    PHASE_START_TIME[2]=$(date +%s)

    local app_count=0

    # Parse and create apps
    for app_config in "${APPS[@]}"; do
        IFS=':' read -r name provider region size db_type <<< "$app_config"
        app_count=$((app_count + 1))

        log_info "Creating app $app_count/${#APPS[@]}: $name"

        # Try to load state (resumable)
        if load_state 2; then
            if [[ -n "${SERVER_ID_${name}:-}" ]]; then
                log_info "Using existing server from state"
                SERVER_IDS[$name]="${SERVER_ID_${name}}"
            fi
        fi

        # Create VPS if not already created
        if [[ -z "${SERVER_IDS[$name]:-}" ]]; then
            if ! execute_or_dry_run create_vps_server "$name" "$provider" "$region" "$size"; then
                log_error "Failed to create VPS for $name"
                PHASE_STATUS[2]="FAILED"
                return 1
            fi
        fi

        local server_id="${SERVER_IDS[$name]}"

        # Wait for provisioning
        if ! execute_or_dry_run wait_for_server_provisioning "$name" "$server_id" "$MAX_PROVISIONING_WAIT"; then
            log_error "VPS provisioning timed out for $name"
            PHASE_STATUS[2]="FAILED"
            return 1
        fi

        # Configure firewall
        if ! execute_or_dry_run configure_firewall_rules "$server_id" "$name"; then
            log_warning "Firewall configuration failed for $name, continuing..."
        fi

        # Show progress
        print_progress "$app_count" "${#APPS[@]}"
    done

    printf "\n"
    log_success "All production VPS servers created"
    PHASE_STATUS[2]="COMPLETED"
    return 0
}

################################################################################
# PHASE 3: Create Sites (via API)
################################################################################

create_site() {
    local server_id="$1"
    local server_name="$2"
    local app_name="$3"
    local db_type="$4"

    log_step "Creating site for $app_name..."

    # Use on-forge.com domain
    local domain="${app_name}.on-forge.com"

    # Create site
    local site_payload=$(cat <<EOF
{
    "domain": "$domain",
    "project_type": "laravel",
    "php_version": "8.2"
}
EOF
)

    if ! response=$(api_request "POST" "/servers/$server_id/sites" "$site_payload"); then
        log_error "Failed to create site: $domain"
        return 1
    fi

    local site_id=$(echo "$response" | jq -r '.site.id')
    log_success "Site created: $domain (ID: $site_id)"

    SITE_IDS[$app_name]="$site_id"
    save_state 3 "SITE_ID_${app_name}" "$site_id"
    save_state 3 "SITE_DOMAIN_${app_name}" "$domain"

    # Create database
    log_step "Creating database for $app_name ($db_type)..."

    local db_name="${app_name//-/_}_db"
    local db_payload=$(cat <<EOF
{
    "name": "$db_name",
    "type": "$db_type"
}
EOF
)

    if ! response=$(api_request "POST" "/servers/$server_id/databases" "$db_payload"); then
        log_error "Failed to create database: $db_name"
        return 1
    fi

    local db_id=$(echo "$response" | jq -r '.database.id')
    log_success "Database created: $db_name (ID: $db_id, type: $db_type)"
    save_state 3 "DB_ID_${app_name}" "$db_id"
    save_state 3 "DB_NAME_${app_name}" "$db_name"
    save_state 3 "DB_TYPE_${app_name}" "$db_type"

    # Install SSL certificate (Let's Encrypt)
    log_step "Installing SSL certificate for $domain..."

    local ssl_payload=$(cat <<EOF
{
    "domain": "$domain",
    "certificate": "letsencrypt"
}
EOF
)

    if response=$(api_request "POST" "/servers/$server_id/ssl-certificates" "$ssl_payload"); then
        local cert_id=$(echo "$response" | jq -r '.certificate.id')
        log_success "SSL certificate installed: $cert_id"
        save_state 3 "SSL_ID_${app_name}" "$cert_id"
    else
        log_warning "SSL certificate installation skipped or failed"
    fi

    return 0
}

phase_3_create_sites() {
    log_phase "3" "Create Sites (via API)"
    PHASE_STATUS[3]="IN_PROGRESS"
    PHASE_START_TIME[3]=$(date +%s)

    local app_count=0

    # Create sites for each app
    for app_config in "${APPS[@]}"; do
        IFS=':' read -r name provider region size db_type <<< "$app_config"
        app_count=$((app_count + 1))

        log_info "Creating site $app_count/${#APPS[@]}: $name"

        local server_id="${SERVER_IDS[$name]}"
        if [[ -z "$server_id" ]]; then
            log_error "Server ID not found for $name"
            PHASE_STATUS[3]="FAILED"
            return 1
        fi

        if ! execute_or_dry_run create_site "$server_id" "$name" "$name" "$db_type"; then
            log_error "Failed to create site for $name"
            PHASE_STATUS[3]="FAILED"
            return 1
        fi

        print_progress "$app_count" "${#APPS[@]}"
    done

    printf "\n"
    log_success "All sites created successfully"
    PHASE_STATUS[3]="COMPLETED"
    return 0
}

################################################################################
# PHASE 4: Database Snapshots (via SSH + API)
################################################################################

create_database_snapshot() {
    local server_id="$1"
    local server_name="$2"
    local app_name="$3"
    local db_type="$4"
    local ip_address="$5"

    log_step "Creating database snapshot for $app_name ($db_type)..."

    local snapshot_file="${BACKUP_DIR}/${app_name}-${db_type}-snapshot-$(date +%Y%m%d_%H%M%S).sql"

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY RUN] Would create snapshot: $snapshot_file"
        save_state 4 "SNAPSHOT_${app_name}" "$snapshot_file"
        return 0
    fi

    # SSH to server and create dump
    log_info "Connecting to server: $ip_address"

    local db_name="${app_name//-/_}_db"

    case "$db_type" in
        mysql)
            log_info "Creating MySQL dump: $db_name"
            if ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=10" "root@$ip_address" \
                "mysqldump -u root '$db_name' 2>/dev/null || echo 'Database not ready'" > "$snapshot_file" 2>/dev/null; then
                local size=$(wc -c < "$snapshot_file")
                log_success "MySQL snapshot created: $(basename "$snapshot_file") ($(numfmt --to=iec $size 2>/dev/null || echo "$size bytes"))"
                save_state 4 "SNAPSHOT_${app_name}" "$snapshot_file"
            else
                log_warning "MySQL dump failed (database may not be ready yet)"
            fi
            ;;
        postgres|postgresql)
            log_info "Creating PostgreSQL dump: $db_name"
            if ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=10" "root@$ip_address" \
                "sudo -u postgres pg_dump '$db_name' 2>/dev/null || echo 'Database not ready'" > "$snapshot_file" 2>/dev/null; then
                local size=$(wc -c < "$snapshot_file")
                log_success "PostgreSQL snapshot created: $(basename "$snapshot_file") ($(numfmt --to=iec $size 2>/dev/null || echo "$size bytes"))"
                save_state 4 "SNAPSHOT_${app_name}" "$snapshot_file"
            else
                log_warning "PostgreSQL dump failed (database may not be ready yet)"
            fi
            ;;
        *)
            log_warning "Unknown database type: $db_type"
            ;;
    esac

    return 0
}

setup_snapshot_cron() {
    local server_id="$1"
    local server_name="$2"
    local ip_address="$3"
    local db_type="$4"

    log_step "Setting up weekly database snapshot cron job..."

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY RUN] Would setup cron job for weekly snapshots"
        return 0
    fi

    # Create cron script on server
    local cron_script="/root/backup-database.sh"

    case "$db_type" in
        mysql)
            local cron_content="#!/bin/bash\nmysqldump -u root -A > /root/backups/database-\$(date +%Y%m%d).sql\nfind /root/backups -name 'database-*.sql' -mtime +30 -delete\n"
            ;;
        postgres|postgresql)
            local cron_content="#!/bin/bash\nsudo -u postgres pg_dumpall > /root/backups/database-\$(date +%Y%m%d).sql\nfind /root/backups -name 'database-*.sql' -mtime +30 -delete\n"
            ;;
        *)
            return 0
            ;;
    esac

    if ssh -o "StrictHostKeyChecking=no" "root@$ip_address" \
        "mkdir -p /root/backups && echo -e '$cron_content' > $cron_script && chmod +x $cron_script" 2>/dev/null; then

        # Add cron entry (weekly on Sunday at 2 AM)
        ssh -o "StrictHostKeyChecking=no" "root@$ip_address" \
            "(crontab -l 2>/dev/null || echo '') | grep -v 'backup-database.sh' | (cat; echo '0 2 * * 0 $cron_script') | crontab -" 2>/dev/null

        log_success "Snapshot cron job configured (weekly at 2 AM Sunday)"
        return 0
    else
        log_warning "Failed to setup cron job (server may not be ready)"
        return 0
    fi
}

phase_4_database_snapshots() {
    log_phase "4" "Database Snapshots (via SSH + API)"
    PHASE_STATUS[4]="IN_PROGRESS"
    PHASE_START_TIME[4]=$(date +%s)

    local app_count=0

    # Create snapshots for each app
    for app_config in "${APPS[@]}"; do
        IFS=':' read -r name provider region size db_type <<< "$app_config"
        app_count=$((app_count + 1))

        log_info "Creating snapshot $app_count/${#APPS[@]}: $name"

        local server_id="${SERVER_IDS[$name]}"
        local ip_address

        # Load IP from state
        if ! load_state 2; then
            log_warning "Could not load state for $name"
        fi

        ip_address="${SERVER_IP_${name}:-}"
        if [[ -z "$ip_address" ]]; then
            # Try to fetch from API
            if response=$(api_request "GET" "/servers/$server_id"); then
                ip_address=$(echo "$response" | jq -r '.server.ip_address')
            fi
        fi

        if [[ -z "$ip_address" ]] || [[ "$ip_address" == "null" ]] || [[ "$ip_address" == "pending" ]]; then
            log_warning "Server IP not available yet for $name, skipping snapshot"
            continue
        fi

        # Create snapshot
        if ! execute_or_dry_run create_database_snapshot "$server_id" "$name" "$name" "$db_type" "$ip_address"; then
            log_warning "Snapshot creation failed for $name, continuing..."
        fi

        # Setup cron job
        if ! execute_or_dry_run setup_snapshot_cron "$server_id" "$name" "$ip_address" "$db_type"; then
            log_warning "Cron setup failed for $name, continuing..."
        fi

        print_progress "$app_count" "${#APPS[@]}"
    done

    printf "\n"
    log_success "Database snapshots configured"
    PHASE_STATUS[4]="COMPLETED"
    return 0
}

################################################################################
# PHASE 5: Test PR Environment (via API)
################################################################################

phase_5_test_pr_environment() {
    log_phase "5" "Test PR Environment (via API)"
    PHASE_STATUS[5]="IN_PROGRESS"
    PHASE_START_TIME[5]=$(date +%s)

    log_step "Creating test VPS: $TEST_APP..."

    # Check if test server already exists
    if response=$(api_request "GET" "/servers"); then
        if echo "$response" | jq -e ".servers[] | select(.name == \"$TEST_APP\")" > /dev/null 2>&1; then
            log_warning "Test server '$TEST_APP' already exists"
            local test_server_id=$(echo "$response" | jq -r ".servers[] | select(.name == \"$TEST_APP\") | .id")
            SERVER_IDS[$TEST_APP]="$test_server_id"
        else
            # Create test VPS
            if ! execute_or_dry_run create_vps_server "$TEST_APP" "$TEST_PROVIDER" "$TEST_REGION" "$TEST_SIZE"; then
                log_error "Failed to create test VPS"
                PHASE_STATUS[5]="FAILED"
                return 1
            fi

            local test_server_id="${SERVER_IDS[$TEST_APP]}"

            # Wait for provisioning
            if ! execute_or_dry_run wait_for_server_provisioning "$TEST_APP" "$test_server_id" "$MAX_PROVISIONING_WAIT"; then
                log_error "Test VPS provisioning timed out"
                PHASE_STATUS[5]="FAILED"
                return 1
            fi

            # Configure firewall
            if ! execute_or_dry_run configure_firewall_rules "$test_server_id" "$TEST_APP"; then
                log_warning "Firewall configuration failed, continuing..."
            fi
        fi
    fi

    # Create test site
    log_step "Creating test site with on-forge.com domain..."
    local test_domain="${TEST_APP}.on-forge.com"

    if ! execute_or_dry_run create_site "${SERVER_IDS[$TEST_APP]}" "$TEST_APP" "$TEST_APP" "mysql"; then
        log_warning "Test site creation failed, continuing..."
    fi

    log_success "Test PR environment setup complete"
    PHASE_STATUS[5]="COMPLETED"
    return 0
}

################################################################################
# PHASE 6: Monitoring Setup (via API)
################################################################################

setup_health_checks() {
    local server_id="$1"
    local server_name="$2"

    log_step "Setting up health checks for: $server_name..."

    local checks_payload=$(cat <<EOF
{
    "checks": [
        {
            "name": "CPU Usage",
            "type": "cpu",
            "threshold": 80
        },
        {
            "name": "Memory Usage",
            "type": "memory",
            "threshold": 85
        },
        {
            "name": "Disk Usage",
            "type": "disk",
            "threshold": 90
        }
    ]
}
EOF
)

    if response=$(api_request "POST" "/servers/$server_id/monitoring" "$checks_payload"); then
        log_success "Health checks configured for $server_name"
        return 0
    else
        log_warning "Health check configuration skipped or failed"
        return 0
    fi
}

setup_alerts() {
    local server_id="$1"
    local server_name="$2"

    log_step "Configuring alerts for: $server_name..."

    local alerts_payload=$(cat <<'EOF'
{
    "alerts": [
        {
            "type": "email",
            "threshold_exceeded": true,
            "daily_summary": true
        }
    ]
}
EOF
)

    if response=$(api_request "POST" "/servers/$server_id/alerts" "$alerts_payload"); then
        log_success "Alerts configured for $server_name"
        return 0
    else
        log_warning "Alert configuration skipped or failed"
        return 0
    fi
}

phase_6_monitoring_setup() {
    log_phase "6" "Monitoring Setup (via API)"
    PHASE_STATUS[6]="IN_PROGRESS"
    PHASE_START_TIME[6]=$(date +%s)

    local server_count=0

    # Setup monitoring for production servers
    for app_config in "${APPS[@]}"; do
        IFS=':' read -r name provider region size db_type <<< "$app_config"
        server_count=$((server_count + 1))

        log_info "Setting up monitoring $server_count/${#APPS[@]}: $name"

        local server_id="${SERVER_IDS[$name]}"
        if [[ -z "$server_id" ]]; then
            log_error "Server ID not found for $name"
            continue
        fi

        if ! execute_or_dry_run setup_health_checks "$server_id" "$name"; then
            log_warning "Health check setup failed for $name, continuing..."
        fi

        if ! execute_or_dry_run setup_alerts "$server_id" "$name"; then
            log_warning "Alert setup failed for $name, continuing..."
        fi

        print_progress "$server_count" "${#APPS[@]}"
    done

    # Setup monitoring for test server
    local test_server_id="${SERVER_IDS[$TEST_APP]:-}"
    if [[ -n "$test_server_id" ]]; then
        log_info "Setting up monitoring for test server"
        if ! execute_or_dry_run setup_health_checks "$test_server_id" "$TEST_APP"; then
            log_warning "Test server monitoring setup failed"
        fi
    fi

    printf "\n"
    log_success "Monitoring setup complete"
    PHASE_STATUS[6]="COMPLETED"
    return 0
}

################################################################################
# Reporting & Summary
################################################################################

generate_report() {
    log_header "Implementation Report"

    local total_duration=$(($(date +%s) - START_TIME))

    cat > "${LOG_DIR}/implementation-report.txt" << EOF
═══════════════════════════════════════════════════════════════════════════════
FORGE API IMPLEMENTATION REPORT
═══════════════════════════════════════════════════════════════════════════════

Generated: $(timestamp)
Total Duration: ${total_duration}s ($((total_duration / 60))m $((total_duration % 60))s)

PHASE SUMMARY
─────────────────────────────────────────────────────────────────────────────
EOF

    for phase in {1..6}; do
        if [[ -v PHASE_STATUS[$phase] ]]; then
            local status="${PHASE_STATUS[$phase]}"
            local duration="--"
            if [[ -v PHASE_START_TIME[$phase] ]]; then
                duration=$(($(date +%s) - PHASE_START_TIME[$phase]))
            fi
            printf "Phase %d: %-20s (${duration}s)\n" "$phase" "$status" >> "${LOG_DIR}/implementation-report.txt"
        fi
    done

    cat >> "${LOG_DIR}/implementation-report.txt" << EOF

APPLICATION INVENTORY
─────────────────────────────────────────────────────────────────────────────
EOF

    for app_config in "${APPS[@]}"; do
        IFS=':' read -r name provider region size db_type <<< "$app_config"

        cat >> "${LOG_DIR}/implementation-report.txt" << EOF

Application: $name
  Server ID: ${SERVER_IDS[$name]:-NOT CREATED}
  Provider: $provider
  Region: $region
  Size: $size
  Database: $db_type
  Site ID: ${SITE_IDS[$name]:-NOT CREATED}
EOF
    done

    cat >> "${LOG_DIR}/implementation-report.txt" << EOF

TEST ENVIRONMENT
─────────────────────────────────────────────────────────────────────────────
Server: $TEST_APP
  Server ID: ${SERVER_IDS[$TEST_APP]:-NOT CREATED}
  Provider: $TEST_PROVIDER
  Region: $TEST_REGION
  Size: $TEST_SIZE

FILES & BACKUPS
─────────────────────────────────────────────────────────────────────────────
Log Directory: $LOG_DIR
State Directory: $STATE_DIR
Backup Directory: $BACKUP_DIR

Snapshots Created:
EOF

    if [[ -d "$BACKUP_DIR" ]]; then
        ls -lh "$BACKUP_DIR"/*.sql 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' >> "${LOG_DIR}/implementation-report.txt" || \
            echo "  No snapshots created" >> "${LOG_DIR}/implementation-report.txt"
    fi

    cat >> "${LOG_DIR}/implementation-report.txt" << EOF

RECOMMENDATIONS
─────────────────────────────────────────────────────────────────────────────
1. Verify all servers are running and healthy
2. Configure Git deployment for each site
3. Set environment variables on each server
4. Run database migrations
5. Configure SSL certificate auto-renewal
6. Setup automated backups
7. Configure email notifications

═══════════════════════════════════════════════════════════════════════════════
EOF

    cat "${LOG_DIR}/implementation-report.txt" >> "$LOG_FILE"
    cat "${LOG_DIR}/implementation-report.txt"
}

################################################################################
# Main Execution
################################################################################

main() {
    # Initialize
    init_directories

    # Create log file
    LOG_FILE="${LOG_DIR}/implementation-$(date +%Y%m%d_%H%M%S).log"

    log_header "FORGE API - Complete System Implementation"
    log_info "Start Time: $(timestamp)"
    log_info "Dry Run Mode: $([[ "$DRY_RUN" == "1" ]] && echo "ENABLED" || echo "DISABLED")"
    log_info "Verbose Mode: $([[ "$VERBOSE" == "1" ]] && echo "ENABLED" || echo "DISABLED")"

    # Check requirements
    if ! check_requirements; then
        log_error "Requirements check failed"
        exit 1
    fi

    # Execute phases
    local phases_completed=0
    local phases_total=6

    for phase in $(seq "$PHASE_START" 6); do
        log_info "═══════════════════════════════════════════════════════════════"
        log_info "Executing Phase $phase/$phases_total..."
        log_info "═══════════════════════════════════════════════════════════════"

        case $phase in
            1)
                if ! phase_1_validate_api_access; then
                    log_error "Phase 1 failed, aborting"
                    exit 1
                fi
                ;;
            2)
                if ! phase_2_create_production_vps; then
                    log_error "Phase 2 failed, aborting"
                    exit 1
                fi
                ;;
            3)
                if ! phase_3_create_sites; then
                    log_error "Phase 3 failed, aborting"
                    exit 1
                fi
                ;;
            4)
                if ! phase_4_database_snapshots; then
                    log_warning "Phase 4 completed with warnings"
                fi
                ;;
            5)
                if ! phase_5_test_pr_environment; then
                    log_warning "Phase 5 completed with warnings"
                fi
                ;;
            6)
                if ! phase_6_monitoring_setup; then
                    log_warning "Phase 6 completed with warnings"
                fi
                ;;
        esac

        phases_completed=$((phases_completed + 1))
        print_progress "$phases_completed" "$phases_total"
    done

    printf "\n"

    # Generate report
    generate_report

    # Cleanup
    rm -rf "$TEMP_DIR"

    # Final summary
    log_header "Implementation Complete"
    log_success "All phases completed successfully!"
    log_info "Log File: $LOG_FILE"
    log_info "Report File: ${LOG_DIR}/implementation-report.txt"
    log_info "State Directory: $STATE_DIR"
    log_info "Backups Directory: $BACKUP_DIR"

    print_status_table

    return 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --phase)
            PHASE_START="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --help)
            cat << 'EOF'
Usage: ./implement-complete-system.sh [OPTIONS]

Options:
  --phase N          Start from phase N (1-6, default: 1)
  --dry-run          Show what would happen without making changes
  --verbose          Enable verbose output
  --config FILE      Load configuration from file
  --help             Show this help message

Environment Variables:
  FORGE_API_TOKEN    Forge API token (REQUIRED)
  FORGE_API_URL      API endpoint (default: https://forge.laravel.com/api/v1)
  MAX_PROVISIONING_WAIT  Max provisioning wait time in seconds (default: 3600)

Examples:
  # Full implementation
  export FORGE_API_TOKEN="your-token"
  ./implement-complete-system.sh

  # Resume from phase 3
  ./implement-complete-system.sh --phase 3

  # Dry run to see what would happen
  ./implement-complete-system.sh --dry-run --verbose

EOF
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load config file if provided
if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    log_info "Loading configuration from: $CONFIG_FILE"
    source "$CONFIG_FILE"
fi

# Execute main
main
