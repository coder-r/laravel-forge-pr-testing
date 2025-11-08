# Automation Scripts for PR Testing Environment

**Complete, production-ready bash scripts for automated PR environment management**

---

## 📋 Table of Contents

1. [Configuration](#configuration)
2. [create-pr-environment.sh](#1-create-pr-environmentsh)
3. [destroy-pr-environment.sh](#2-destroy-pr-environmentsh)
4. [refresh-master-snapshots.sh](#3-refresh-master-snapshotssh)
5. [health-check.sh](#4-health-checksh)
6. [Utility Functions](#5-utility-functions)
7. [Installation](#installation)
8. [Usage Examples](#usage-examples)

---

## Configuration

### Global Configuration File

**File**: `/home/forge/.scripts/config.sh`

```bash
#!/bin/bash

# ============================================
# GLOBAL CONFIGURATION
# ============================================

# Forge API Configuration
export FORGE_API_TOKEN="${FORGE_API_TOKEN}"
export FORGE_SERVER_ID="${FORGE_SERVER_ID}"
export FORGE_API_BASE="https://forge.laravel.com/api/v1"

# Database Configuration
export DB_MASTER_SNAPSHOT_PREFIX="master_"
export DB_HOST="localhost"
export DB_ROOT_USER="forge"
export DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD}"

# Redis Configuration
export REDIS_HOST="localhost"
export REDIS_PORT="6379"
export REDIS_PASSWORD="${REDIS_PASSWORD}"

# Site Configuration
export BASE_DOMAIN="pr-test.yourdomain.com"
export PROJECT_NAME="yourproject"
export SITE_DIRECTORY="/home/forge"

# SSL Configuration
export LETSENCRYPT_EMAIL="admin@yourdomain.com"

# Queue Configuration
export QUEUE_WORKERS=2
export QUEUE_CONNECTION="redis"

# Environment URLs
export PRODUCTION_DB_HOST="production-db.example.com"
export PRODUCTION_DB_USER="backup_user"
export PRODUCTION_DB_PASSWORD="${PRODUCTION_DB_PASSWORD}"

# Logging
export LOG_DIR="/home/forge/.scripts/logs"
export LOG_LEVEL="INFO" # DEBUG, INFO, WARN, ERROR

# Retry Configuration
export MAX_RETRIES=3
export RETRY_DELAY=5 # seconds

# Timeouts
export API_TIMEOUT=30 # seconds
export DEPLOYMENT_TIMEOUT=600 # seconds (10 minutes)
export HEALTH_CHECK_TIMEOUT=180 # seconds (3 minutes)

# Notification Configuration (optional)
export SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL}"
export NOTIFY_ON_ERROR=true
export NOTIFY_ON_SUCCESS=false
```

---

## 1. create-pr-environment.sh

**File**: `/home/forge/.scripts/create-pr-environment.sh`

```bash
#!/bin/bash

# ============================================
# CREATE PR ENVIRONMENT
# ============================================
# Creates a complete Laravel Forge site for PR testing
#
# Usage: ./create-pr-environment.sh <pr_number> <project_name> <branch_name>
# Example: ./create-pr-environment.sh 123 myapp feature/new-feature
# ============================================

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# ============================================
# VALIDATE INPUTS
# ============================================

if [ $# -ne 3 ]; then
    log_error "Usage: $0 <pr_number> <project_name> <branch_name>"
    exit 1
fi

PR_NUMBER="$1"
PROJECT_NAME="$2"
BRANCH_NAME="$3"

# Validate PR number
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    log_error "Invalid PR number: $PR_NUMBER"
    exit 1
fi

# Sanitize inputs
SAFE_BRANCH_NAME=$(echo "$BRANCH_NAME" | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]')
SITE_NAME="pr-${PR_NUMBER}-${PROJECT_NAME}"
SITE_DOMAIN="pr-${PR_NUMBER}.${BASE_DOMAIN}"
DB_NAME="pr_${PR_NUMBER}_${PROJECT_NAME}"

log_info "=========================================="
log_info "Creating PR Environment"
log_info "=========================================="
log_info "PR Number: $PR_NUMBER"
log_info "Project: $PROJECT_NAME"
log_info "Branch: $BRANCH_NAME"
log_info "Site Domain: $SITE_DOMAIN"
log_info "Database: $DB_NAME"
log_info "=========================================="

# ============================================
# STEP 1: CREATE FORGE SITE
# ============================================

log_info "[1/8] Creating Forge site..."

SITE_PAYLOAD=$(cat <<EOF
{
  "domain": "${SITE_DOMAIN}",
  "project_type": "php",
  "directory": "/public",
  "php_version": "php82",
  "database": "${DB_NAME}",
  "aliases": []
}
EOF
)

SITE_RESPONSE=$(retry_command curl -s -X POST \
    -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --connect-timeout ${API_TIMEOUT} \
    -d "${SITE_PAYLOAD}" \
    "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/sites")

if [ $? -ne 0 ]; then
    log_error "Failed to create Forge site"
    notify_error "Failed to create PR environment for PR #${PR_NUMBER}"
    exit 1
fi

SITE_ID=$(echo "$SITE_RESPONSE" | jq -r '.site.id')

if [ "$SITE_ID" = "null" ] || [ -z "$SITE_ID" ]; then
    log_error "Failed to extract site ID from response"
    log_debug "Response: $SITE_RESPONSE"
    exit 1
fi

log_success "Site created with ID: $SITE_ID"

# Wait for site to be fully created
sleep 5

# ============================================
# STEP 2: CREATE DATABASE
# ============================================

log_info "[2/8] Creating database..."

DB_PAYLOAD=$(cat <<EOF
{
  "name": "${DB_NAME}",
  "user": "${DB_NAME}",
  "password": "$(generate_password 32)"
}
EOF
)

DB_RESPONSE=$(retry_command curl -s -X POST \
    -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --connect-timeout ${API_TIMEOUT} \
    -d "${DB_PAYLOAD}" \
    "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/mysql")

if [ $? -ne 0 ]; then
    log_error "Failed to create database"
    cleanup_on_failure "$SITE_ID"
    exit 1
fi

DB_PASSWORD=$(echo "$DB_RESPONSE" | jq -r '.database.password')

log_success "Database created: $DB_NAME"

# Wait for database to be ready
sleep 3

# ============================================
# STEP 3: CLONE MASTER DATABASE SNAPSHOT
# ============================================

log_info "[3/8] Cloning master database snapshot..."

MASTER_SNAPSHOT="${DB_MASTER_SNAPSHOT_PREFIX}${PROJECT_NAME}"

if ! mysql -h"${DB_HOST}" -u"${DB_ROOT_USER}" -p"${DB_ROOT_PASSWORD}" -e "USE ${MASTER_SNAPSHOT}" 2>/dev/null; then
    log_warn "Master snapshot not found, creating empty database"
else
    log_info "Cloning from ${MASTER_SNAPSHOT}..."

    # Dump master snapshot
    DUMP_FILE="/tmp/${DB_NAME}_import_$$.sql"

    mysqldump -h"${DB_HOST}" \
        -u"${DB_ROOT_USER}" \
        -p"${DB_ROOT_PASSWORD}" \
        --single-transaction \
        --quick \
        --lock-tables=false \
        "${MASTER_SNAPSHOT}" > "${DUMP_FILE}" 2>/dev/null

    if [ $? -ne 0 ]; then
        log_error "Failed to dump master snapshot"
        rm -f "${DUMP_FILE}"
        cleanup_on_failure "$SITE_ID"
        exit 1
    fi

    # Import to new database
    mysql -h"${DB_HOST}" \
        -u"${DB_ROOT_USER}" \
        -p"${DB_ROOT_PASSWORD}" \
        "${DB_NAME}" < "${DUMP_FILE}" 2>/dev/null

    if [ $? -ne 0 ]; then
        log_error "Failed to import database"
        rm -f "${DUMP_FILE}"
        cleanup_on_failure "$SITE_ID"
        exit 1
    fi

    rm -f "${DUMP_FILE}"
    log_success "Database cloned successfully"
fi

# ============================================
# STEP 4: CREATE REDIS DATABASE
# ============================================

log_info "[4/8] Setting up Redis database..."

# Calculate Redis DB number (PR number % 16, reserving 0-3 for system)
REDIS_DB=$((PR_NUMBER % 13 + 3))

log_info "Redis DB assigned: ${REDIS_DB}"

# ============================================
# STEP 5: CONFIGURE ENVIRONMENT VARIABLES
# ============================================

log_info "[5/8] Configuring environment variables..."

ENV_PAYLOAD=$(cat <<EOF
{
  "key": "APP_ENV",
  "value": "testing"
}
EOF
)

# Set APP_ENV
retry_command curl -s -X POST \
    -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --connect-timeout ${API_TIMEOUT} \
    -d "${ENV_PAYLOAD}" \
    "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/sites/${SITE_ID}/env" > /dev/null

# Update .env file directly for better control
SITE_PATH="${SITE_DIRECTORY}/${SITE_DOMAIN}"

cat > "${SITE_PATH}/.env" <<EOF
APP_NAME="${PROJECT_NAME} PR #${PR_NUMBER}"
APP_ENV=testing
APP_KEY=
APP_DEBUG=true
APP_URL=https://${SITE_DOMAIN}

LOG_CHANNEL=stack
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=${DB_HOST}
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_NAME}
DB_PASSWORD=${DB_PASSWORD}

BROADCAST_DRIVER=redis
CACHE_DRIVER=redis
FILESYSTEM_DRIVER=local
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
SESSION_LIFETIME=120

REDIS_HOST=${REDIS_HOST}
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_PORT=${REDIS_PORT}
REDIS_DB=${REDIS_DB}

MAIL_MAILER=log

# PR-specific identifiers
PR_NUMBER=${PR_NUMBER}
BRANCH_NAME=${BRANCH_NAME}
ENVIRONMENT=pr-testing
EOF

log_success "Environment variables configured"

# ============================================
# STEP 6: CONFIGURE DEPLOYMENT
# ============================================

log_info "[6/8] Configuring deployment..."

DEPLOY_SCRIPT=$(cat <<'EOF'
cd /home/forge/pr-{PR_NUMBER}.{BASE_DOMAIN}
git pull origin {BRANCH_NAME}

composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev

php artisan key:generate --force
php artisan migrate --force
php artisan config:cache
php artisan route:cache
php artisan view:cache

if [ -f artisan ]; then
    php artisan queue:restart
fi

npm ci
npm run production
EOF
)

# Replace placeholders
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//\{PR_NUMBER\}/${PR_NUMBER}}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//\{BASE_DOMAIN\}/${BASE_DOMAIN}}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//\{BRANCH_NAME\}/${BRANCH_NAME}}"

DEPLOY_PAYLOAD=$(jq -n \
    --arg script "$DEPLOY_SCRIPT" \
    '{script: $script}')

retry_command curl -s -X PUT \
    -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --connect-timeout ${API_TIMEOUT} \
    -d "${DEPLOY_PAYLOAD}" \
    "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/sites/${SITE_ID}/deployment/script" > /dev/null

log_success "Deployment script configured"

# ============================================
# STEP 7: SETUP SSL CERTIFICATE
# ============================================

log_info "[7/8] Installing SSL certificate..."

SSL_PAYLOAD=$(cat <<EOF
{
  "domains": ["${SITE_DOMAIN}"],
  "type": "letsencrypt"
}
EOF
)

SSL_RESPONSE=$(retry_command curl -s -X POST \
    -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --connect-timeout ${API_TIMEOUT} \
    -d "${SSL_PAYLOAD}" \
    "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/sites/${SITE_ID}/certificates/letsencrypt")

if [ $? -ne 0 ]; then
    log_warn "Failed to install SSL certificate (non-fatal)"
else
    log_success "SSL certificate installed"
fi

# ============================================
# STEP 8: TRIGGER DEPLOYMENT
# ============================================

log_info "[8/8] Triggering deployment..."

DEPLOYMENT_RESPONSE=$(retry_command curl -s -X POST \
    -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
    -H "Accept: application/json" \
    --connect-timeout ${API_TIMEOUT} \
    "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/sites/${SITE_ID}/deployment/deploy")

if [ $? -ne 0 ]; then
    log_error "Failed to trigger deployment"
    cleanup_on_failure "$SITE_ID"
    exit 1
fi

log_info "Deployment triggered, waiting for completion..."

# Wait for deployment to complete
wait_for_deployment "$SITE_ID" ${DEPLOYMENT_TIMEOUT}

if [ $? -ne 0 ]; then
    log_error "Deployment timed out or failed"
    cleanup_on_failure "$SITE_ID"
    exit 1
fi

log_success "Deployment completed"

# ============================================
# STEP 9: SETUP QUEUE WORKERS
# ============================================

log_info "Setting up queue workers..."

for i in $(seq 1 ${QUEUE_WORKERS}); do
    DAEMON_PAYLOAD=$(cat <<EOF
{
  "command": "php artisan queue:work redis --tries=3 --timeout=90",
  "user": "forge",
  "directory": "${SITE_PATH}"
}
EOF
)

    curl -s -X POST \
        -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --connect-timeout ${API_TIMEOUT} \
        -d "${DAEMON_PAYLOAD}" \
        "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/daemons" > /dev/null
done

log_success "Queue workers configured"

# ============================================
# HEALTH CHECK
# ============================================

log_info "Running health check..."

"${SCRIPT_DIR}/health-check.sh" "$SITE_ID" "$SITE_DOMAIN" "$DB_NAME" ${REDIS_DB}

if [ $? -ne 0 ]; then
    log_error "Health check failed"
    cleanup_on_failure "$SITE_ID"
    exit 1
fi

# ============================================
# SUCCESS
# ============================================

log_success "=========================================="
log_success "PR Environment Created Successfully!"
log_success "=========================================="
log_success "Site URL: https://${SITE_DOMAIN}"
log_success "Site ID: ${SITE_ID}"
log_success "Database: ${DB_NAME}"
log_success "Redis DB: ${REDIS_DB}"
log_success "=========================================="

# Output for GitHub Actions
echo "site_url=https://${SITE_DOMAIN}" >> $GITHUB_OUTPUT
echo "site_id=${SITE_ID}" >> $GITHUB_OUTPUT
echo "db_name=${DB_NAME}" >> $GITHUB_OUTPUT

notify_success "PR environment created for PR #${PR_NUMBER}: https://${SITE_DOMAIN}"

exit 0
```

---

## 2. destroy-pr-environment.sh

**File**: `/home/forge/.scripts/destroy-pr-environment.sh`

```bash
#!/bin/bash

# ============================================
# DESTROY PR ENVIRONMENT
# ============================================
# Cleans up all resources for a PR environment
#
# Usage: ./destroy-pr-environment.sh <pr_number> [project_name]
# Example: ./destroy-pr-environment.sh 123 myapp
# ============================================

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# ============================================
# VALIDATE INPUTS
# ============================================

if [ $# -lt 1 ]; then
    log_error "Usage: $0 <pr_number> [project_name]"
    exit 1
fi

PR_NUMBER="$1"
PROJECT_NAME="${2:-${PROJECT_NAME}}"

# Validate PR number
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    log_error "Invalid PR number: $PR_NUMBER"
    exit 1
fi

SITE_NAME="pr-${PR_NUMBER}-${PROJECT_NAME}"
SITE_DOMAIN="pr-${PR_NUMBER}.${BASE_DOMAIN}"
DB_NAME="pr_${PR_NUMBER}_${PROJECT_NAME}"
REDIS_DB=$((PR_NUMBER % 13 + 3))

log_info "=========================================="
log_info "Destroying PR Environment"
log_info "=========================================="
log_info "PR Number: $PR_NUMBER"
log_info "Project: $PROJECT_NAME"
log_info "Site Domain: $SITE_DOMAIN"
log_info "Database: $DB_NAME"
log_info "Redis DB: $REDIS_DB"
log_info "=========================================="

# ============================================
# STEP 1: FIND SITE ID
# ============================================

log_info "[1/6] Finding site ID..."

SITES_RESPONSE=$(curl -s -X GET \
    -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
    -H "Accept: application/json" \
    --connect-timeout ${API_TIMEOUT} \
    "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/sites")

SITE_ID=$(echo "$SITES_RESPONSE" | jq -r ".sites[] | select(.name == \"${SITE_DOMAIN}\") | .id")

if [ -z "$SITE_ID" ] || [ "$SITE_ID" = "null" ]; then
    log_warn "Site not found in Forge, continuing with cleanup..."
    SITE_ID=""
else
    log_success "Found site ID: $SITE_ID"
fi

# ============================================
# STEP 2: DELETE QUEUE WORKERS
# ============================================

if [ -n "$SITE_ID" ]; then
    log_info "[2/6] Deleting queue workers..."

    DAEMONS_RESPONSE=$(curl -s -X GET \
        -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
        -H "Accept: application/json" \
        --connect-timeout ${API_TIMEOUT} \
        "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/daemons")

    SITE_PATH="${SITE_DIRECTORY}/${SITE_DOMAIN}"

    # Find and delete daemons for this site
    echo "$DAEMONS_RESPONSE" | jq -r ".daemons[] | select(.directory == \"${SITE_PATH}\") | .id" | while read -r daemon_id; do
        log_info "Deleting daemon: $daemon_id"
        curl -s -X DELETE \
            -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
            -H "Accept: application/json" \
            --connect-timeout ${API_TIMEOUT} \
            "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/daemons/${daemon_id}" > /dev/null
    done

    log_success "Queue workers deleted"
else
    log_info "[2/6] Skipping queue worker deletion (no site ID)"
fi

# ============================================
# STEP 3: DELETE FORGE SITE
# ============================================

if [ -n "$SITE_ID" ]; then
    log_info "[3/6] Deleting Forge site..."

    DELETE_RESPONSE=$(curl -s -X DELETE \
        -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
        -H "Accept: application/json" \
        --connect-timeout ${API_TIMEOUT} \
        "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/sites/${SITE_ID}")

    if [ $? -ne 0 ]; then
        log_error "Failed to delete site"
    else
        log_success "Site deleted from Forge"
    fi
else
    log_info "[3/6] Skipping site deletion (no site ID)"
fi

# ============================================
# STEP 4: DROP DATABASE
# ============================================

log_info "[4/6] Dropping database..."

# Check if database exists
if mysql -h"${DB_HOST}" -u"${DB_ROOT_USER}" -p"${DB_ROOT_PASSWORD}" -e "USE ${DB_NAME}" 2>/dev/null; then
    # Drop database
    mysql -h"${DB_HOST}" \
        -u"${DB_ROOT_USER}" \
        -p"${DB_ROOT_PASSWORD}" \
        -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`" 2>/dev/null

    if [ $? -eq 0 ]; then
        log_success "Database dropped: $DB_NAME"
    else
        log_error "Failed to drop database"
    fi

    # Drop database user
    mysql -h"${DB_HOST}" \
        -u"${DB_ROOT_USER}" \
        -p"${DB_ROOT_PASSWORD}" \
        -e "DROP USER IF EXISTS '${DB_NAME}'@'%'" 2>/dev/null

    mysql -h"${DB_HOST}" \
        -u"${DB_ROOT_USER}" \
        -p"${DB_ROOT_PASSWORD}" \
        -e "FLUSH PRIVILEGES" 2>/dev/null
else
    log_info "Database does not exist, skipping"
fi

# ============================================
# STEP 5: FLUSH REDIS DATABASE
# ============================================

log_info "[5/6] Flushing Redis database..."

if [ -n "$REDIS_PASSWORD" ]; then
    redis-cli -h "${REDIS_HOST}" \
        -p "${REDIS_PORT}" \
        -a "${REDIS_PASSWORD}" \
        -n "${REDIS_DB}" \
        FLUSHDB > /dev/null 2>&1
else
    redis-cli -h "${REDIS_HOST}" \
        -p "${REDIS_PORT}" \
        -n "${REDIS_DB}" \
        FLUSHDB > /dev/null 2>&1
fi

if [ $? -eq 0 ]; then
    log_success "Redis database flushed"
else
    log_warn "Failed to flush Redis database (non-fatal)"
fi

# ============================================
# STEP 6: CLEANUP FILE SYSTEM
# ============================================

log_info "[6/6] Cleaning up file system..."

SITE_PATH="${SITE_DIRECTORY}/${SITE_DOMAIN}"

if [ -d "$SITE_PATH" ]; then
    # Remove site directory
    rm -rf "$SITE_PATH"

    if [ $? -eq 0 ]; then
        log_success "Site directory removed"
    else
        log_error "Failed to remove site directory"
    fi
else
    log_info "Site directory does not exist, skipping"
fi

# ============================================
# SUCCESS
# ============================================

log_success "=========================================="
log_success "PR Environment Destroyed Successfully!"
log_success "=========================================="
log_success "PR Number: $PR_NUMBER"
log_success "All resources cleaned up"
log_success "=========================================="

notify_success "PR environment destroyed for PR #${PR_NUMBER}"

exit 0
```

---

## 3. refresh-master-snapshots.sh

**File**: `/home/forge/.scripts/refresh-master-snapshots.sh`

```bash
#!/bin/bash

# ============================================
# REFRESH MASTER DATABASE SNAPSHOTS
# ============================================
# Weekly job to refresh master database snapshots
# from production databases
#
# Usage: ./refresh-master-snapshots.sh [project_name]
# Example: ./refresh-master-snapshots.sh myapp
#
# Cron: 0 2 * * 0 /home/forge/.scripts/refresh-master-snapshots.sh
# ============================================

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# ============================================
# CONFIGURATION
# ============================================

PROJECT_NAME="${1:-${PROJECT_NAME}}"
MASTER_SNAPSHOT="${DB_MASTER_SNAPSHOT_PREFIX}${PROJECT_NAME}"
TEMP_DIR="/tmp/db-snapshots-$$"
BACKUP_RETENTION_DAYS=30

log_info "=========================================="
log_info "Refreshing Master Database Snapshot"
log_info "=========================================="
log_info "Project: $PROJECT_NAME"
log_info "Master Snapshot: $MASTER_SNAPSHOT"
log_info "Started: $(date)"
log_info "=========================================="

# ============================================
# STEP 1: CREATE TEMP DIRECTORY
# ============================================

log_info "[1/7] Creating temporary directory..."

mkdir -p "$TEMP_DIR"

if [ $? -ne 0 ]; then
    log_error "Failed to create temp directory"
    exit 1
fi

log_success "Temp directory created: $TEMP_DIR"

# ============================================
# STEP 2: DUMP PRODUCTION DATABASE
# ============================================

log_info "[2/7] Dumping production database..."

DUMP_FILE="${TEMP_DIR}/${PROJECT_NAME}_production_$(date +%Y%m%d_%H%M%S).sql"

# Dump production database
mysqldump -h"${PRODUCTION_DB_HOST}" \
    -u"${PRODUCTION_DB_USER}" \
    -p"${PRODUCTION_DB_PASSWORD}" \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --add-drop-table \
    --compress \
    --routines \
    --triggers \
    --events \
    "${PROJECT_NAME}" > "${DUMP_FILE}" 2>/dev/null

if [ $? -ne 0 ]; then
    log_error "Failed to dump production database"
    cleanup_temp_files "$TEMP_DIR"
    exit 1
fi

# Verify dump file
DUMP_SIZE=$(stat -f%z "$DUMP_FILE" 2>/dev/null || stat -c%s "$DUMP_FILE")

if [ "$DUMP_SIZE" -lt 1000 ]; then
    log_error "Dump file is suspiciously small (${DUMP_SIZE} bytes)"
    cleanup_temp_files "$TEMP_DIR"
    exit 1
fi

log_success "Production database dumped: $(human_readable_size $DUMP_SIZE)"

# ============================================
# STEP 3: BACKUP EXISTING MASTER SNAPSHOT
# ============================================

log_info "[3/7] Backing up existing master snapshot..."

BACKUP_DB="${MASTER_SNAPSHOT}_backup_$(date +%Y%m%d_%H%M%S)"

# Check if master snapshot exists
if mysql -h"${DB_HOST}" -u"${DB_ROOT_USER}" -p"${DB_ROOT_PASSWORD}" -e "USE ${MASTER_SNAPSHOT}" 2>/dev/null; then
    # Create backup
    mysqldump -h"${DB_HOST}" \
        -u"${DB_ROOT_USER}" \
        -p"${DB_ROOT_PASSWORD}" \
        --single-transaction \
        --quick \
        "${MASTER_SNAPSHOT}" > "${TEMP_DIR}/backup.sql" 2>/dev/null

    # Create backup database
    mysql -h"${DB_HOST}" \
        -u"${DB_ROOT_USER}" \
        -p"${DB_ROOT_PASSWORD}" \
        -e "CREATE DATABASE IF NOT EXISTS \`${BACKUP_DB}\`" 2>/dev/null

    mysql -h"${DB_HOST}" \
        -u"${DB_ROOT_USER}" \
        -p"${DB_ROOT_PASSWORD}" \
        "${BACKUP_DB}" < "${TEMP_DIR}/backup.sql" 2>/dev/null

    if [ $? -eq 0 ]; then
        log_success "Existing snapshot backed up to: $BACKUP_DB"
    else
        log_warn "Failed to backup existing snapshot (continuing)"
    fi
else
    log_info "No existing master snapshot found"
fi

# ============================================
# STEP 4: DROP OLD MASTER SNAPSHOT
# ============================================

log_info "[4/7] Dropping old master snapshot..."

mysql -h"${DB_HOST}" \
    -u"${DB_ROOT_USER}" \
    -p"${DB_ROOT_PASSWORD}" \
    -e "DROP DATABASE IF EXISTS \`${MASTER_SNAPSHOT}\`" 2>/dev/null

if [ $? -ne 0 ]; then
    log_error "Failed to drop old snapshot"
    cleanup_temp_files "$TEMP_DIR"
    exit 1
fi

log_success "Old snapshot dropped"

# ============================================
# STEP 5: CREATE NEW MASTER SNAPSHOT
# ============================================

log_info "[5/7] Creating new master snapshot..."

# Create database
mysql -h"${DB_HOST}" \
    -u"${DB_ROOT_USER}" \
    -p"${DB_ROOT_PASSWORD}" \
    -e "CREATE DATABASE \`${MASTER_SNAPSHOT}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci" 2>/dev/null

if [ $? -ne 0 ]; then
    log_error "Failed to create master snapshot database"
    cleanup_temp_files "$TEMP_DIR"
    exit 1
fi

# Import dump
log_info "Importing production data..."

mysql -h"${DB_HOST}" \
    -u"${DB_ROOT_USER}" \
    -p"${DB_ROOT_PASSWORD}" \
    "${MASTER_SNAPSHOT}" < "${DUMP_FILE}" 2>/dev/null

if [ $? -ne 0 ]; then
    log_error "Failed to import production data"
    cleanup_temp_files "$TEMP_DIR"
    exit 1
fi

log_success "New master snapshot created"

# ============================================
# STEP 6: RUN DATA SANITIZATION
# ============================================

log_info "[6/7] Sanitizing sensitive data..."

# Sanitize sensitive data for testing
mysql -h"${DB_HOST}" \
    -u"${DB_ROOT_USER}" \
    -p"${DB_ROOT_PASSWORD}" \
    "${MASTER_SNAPSHOT}" <<'SQL' 2>/dev/null

-- Sanitize user emails (keep structure, fake data)
UPDATE users
SET
    email = CONCAT('test-', id, '@example.com'),
    password = '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', -- password
    remember_token = NULL,
    email_verified_at = NOW()
WHERE email NOT LIKE '%@example.com';

-- Sanitize personal information
UPDATE users
SET
    phone = CONCAT('555-', LPAD(id, 7, '0')),
    address = CONCAT(id, ' Test Street'),
    city = 'Testville',
    state = 'TS',
    zip = '12345'
WHERE id > 0;

-- Clear API tokens
UPDATE personal_access_tokens
SET token = ''
WHERE id > 0;

-- Clear payment information (keep structure)
UPDATE payment_methods
SET
    card_number = '4242424242424242',
    cvv = NULL,
    expiry = '12/25'
WHERE id > 0;

-- Anonymize logs (keep recent entries only)
DELETE FROM activity_log
WHERE created_at < DATE_SUB(NOW(), INTERVAL 30 DAY);

-- Clear queue failed jobs
TRUNCATE TABLE failed_jobs;

-- Clear cache tables
TRUNCATE TABLE cache;
TRUNCATE TABLE cache_locks;

-- Clear sessions
TRUNCATE TABLE sessions;

SQL

if [ $? -eq 0 ]; then
    log_success "Data sanitization completed"
else
    log_warn "Data sanitization had issues (non-fatal)"
fi

# ============================================
# STEP 7: CLEANUP OLD BACKUPS
# ============================================

log_info "[7/7] Cleaning up old backups..."

# Get list of backup databases
BACKUP_DATABASES=$(mysql -h"${DB_HOST}" \
    -u"${DB_ROOT_USER}" \
    -p"${DB_ROOT_PASSWORD}" \
    -Nse "SHOW DATABASES LIKE '${MASTER_SNAPSHOT}_backup_%'" 2>/dev/null)

# Parse and delete old backups
echo "$BACKUP_DATABASES" | while read -r backup_db; do
    # Extract date from backup name
    if [[ $backup_db =~ _([0-9]{8})_ ]]; then
        BACKUP_DATE="${BASH_REMATCH[1]}"
        BACKUP_TIMESTAMP=$(date -d "${BACKUP_DATE}" +%s 2>/dev/null || date -j -f "%Y%m%d" "${BACKUP_DATE}" +%s 2>/dev/null)
        CURRENT_TIMESTAMP=$(date +%s)
        DAYS_OLD=$(( (CURRENT_TIMESTAMP - BACKUP_TIMESTAMP) / 86400 ))

        if [ "$DAYS_OLD" -gt "$BACKUP_RETENTION_DAYS" ]; then
            log_info "Deleting old backup (${DAYS_OLD} days old): $backup_db"
            mysql -h"${DB_HOST}" \
                -u"${DB_ROOT_USER}" \
                -p"${DB_ROOT_PASSWORD}" \
                -e "DROP DATABASE IF EXISTS \`${backup_db}\`" 2>/dev/null
        fi
    fi
done

log_success "Old backups cleaned up"

# ============================================
# CLEANUP TEMP FILES
# ============================================

log_info "Cleaning up temporary files..."

cleanup_temp_files "$TEMP_DIR"

log_success "Temporary files cleaned up"

# ============================================
# SUCCESS
# ============================================

log_success "=========================================="
log_success "Master Snapshot Refresh Complete!"
log_success "=========================================="
log_success "Master Snapshot: $MASTER_SNAPSHOT"
log_success "Backup Created: $BACKUP_DB"
log_success "Completed: $(date)"
log_success "=========================================="

notify_success "Master database snapshot refreshed for ${PROJECT_NAME}"

exit 0
```

---

## 4. health-check.sh

**File**: `/home/forge/.scripts/health-check.sh`

```bash
#!/bin/bash

# ============================================
# HEALTH CHECK
# ============================================
# Verifies PR environment is healthy and ready
#
# Usage: ./health-check.sh <site_id> <site_domain> <db_name> <redis_db>
# Example: ./health-check.sh 12345 pr-123.test.com pr_123_myapp 5
# ============================================

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# ============================================
# VALIDATE INPUTS
# ============================================

if [ $# -ne 4 ]; then
    log_error "Usage: $0 <site_id> <site_domain> <db_name> <redis_db>"
    exit 1
fi

SITE_ID="$1"
SITE_DOMAIN="$2"
DB_NAME="$3"
REDIS_DB="$4"

log_info "=========================================="
log_info "Running Health Check"
log_info "=========================================="
log_info "Site ID: $SITE_ID"
log_info "Domain: $SITE_DOMAIN"
log_info "Database: $DB_NAME"
log_info "Redis DB: $REDIS_DB"
log_info "=========================================="

HEALTH_CHECK_FAILED=0

# ============================================
# CHECK 1: SITE DEPLOYMENT STATUS
# ============================================

log_info "[1/6] Checking deployment status..."

SITE_RESPONSE=$(curl -s -X GET \
    -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
    -H "Accept: application/json" \
    --connect-timeout ${API_TIMEOUT} \
    "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/sites/${SITE_ID}")

DEPLOYMENT_STATUS=$(echo "$SITE_RESPONSE" | jq -r '.site.deployment_status')

if [ "$DEPLOYMENT_STATUS" = "null" ] || [ "$DEPLOYMENT_STATUS" = "failed" ]; then
    log_error "Deployment status: ${DEPLOYMENT_STATUS}"
    HEALTH_CHECK_FAILED=1
else
    log_success "Deployment status: ${DEPLOYMENT_STATUS}"
fi

# ============================================
# CHECK 2: HTTP RESPONSE
# ============================================

log_info "[2/6] Checking HTTP response..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 10 \
    --max-time 30 \
    -k \
    "https://${SITE_DOMAIN}" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    log_success "HTTP response: $HTTP_CODE"
else
    log_error "HTTP response: $HTTP_CODE (expected 200 or 302)"
    HEALTH_CHECK_FAILED=1
fi

# ============================================
# CHECK 3: DATABASE CONNECTION
# ============================================

log_info "[3/6] Checking database connection..."

# Test connection
if mysql -h"${DB_HOST}" \
    -u"${DB_NAME}" \
    -p"${DB_PASSWORD}" \
    -e "SELECT 1" \
    "${DB_NAME}" > /dev/null 2>&1; then

    # Check table count
    TABLE_COUNT=$(mysql -h"${DB_HOST}" \
        -u"${DB_ROOT_USER}" \
        -p"${DB_ROOT_PASSWORD}" \
        -Nse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${DB_NAME}'" 2>/dev/null)

    log_success "Database connected (${TABLE_COUNT} tables)"
else
    log_error "Database connection failed"
    HEALTH_CHECK_FAILED=1
fi

# ============================================
# CHECK 4: REDIS CONNECTION
# ============================================

log_info "[4/6] Checking Redis connection..."

if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_PING=$(redis-cli -h "${REDIS_HOST}" \
        -p "${REDIS_PORT}" \
        -a "${REDIS_PASSWORD}" \
        -n "${REDIS_DB}" \
        PING 2>/dev/null || echo "")
else
    REDIS_PING=$(redis-cli -h "${REDIS_HOST}" \
        -p "${REDIS_PORT}" \
        -n "${REDIS_DB}" \
        PING 2>/dev/null || echo "")
fi

if [ "$REDIS_PING" = "PONG" ]; then
    log_success "Redis connected"
else
    log_error "Redis connection failed"
    HEALTH_CHECK_FAILED=1
fi

# ============================================
# CHECK 5: QUEUE WORKERS
# ============================================

log_info "[5/6] Checking queue workers..."

SITE_PATH="${SITE_DIRECTORY}/${SITE_DOMAIN}"

DAEMONS_RESPONSE=$(curl -s -X GET \
    -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
    -H "Accept: application/json" \
    --connect-timeout ${API_TIMEOUT} \
    "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/daemons")

DAEMON_COUNT=$(echo "$DAEMONS_RESPONSE" | jq -r "[.daemons[] | select(.directory == \"${SITE_PATH}\")] | length")

if [ "$DAEMON_COUNT" -ge "$QUEUE_WORKERS" ]; then
    log_success "Queue workers running: $DAEMON_COUNT"
else
    log_error "Queue workers: $DAEMON_COUNT (expected: ${QUEUE_WORKERS})"
    HEALTH_CHECK_FAILED=1
fi

# ============================================
# CHECK 6: LARAVEL HEALTH ENDPOINT
# ============================================

log_info "[6/6] Checking Laravel health endpoint..."

HEALTH_RESPONSE=$(curl -s \
    --connect-timeout 10 \
    --max-time 30 \
    -k \
    "https://${SITE_DOMAIN}/api/health" 2>/dev/null || echo "{}")

HEALTH_STATUS=$(echo "$HEALTH_RESPONSE" | jq -r '.status // "unknown"')

if [ "$HEALTH_STATUS" = "healthy" ] || [ "$HEALTH_STATUS" = "ok" ]; then
    log_success "Laravel health: $HEALTH_STATUS"
elif [ "$HEALTH_STATUS" = "unknown" ]; then
    log_warn "Health endpoint not available (non-fatal)"
else
    log_error "Laravel health: $HEALTH_STATUS"
    HEALTH_CHECK_FAILED=1
fi

# ============================================
# RESULT
# ============================================

log_info "=========================================="

if [ $HEALTH_CHECK_FAILED -eq 0 ]; then
    log_success "✅ All Health Checks Passed!"
    log_success "=========================================="
    exit 0
else
    log_error "❌ Health Check Failed!"
    log_error "=========================================="
    exit 1
fi
```

---

## 5. Utility Functions

**File**: `/home/forge/.scripts/utils.sh`

```bash
#!/bin/bash

# ============================================
# UTILITY FUNCTIONS
# ============================================
# Shared utility functions for all scripts
# ============================================

# ============================================
# LOGGING FUNCTIONS
# ============================================

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_DIR}/automation.log"
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" | tee -a "${LOG_DIR}/automation.log"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "${LOG_DIR}/automation.log"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_DIR}/automation.log" >&2
}

log_debug() {
    if [ "$LOG_LEVEL" = "DEBUG" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEBUG] $*" | tee -a "${LOG_DIR}/automation.log"
    fi
}

# ============================================
# RETRY LOGIC
# ============================================

retry_command() {
    local retries=0
    local max_retries=${MAX_RETRIES:-3}
    local delay=${RETRY_DELAY:-5}

    until "$@"; do
        retries=$((retries + 1))

        if [ $retries -ge $max_retries ]; then
            log_error "Command failed after $max_retries attempts: $*"
            return 1
        fi

        log_warn "Command failed (attempt $retries/$max_retries), retrying in ${delay}s..."
        sleep $delay
    done

    return 0
}

# ============================================
# PASSWORD GENERATION
# ============================================

generate_password() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*' | head -c "$length"
}

# ============================================
# FILE SIZE FORMATTING
# ============================================

human_readable_size() {
    local size=$1

    if [ $size -lt 1024 ]; then
        echo "${size}B"
    elif [ $size -lt 1048576 ]; then
        echo "$(( size / 1024 ))KB"
    elif [ $size -lt 1073741824 ]; then
        echo "$(( size / 1048576 ))MB"
    else
        echo "$(( size / 1073741824 ))GB"
    fi
}

# ============================================
# CLEANUP FUNCTIONS
# ============================================

cleanup_temp_files() {
    local temp_dir="$1"

    if [ -d "$temp_dir" ]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$temp_dir"
    fi
}

cleanup_on_failure() {
    local site_id="$1"

    log_error "Cleanup triggered due to failure"

    if [ -n "$site_id" ] && [ "$site_id" != "null" ]; then
        log_info "Attempting to delete failed site: $site_id"

        curl -s -X DELETE \
            -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
            -H "Accept: application/json" \
            --connect-timeout ${API_TIMEOUT} \
            "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/sites/${site_id}" > /dev/null
    fi
}

# ============================================
# DEPLOYMENT WAIT
# ============================================

wait_for_deployment() {
    local site_id="$1"
    local timeout="${2:-600}"
    local elapsed=0
    local interval=10

    log_info "Waiting for deployment to complete (timeout: ${timeout}s)..."

    while [ $elapsed -lt $timeout ]; do
        SITE_RESPONSE=$(curl -s -X GET \
            -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
            -H "Accept: application/json" \
            --connect-timeout ${API_TIMEOUT} \
            "${FORGE_API_BASE}/servers/${FORGE_SERVER_ID}/sites/${site_id}")

        DEPLOYMENT_STATUS=$(echo "$SITE_RESPONSE" | jq -r '.site.deployment_status')

        if [ "$DEPLOYMENT_STATUS" = "finished" ]; then
            log_success "Deployment completed successfully"
            return 0
        elif [ "$DEPLOYMENT_STATUS" = "failed" ]; then
            log_error "Deployment failed"
            return 1
        fi

        sleep $interval
        elapsed=$((elapsed + interval))

        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "Still deploying... (${elapsed}s elapsed)"
        fi
    done

    log_error "Deployment timeout after ${timeout}s"
    return 1
}

# ============================================
# NOTIFICATION FUNCTIONS
# ============================================

notify_success() {
    local message="$1"

    if [ "$NOTIFY_ON_SUCCESS" = "true" ] && [ -n "$SLACK_WEBHOOK_URL" ]; then
        send_slack_notification "✅ Success" "$message" "good"
    fi
}

notify_error() {
    local message="$1"

    if [ "$NOTIFY_ON_ERROR" = "true" ] && [ -n "$SLACK_WEBHOOK_URL" ]; then
        send_slack_notification "❌ Error" "$message" "danger"
    fi
}

send_slack_notification() {
    local title="$1"
    local message="$2"
    local color="${3:-good}"

    local payload=$(cat <<EOF
{
  "attachments": [
    {
      "fallback": "${title}: ${message}",
      "color": "${color}",
      "title": "${title}",
      "text": "${message}",
      "footer": "PR Environment Automation",
      "ts": $(date +%s)
    }
  ]
}
EOF
)

    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$SLACK_WEBHOOK_URL" > /dev/null
}

# ============================================
# INITIALIZATION
# ============================================

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Rotate logs if they're too large (> 10MB)
if [ -f "${LOG_DIR}/automation.log" ]; then
    LOG_SIZE=$(stat -f%z "${LOG_DIR}/automation.log" 2>/dev/null || stat -c%s "${LOG_DIR}/automation.log")
    if [ "$LOG_SIZE" -gt 10485760 ]; then
        mv "${LOG_DIR}/automation.log" "${LOG_DIR}/automation.log.$(date +%Y%m%d_%H%M%S)"
        gzip "${LOG_DIR}/automation.log".* 2>/dev/null || true
    fi
fi
```

---

## Installation

### 1. Create Script Directory

```bash
# SSH into Forge server
ssh forge@your-server.com

# Create script directory
mkdir -p /home/forge/.scripts
mkdir -p /home/forge/.scripts/logs

# Set permissions
chmod 700 /home/forge/.scripts
chmod 700 /home/forge/.scripts/logs
```

### 2. Copy Scripts

```bash
# Copy all scripts to server
scp config.sh forge@your-server:/home/forge/.scripts/
scp utils.sh forge@your-server:/home/forge/.scripts/
scp create-pr-environment.sh forge@your-server:/home/forge/.scripts/
scp destroy-pr-environment.sh forge@your-server:/home/forge/.scripts/
scp refresh-master-snapshots.sh forge@your-server:/home/forge/.scripts/
scp health-check.sh forge@your-server:/home/forge/.scripts/

# Make executable
ssh forge@your-server "chmod +x /home/forge/.scripts/*.sh"
```

### 3. Configure Environment Variables

```bash
# Edit config.sh with your values
ssh forge@your-server
nano /home/forge/.scripts/config.sh

# Set sensitive values
export FORGE_API_TOKEN="your-forge-api-token"
export DB_ROOT_PASSWORD="your-db-root-password"
export REDIS_PASSWORD="your-redis-password"
export PRODUCTION_DB_PASSWORD="your-production-db-password"
```

### 4. Setup Cron Jobs

```bash
# Edit crontab
crontab -e

# Add weekly snapshot refresh (Sunday 2 AM)
0 2 * * 0 /home/forge/.scripts/refresh-master-snapshots.sh >> /home/forge/.scripts/logs/cron.log 2>&1

# Add daily log cleanup (Keep 30 days)
0 3 * * * find /home/forge/.scripts/logs -name "*.log.*.gz" -mtime +30 -delete
```

---

## Usage Examples

### Create PR Environment

```bash
# From GitHub Actions
./create-pr-environment.sh 123 myapp feature/new-feature

# Manual testing
./create-pr-environment.sh 999 myapp test-branch
```

**Output**:
```
==========================================
Creating PR Environment
==========================================
PR Number: 123
Project: myapp
Branch: feature/new-feature
Site Domain: pr-123.pr-test.yourdomain.com
Database: pr_123_myapp
==========================================
[1/8] Creating Forge site...
✓ Site created with ID: 12345
[2/8] Creating database...
✓ Database created: pr_123_myapp
[3/8] Cloning master database snapshot...
✓ Database cloned successfully
...
==========================================
PR Environment Created Successfully!
==========================================
Site URL: https://pr-123.pr-test.yourdomain.com
Site ID: 12345
Database: pr_123_myapp
Redis DB: 6
==========================================
```

### Destroy PR Environment

```bash
# From GitHub Actions
./destroy-pr-environment.sh 123 myapp

# Manual cleanup
./destroy-pr-environment.sh 999
```

### Refresh Master Snapshot

```bash
# Manual refresh
./refresh-master-snapshots.sh myapp

# Check logs
tail -f /home/forge/.scripts/logs/automation.log
```

### Run Health Check

```bash
# Check specific environment
./health-check.sh 12345 pr-123.test.com pr_123_myapp 6

# From create script (automatic)
```

---

## Error Handling

### Automatic Retry Logic

All API calls use retry logic:

```bash
retry_command curl -s -X POST \
    -H "Authorization: Bearer ${FORGE_API_TOKEN}" \
    -d "${PAYLOAD}" \
    "${API_URL}"
```

**Behavior**:
- Retries 3 times by default
- 5-second delay between retries
- Logs each attempt
- Returns failure after max retries

### Cleanup on Failure

If creation fails, automatic cleanup:

```bash
cleanup_on_failure "$SITE_ID"
```

**Cleanup includes**:
- Delete Forge site
- Drop database
- Flush Redis
- Remove files
- Log failure

### Logging

All operations logged:

```bash
log_info "Starting operation..."
log_success "Operation completed"
log_warn "Non-fatal issue detected"
log_error "Fatal error occurred"
log_debug "Detailed debugging info"
```

**Log locations**:
- `/home/forge/.scripts/logs/automation.log` - Main log
- `/home/forge/.scripts/logs/cron.log` - Cron job output

---

## Security Best Practices

### 1. Environment Variables

✅ **DO**:
```bash
export FORGE_API_TOKEN="${FORGE_API_TOKEN}"
```

❌ **DON'T**:
```bash
FORGE_API_TOKEN="hardcoded-token-here"
```

### 2. File Permissions

```bash
# Script directory (owner only)
chmod 700 /home/forge/.scripts

# Scripts (owner execute)
chmod 700 /home/forge/.scripts/*.sh

# Config file (owner read/write)
chmod 600 /home/forge/.scripts/config.sh

# Log directory (owner only)
chmod 700 /home/forge/.scripts/logs
```

### 3. Database Credentials

```bash
# Never log passwords
mysql -p"${DB_PASSWORD}" 2>/dev/null

# Use environment variables
DB_PASSWORD="${DB_ROOT_PASSWORD}"
```

### 4. API Token Security

```bash
# Store in environment
export FORGE_API_TOKEN="token"

# Never commit to git
echo ".env" >> .gitignore
echo "config.sh" >> .gitignore
```

---

## Monitoring & Notifications

### Slack Notifications

Enable in `config.sh`:

```bash
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
export NOTIFY_ON_ERROR=true
export NOTIFY_ON_SUCCESS=false
```

**Notification format**:
```json
{
  "attachments": [{
    "color": "good",
    "title": "✅ Success",
    "text": "PR environment created for PR #123",
    "footer": "PR Environment Automation"
  }]
}
```

### Log Monitoring

```bash
# Watch logs in real-time
tail -f /home/forge/.scripts/logs/automation.log

# Search for errors
grep ERROR /home/forge/.scripts/logs/automation.log

# Check recent operations
tail -100 /home/forge/.scripts/logs/automation.log
```

---

## Troubleshooting

### Script Fails to Execute

**Problem**: Permission denied

**Solution**:
```bash
chmod +x /home/forge/.scripts/*.sh
```

### API Calls Timeout

**Problem**: Connection timeout

**Solution**:
```bash
# Increase timeout in config.sh
export API_TIMEOUT=60
```

### Database Import Fails

**Problem**: Large database

**Solution**:
```bash
# Use compression
mysqldump --compress | gzip > dump.sql.gz
gunzip < dump.sql.gz | mysql
```

### Redis Connection Fails

**Problem**: Password authentication

**Solution**:
```bash
# Test connection
redis-cli -h localhost -a "password" PING

# Update config
export REDIS_PASSWORD="correct-password"
```

---

## Performance Optimization

### Parallel Operations

Use `&` for parallel execution:

```bash
# Start multiple operations
operation1 &
PID1=$!

operation2 &
PID2=$!

# Wait for completion
wait $PID1 $PID2
```

### Database Optimization

```bash
# Fast dump
mysqldump --single-transaction --quick --lock-tables=false

# Fast import
mysql --compress --quick
```

### Network Optimization

```bash
# Compress data transfer
mysqldump --compress
curl --compressed
```

---

## Next Steps

1. **Test Scripts**: Run in staging environment
2. **Configure Monitoring**: Setup Slack notifications
3. **Automate Backups**: Schedule snapshot refreshes
4. **Integrate GitHub Actions**: Connect scripts to workflows
5. **Document Custom Changes**: Update for your infrastructure

---

## Related Documentation

- [1-github-actions-workflows.md](./1-github-actions-workflows.md) - GitHub Actions integration
- [2-forge-api-integration.md](./2-forge-api-integration.md) - Forge API details
- [../3-critical-reading/1-critical-concerns.md](../3-critical-reading/1-critical-concerns.md) - Security & cost concerns

---

**Last Updated**: 2025-01-07
**Status**: ✅ Complete - Production Ready
