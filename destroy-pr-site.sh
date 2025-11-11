#!/bin/bash
set -euo pipefail

##############################################################
# DESTROY PR TEST SITE
##############################################################
# Cleans up PR test environment when done
# Usage: ./destroy-pr-site.sh [site-domain or site-id]
##############################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
FORGE_TOKEN_FILE="${SCRIPT_DIR}/.forge-token"
SERVER_ID="986747"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

check_token() {
    if [ ! -f "$FORGE_TOKEN_FILE" ]; then
        echo "Error: Forge token not found at $FORGE_TOKEN_FILE"
        exit 1
    fi
    FORGE_TOKEN=$(cat "$FORGE_TOKEN_FILE")
}

find_site() {
    local input="$1"

    # Check if it's a site ID (numeric)
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        SITE_ID="$input"
    else
        # It's a domain, find the site ID
        log_info "Looking up site by domain: $input"
        SITES=$(curl -s "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites" \
            -H "Authorization: Bearer $FORGE_TOKEN")

        SITE_ID=$(echo "$SITES" | jq -r ".sites[] | select(.name == \"$input\") | .id")

        if [ -z "$SITE_ID" ]; then
            log_warning "Site not found: $input"
            echo "Available sites:"
            echo "$SITES" | jq -r '.sites[] | "\(.id): \(.name)"'
            exit 1
        fi
    fi

    # Get site details
    SITE_INFO=$(curl -s "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID}" \
        -H "Authorization: Bearer $FORGE_TOKEN")

    SITE_DOMAIN=$(echo "$SITE_INFO" | jq -r '.site.name')

    log_success "Found site: $SITE_DOMAIN (ID: $SITE_ID)"
}

confirm_deletion() {
    echo ""
    log_warning "You are about to DELETE:"
    echo "  Site ID: $SITE_ID"
    echo "  Domain: $SITE_DOMAIN"
    echo ""
    echo "This will:"
    echo "  - Remove all files"
    echo "  - Delete nginx configuration"
    echo "  - Remove SSL certificates"
    echo "  - Free up resources"
    echo ""
    echo "Database will NOT be affected (reusable for other sites)"
    echo ""
    read -p "Are you sure? Type 'yes' to continue: " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        log_info "Deletion cancelled"
        exit 0
    fi
}

delete_site() {
    log_info "Deleting site..."

    RESULT=$(curl -s -X DELETE "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID}" \
        -H "Authorization: Bearer $FORGE_TOKEN")

    if echo "$RESULT" | grep -q "error\|Error"; then
        log_warning "Deletion may have failed: $RESULT"
    else
        log_success "Site deleted successfully"
    fi
}

cleanup_records() {
    # Remove from last-pr-site.json if it exists
    if [ -f "${SCRIPT_DIR}/.last-pr-site.json" ]; then
        SAVED_ID=$(jq -r '.site_id' "${SCRIPT_DIR}/.last-pr-site.json")
        if [ "$SAVED_ID" = "$SITE_ID" ]; then
            rm "${SCRIPT_DIR}/.last-pr-site.json"
            log_success "Cleaned up site records"
        fi
    fi
}

main() {
    echo ""
    echo "=========================================="
    echo "  PR SITE CLEANUP"
    echo "=========================================="
    echo ""

    if [ $# -eq 0 ]; then
        # No argument, check for last site
        if [ -f "${SCRIPT_DIR}/.last-pr-site.json" ]; then
            SITE_ID=$(jq -r '.site_id' "${SCRIPT_DIR}/.last-pr-site.json")
            SITE_DOMAIN=$(jq -r '.domain' "${SCRIPT_DIR}/.last-pr-site.json")
            log_info "Using last created site"
        else
            echo "Usage: $0 <site-domain or site-id>"
            echo "Example: $0 pr-feature-auth.on-forge.com"
            echo "Example: $0 2926027"
            exit 1
        fi
    else
        check_token
        find_site "$1"
    fi

    confirm_deletion
    delete_site
    cleanup_records

    echo ""
    log_success "Cleanup complete!"
    echo ""
}

main "$@"
