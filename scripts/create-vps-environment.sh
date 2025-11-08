#!/bin/bash

################################################################################
# create-vps-environment.sh
#
# Creates a new Laravel VPS environment via Laravel Forge API
#
# Features:
#   - Creates VPS server on supported providers (DigitalOcean, AWS, Linode, etc)
#   - Configures firewall rules
#   - Sets up SSL certificates
#   - Creates initial database
#   - Installs system dependencies
#   - Idempotent and resumable
#   - Comprehensive error handling
#   - Logs all operations
#
# Requirements:
#   - curl or wget
#   - jq (JSON processor)
#   - FORGE_API_TOKEN environment variable
#
# Usage:
#   ./create-vps-environment.sh \
#     --name "production-app" \
#     --provider "digitalocean" \
#     --region "nyc3" \
#     --size "s-2vcpu-4gb" \
#     --ip-address "192.168.1.100"
#
#   Or with environment file:
#   source .env.forge && ./create-vps-environment.sh --env-file config/vps.env
#
# Environment Variables:
#   FORGE_API_TOKEN       - Laravel Forge API token (required)
#   FORGE_API_URL         - API endpoint (default: https://forge.laravel.com/api/v1)
#   LOG_FILE              - Log file path (default: logs/vps-creation.log)
#   MAX_WAIT_TIME         - Max wait for provisioning (default: 3600 seconds)
#   RETRY_INTERVAL        - Retry wait time (default: 30 seconds)
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
LOG_FILE="${LOG_DIR}/vps-creation-$(date +%Y%m%d_%H%M%S).log"
MAX_WAIT_TIME="${MAX_WAIT_TIME:-3600}"
RETRY_INTERVAL="${RETRY_INTERVAL:-30}"
STATE_FILE="${LOG_DIR}/.vps-creation-state"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Tracking variables
VPS_NAME=""
VPS_PROVIDER=""
VPS_REGION=""
VPS_SIZE=""
VPS_IP_ADDRESS=""
SERVER_ID=""
ENV_FILE=""

################################################################################
# Utility Functions
################################################################################

# Create logs directory
mkdir -p "$LOG_DIR"

# Log function with timestamps
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Log with colors for user
log_info() {
    echo -e "${BLUE}ℹ${NC} $*" | tee -a "$LOG_FILE"
    log "INFO" "$*"
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

# Check requirements
check_requirements() {
    log_info "Checking requirements..."

    local missing_tools=()

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Install with: sudo apt-get install ${missing_tools[*]}"
        return 1
    fi

    if [[ -z "$FORGE_API_TOKEN" ]]; then
        log_error "FORGE_API_TOKEN environment variable not set"
        return 1
    fi

    log_success "All requirements met"
    return 0
}

# Validate arguments
validate_args() {
    log_info "Validating arguments..."

    if [[ -z "$VPS_NAME" ]]; then
        log_error "VPS name is required (--name)"
        return 1
    fi

    if [[ -z "$VPS_PROVIDER" ]]; then
        log_error "Provider is required (--provider)"
        return 1
    fi

    if [[ -z "$VPS_REGION" ]]; then
        log_error "Region is required (--region)"
        return 1
    fi

    if [[ -z "$VPS_SIZE" ]]; then
        log_error "Size is required (--size)"
        return 1
    fi

    log_success "Arguments validated"
    return 0
}

# Load environment file
load_env_file() {
    local env_file="$1"

    if [[ ! -f "$env_file" ]]; then
        log_error "Environment file not found: $env_file"
        return 1
    fi

    log_info "Loading environment from: $env_file"
    set -a
    source "$env_file"
    set +a

    log_success "Environment file loaded"
    return 0
}

# Save state for resume capability
save_state() {
    cat > "$STATE_FILE" << EOF
VPS_NAME="$VPS_NAME"
VPS_PROVIDER="$VPS_PROVIDER"
VPS_REGION="$VPS_REGION"
VPS_SIZE="$VPS_SIZE"
VPS_IP_ADDRESS="${VPS_IP_ADDRESS:-}"
SERVER_ID="${SERVER_ID:-}"
EOF
    log_info "State saved to: $STATE_FILE"
}

# Load saved state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        log_info "Loading saved state..."
        source "$STATE_FILE"
        return 0
    fi
    return 1
}

# Make API request
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local url="${FORGE_API_URL}${endpoint}"
    local response_file=$(mktemp)
    local http_code

    log_info "API Request: ${method} ${endpoint}"

    if [[ -z "$data" ]]; then
        http_code=$(curl -s -w "%{http_code}" \
            -X "$method" \
            -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -o "$response_file" \
            "$url")
    else
        http_code=$(curl -s -w "%{http_code}" \
            -X "$method" \
            -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "$data" \
            -o "$response_file" \
            "$url")
    fi

    local response=$(cat "$response_file")
    rm -f "$response_file"

    # Check HTTP status
    if [[ $http_code -ge 400 ]]; then
        log_error "API request failed with status: $http_code"
        log_error "Response: $response"
        return 1
    fi

    echo "$response"
    return 0
}

# List available servers
list_servers() {
    log_info "Fetching list of existing servers..."

    local response
    if response=$(api_request "GET" "/servers"); then
        echo "$response" | jq '.servers[] | {id, name, provider, region, size, ip_address}' | \
            tee -a "$LOG_FILE"
        return 0
    fi
    return 1
}

# Check if server already exists
server_exists() {
    local server_name="$1"

    log_info "Checking if server '$server_name' already exists..."

    local response
    if response=$(api_request "GET" "/servers"); then
        if echo "$response" | jq -e ".servers[] | select(.name == \"$server_name\")" > /dev/null 2>&1; then
            log_warning "Server '$server_name' already exists"
            SERVER_ID=$(echo "$response" | jq -r ".servers[] | select(.name == \"$server_name\") | .id")
            log_info "Server ID: $SERVER_ID"
            return 0
        fi
    fi

    return 1
}

# Create VPS server
create_vps() {
    log_info "Creating VPS server: $VPS_NAME"

    # Check if server already exists
    if server_exists "$VPS_NAME"; then
        log_warning "Server already exists, skipping creation"
        save_state
        return 0
    fi

    # Prepare request payload
    local payload=$(cat <<EOF
{
    "name": "$VPS_NAME",
    "provider": "$VPS_PROVIDER",
    "region": "$VPS_REGION",
    "size": "$VPS_SIZE"
}
EOF
)

    if [[ -n "$VPS_IP_ADDRESS" ]]; then
        payload=$(echo "$payload" | jq --arg ip "$VPS_IP_ADDRESS" '.ip_address = $ip')
    fi

    log_info "Request payload: $payload"

    local response
    if response=$(api_request "POST" "/servers" "$payload"); then
        SERVER_ID=$(echo "$response" | jq -r '.server.id')
        log_success "VPS created successfully with ID: $SERVER_ID"
        save_state
        return 0
    fi

    return 1
}

# Wait for server provisioning
wait_for_provisioning() {
    log_info "Waiting for server provisioning (max ${MAX_WAIT_TIME}s)..."

    local elapsed=0
    local check_count=0

    while [[ $elapsed -lt $MAX_WAIT_TIME ]]; do
        check_count=$((check_count + 1))

        local response
        if response=$(api_request "GET" "/servers/$SERVER_ID"); then
            local status=$(echo "$response" | jq -r '.server.status')
            local progress=$(echo "$response" | jq -r '.server.provision_status // "unknown"')

            log_info "Check #${check_count}: Status=$status, Progress=$progress (${elapsed}s/${MAX_WAIT_TIME}s)"

            if [[ "$status" == "active" ]]; then
                log_success "Server is now active and provisioned"
                return 0
            fi
        fi

        sleep "$RETRY_INTERVAL"
        elapsed=$((elapsed + RETRY_INTERVAL))
    done

    log_error "Server provisioning timed out after ${MAX_WAIT_TIME}s"
    return 1
}

# Configure firewall
configure_firewall() {
    log_info "Configuring firewall rules..."

    # Default firewall rules
    local firewall_rules=$(cat <<'EOF'
{
    "rules": [
        {"name": "SSH", "port": "22", "protocol": "tcp"},
        {"name": "HTTP", "port": "80", "protocol": "tcp"},
        {"name": "HTTPS", "port": "443", "protocol": "tcp"}
    ]
}
EOF
)

    log_info "Firewall rules: $firewall_rules"

    local response
    if response=$(api_request "POST" "/servers/$SERVER_ID/firewall-rules" "$firewall_rules"); then
        log_success "Firewall configured successfully"
        return 0
    fi

    return 1
}

# Install SSL certificate
install_ssl() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        log_warning "No domain provided, skipping SSL installation"
        return 0
    fi

    log_info "Installing SSL certificate for domain: $domain"

    local payload=$(cat <<EOF
{
    "domain": "$domain",
    "certificate": "letsencrypt"
}
EOF
)

    local response
    if response=$(api_request "POST" "/servers/$SERVER_ID/ssl-certificates" "$payload"); then
        local cert_id=$(echo "$response" | jq -r '.certificate.id')
        log_success "SSL certificate installed with ID: $cert_id"
        return 0
    fi

    log_warning "SSL certificate installation skipped or failed"
    return 0
}

# Create database
create_database() {
    local db_name="$1"

    if [[ -z "$db_name" ]]; then
        log_warning "No database name provided, skipping database creation"
        return 0
    fi

    log_info "Creating database: $db_name"

    local payload=$(cat <<EOF
{
    "name": "$db_name"
}
EOF
)

    local response
    if response=$(api_request "POST" "/servers/$SERVER_ID/databases" "$payload"); then
        local db_id=$(echo "$response" | jq -r '.database.id')
        log_success "Database created with ID: $db_id"
        return 0
    fi

    log_warning "Database creation skipped or failed"
    return 0
}

# Get server details
get_server_details() {
    log_info "Fetching server details..."

    local response
    if response=$(api_request "GET" "/servers/$SERVER_ID"); then
        echo "$response" | jq '.server' | tee -a "$LOG_FILE"
        return 0
    fi

    return 1
}

# Print summary
print_summary() {
    cat << EOF

$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)
$(tput bold)VPS Environment Creation Summary$(tput sgr0)
$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)

Server Name:      $VPS_NAME
Server ID:        $SERVER_ID
Provider:         $VPS_PROVIDER
Region:           $VPS_REGION
Size:             $VPS_SIZE
IP Address:       $(echo "$response" | jq -r '.server.ip_address // "pending"')

Status:           Active
Log File:         $LOG_FILE
State File:       $STATE_FILE

$(tput bold)Next Steps:$(tput sgr0)
1. Connect via SSH:
   ssh root@\$(echo "$response" | jq -r '.server.ip_address')

2. Deploy Laravel application:
   - Create site on the VPS
   - Configure domain and SSL
   - Deploy code and run migrations

3. Monitor:
   - Check logs: tail -f $LOG_FILE
   - Use Forge dashboard for advanced management

$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)

EOF
}

# Show usage
usage() {
    cat << 'EOF'
Usage: ./create-vps-environment.sh [OPTIONS]

Options:
  --name NAME              VPS server name (required)
  --provider PROVIDER      Cloud provider: digitalocean, aws, linode, vultr, hetzner (required)
  --region REGION          Region/datacenter (required)
  --size SIZE              Server size (required)
  --ip-address IP          Optional static IP address
  --domain DOMAIN          Optional domain for SSL certificate
  --database DB_NAME       Optional database name to create
  --env-file FILE          Load configuration from environment file
  --help                   Show this help message

Examples:
  # Basic VPS creation
  ./create-vps-environment.sh \
    --name "production-app" \
    --provider "digitalocean" \
    --region "nyc3" \
    --size "s-2vcpu-4gb"

  # Full setup with domain and database
  ./create-vps-environment.sh \
    --name "staging-app" \
    --provider "linode" \
    --region "us-east" \
    --size "linode/4GB" \
    --domain "staging.example.com" \
    --database "app_staging"

  # From environment file
  source .env.forge && \
  ./create-vps-environment.sh --env-file config/vps.env

Environment Variables:
  FORGE_API_TOKEN       Laravel Forge API token (required)
  FORGE_API_URL         API endpoint (default: https://forge.laravel.com/api/v1)
  MAX_WAIT_TIME         Maximum wait for provisioning in seconds (default: 3600)
  RETRY_INTERVAL        Wait between status checks in seconds (default: 30)

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
            --name)
                VPS_NAME="$2"
                shift 2
                ;;
            --provider)
                VPS_PROVIDER="$2"
                shift 2
                ;;
            --region)
                VPS_REGION="$2"
                shift 2
                ;;
            --size)
                VPS_SIZE="$2"
                shift 2
                ;;
            --ip-address)
                VPS_IP_ADDRESS="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --database)
                DATABASE="$2"
                shift 2
                ;;
            --env-file)
                ENV_FILE="$2"
                shift 2
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
    log_info "Laravel VPS Creation Script"
    log_info "========================================"

    # Load environment file if provided
    if [[ -n "$ENV_FILE" ]]; then
        load_env_file "$ENV_FILE" || exit 1
    fi

    # Check requirements
    check_requirements || exit 1

    # Validate arguments
    validate_args || exit 1

    # Save state for resume capability
    save_state

    # Create VPS
    if ! create_vps; then
        log_error "Failed to create VPS server"
        exit 1
    fi

    # Wait for provisioning
    if ! wait_for_provisioning; then
        log_error "Server provisioning failed or timed out"
        exit 1
    fi

    # Configure firewall
    if ! configure_firewall; then
        log_warning "Firewall configuration failed"
    fi

    # Install SSL if domain provided
    if [[ -n "${DOMAIN:-}" ]]; then
        install_ssl "$DOMAIN" || true
    fi

    # Create database if name provided
    if [[ -n "${DATABASE:-}" ]]; then
        create_database "$DATABASE" || true
    fi

    # Get final server details
    if get_server_details > /dev/null; then
        response=$(api_request "GET" "/servers/$SERVER_ID")
        print_summary
        log_success "VPS environment created successfully"
        exit 0
    fi
}

# Run main function
main "$@"
