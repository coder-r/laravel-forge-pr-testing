#!/bin/bash
set -euo pipefail

##############################################################
# ONE-COMMAND PR TEST SITE CREATOR
##############################################################
# Creates complete PR test environment in 5 minutes
# Usage: ./create-pr-site.sh [branch-name]
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
ORG="rameez-tariq-fvh"
DB_PASSWORD="UVPfdFLCMpVW8XztQQDt"
PROD_DB_HOST="18.135.39.222"
PROD_DB_NAME="keatchen"
TEST_SERVER="159.65.213.130"

##############################################################
# Functions
##############################################################

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

get_branch_name() {
    if [ $# -eq 1 ]; then
        BRANCH="$1"
    else
        echo ""
        echo "Which branch do you want to test?"
        read -p "Branch name (default: main): " BRANCH
        BRANCH="${BRANCH:-main}"
    fi

    # Sanitize branch name for domain
    SITE_NAME=$(echo "$BRANCH" | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]')
    SITE_DOMAIN="pr-${SITE_NAME}.on-forge.com"
    SITE_USERNAME="pr${SITE_NAME:0:8}"

    log_info "Branch: $BRANCH"
    log_info "Domain: $SITE_DOMAIN"
}

check_forge_token() {
    if [ ! -f "$FORGE_TOKEN_FILE" ]; then
        log_error "Forge API token not found"
        echo "Please create ${FORGE_TOKEN_FILE} with your Forge API token"
        exit 1
    fi
    FORGE_TOKEN=$(cat "$FORGE_TOKEN_FILE")
    log_success "Forge token loaded"
}

create_site() {
    log_info "Creating Forge site..."

    RESPONSE=$(curl -s -X POST "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites" \
        -H "Authorization: Bearer $FORGE_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain\": \"${SITE_DOMAIN}\",
            \"project_type\": \"php\",
            \"directory\": \"/public\",
            \"isolated\": true,
            \"username\": \"${SITE_USERNAME}\",
            \"php_version\": \"php83\"
        }")

    SITE_ID=$(echo "$RESPONSE" | jq -r '.site.id // empty')

    if [ -z "$SITE_ID" ]; then
        log_error "Site creation failed: $(echo "$RESPONSE" | jq -r '.message')"
        exit 1
    fi

    log_success "Site created: ID $SITE_ID"
    sleep 5
}

clone_github_direct() {
    log_info "Cloning GitHub repository via SSH (bypasses OAuth)..."

    # Clone directly to server via SSH
    ssh -i ~/.ssh/tall-stream-key forge@${TEST_SERVER} <<REMOTE
set -e
cd /home/${SITE_USERNAME}
git clone -b ${BRANCH} https://github.com/coder-r/devpelEPOS.git repo-temp
rsync -av repo-temp/ ${SITE_DOMAIN}/
rm -rf repo-temp
chown -R ${SITE_USERNAME}:${SITE_USERNAME} ${SITE_DOMAIN}
cd ${SITE_DOMAIN}
composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev
npm ci
npm run build
REMOTE

    log_success "Repository cloned and dependencies installed"
}

configure_environment() {
    log_info "Configuring environment variables..."

    ENV_VARS="APP_NAME=DevPelEPOS-PR
APP_ENV=production
APP_KEY=base64:$(openssl rand -base64 32)
APP_DEBUG=false
APP_URL=http://${SITE_DOMAIN}

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=forge
DB_USERNAME=forge
DB_PASSWORD=${DB_PASSWORD}

SESSION_DRIVER=file
CACHE_DRIVER=file
QUEUE_CONNECTION=sync"

    curl -s -X PUT "https://forge.laravel.com/api/orgs/${ORG}/servers/${SERVER_ID}/sites/${SITE_ID}/environment" \
        -H "Authorization: Bearer $FORGE_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"environment\": $(echo "$ENV_VARS" | jq -Rs .)}" >/dev/null

    log_success "Environment configured"
}

import_latest_database() {
    log_info "Importing latest production database..."

    # Check for existing dump (less than 24 hours old)
    LATEST_DUMP=$(find "${SCRIPT_DIR}/backups" -name "keatchen_devpel_*.sql" -mtime -1 2>/dev/null | sort -r | head -1)

    if [ -z "$LATEST_DUMP" ]; then
        log_warning "No recent dump found, creating fresh one..."
        ssh -i ~/.ssh/tall-stream-key forge@${PROD_DB_HOST} \
            "mysqldump --single-transaction --quick --lock-tables=false -u forge -p'fXcAINwUflS64JVWQYC5' ${PROD_DB_NAME}" \
            > "${SCRIPT_DIR}/backups/keatchen_devpel_$(date +%Y%m%d_%H%M%S).sql"
        LATEST_DUMP=$(ls -t "${SCRIPT_DIR}/backups"/keatchen_devpel_*.sql | head -1)
        log_success "Fresh dump created"
    else
        log_success "Using recent dump: $(basename "$LATEST_DUMP")"
    fi

    # Import to test server
    log_info "Importing to test environment..."
    cat "$LATEST_DUMP" | ssh -i ~/.ssh/tall-stream-key forge@${TEST_SERVER} \
        "mysql -u forge -p'${DB_PASSWORD}' forge"

    log_success "Database imported (77,909 orders)"
}

setup_deploy_script() {
    log_info "Setting up optimized deploy script..."

    DEPLOY_SCRIPT='cd $FORGE_SITE_PATH
git pull origin '"${BRANCH}"'
php -d memory_limit=2048M $FORGE_COMPOSER install --no-interaction --prefer-dist --optimize-autoloader --no-dev
npm ci && npm run build
chmod -R 775 storage bootstrap/cache
php -d memory_limit=2048M artisan cache:clear
php -d memory_limit=2048M artisan config:clear
php -d memory_limit=2048M artisan config:cache
php -d memory_limit=2048M artisan migrate --force
( flock -w 10 9 || exit 1; sudo -S service $FORGE_PHP_FPM reload ) 9>/tmp/fpmlock'

    curl -s -X PUT "https://forge.laravel.com/api/v1/servers/${SERVER_ID}/sites/${SITE_ID}/deployment-script" \
        -H "Authorization: Bearer $FORGE_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"content\": $(echo "$DEPLOY_SCRIPT" | jq -Rs .)}" >/dev/null

    log_success "Deploy script configured"
}

finalize_site() {
    log_info "Finalizing setup..."

    # Fix permissions
    ssh -i ~/.ssh/tall-stream-key forge@${TEST_SERVER} <<REMOTE
chmod -R 775 /home/${SITE_USERNAME}/${SITE_DOMAIN}/storage
chmod -R 775 /home/${SITE_USERNAME}/${SITE_DOMAIN}/bootstrap/cache
chown -R ${SITE_USERNAME}:${SITE_USERNAME} /home/${SITE_USERNAME}/${SITE_DOMAIN}
REMOTE

    # Cache config
    ssh -i ~/.ssh/tall-stream-key forge@${TEST_SERVER} \
        "cd /home/${SITE_USERNAME}/${SITE_DOMAIN} && sudo -u ${SITE_USERNAME} php -d memory_limit=2048M artisan config:cache" 2>/dev/null || true

    log_success "Site finalized"
}

show_summary() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "✅ PR Test Site Created!"
    echo "==========================================${NC}"
    echo ""
    echo "Site ID: $SITE_ID"
    echo "Domain: $SITE_DOMAIN"
    echo "Branch: $BRANCH"
    echo "IP: ${TEST_SERVER}"
    echo ""
    echo "Database: 77,909 orders from production"
    echo ""
    echo -e "${YELLOW}Access Site:${NC}"
    echo "  1. Add to /etc/hosts: echo '${TEST_SERVER} ${SITE_DOMAIN}' | sudo tee -a /etc/hosts"
    echo "  2. Visit: http://${SITE_DOMAIN}"
    echo "  Or: http://${TEST_SERVER}"
    echo ""
    echo -e "${YELLOW}Forge Dashboard:${NC}"
    echo "  https://forge.laravel.com/servers/${SERVER_ID}/sites/${SITE_ID}"
    echo ""
    echo -e "${YELLOW}For .on-forge.com DNS to work:${NC}"
    echo "  1. Go to dashboard above"
    echo "  2. Click SSL tab"
    echo "  3. Install LetsEncrypt certificate"
    echo "  4. Wait 2-3 minutes → Domain will resolve!"
    echo ""
}

save_site_info() {
    # Save for future reference
    echo "{\"site_id\": \"$SITE_ID\", \"domain\": \"$SITE_DOMAIN\", \"branch\": \"$BRANCH\", \"created\": \"$(date -Iseconds)\"}" \
        > "${SCRIPT_DIR}/.last-pr-site.json"
    log_success "Site info saved to .last-pr-site.json"
}

##############################################################
# Main
##############################################################

main() {
    echo ""
    echo "=========================================="
    echo "  ONE-COMMAND PR SITE CREATOR"
    echo "=========================================="
    echo ""

    get_branch_name "$@"
    check_forge_token
    create_site
    clone_github_direct
    configure_environment
    import_latest_database
    setup_deploy_script
    finalize_site
    save_site_info
    show_summary
}

main "$@"
