#!/bin/bash

################################################################################
# ssh-clone-database.sh
#
# SSH-based database cloning for Laravel Forge environments
#
# This script uses SSH to clone databases between servers without requiring
# direct MySQL access, which is typically blocked by firewalls.
#
# Features:
#   - Works through SSH (no direct MySQL access needed)
#   - Compressed transfer using gzip
#   - Two methods: direct pipe and file-based fallback
#   - Automatic cleanup of temporary files
#   - Progress logging and error handling
#   - Compatible with Forge server configurations
#
# Requirements:
#   - SSH access to both source and target servers
#   - MySQL/MariaDB on both servers
#   - Sufficient disk space for temporary dumps
#
# Usage:
#   ./ssh-clone-database.sh \
#     --source-host "1.2.3.4" \
#     --source-db "production_db" \
#     --target-host "5.6.7.8" \
#     --target-db "pr_123_db" \
#     --target-user "pr_123_user" \
#     --target-password "secret"
#
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"
LOG_FILE="${LOG_DIR}/ssh-clone-database-$(date +%Y%m%d_%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parameters
SOURCE_HOST=""
SOURCE_DB=""
SOURCE_USER="${SOURCE_USER:-root}"
TARGET_HOST=""
TARGET_DB=""
TARGET_USER=""
TARGET_PASSWORD=""
SSH_USER="${SSH_USER:-forge}"
SSH_OPTIONS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"

################################################################################
# Utility Functions
################################################################################

mkdir -p "$LOG_DIR"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
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

################################################################################
# Database Cloning Functions
################################################################################

# Check SSH connectivity
check_ssh_connectivity() {
    local host="$1"
    local user="$2"

    log_info "Checking SSH connectivity to ${user}@${host}..."

    if ssh ${SSH_OPTIONS} "${user}@${host}" "echo 'SSH OK'" >/dev/null 2>&1; then
        log_success "SSH connection successful to ${host}"
        return 0
    else
        log_error "SSH connection failed to ${host}"
        return 1
    fi
}

# Check database exists on source
check_source_database() {
    local host="$1"
    local user="$2"
    local db_name="$3"
    local db_user="$4"

    log_info "Checking source database exists: ${db_name}"

    if ssh ${SSH_OPTIONS} "${user}@${host}" \
        "mysql --user='${db_user}' --execute='USE ${db_name}' 2>/dev/null"; then
        log_success "Source database exists: ${db_name}"
        return 0
    else
        log_error "Source database not found: ${db_name}"
        return 1
    fi
}

# Check target database exists
check_target_database() {
    local host="$1"
    local user="$2"
    local db_name="$3"
    local db_user="$4"
    local db_password="$5"

    log_info "Checking target database exists: ${db_name}"

    if ssh ${SSH_OPTIONS} "${user}@${host}" \
        "mysql --user='${db_user}' --password='${db_password}' --execute='USE ${db_name}' 2>/dev/null"; then
        log_success "Target database exists: ${db_name}"
        return 0
    else
        log_warning "Target database not found: ${db_name}"
        return 1
    fi
}

# Method 1: Direct SSH pipe (fastest)
clone_via_ssh_pipe() {
    local source_host="$1"
    local source_db="$2"
    local source_db_user="$3"
    local target_host="$4"
    local target_db="$5"
    local target_db_user="$6"
    local target_db_password="$7"

    log_info "Attempting SSH pipe method..."
    log_info "Source: ${source_host}:${source_db}"
    log_info "Target: ${target_host}:${target_db}"

    # Dump on source, compress, transfer, decompress, import on target
    if ssh ${SSH_OPTIONS} "${SSH_USER}@${source_host}" \
        "mysqldump --single-transaction --quick --lock-tables=false --user='${source_db_user}' ${source_db} 2>/dev/null | gzip" | \
       ssh ${SSH_OPTIONS} "${SSH_USER}@${target_host}" \
        "gunzip | mysql --user='${target_db_user}' --password='${target_db_password}' ${target_db} 2>/dev/null"; then

        log_success "Database cloned successfully via SSH pipe"
        return 0
    else
        local exit_code=$?
        log_warning "SSH pipe method failed with exit code: ${exit_code}"
        return 1
    fi
}

# Method 2: File-based approach (fallback)
clone_via_file_transfer() {
    local source_host="$1"
    local source_db="$2"
    local source_db_user="$3"
    local target_host="$4"
    local target_db="$5"
    local target_db_user="$6"
    local target_db_password="$7"

    log_info "Attempting file transfer method..."

    local temp_file="/tmp/db_clone_$(date +%s).sql.gz"

    # Step 1: Create dump on source server
    log_info "Creating compressed dump on source server..."
    if ! ssh ${SSH_OPTIONS} "${SSH_USER}@${source_host}" \
        "mysqldump --single-transaction --quick --lock-tables=false --user='${source_db_user}' ${source_db} 2>/dev/null | gzip > ${temp_file}"; then
        log_error "Failed to create dump on source server"
        return 1
    fi

    # Get dump file size
    local dump_size
    dump_size=$(ssh ${SSH_OPTIONS} "${SSH_USER}@${source_host}" \
        "du -h ${temp_file} 2>/dev/null | cut -f1" || echo "unknown")
    log_info "Dump file size: ${dump_size}"

    # Step 2: Transfer dump to target server
    log_info "Transferring dump to target server..."
    if ! ssh ${SSH_OPTIONS} "${SSH_USER}@${source_host}" \
        "cat ${temp_file}" | \
       ssh ${SSH_OPTIONS} "${SSH_USER}@${target_host}" \
        "cat > ${temp_file}"; then
        log_error "Failed to transfer dump file"
        # Cleanup source
        ssh ${SSH_OPTIONS} "${SSH_USER}@${source_host}" "rm -f ${temp_file}" 2>/dev/null || true
        return 1
    fi

    # Step 3: Import on target server
    log_info "Importing dump on target server..."
    if ! ssh ${SSH_OPTIONS} "${SSH_USER}@${target_host}" \
        "gunzip < ${temp_file} | mysql --user='${target_db_user}' --password='${target_db_password}' ${target_db} 2>/dev/null"; then
        log_error "Failed to import dump on target server"
        # Cleanup both servers
        ssh ${SSH_OPTIONS} "${SSH_USER}@${source_host}" "rm -f ${temp_file}" 2>/dev/null || true
        ssh ${SSH_OPTIONS} "${SSH_USER}@${target_host}" "rm -f ${temp_file}" 2>/dev/null || true
        return 1
    fi

    # Step 4: Cleanup temporary files
    log_info "Cleaning up temporary files..."
    ssh ${SSH_OPTIONS} "${SSH_USER}@${source_host}" "rm -f ${temp_file}" 2>/dev/null || true
    ssh ${SSH_OPTIONS} "${SSH_USER}@${target_host}" "rm -f ${temp_file}" 2>/dev/null || true

    log_success "Database cloned successfully via file transfer method"
    return 0
}

# Verify clone (check table count)
verify_clone() {
    local host="$1"
    local db_name="$2"
    local db_user="$3"
    local db_password="$4"

    log_info "Verifying clone integrity..."

    local table_count
    table_count=$(ssh ${SSH_OPTIONS} "${SSH_USER}@${host}" \
        "mysql --user='${db_user}' --password='${db_password}' --execute='SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"${db_name}\"' --batch --skip-column-names 2>/dev/null" || echo "0")

    if [[ "$table_count" -gt 0 ]]; then
        log_success "Clone verification passed: ${table_count} tables found"
        return 0
    else
        log_warning "Clone verification: no tables found (database might be empty or import failed)"
        return 1
    fi
}

################################################################################
# Main Execution
################################################################################

usage() {
    cat << 'EOF'
Usage: ./ssh-clone-database.sh [OPTIONS]

Required Options:
  --source-host HOST           Source server IP or hostname
  --source-db NAME             Source database name
  --target-host HOST           Target server IP or hostname
  --target-db NAME             Target database name
  --target-user USER           Target database user
  --target-password PASS       Target database password

Optional Options:
  --source-user USER           Source database user (default: root)
  --ssh-user USER              SSH username (default: forge)
  --verify                     Verify clone after completion
  --help                       Show this help message

Examples:
  # Clone database between servers
  ./ssh-clone-database.sh \
    --source-host "192.168.1.10" \
    --source-db "production_db" \
    --target-host "192.168.1.20" \
    --target-db "pr_123_db" \
    --target-user "pr_123_user" \
    --target-password "secret123"

  # Clone with verification
  ./ssh-clone-database.sh \
    --source-host "192.168.1.10" \
    --source-db "production_db" \
    --source-user "root" \
    --target-host "192.168.1.20" \
    --target-db "staging_db" \
    --target-user "staging_user" \
    --target-password "secret123" \
    --verify

Environment Variables:
  SOURCE_USER                  Source database user (default: root)
  SSH_USER                     SSH username (default: forge)
  LOG_DIR                      Log directory (default: ./logs)

EOF
    exit 1
}

main() {
    local verify=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source-host)
                SOURCE_HOST="$2"
                shift 2
                ;;
            --source-db)
                SOURCE_DB="$2"
                shift 2
                ;;
            --source-user)
                SOURCE_USER="$2"
                shift 2
                ;;
            --target-host)
                TARGET_HOST="$2"
                shift 2
                ;;
            --target-db)
                TARGET_DB="$2"
                shift 2
                ;;
            --target-user)
                TARGET_USER="$2"
                shift 2
                ;;
            --target-password)
                TARGET_PASSWORD="$2"
                shift 2
                ;;
            --ssh-user)
                SSH_USER="$2"
                shift 2
                ;;
            --verify)
                verify=true
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
    log_info "SSH Database Clone Script"
    log_info "========================================"

    # Validate required arguments
    if [[ -z "$SOURCE_HOST" || -z "$SOURCE_DB" || -z "$TARGET_HOST" || -z "$TARGET_DB" || -z "$TARGET_USER" || -z "$TARGET_PASSWORD" ]]; then
        log_error "Missing required arguments"
        usage
    fi

    log_info "Configuration:"
    log_info "  Source: ${SSH_USER}@${SOURCE_HOST}:${SOURCE_DB} (user: ${SOURCE_USER})"
    log_info "  Target: ${SSH_USER}@${TARGET_HOST}:${TARGET_DB} (user: ${TARGET_USER})"

    # Check SSH connectivity
    check_ssh_connectivity "$SOURCE_HOST" "$SSH_USER" || exit 1
    check_ssh_connectivity "$TARGET_HOST" "$SSH_USER" || exit 1

    # Check databases exist
    check_source_database "$SOURCE_HOST" "$SSH_USER" "$SOURCE_DB" "$SOURCE_USER" || exit 1
    check_target_database "$TARGET_HOST" "$SSH_USER" "$TARGET_DB" "$TARGET_USER" "$TARGET_PASSWORD" || {
        log_warning "Target database check failed, but continuing..."
    }

    # Try SSH pipe method first (fastest)
    if clone_via_ssh_pipe "$SOURCE_HOST" "$SOURCE_DB" "$SOURCE_USER" \
                          "$TARGET_HOST" "$TARGET_DB" "$TARGET_USER" "$TARGET_PASSWORD"; then
        log_success "Clone completed using SSH pipe method"
    else
        # Fallback to file transfer method
        log_info "Falling back to file transfer method..."
        if clone_via_file_transfer "$SOURCE_HOST" "$SOURCE_DB" "$SOURCE_USER" \
                                   "$TARGET_HOST" "$TARGET_DB" "$TARGET_USER" "$TARGET_PASSWORD"; then
            log_success "Clone completed using file transfer method"
        else
            log_error "All clone methods failed"
            exit 1
        fi
    fi

    # Verify clone if requested
    if [[ "$verify" == true ]]; then
        verify_clone "$TARGET_HOST" "$TARGET_DB" "$TARGET_USER" "$TARGET_PASSWORD" || {
            log_warning "Verification failed or incomplete"
        }
    fi

    log_success "Database clone operation completed successfully"
    log_info "Log file: ${LOG_FILE}"

    exit 0
}

# Run main function
main "$@"
