#!/bin/bash

################################################################################
# Forge API Helper Functions Library
#
# Provides utility functions for working with the Laravel Forge API
# Source this file in other scripts:
#   source ./forge-api-helpers.sh
#
################################################################################

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

# API Configuration
readonly FORGE_API_BASE="${FORGE_API_BASE:-https://forge.laravel.com/api/v1}"
readonly FORGE_API_TOKEN="${FORGE_API_TOKEN:-}"
readonly FORGE_SERVER_ID="${FORGE_SERVER_ID:-}"

################################################################################
# Core API Functions
################################################################################

# Validate API token
forge_validate_token() {
    if [ -z "$FORGE_API_TOKEN" ]; then
        echo -e "${RED}Error: FORGE_API_TOKEN not set${RESET}" >&2
        return 1
    fi

    local response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $FORGE_API_TOKEN" \
        "$FORGE_API_BASE/servers" \
        -H "Accept: application/json")

    if [ "$response" = "200" ]; then
        echo -e "${GREEN}Token valid${RESET}"
        return 0
    else
        echo -e "${RED}Token invalid (HTTP $response)${RESET}" >&2
        return 1
    fi
}

# Validate server ID
forge_validate_server() {
    if [ -z "$FORGE_SERVER_ID" ]; then
        echo -e "${RED}Error: FORGE_SERVER_ID not set${RESET}" >&2
        return 1
    fi

    local response=$(forge_api_get "/servers/$FORGE_SERVER_ID")

    if echo "$response" | grep -q "error\|401\|403"; then
        echo -e "${RED}Server ID invalid or inaccessible${RESET}" >&2
        return 1
    fi

    echo -e "${GREEN}Server ID valid${RESET}"
    return 0
}

# Make GET request to Forge API
forge_api_get() {
    local endpoint="$1"
    local url="${FORGE_API_BASE}${endpoint}"

    curl -s \
        -H "Authorization: Bearer $FORGE_API_TOKEN" \
        -H "Accept: application/json" \
        "$url"
}

# Make POST request to Forge API
forge_api_post() {
    local endpoint="$1"
    local data="$2"
    local url="${FORGE_API_BASE}${endpoint}"

    curl -s -X POST \
        -H "Authorization: Bearer $FORGE_API_TOKEN" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "$data" \
        "$url"
}

# Make DELETE request to Forge API
forge_api_delete() {
    local endpoint="$1"
    local url="${FORGE_API_BASE}${endpoint}"

    curl -s -X DELETE \
        -H "Authorization: Bearer $FORGE_API_TOKEN" \
        -H "Accept: application/json" \
        "$url"
}

################################################################################
# Server Management Functions
################################################################################

# Get list of all servers
forge_get_servers() {
    forge_api_get "/servers"
}

# Get specific server information
forge_get_server() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    forge_api_get "/servers/$server_id"
}

# Get server SSH keys
forge_get_server_ssh_keys() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    forge_api_get "/servers/$server_id/ssh-keys"
}

# Get server daemons
forge_get_server_daemons() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    forge_api_get "/servers/$server_id/daemons"
}

# Get server cron jobs
forge_get_server_cron_jobs() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    forge_api_get "/servers/$server_id/cron-jobs"
}

# Reboot server
forge_reboot_server() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    forge_api_post "/servers/$server_id/reboot" "{}"
    echo -e "${GREEN}Server reboot initiated${RESET}"
}

################################################################################
# Site Management Functions
################################################################################

# Get all sites on server
forge_get_sites() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    forge_api_get "/servers/$server_id/sites"
}

# Get specific site information
forge_get_site() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local site_id="$2"
    forge_api_get "/servers/$server_id/sites/$site_id"
}

# Get site deployment log
forge_get_site_deployment_log() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local site_id="$2"
    forge_api_get "/servers/$server_id/sites/$site_id/deployment-log"
}

# Get site PHP version
forge_get_site_php_version() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local site_id="$2"

    local site_data=$(forge_get_site "$server_id" "$site_id")
    echo "$site_data" | grep -o '"php_version":"[^"]*' | cut -d'"' -f4
}

# Update site PHP version
forge_update_site_php_version() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local site_id="$2"
    local php_version="$3"

    local data=$(cat <<EOF
{
    "php_version": "$php_version"
}
EOF
)

    forge_api_post "/servers/$server_id/sites/$site_id/php" "$data"
    echo -e "${GREEN}PHP version updated to $php_version${RESET}"
}

# Get site SSL certificates
forge_get_site_certificates() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local site_id="$2"
    forge_api_get "/servers/$server_id/sites/$site_id/certificates"
}

# Get site environment
forge_get_site_env() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local site_id="$2"
    forge_api_get "/servers/$server_id/sites/$site_id/env"
}

# Deploy site
forge_deploy_site() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local site_id="$2"

    forge_api_post "/servers/$server_id/sites/$site_id/deployment/deploy" "{}"
    echo -e "${GREEN}Deployment initiated${RESET}"
}

# Create new site
forge_create_site() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local domain="$2"
    local project_type="${3:-php}"

    local data=$(cat <<EOF
{
    "domain": "$domain",
    "project_type": "$project_type"
}
EOF
)

    forge_api_post "/servers/$server_id/sites" "$data"
    echo -e "${GREEN}Site created for $domain${RESET}"
}

################################################################################
# Database Functions
################################################################################

# Get all databases on server
forge_get_databases() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    forge_api_get "/servers/$server_id/databases"
}

# Get specific database
forge_get_database() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local database_id="$2"
    forge_api_get "/servers/$server_id/databases/$database_id"
}

# Get database users
forge_get_database_users() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    forge_api_get "/servers/$server_id/database-users"
}

# Create new database
forge_create_database() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local name="$2"

    local data=$(cat <<EOF
{
    "name": "$name"
}
EOF
)

    forge_api_post "/servers/$server_id/databases" "$data"
    echo -e "${GREEN}Database '$name' created${RESET}"
}

# Create database user
forge_create_database_user() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local name="$2"
    local password="$3"

    local data=$(cat <<EOF
{
    "name": "$name",
    "password": "$password"
}
EOF
)

    forge_api_post "/servers/$server_id/database-users" "$data"
    echo -e "${GREEN}Database user '$name' created${RESET}"
}

################################################################################
# Worker Functions
################################################################################

# Get all workers
forge_get_workers() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    forge_api_get "/servers/$server_id/workers"
}

# Get specific worker
forge_get_worker() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local worker_id="$2"
    forge_api_get "/servers/$server_id/workers/$worker_id"
}

# Create new worker
forge_create_worker() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local site_id="$2"
    local name="$3"

    local data=$(cat <<EOF
{
    "name": "$name",
    "connection": "default",
    "queue": "default",
    "force": false
}
EOF
)

    forge_api_post "/servers/$server_id/sites/$site_id/workers" "$data"
    echo -e "${GREEN}Worker '$name' created${RESET}"
}

# Restart worker
forge_restart_worker() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local worker_id="$2"

    forge_api_post "/servers/$server_id/workers/$worker_id/restart" "{}"
    echo -e "${GREEN}Worker restarted${RESET}"
}

# Delete worker
forge_delete_worker() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local worker_id="$2"

    forge_api_delete "/servers/$server_id/workers/$worker_id"
    echo -e "${GREEN}Worker deleted${RESET}"
}

################################################################################
# Certificate Functions
################################################################################

# Get LetsEncrypt certificate status
forge_get_certificate() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local site_id="$2"

    forge_api_get "/servers/$server_id/sites/$site_id/certificates"
}

# Create LetsEncrypt certificate
forge_create_letsencrypt_certificate() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local site_id="$2"

    local data=$(cat <<EOF
{
    "domain": "domain.com",
    "country": "US",
    "state": "State",
    "city": "City",
    "organization": "Organization"
}
EOF
)

    forge_api_post "/servers/$server_id/sites/$site_id/certificates/letsencrypt" "$data"
    echo -e "${GREEN}LetsEncrypt certificate requested${RESET}"
}

################################################################################
# Firewall Functions
################################################################################

# Get firewall rules
forge_get_firewall_rules() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    forge_api_get "/servers/$server_id/firewall-rules"
}

# Create firewall rule
forge_create_firewall_rule() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local name="$2"
    local port="$3"

    local data=$(cat <<EOF
{
    "name": "$name",
    "port": $port
}
EOF
)

    forge_api_post "/servers/$server_id/firewall-rules" "$data"
    echo -e "${GREEN}Firewall rule created: $name on port $port${RESET}"
}

# Delete firewall rule
forge_delete_firewall_rule() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local rule_id="$2"

    forge_api_delete "/servers/$server_id/firewall-rules/$rule_id"
    echo -e "${GREEN}Firewall rule deleted${RESET}"
}

################################################################################
# Monitoring & Analysis Functions
################################################################################

# Get server creation date
forge_get_server_created_date() {
    local server_id="${1:-$FORGE_SERVER_ID}"

    local server_data=$(forge_get_server "$server_id")
    echo "$server_data" | grep -o '"created_at":"[^"]*' | cut -d'"' -f4
}

# Calculate monthly cost estimate
forge_estimate_monthly_cost() {
    local server_size="$1"

    case "$server_size" in
        "512")      echo "5.00" ;;      # $5/month
        "1GB")      echo "10.00" ;;     # $10/month
        "2GB")      echo "20.00" ;;     # $20/month
        "4GB")      echo "40.00" ;;     # $40/month
        "8GB")      echo "80.00" ;;     # $80/month
        "16GB")     echo "160.00" ;;    # $160/month
        *)          echo "0.00" ;;
    esac
}

# Count total resources
forge_count_resources() {
    local server_id="${1:-$FORGE_SERVER_ID}"

    local sites=$(forge_get_sites "$server_id" | grep -o '"id":[0-9]*' | wc -l)
    local databases=$(forge_get_databases "$server_id" | grep -o '"id":[0-9]*' | wc -l)
    local workers=$(forge_get_workers "$server_id" | grep -o '"id":[0-9]*' | wc -l)

    echo "Sites: $sites, Databases: $databases, Workers: $workers"
}

# List all domains on server
forge_list_domains() {
    local server_id="${1:-$FORGE_SERVER_ID}"

    local sites=$(forge_get_sites "$server_id")
    echo "$sites" | grep -o '"domain":"[^"]*' | cut -d'"' -f4
}

# Generate server report
forge_generate_server_report() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local output_file="${2:-/tmp/forge_server_report.txt}"

    {
        echo "=================================="
        echo "Forge Server Report"
        echo "Generated: $(date)"
        echo "Server ID: $server_id"
        echo "=================================="
        echo ""

        echo "Server Information:"
        local server_data=$(forge_get_server "$server_id")
        echo "$server_data" | jq . 2>/dev/null || echo "$server_data"
        echo ""

        echo "Sites:"
        forge_list_domains "$server_id"
        echo ""

        echo "Resource Count:"
        forge_count_resources "$server_id"
        echo ""

    } > "$output_file"

    echo -e "${GREEN}Report generated: $output_file${RESET}"
}

################################################################################
# Utility Functions
################################################################################

# Pretty print JSON
forge_pretty_json() {
    jq . 2>/dev/null || cat
}

# Extract value from JSON response
forge_json_extract() {
    local json="$1"
    local key="$2"

    echo "$json" | grep -o "\"$key\":[^,}]*" | cut -d':' -f2- | sed 's/[",]//g'
}

# Format bytes to human readable
forge_format_bytes() {
    local bytes=$1

    if command -v numfmt &>/dev/null; then
        numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
    else
        echo "${bytes}B"
    fi
}

# Print formatted table
forge_print_table() {
    local headers=("$@")
    local width=20

    for header in "${headers[@]}"; do
        printf "%-${width}s" "$header"
    done
    echo ""

    for header in "${headers[@]}"; do
        printf "%-${width}s" "$(printf '%.0s-' $(seq 1 $width))"
    done
    echo ""
}

################################################################################
# Batch Operations
################################################################################

# Restart all workers
forge_restart_all_workers() {
    local server_id="${1:-$FORGE_SERVER_ID}"

    local workers=$(forge_get_workers "$server_id")
    local worker_ids=$(echo "$workers" | grep -o '"id":[0-9]*' | cut -d':' -f2)

    if [ -z "$worker_ids" ]; then
        echo -e "${YELLOW}No workers found${RESET}"
        return
    fi

    echo "$worker_ids" | while read -r worker_id; do
        forge_restart_worker "$server_id" "$worker_id"
        echo -e "${GREEN}Restarted worker $worker_id${RESET}"
    done
}

# List all SSL certificates with expiry
forge_list_certificates_with_expiry() {
    local server_id="${1:-$FORGE_SERVER_ID}"

    local sites=$(forge_get_sites "$server_id")
    local site_ids=$(echo "$sites" | grep -o '"id":[0-9]*' | cut -d':' -f2)

    echo "$site_ids" | while read -r site_id; do
        local certs=$(forge_get_site_certificates "$server_id" "$site_id")
        echo "$certs" | grep -o '"domain":"[^"]*' | cut -d'"' -f4
    done | sort -u
}

################################################################################
# Export Functions
################################################################################

# Export server configuration to JSON
forge_export_server_config() {
    local server_id="${1:-$FORGE_SERVER_ID}"
    local output_file="${2:-server_config.json}"

    {
        echo "{"
        echo '  "server": '"$(forge_get_server "$server_id")"','
        echo '  "sites": '"$(forge_get_sites "$server_id")"','
        echo '  "databases": '"$(forge_get_databases "$server_id")"','
        echo '  "workers": '"$(forge_get_workers "$server_id")"','
        echo '  "firewall_rules": '"$(forge_get_firewall_rules "$server_id")"
        echo "}"
    } > "$output_file"

    echo -e "${GREEN}Configuration exported to $output_file${RESET}"
}

echo -e "${CYAN}Forge API Helper Functions Library Loaded${RESET}"
