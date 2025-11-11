#!/bin/bash
set -euo pipefail

#######################################################
# Production Database Cloning Script (READ-ONLY)
#######################################################
# Safely clones keatchen production database to test environment
# Source: tall-stream (886474) - 18.135.39.222
# Target: curved-sanctuary (986747) - pr-test-devpel.on-forge.com
#######################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Production Server (READ-ONLY ACCESS)
PROD_SERVER="tall-stream"
PROD_SERVER_ID="886474"
PROD_HOST="18.135.39.222"
PROD_USER="forge"
PROD_DB="PROD_APP"  # Production database name
PROD_SSH_KEY="${FORGE_SSH_KEY:-$HOME/.ssh/id_rsa}"

# Test Environment
TEST_SERVER="curved-sanctuary"
TEST_SERVER_ID="986747"
TEST_SITE_ID="2925742"
TEST_HOST="159.65.213.130"
TEST_DB="forge"
TEST_USER="forge"

# Backup location
BACKUP_DIR="${PROJECT_ROOT}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DUMP_FILE="${BACKUP_DIR}/keatchen_prod_${TIMESTAMP}.sql"
SANITIZED_FILE="${BACKUP_DIR}/keatchen_sanitized_${TIMESTAMP}.sql"

#######################################################
# Functions
#######################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check SSH access to production
    if ! ssh -i "$PROD_SSH_KEY" -o ConnectTimeout=5 "${PROD_USER}@${PROD_HOST}" "echo 'SSH OK'" &>/dev/null; then
        log_error "Cannot connect to production server via SSH"
        log_info "Please ensure SSH key is configured: $PROD_SSH_KEY"
        exit 1
    fi
    log_success "Production SSH access verified"

    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    log_success "Backup directory ready: $BACKUP_DIR"
}

dump_production_database() {
    log_info "Creating production database dump (READ-ONLY)..."
    log_warning "This will NOT modify production - safe read-only operation"

    # SSH into production and create dump
    ssh -i "$PROD_SSH_KEY" "${PROD_USER}@${PROD_HOST}" << 'REMOTE_SCRIPT' > "$DUMP_FILE"
#!/bin/bash
set -euo pipefail

# Database credentials from .env
DB_NAME="PROD_APP"
DB_USER="forge"
DB_PASS="fXcAINwUflS64JVWQYC5"

# Create compressed dump with progress
mysqldump \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --routines \
    --triggers \
    --events \
    -u"${DB_USER}" \
    -p"${DB_PASS}" \
    "${DB_NAME}" \
    2>/dev/null

echo "-- Dump completed at $(date)" >&2
REMOTE_SCRIPT

    local dump_size=$(du -h "$DUMP_FILE" | cut -f1)
    log_success "Production dump created: $DUMP_FILE ($dump_size)"
}

sanitize_database_dump() {
    log_info "Sanitizing database dump for test environment..."

    # Create sanitized version
    cat "$DUMP_FILE" | sed \
        -e 's/DEFINER=[^ ]* / /g' \
        -e 's/DEFINER=[^ ]*@[^ ]* / /g' \
        > "$SANITIZED_FILE"

    log_success "Database dump sanitized: $SANITIZED_FILE"
}

import_to_test_environment() {
    log_info "Importing database to test environment..."
    log_info "Target: $TEST_HOST (Site ID: $TEST_SITE_ID)"

    # Transfer dump to test server
    log_info "Transferring dump file..."
    scp -i "$PROD_SSH_KEY" "$SANITIZED_FILE" "${TEST_USER}@${TEST_HOST}:/tmp/import.sql"

    # Import via SSH
    log_info "Importing to database '$TEST_DB'..."
    ssh -i "$PROD_SSH_KEY" "${TEST_USER}@${TEST_HOST}" << REMOTE_IMPORT
#!/bin/bash
set -euo pipefail

# Import the dump
mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge < /tmp/import.sql

# Clean up
rm /tmp/import.sql

echo "Import completed successfully"
REMOTE_IMPORT

    log_success "Database imported successfully to test environment"
}

verify_import() {
    log_info "Verifying database import..."

    # Check table count
    local table_count=$(ssh -i "$PROD_SSH_KEY" "${TEST_USER}@${TEST_HOST}" \
        "mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge -e 'SHOW TABLES;' | wc -l")

    log_success "Database contains $((table_count - 1)) tables"

    # Check for orders table (key table for Saturday peak testing)
    local orders_count=$(ssh -i "$PROD_SSH_KEY" "${TEST_USER}@${TEST_HOST}" \
        "mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge -e 'SELECT COUNT(*) FROM orders;' 2>/dev/null" || echo "0")

    if [ -n "$orders_count" ]; then
        log_success "Orders table verified: $orders_count orders"
    fi
}

cleanup_old_backups() {
    log_info "Cleaning up old backups (keeping last 5)..."

    # Keep only the 5 most recent dumps
    ls -t "${BACKUP_DIR}"/keatchen_prod_*.sql 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
    ls -t "${BACKUP_DIR}"/keatchen_sanitized_*.sql 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true

    log_success "Old backups cleaned up"
}

#######################################################
# Main Execution
#######################################################

main() {
    echo ""
    echo "================================================"
    echo "  Production Database Cloning (READ-ONLY)"
    echo "================================================"
    echo ""
    echo "Source: ${PROD_SERVER} (${PROD_HOST})"
    echo "Database: ${PROD_DB}"
    echo "Target: ${TEST_SERVER} (${TEST_HOST})"
    echo "Database: ${TEST_DB}"
    echo ""
    log_warning "READ-ONLY operation - production will NOT be modified"
    echo ""

    check_prerequisites
    dump_production_database
    sanitize_database_dump
    import_to_test_environment
    verify_import
    cleanup_old_backups

    echo ""
    echo "================================================"
    echo "  ✅ Database Cloning Complete!"
    echo "================================================"
    echo ""
    echo "Dump file: $DUMP_FILE"
    echo "Sanitized: $SANITIZED_FILE"
    echo "Imported to: ${TEST_HOST} (database: ${TEST_DB})"
    echo ""
    echo "Next step: Run saturday-peak-data.sh to transform timestamps"
    echo ""
}

# Run main function
main "$@"
