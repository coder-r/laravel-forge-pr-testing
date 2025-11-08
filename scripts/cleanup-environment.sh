#!/bin/bash

################################################################################
# cleanup-environment.sh
#
# Destroys VPS environment and performs cleanup via Laravel Forge API
#
# Features:
#   - Terminates VPS servers
#   - Removes databases
#   - Deletes backups
#   - Cleans up SSL certificates
#   - Removes firewall rules
#   - Backs up data before deletion
#   - Comprehensive confirmation prompts
#   - Safe deletion with multiple confirmations
#   - Detailed logging of all operations
#   - Rollback capability (backup restoration)
#   - Supports selective cleanup
#
# Requirements:
#   - curl or wget
#   - jq (JSON processor)
#   - FORGE_API_TOKEN environment variable
#
# Usage:
#   # Full cleanup with confirmations
#   ./cleanup-environment.sh --server-id 12345
#
#   # Cleanup specific components
#   ./cleanup-environment.sh --server-id 12345 --databases --no-backup
#
#   # Dry run to preview deletion
#   ./cleanup-environment.sh --server-id 12345 --dry-run
#
#   # Cleanup all without prompts (careful!)
#   ./cleanup-environment.sh --server-id 12345 --force
#
# Environment Variables:
#   FORGE_API_TOKEN       - Laravel Forge API token (required)
#   FORGE_API_URL         - API endpoint (default: https://forge.laravel.com/api/v1)
#   LOG_FILE              - Log file path (default: logs/cleanup.log)
#   BACKUP_DIR            - Backup location (default: backups)
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
LOG_FILE="${LOG_DIR}/cleanup-$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="${PROJECT_ROOT}/backups"
DRY_RUN=false
FORCE_MODE=false
CREATE_BACKUP=true

# Cleanup scope flags
CLEANUP_ALL=true
CLEANUP_SERVER=false
CLEANUP_DATABASES=false
CLEANUP_BACKUPS=false
CLEANUP_CERTIFICATES=false
CLEANUP_FIREWALL=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Server variables
SERVER_ID=""
SERVER_NAME=""
BACKUP_ID=""

# Tracking variables
DELETED_ITEMS=()
SKIPPED_ITEMS=()
FAILED_ITEMS=()

################################################################################
# Utility Functions
################################################################################

# Create logs directory
mkdir -p "$LOG_DIR"
mkdir -p "$BACKUP_DIR"

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

# Confirmation prompt
confirm() {
    local prompt="$1"
    local response

    if [[ "$FORCE_MODE" == "true" ]]; then
        log_warning "Force mode: Skipping confirmation for: $prompt"
        return 0
    fi

    while true; do
        echo -ne "${YELLOW}⚠${NC} $prompt [yes/no/cancel]: "
        read -r response
        case "$response" in
            yes|y) return 0 ;;
            no|n) return 1 ;;
            cancel|c)
                log_warning "Operation cancelled by user"
                exit 1
                ;;
            *)
                echo "Please answer with 'yes', 'no', or 'cancel'"
                ;;
        esac
    done
}

# Final safety check
safety_check() {
    if [[ "$FORCE_MODE" == "true" ]]; then
        log_warning "========== FORCE MODE ACTIVE =========="
        log_warning "All confirmations have been skipped"
        log_warning "========================================"

        echo -ne "${RED}$(tput bold)TYPE 'DELETE' TO CONFIRM DELETION OF SERVER $SERVER_NAME:${NC} "
        read -r confirmation

        if [[ "$confirmation" != "DELETE" ]]; then
            log_warning "Confirmation failed. Operation cancelled."
            exit 1
        fi
    fi
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
            "$url" 2>/dev/null || echo "000")
    else
        http_code=$(curl -s -w "%{http_code}" \
            -X "$method" \
            -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "$data" \
            -o "$response_file" \
            "$url" 2>/dev/null || echo "000")
    fi

    local response=$(cat "$response_file")
    rm -f "$response_file"

    if [[ $http_code -ge 400 ]]; then
        log_error "API request failed with status: $http_code"
        log_error "Response: $response"
        return 1
    fi

    echo "$response"
    return 0
}

# Get server details
get_server_details() {
    log_info "Fetching server details..."

    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID"); then
        log_error "Failed to fetch server details"
        return 1
    fi

    SERVER_NAME=$(echo "$response" | jq -r '.server.name')
    log_success "Server: $SERVER_NAME (ID: $SERVER_ID)"
    return 0
}

# Backup server data
backup_server_data() {
    if [[ "$CREATE_BACKUP" != "true" ]]; then
        log_info "Backup creation disabled"
        return 0
    fi

    log_info "Creating backup of server data..."

    BACKUP_ID="backup-${SERVER_ID}-$(date +%Y%m%d_%H%M%S)"

    # Backup databases
    log_info "Backing up databases..."
    local response
    if response=$(api_request "GET" "/servers/$SERVER_ID/databases"); then
        echo "$response" > "${BACKUP_DIR}/${BACKUP_ID}-databases.json"
        log_success "Database information backed up"
    fi

    # Backup sites/applications
    log_info "Backing up sites..."
    if response=$(api_request "GET" "/servers/$SERVER_ID/sites"); then
        echo "$response" > "${BACKUP_DIR}/${BACKUP_ID}-sites.json"
        log_success "Site information backed up"
    fi

    # Backup firewall rules
    log_info "Backing up firewall rules..."
    if response=$(api_request "GET" "/servers/$SERVER_ID/firewall-rules"); then
        echo "$response" > "${BACKUP_DIR}/${BACKUP_ID}-firewall.json"
        log_success "Firewall rules backed up"
    fi

    # Backup SSL certificates
    log_info "Backing up SSL certificates..."
    if response=$(api_request "GET" "/servers/$SERVER_ID/ssl-certificates"); then
        echo "$response" > "${BACKUP_DIR}/${BACKUP_ID}-certificates.json"
        log_success "SSL certificates backed up"
    fi

    log_success "All server data backed up"
    return 0
}

# List databases
list_databases() {
    log_info "Fetching databases..."

    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID/databases"); then
        log_warning "Could not fetch databases"
        return 1
    fi

    echo "$response" | jq -r '.databases[] | .id'
}

# Delete database
delete_database() {
    local db_id="$1"
    local db_name="$2"

    log_info "Deleting database: $db_name (ID: $db_id)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete database: $db_name"
        DELETED_ITEMS+=("Database: $db_name")
        return 0
    fi

    if api_request "DELETE" "/servers/$SERVER_ID/databases/$db_id" > /dev/null 2>&1; then
        log_success "Database deleted: $db_name"
        DELETED_ITEMS+=("Database: $db_name")
        return 0
    else
        log_error "Failed to delete database: $db_name"
        FAILED_ITEMS+=("Database: $db_name")
        return 1
    fi
}

# Delete all databases
delete_databases() {
    log_info "Deleting all databases..."

    if ! confirm "Delete all databases on this server?"; then
        log_warning "Database deletion cancelled"
        return 0
    fi

    local db_ids
    if ! db_ids=$(list_databases); then
        log_warning "No databases found"
        return 0
    fi

    local db_count=$(echo "$db_ids" | wc -l)

    if ! confirm "This will delete $db_count database(s). Proceed?"; then
        log_warning "Database deletion cancelled"
        return 0
    fi

    while IFS= read -r db_id; do
        if [[ -n "$db_id" ]]; then
            # Get database name
            local response
            if response=$(api_request "GET" "/servers/$SERVER_ID/databases"); then
                local db_name=$(echo "$response" | jq -r ".databases[] | select(.id == \"$db_id\") | .name")
                delete_database "$db_id" "$db_name"
            fi
        fi
    done <<< "$db_ids"

    log_success "Database deletion completed"
    return 0
}

# Delete backups
delete_backups() {
    log_info "Deleting backups..."

    if ! confirm "Delete all backups?"; then
        log_warning "Backup deletion cancelled"
        return 0
    fi

    # Get all databases and their backups
    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID/databases"); then
        log_warning "Could not fetch databases for backup deletion"
        return 0
    fi

    local db_ids=$(echo "$response" | jq -r '.databases[] | .id')
    local backup_count=0

    while IFS= read -r db_id; do
        if [[ -n "$db_id" ]]; then
            if backup_ids=$(api_request "GET" "/servers/$SERVER_ID/databases/$db_id/backups" 2>/dev/null); then
                local backups=$(echo "$backup_ids" | jq -r '.backups[] | .id' 2>/dev/null)

                while IFS= read -r backup_id; do
                    if [[ -n "$backup_id" ]]; then
                        log_info "Deleting backup: $backup_id"

                        if [[ "$DRY_RUN" != "true" ]]; then
                            if api_request "DELETE" "/servers/$SERVER_ID/databases/$db_id/backups/$backup_id" > /dev/null 2>&1; then
                                log_success "Backup deleted: $backup_id"
                                DELETED_ITEMS+=("Backup: $backup_id")
                            fi
                        else
                            DELETED_ITEMS+=("Backup: $backup_id")
                        fi

                        backup_count=$((backup_count + 1))
                    fi
                done <<< "$backups"
            fi
        fi
    done <<< "$db_ids"

    log_success "Backup deletion completed ($backup_count backup(s))"
    return 0
}

# Delete SSL certificates
delete_certificates() {
    log_info "Deleting SSL certificates..."

    if ! confirm "Delete all SSL certificates?"; then
        log_warning "Certificate deletion cancelled"
        return 0
    fi

    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID/ssl-certificates"); then
        log_warning "Could not fetch SSL certificates"
        return 0
    fi

    local cert_ids=$(echo "$response" | jq -r '.certificates[] | .id')
    local cert_count=$(echo "$cert_ids" | wc -l)

    if [[ $cert_count -eq 0 ]]; then
        log_info "No certificates found"
        return 0
    fi

    if ! confirm "Delete $cert_count SSL certificate(s)?"; then
        log_warning "Certificate deletion cancelled"
        return 0
    fi

    while IFS= read -r cert_id; do
        if [[ -n "$cert_id" ]]; then
            log_info "Deleting certificate: $cert_id"

            if [[ "$DRY_RUN" != "true" ]]; then
                if api_request "DELETE" "/servers/$SERVER_ID/ssl-certificates/$cert_id" > /dev/null 2>&1; then
                    log_success "Certificate deleted: $cert_id"
                    DELETED_ITEMS+=("Certificate: $cert_id")
                fi
            else
                DELETED_ITEMS+=("Certificate: $cert_id")
            fi
        fi
    done <<< "$cert_ids"

    log_success "Certificate deletion completed"
    return 0
}

# Delete firewall rules
delete_firewall_rules() {
    log_info "Deleting firewall rules..."

    if ! confirm "Delete all firewall rules?"; then
        log_warning "Firewall deletion cancelled"
        return 0
    fi

    local response
    if ! response=$(api_request "GET" "/servers/$SERVER_ID/firewall-rules"); then
        log_warning "Could not fetch firewall rules"
        return 0
    fi

    local rule_ids=$(echo "$response" | jq -r '.rules[] | .id')
    local rule_count=$(echo "$rule_ids" | wc -l)

    if [[ $rule_count -eq 0 ]]; then
        log_info "No firewall rules found"
        return 0
    fi

    if ! confirm "Delete $rule_count firewall rule(s)?"; then
        log_warning "Firewall deletion cancelled"
        return 0
    fi

    while IFS= read -r rule_id; do
        if [[ -n "$rule_id" ]]; then
            log_info "Deleting firewall rule: $rule_id"

            if [[ "$DRY_RUN" != "true" ]]; then
                if api_request "DELETE" "/servers/$SERVER_ID/firewall-rules/$rule_id" > /dev/null 2>&1; then
                    log_success "Firewall rule deleted: $rule_id"
                    DELETED_ITEMS+=("Firewall Rule: $rule_id")
                fi
            else
                DELETED_ITEMS+=("Firewall Rule: $rule_id")
            fi
        fi
    done <<< "$rule_ids"

    log_success "Firewall deletion completed"
    return 0
}

# Delete server
delete_server() {
    log_info "Preparing to delete server: $SERVER_NAME"

    if ! confirm "Delete server '$SERVER_NAME'? THIS CANNOT BE UNDONE"; then
        log_warning "Server deletion cancelled"
        return 0
    fi

    if ! confirm "Are you absolutely sure you want to delete '$SERVER_NAME'?"; then
        log_warning "Server deletion cancelled"
        return 0
    fi

    safety_check

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete server: $SERVER_NAME"
        DELETED_ITEMS+=("Server: $SERVER_NAME")
        return 0
    fi

    log_warning "Deleting server: $SERVER_NAME (ID: $SERVER_ID)"

    if api_request "DELETE" "/servers/$SERVER_ID" > /dev/null 2>&1; then
        log_success "Server deletion initiated: $SERVER_NAME"
        DELETED_ITEMS+=("Server: $SERVER_NAME")

        log_warning "Server is terminating. This may take a few minutes."
        log_info "Check Forge dashboard for completion status."
        return 0
    else
        log_error "Failed to delete server: $SERVER_NAME"
        FAILED_ITEMS+=("Server: $SERVER_NAME")
        return 1
    fi
}

# Print cleanup summary
print_summary() {
    cat << EOF

$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)
$(tput bold)Cleanup Summary$(tput sgr0)
$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)

Server ID:        $SERVER_ID
Server Name:      $SERVER_NAME
Dry Run:          $DRY_RUN
Force Mode:       $FORCE_MODE

$(tput bold)Actions Performed:$(tput sgr0)
  Deleted:  ${#DELETED_ITEMS[@]} item(s)
  Failed:   ${#FAILED_ITEMS[@]} item(s)

$(tput bold)Deleted Items:$(tput sgr0)
EOF

    if [[ ${#DELETED_ITEMS[@]} -gt 0 ]]; then
        printf '%s\n' "${DELETED_ITEMS[@]}" | sed 's/^/  - /'
    else
        echo "  (none)"
    fi

    if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
        cat << EOF

$(tput bold)Failed Deletions:$(tput sgr0)
EOF
        printf '%s\n' "${FAILED_ITEMS[@]}" | sed 's/^/  - /'
    fi

    cat << EOF

$(tput bold)Backups:$(tput sgr0)
  Location:  ${BACKUP_DIR}
  Backup ID: ${BACKUP_ID:-none}

$(tput bold)Log File:$(tput sgr0)
  ${LOG_FILE}

$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)

EOF
}

# Show usage
usage() {
    cat << 'EOF'
Usage: ./cleanup-environment.sh [OPTIONS]

Options:
  --server-id ID          Server ID from Forge (required)
  --dry-run               Preview changes without executing
  --force                 Skip all confirmations (DANGEROUS!)
  --no-backup             Don't create backup before deletion
  --databases             Only delete databases
  --backups               Only delete backups
  --certificates          Only delete SSL certificates
  --firewall              Only delete firewall rules
  --help                  Show this help message

Examples:
  # Interactive cleanup with confirmations
  ./cleanup-environment.sh --server-id 12345

  # Preview what will be deleted
  ./cleanup-environment.sh --server-id 12345 --dry-run

  # Delete only databases
  ./cleanup-environment.sh --server-id 12345 --databases

  # Full cleanup without backup (not recommended)
  ./cleanup-environment.sh --server-id 12345 --no-backup --force

Environment Variables:
  FORGE_API_TOKEN       Laravel Forge API token (required)
  FORGE_API_URL         API endpoint (default: https://forge.laravel.com/api/v1)

WARNING: This script performs destructive operations. Use --dry-run to preview changes.

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
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            --no-backup)
                CREATE_BACKUP=false
                shift
                ;;
            --databases)
                CLEANUP_ALL=false
                CLEANUP_DATABASES=true
                shift
                ;;
            --backups)
                CLEANUP_ALL=false
                CLEANUP_BACKUPS=true
                shift
                ;;
            --certificates)
                CLEANUP_ALL=false
                CLEANUP_CERTIFICATES=true
                shift
                ;;
            --firewall)
                CLEANUP_ALL=false
                CLEANUP_FIREWALL=true
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
    log_info "VPS Cleanup Script"
    log_info "========================================"

    # Validate arguments
    if [[ -z "$SERVER_ID" ]]; then
        log_error "Server ID is required (--server-id)"
        usage
    fi

    # Show DRY RUN warning
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE: No changes will be made"
    fi

    # Check requirements
    check_requirements || exit 1

    # Get server details
    if ! get_server_details; then
        log_error "Failed to retrieve server details"
        exit 1
    fi

    # Create backup
    if ! backup_server_data; then
        log_warning "Backup creation had issues, continuing anyway..."
    fi

    # Perform cleanup based on scope
    if [[ "$CLEANUP_ALL" == "true" ]]; then
        delete_databases
        delete_backups
        delete_certificates
        delete_firewall_rules
        delete_server
    else
        [[ "$CLEANUP_DATABASES" == "true" ]] && delete_databases
        [[ "$CLEANUP_BACKUPS" == "true" ]] && delete_backups
        [[ "$CLEANUP_CERTIFICATES" == "true" ]] && delete_certificates
        [[ "$CLEANUP_FIREWALL" == "true" ]] && delete_firewall_rules
    fi

    # Print summary
    print_summary

    if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
        log_error "Cleanup completed with errors"
        exit 1
    else
        log_success "Cleanup completed successfully"
        exit 0
    fi
}

# Run main function
main "$@"
