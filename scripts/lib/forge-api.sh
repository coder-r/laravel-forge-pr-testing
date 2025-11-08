#!/bin/bash

################################################################################
# Forge API Client Library - Complete v1 API Implementation
#
# A comprehensive bash library for interacting with the Laravel Forge API.
# Handles all major operations: servers, sites, databases, deployments, SSL,
# workers, and monitoring.
#
# USAGE:
#   source /path/to/forge-api.sh
#   forge_api_init "your-api-token"
#   list_servers
#   create_site "$server_id" "example.com" "laravel"
#
# DEPENDENCIES:
#   - curl
#   - jq (for JSON parsing)
#   - bash 4.0+
#
# API BASE: https://forge.laravel.com/api/v1
# RATE LIMIT: 60 requests per minute
#
################################################################################

# Global Configuration
FORGE_API_BASE="https://forge.laravel.com/api/v1"
FORGE_API_TOKEN=""
FORGE_DEBUG="${FORGE_DEBUG:-0}"
FORGE_LOG_FILE="${FORGE_LOG_FILE:-/tmp/forge-api.log}"
FORGE_RETRY_MAX=3
FORGE_RETRY_DELAY=1
FORGE_RATE_LIMIT_DELAY=1  # seconds between requests (60 req/min = 1 req/sec)

# Request tracking for rate limiting
FORGE_LAST_REQUEST_TIME=0

################################################################################
# INITIALIZATION & CONFIGURATION
################################################################################

# Initialize the API client with authentication token
# Usage: forge_api_init "your-api-token"
forge_api_init() {
    if [[ -z "$1" ]]; then
        echo "ERROR: API token required" >&2
        return 1
    fi
    FORGE_API_TOKEN="$1"
    _forge_log "Forge API initialized with token: ${FORGE_API_TOKEN:0:10}..."
    return 0
}

# Enable debug logging
forge_api_debug() {
    FORGE_DEBUG=1
    _forge_log "Debug logging enabled"
}

# Disable debug logging
forge_api_quiet() {
    FORGE_DEBUG=0
}

# Set custom log file
forge_api_set_log_file() {
    if [[ -z "$1" ]]; then
        echo "ERROR: Log file path required" >&2
        return 1
    fi
    FORGE_LOG_FILE="$1"
    mkdir -p "$(dirname "$FORGE_LOG_FILE")"
    _forge_log "Log file set to: $FORGE_LOG_FILE"
}

################################################################################
# INTERNAL UTILITIES
################################################################################

# Internal logging function
_forge_log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" >> "$FORGE_LOG_FILE"
    if [[ "$FORGE_DEBUG" == "1" ]]; then
        echo "[$timestamp] DEBUG: $*" >&2
    fi
}

# Enforce rate limiting (60 requests per minute = 1 request per second)
_forge_rate_limit() {
    local current_time
    current_time=$(date +%s%N)  # nanoseconds
    local elapsed_ms=$(( (current_time - FORGE_LAST_REQUEST_TIME) / 1000000 ))
    local min_delay_ms=$((FORGE_RATE_LIMIT_DELAY * 1000))

    if [[ $elapsed_ms -lt $min_delay_ms ]]; then
        local sleep_time=$(( (min_delay_ms - elapsed_ms) / 1000 ))
        if [[ $sleep_time -lt 1 ]]; then
            sleep 0.$(printf "%03d" $((min_delay_ms - elapsed_ms)))
        else
            sleep "$sleep_time"
        fi
    fi

    FORGE_LAST_REQUEST_TIME=$(date +%s%N)
}

# Validate API token is set
_forge_check_auth() {
    if [[ -z "$FORGE_API_TOKEN" ]]; then
        echo "ERROR: Forge API token not initialized. Call forge_api_init first." >&2
        return 1
    fi
    return 0
}

# Construct full API URL
_forge_api_url() {
    echo "${FORGE_API_BASE}${1}"
}

# Parse HTTP status code from curl response
_forge_parse_status() {
    local response="$1"
    echo "$response" | tail -n 1
}

# Parse response body (everything except last line which is HTTP status)
_forge_parse_body() {
    local response="$1"
    echo "$response" | head -n -1
}

# Make HTTP request with retry logic and error handling
# Usage: _forge_request "GET|POST|PUT|DELETE" "endpoint" "[data]" "[expected_status]"
_forge_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local expected_status="${4:-200}"
    local attempt=1
    local url

    _forge_check_auth || return 1

    url=$(_forge_api_url "$endpoint")

    _forge_log "Request: $method $endpoint (attempt $attempt/$FORGE_RETRY_MAX)"

    # Retry loop with exponential backoff
    while [[ $attempt -le $FORGE_RETRY_MAX ]]; do
        local response
        local http_status
        local curl_exit_code

        _forge_rate_limit

        # Make the request
        if [[ -z "$data" ]]; then
            response=$(curl -s -w "\n%{http_code}" \
                -X "$method" \
                -H "Authorization: Bearer $FORGE_API_TOKEN" \
                -H "Content-Type: application/json" \
                -H "Accept: application/json" \
                "$url" 2>&1)
        else
            response=$(curl -s -w "\n%{http_code}" \
                -X "$method" \
                -H "Authorization: Bearer $FORGE_API_TOKEN" \
                -H "Content-Type: application/json" \
                -H "Accept: application/json" \
                -d "$data" \
                "$url" 2>&1)
        fi

        curl_exit_code=$?
        http_status=$(_forge_parse_status "$response")

        # Check for curl errors
        if [[ $curl_exit_code -ne 0 ]]; then
            _forge_log "WARN: curl error (exit code: $curl_exit_code) on attempt $attempt"
            if [[ $attempt -lt $FORGE_RETRY_MAX ]]; then
                local backoff=$((FORGE_RETRY_DELAY * (2 ** (attempt - 1))))
                _forge_log "Retrying in ${backoff}s..."
                sleep "$backoff"
                ((attempt++))
                continue
            fi
            return 1
        fi

        # Check HTTP status
        if [[ "$http_status" == "$expected_status" ]] || [[ "$http_status" == "20"* ]]; then
            _forge_parse_body "$response"
            _forge_log "Success: $method $endpoint (status: $http_status)"
            return 0
        fi

        # Handle specific error statuses
        case "$http_status" in
            401)
                _forge_log "ERROR: Unauthorized (401) - Invalid or expired token"
                return 1
                ;;
            403)
                _forge_log "ERROR: Forbidden (403) - Insufficient permissions"
                return 1
                ;;
            404)
                _forge_log "ERROR: Not Found (404) - Resource does not exist"
                return 1
                ;;
            422)
                _forge_log "ERROR: Unprocessable Entity (422) - Validation error"
                _forge_parse_body "$response"
                return 1
                ;;
            429)
                _forge_log "WARN: Rate limited (429) - Too many requests"
                if [[ $attempt -lt $FORGE_RETRY_MAX ]]; then
                    local backoff=$((FORGE_RETRY_DELAY * (2 ** (attempt - 1))))
                    _forge_log "Retrying in ${backoff}s..."
                    sleep "$backoff"
                    ((attempt++))
                    continue
                fi
                return 1
                ;;
            500)
                _forge_log "WARN: Server Error (500) on attempt $attempt"
                if [[ $attempt -lt $FORGE_RETRY_MAX ]]; then
                    local backoff=$((FORGE_RETRY_DELAY * (2 ** (attempt - 1))))
                    _forge_log "Retrying in ${backoff}s..."
                    sleep "$backoff"
                    ((attempt++))
                    continue
                fi
                return 1
                ;;
            *)
                _forge_log "ERROR: Unexpected status code $http_status"
                _forge_parse_body "$response"
                return 1
                ;;
        esac
    done

    _forge_log "ERROR: Max retries exceeded for $method $endpoint"
    return 1
}

################################################################################
# SERVER OPERATIONS
################################################################################

# Create a new server
# Usage: create_server "linode" "us-east" "g6-nanode-1" "production-server"
# Providers: "linode", "aws", "digitalocean"
# Sizes vary by provider (g6-nanode-1, t3.micro, s-1vcpu-1gb, etc.)
create_server() {
    local provider="$1"
    local region="$2"
    local size="$3"
    local name="$4"

    if [[ -z "$provider" ]] || [[ -z "$region" ]] || [[ -z "$size" ]] || [[ -z "$name" ]]; then
        echo "ERROR: create_server requires provider, region, size, and name" >&2
        return 1
    fi

    local data
    data=$(cat <<EOF
{
    "provider": "$provider",
    "region": "$region",
    "size": "$size",
    "name": "$name"
}
EOF
    )

    _forge_request "POST" "/servers" "$data" "201"
}

# List all servers
# Usage: list_servers
list_servers() {
    _forge_request "GET" "/servers"
}

# Get specific server details
# Usage: get_server "12345"
get_server() {
    local server_id="$1"

    if [[ -z "$server_id" ]]; then
        echo "ERROR: get_server requires server_id" >&2
        return 1
    fi

    _forge_request "GET" "/servers/$server_id"
}

# Delete a server
# Usage: delete_server "12345"
# WARNING: This is destructive and cannot be undone
delete_server() {
    local server_id="$1"

    if [[ -z "$server_id" ]]; then
        echo "ERROR: delete_server requires server_id" >&2
        return 1
    fi

    _forge_log "WARNING: Deleting server $server_id - this action is irreversible"
    _forge_request "DELETE" "/servers/$server_id" "" "200"
}

# Reboot a server
# Usage: reboot_server "12345"
reboot_server() {
    local server_id="$1"

    if [[ -z "$server_id" ]]; then
        echo "ERROR: reboot_server requires server_id" >&2
        return 1
    fi

    local data='{"reboot": true}'
    _forge_request "POST" "/servers/$server_id/reboot" "$data" "200"
}

################################################################################
# SITE OPERATIONS
################################################################################

# Create a new site on a server
# Usage: create_site "12345" "example.com" "laravel" "true" "8.1"
# project_type: "laravel", "symfony", "wordpress", "static", "html"
# isolated: "true" or "false" (isolated PHP-FPM pool)
# php_version: "8.0", "8.1", "8.2", "8.3"
create_site() {
    local server_id="$1"
    local domain="$2"
    local project_type="$3"
    local isolated="${4:-true}"
    local php_version="${5:-8.2}"

    if [[ -z "$server_id" ]] || [[ -z "$domain" ]] || [[ -z "$project_type" ]]; then
        echo "ERROR: create_site requires server_id, domain, and project_type" >&2
        return 1
    fi

    local data
    data=$(cat <<EOF
{
    "domain": "$domain",
    "project_type": "$project_type",
    "isolated": $isolated,
    "php_version": "$php_version"
}
EOF
    )

    _forge_request "POST" "/servers/$server_id/sites" "$data" "201"
}

# List all sites on a server
# Usage: list_sites "12345"
list_sites() {
    local server_id="$1"

    if [[ -z "$server_id" ]]; then
        echo "ERROR: list_sites requires server_id" >&2
        return 1
    fi

    _forge_request "GET" "/servers/$server_id/sites"
}

# Get specific site details
# Usage: get_site "12345" "67890"
get_site() {
    local server_id="$1"
    local site_id="$2"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]]; then
        echo "ERROR: get_site requires server_id and site_id" >&2
        return 1
    fi

    _forge_request "GET" "/servers/$server_id/sites/$site_id"
}

# Update site configuration
# Usage: update_site "12345" "67890" '{"php_version": "8.3"}'
update_site() {
    local server_id="$1"
    local site_id="$2"
    local params="$3"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]] || [[ -z "$params" ]]; then
        echo "ERROR: update_site requires server_id, site_id, and params JSON" >&2
        return 1
    fi

    _forge_request "PUT" "/servers/$server_id/sites/$site_id" "$params" "200"
}

# Delete a site
# Usage: delete_site "12345" "67890"
# NOTE: This removes the site from Forge management but may not delete web files
delete_site() {
    local server_id="$1"
    local site_id="$2"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]]; then
        echo "ERROR: delete_site requires server_id and site_id" >&2
        return 1
    fi

    _forge_request "DELETE" "/servers/$server_id/sites/$site_id" "" "200"
}

################################################################################
# DATABASE OPERATIONS
################################################################################

# Create a new database on a server
# Usage: create_database "12345" "laravel_db" "laravel_user" "SecurePassword123"
create_database() {
    local server_id="$1"
    local name="$2"
    local user="$3"
    local password="$4"

    if [[ -z "$server_id" ]] || [[ -z "$name" ]] || [[ -z "$user" ]] || [[ -z "$password" ]]; then
        echo "ERROR: create_database requires server_id, name, user, and password" >&2
        return 1
    fi

    local data
    data=$(cat <<EOF
{
    "name": "$name",
    "user": "$user",
    "password": "$password"
}
EOF
    )

    _forge_request "POST" "/servers/$server_id/databases" "$data" "201"
}

# List all databases on a server
# Usage: list_databases "12345"
list_databases() {
    local server_id="$1"

    if [[ -z "$server_id" ]]; then
        echo "ERROR: list_databases requires server_id" >&2
        return 1
    fi

    _forge_request "GET" "/servers/$server_id/databases"
}

# Delete a database
# Usage: delete_database "12345" "67890"
# WARNING: This is destructive and cannot be undone
delete_database() {
    local server_id="$1"
    local database_id="$2"

    if [[ -z "$server_id" ]] || [[ -z "$database_id" ]]; then
        echo "ERROR: delete_database requires server_id and database_id" >&2
        return 1
    fi

    _forge_log "WARNING: Deleting database $database_id - data will be lost"
    _forge_request "DELETE" "/servers/$server_id/databases/$database_id" "" "200"
}

################################################################################
# GIT & DEPLOYMENT OPERATIONS
################################################################################

# Install a Git repository on a site
# Usage: install_git_repository "12345" "67890" "github" "user/repo" "main"
# provider: "github", "gitlab", "bitbucket", "custom"
# branch: typically "main" or "master"
install_git_repository() {
    local server_id="$1"
    local site_id="$2"
    local provider="$3"
    local repository="$4"
    local branch="${5:-main}"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]] || [[ -z "$provider" ]] || [[ -z "$repository" ]]; then
        echo "ERROR: install_git_repository requires server_id, site_id, provider, and repository" >&2
        return 1
    fi

    local data
    data=$(cat <<EOF
{
    "provider": "$provider",
    "repository": "$repository",
    "branch": "$branch"
}
EOF
    )

    _forge_request "POST" "/servers/$server_id/sites/$site_id/git" "$data" "201"
}

# Trigger a deployment for a site
# Usage: deploy_site "12345" "67890"
deploy_site() {
    local server_id="$1"
    local site_id="$2"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]]; then
        echo "ERROR: deploy_site requires server_id and site_id" >&2
        return 1
    fi

    local data='{"deploy": true}'
    _forge_request "POST" "/servers/$server_id/sites/$site_id/deployment/deploy" "$data" "200"
}

# Get deployment log for a site
# Usage: get_deployment_log "12345" "67890"
get_deployment_log() {
    local server_id="$1"
    local site_id="$2"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]]; then
        echo "ERROR: get_deployment_log requires server_id and site_id" >&2
        return 1
    fi

    _forge_request "GET" "/servers/$server_id/sites/$site_id/deployment/log"
}

# Update the deployment script (bash script that runs on deploy)
# Usage: update_deployment_script "12345" "67890" "#!/bin/bash\n..."
update_deployment_script() {
    local server_id="$1"
    local site_id="$2"
    local script="$3"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]] || [[ -z "$script" ]]; then
        echo "ERROR: update_deployment_script requires server_id, site_id, and script" >&2
        return 1
    fi

    # Escape newlines and quotes for JSON
    local escaped_script
    escaped_script=$(echo "$script" | jq -Rs '.')

    local data="{\"content\": $escaped_script}"
    _forge_request "PUT" "/servers/$server_id/sites/$site_id/deployment/script" "$data" "200"
}

################################################################################
# SSL CERTIFICATE OPERATIONS
################################################################################

# Obtain a Let's Encrypt SSL certificate for a site
# Usage: obtain_letsencrypt_certificate "12345" "67890" "example.com www.example.com"
# domains: space-separated list of domains
obtain_letsencrypt_certificate() {
    local server_id="$1"
    local site_id="$2"
    local domains="$3"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]] || [[ -z "$domains" ]]; then
        echo "ERROR: obtain_letsencrypt_certificate requires server_id, site_id, and domains" >&2
        return 1
    fi

    # Convert space-separated domains to JSON array
    local domains_json
    domains_json=$(echo "$domains" | jq -R 'split(" ")')

    local data="{\"domains\": $domains_json}"
    _forge_request "POST" "/servers/$server_id/sites/$site_id/certificates/letsencrypt" "$data" "201"
}

# Activate a certificate for a site
# Usage: activate_certificate "12345" "67890" "cert_id_12345"
activate_certificate() {
    local server_id="$1"
    local site_id="$2"
    local cert_id="$3"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]] || [[ -z "$cert_id" ]]; then
        echo "ERROR: activate_certificate requires server_id, site_id, and cert_id" >&2
        return 1
    fi

    local data="{\"certificate_id\": $cert_id}"
    _forge_request "POST" "/servers/$server_id/sites/$site_id/certificates/activate" "$data" "200"
}

################################################################################
# ENVIRONMENT VARIABLE OPERATIONS
################################################################################

# Update environment variables for a site
# Usage: update_environment "12345" "67890" "APP_DEBUG=false\nAPP_ENV=production"
# env_content: newline-separated KEY=VALUE pairs
update_environment() {
    local server_id="$1"
    local site_id="$2"
    local env_content="$3"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]] || [[ -z "$env_content" ]]; then
        echo "ERROR: update_environment requires server_id, site_id, and env_content" >&2
        return 1
    fi

    # Escape content for JSON
    local escaped_content
    escaped_content=$(echo "$env_content" | jq -Rs '.')

    local data="{\"content\": $escaped_content}"
    _forge_request "PUT" "/servers/$server_id/sites/$site_id/env" "$data" "200"
}

################################################################################
# WORKER OPERATIONS
################################################################################

# Create a queue worker for a site
# Usage: create_worker "12345" "67890" "database" "default" "1"
# connection: "database", "redis", "sqs"
# queue: typically "default"
# processes: number of worker processes to run
create_worker() {
    local server_id="$1"
    local site_id="$2"
    local connection="$3"
    local queue="$4"
    local processes="${5:-1}"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]] || [[ -z "$connection" ]] || [[ -z "$queue" ]]; then
        echo "ERROR: create_worker requires server_id, site_id, connection, and queue" >&2
        return 1
    fi

    local data
    data=$(cat <<EOF
{
    "connection": "$connection",
    "queue": "$queue",
    "processes": $processes
}
EOF
    )

    _forge_request "POST" "/servers/$server_id/sites/$site_id/workers" "$data" "201"
}

# List all workers for a site
# Usage: list_workers "12345" "67890"
list_workers() {
    local server_id="$1"
    local site_id="$2"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]]; then
        echo "ERROR: list_workers requires server_id and site_id" >&2
        return 1
    fi

    _forge_request "GET" "/servers/$server_id/sites/$site_id/workers"
}

# Delete a worker
# Usage: delete_worker "12345" "67890" "worker_id_123"
delete_worker() {
    local server_id="$1"
    local site_id="$2"
    local worker_id="$3"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]] || [[ -z "$worker_id" ]]; then
        echo "ERROR: delete_worker requires server_id, site_id, and worker_id" >&2
        return 1
    fi

    _forge_request "DELETE" "/servers/$server_id/sites/$site_id/workers/$worker_id" "" "200"
}

################################################################################
# MONITORING & HEALTH OPERATIONS
################################################################################

# Get server metrics and health information
# Usage: get_server_metrics "12345"
# Returns: CPU, memory, disk usage, load average, etc.
get_server_metrics() {
    local server_id="$1"

    if [[ -z "$server_id" ]]; then
        echo "ERROR: get_server_metrics requires server_id" >&2
        return 1
    fi

    _forge_request "GET" "/servers/$server_id/metrics"
}

# Check the health status of a site
# Usage: check_site_health "12345" "67890"
# Returns: uptime status, response time, SSL certificate expiry, etc.
check_site_health() {
    local server_id="$1"
    local site_id="$2"

    if [[ -z "$server_id" ]] || [[ -z "$site_id" ]]; then
        echo "ERROR: check_site_health requires server_id and site_id" >&2
        return 1
    fi

    _forge_request "GET" "/servers/$server_id/sites/$site_id/health"
}

################################################################################
# HELPER FUNCTIONS FOR RESPONSE PARSING
################################################################################

# Extract field from JSON response
# Usage: forge_get_field "id" <<< "$response"
forge_get_field() {
    local field="$1"
    jq -r ".${field}" 2>/dev/null || jq -r ".data.${field}" 2>/dev/null
}

# Extract array from JSON response
# Usage: forge_get_array "servers" <<< "$response"
forge_get_array() {
    local field="$1"
    jq -r ".${field}" 2>/dev/null || jq -r ".data" 2>/dev/null
}

# Pretty print JSON response
# Usage: forge_pretty_json <<< "$response"
forge_pretty_json() {
    jq '.' 2>/dev/null || cat
}

# Extract multiple fields into variables
# Usage: forge_extract_fields response "id" "domain" "name"
forge_extract_fields() {
    local response="$1"
    shift
    local fields=("$@")

    for field in "${fields[@]}"; do
        local value
        value=$(echo "$response" | jq -r ".${field} // .data.${field}" 2>/dev/null)
        printf "%s=%s\n" "$field" "$value"
    done
}

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Test API connection
# Usage: forge_test_connection
forge_test_connection() {
    _forge_check_auth || return 1

    echo "Testing Forge API connection..."
    if list_servers > /dev/null 2>&1; then
        echo "SUCCESS: API connection verified"
        return 0
    else
        echo "ERROR: Could not connect to Forge API"
        return 1
    fi
}

# Get current rate limit status from headers
# Note: This is informational, actual rate limiting is handled internally
forge_get_rate_limit_info() {
    echo "Rate Limit Info:"
    echo "  Limit: 60 requests per minute"
    echo "  Minimum delay between requests: 1 second (enforced)"
    echo "  Last request time: $FORGE_LAST_REQUEST_TIME"
}

# Print API library version and info
forge_api_version() {
    cat <<EOF
Forge API Client Library
Version: 1.0.0
API Base: $FORGE_API_BASE
Debug Mode: $FORGE_DEBUG
Log File: $FORGE_LOG_FILE
Retry Policy: $FORGE_RETRY_MAX attempts with exponential backoff
EOF
}

################################################################################
# USAGE EXAMPLES (for reference)
################################################################################

# Example: Complete workflow
# Usage: source /path/to/forge-api.sh && example_workflow
example_workflow() {
    cat <<'EXAMPLE'
# Initialize with API token
forge_api_init "your-forge-api-token"
forge_api_debug  # Enable debug logging

# List existing servers
echo "=== Listing Servers ==="
response=$(list_servers)
echo "$response" | jq '.'

# Create a new server
echo "=== Creating Server ==="
server_response=$(create_server "linode" "us-east" "g6-nanode-1" "web-server-1")
server_id=$(echo "$server_response" | jq -r '.data.id')
echo "Created server: $server_id"

# Create a site on the server
echo "=== Creating Site ==="
site_response=$(create_site "$server_id" "example.com" "laravel" "true" "8.2")
site_id=$(echo "$site_response" | jq -r '.data.id')
echo "Created site: $site_id"

# Create a database
echo "=== Creating Database ==="
db_response=$(create_database "$server_id" "example_db" "example_user" "SecurePassword123!")
db_id=$(echo "$db_response" | jq -r '.data.id')
echo "Created database: $db_id"

# Update environment variables
echo "=== Updating Environment ==="
env_content="APP_ENV=production
APP_DEBUG=false
DB_DATABASE=example_db
DB_USERNAME=example_user"
update_environment "$server_id" "$site_id" "$env_content"

# Install Git repository
echo "=== Installing Git Repository ==="
install_git_repository "$server_id" "$site_id" "github" "user/repo" "main"

# Deploy the site
echo "=== Deploying Site ==="
deploy_site "$server_id" "$site_id"

# Check deployment log
echo "=== Checking Deployment Log ==="
log=$(get_deployment_log "$server_id" "$site_id")
echo "$log" | jq '.data' -r

# Obtain SSL certificate
echo "=== Installing SSL Certificate ==="
obtain_letsencrypt_certificate "$server_id" "$site_id" "example.com www.example.com"

# Create a queue worker
echo "=== Creating Queue Worker ==="
worker_response=$(create_worker "$server_id" "$site_id" "database" "default" "2")
worker_id=$(echo "$worker_response" | jq -r '.data.id')
echo "Created worker: $worker_id"

# Get server metrics
echo "=== Server Metrics ==="
get_server_metrics "$server_id" | jq '.'

# Check site health
echo "=== Site Health ==="
check_site_health "$server_id" "$site_id" | jq '.'

EXAMPLE
}

# End of forge-api.sh library
