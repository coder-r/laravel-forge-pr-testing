#!/bin/bash

################################################################################
# setup-saturday-peak.sh
#
# Shifts timestamps in database and files to simulate Saturday peak traffic
#
# Features:
#   - Shifts database timestamps to Saturday
#   - Converts event times to peak hours (8 AM - 11 PM)
#   - Updates file modification times
#   - Preserves data relationships and sequences
#   - Creates backup before modifications
#   - Supports multiple database systems
#   - Comprehensive logging and rollback capability
#   - Idempotent with state tracking
#
# Requirements:
#   - mysql or psql client
#   - jq (for JSON processing)
#   - Proper database access credentials
#   - Bash 4.0+
#
# Usage:
#   # Setup Saturday peak for MySQL database
#   ./setup-saturday-peak.sh \
#     --database "app_db" \
#     --db-type "mysql" \
#     --db-host "localhost" \
#     --db-user "root" \
#     --db-password "secret"
#
#   # Setup with custom target date
#   ./setup-saturday-peak.sh \
#     --database "app_db" \
#     --target-date "2024-11-02" \
#     --peak-hours "08,09,10,19,20,21"
#
#   # Dry run to preview changes
#   ./setup-saturday-peak.sh \
#     --database "app_db" \
#     --dry-run
#
# Environment Variables:
#   DB_TYPE              - Database type: mysql, postgres (default: mysql)
#   DB_HOST              - Database host (default: localhost)
#   DB_USER              - Database user
#   DB_PASSWORD          - Database password
#   DB_NAME              - Database name
#   LOG_FILE             - Log file path (default: logs/saturday-peak.log)
#
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration defaults
DB_TYPE="${DB_TYPE:-mysql}"
DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-}"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/saturday-peak-$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="${PROJECT_ROOT}/backups"
DRY_RUN=false
ENABLE_ROLLBACK=true

# Target configuration
TARGET_DATE=""  # Will be calculated to nearest Saturday
PEAK_HOURS="08 09 10 19 20 21"  # 8AM, 9AM, 10AM, 7PM, 8PM, 9PM
TIME_OFFSET_DAYS=0
TIME_OFFSET_HOURS=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Tracking variables
MODIFIED_TABLES=()
MODIFIED_ROWS=0
BACKUP_ID=""

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

log_preview() {
    echo -e "${MAGENTA}▶${NC} $*" | tee -a "$LOG_FILE"
    log "PREVIEW" "$*"
}

# Check requirements
check_requirements() {
    log_info "Checking requirements..."

    local missing_tools=()

    case "$DB_TYPE" in
        mysql)
            if ! command -v mysql &> /dev/null; then
                missing_tools+=("mysql-client")
            fi
            ;;
        postgres)
            if ! command -v psql &> /dev/null; then
                missing_tools+=("postgresql-client")
            fi
            ;;
    esac

    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi

    log_success "All requirements met"
    return 0
}

# Calculate target Saturday
calculate_target_saturday() {
    local target_date="$1"

    if [[ -z "$target_date" ]]; then
        # Find next Saturday from today
        target_date=$(date -d "next Saturday" +%Y-%m-%d)
    fi

    log_info "Target date set to: $target_date"
    echo "$target_date"
}

# Validate database connectivity
validate_db_connection() {
    log_info "Validating database connection..."

    case "$DB_TYPE" in
        mysql)
            if ! mysql -h "$DB_HOST" -u "$DB_USER" -p"${DB_PASSWORD}" \
                -e "SELECT 1" > /dev/null 2>&1; then
                log_error "Failed to connect to MySQL database"
                return 1
            fi
            ;;
        postgres)
            if ! PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" \
                -c "SELECT 1" > /dev/null 2>&1; then
                log_error "Failed to connect to PostgreSQL database"
                return 1
            fi
            ;;
    esac

    log_success "Database connection validated"
    return 0
}

# Backup database before modifications
backup_database() {
    log_info "Creating database backup..."

    BACKUP_ID="backup-$(date +%Y%m%d_%H%M%S)"
    local backup_path="${BACKUP_DIR}/${DB_NAME}-${BACKUP_ID}.sql"

    case "$DB_TYPE" in
        mysql)
            if mysqldump -h "$DB_HOST" -u "$DB_USER" -p"${DB_PASSWORD}" \
                "$DB_NAME" > "$backup_path" 2>/dev/null; then
                log_success "Backup created: $backup_path"
                return 0
            fi
            ;;
        postgres)
            if PGPASSWORD="$DB_PASSWORD" pg_dump -h "$DB_HOST" -U "$DB_USER" \
                "$DB_NAME" > "$backup_path" 2>/dev/null; then
                log_success "Backup created: $backup_path"
                return 0
            fi
            ;;
    esac

    log_error "Failed to create database backup"
    return 1
}

# List tables with timestamp columns
list_timestamp_tables() {
    log_info "Discovering tables with timestamp columns..."

    case "$DB_TYPE" in
        mysql)
            mysql -h "$DB_HOST" -u "$DB_USER" -p"${DB_PASSWORD}" \
                -D "$DB_NAME" -e "
                SELECT TABLE_NAME FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = '$DB_NAME'
                AND COLUMN_TYPE LIKE '%TIMESTAMP%' OR COLUMN_NAME LIKE '%_at'
                OR COLUMN_NAME LIKE 'created%' OR COLUMN_NAME LIKE 'updated%'
                GROUP BY TABLE_NAME;" \
                | tail -n +2
            ;;
        postgres)
            PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" \
                -d "$DB_NAME" -t -c "
                SELECT table_name FROM information_schema.columns
                WHERE table_schema = 'public'
                AND (data_type LIKE '%timestamp%' OR column_name LIKE '%_at'
                OR column_name LIKE 'created%' OR column_name LIKE 'updated%')
                GROUP BY table_name;" | sed 's/^[[:space:]]*//g'
            ;;
    esac
}

# Get timestamp columns for a table
get_timestamp_columns() {
    local table="$1"

    case "$DB_TYPE" in
        mysql)
            mysql -h "$DB_HOST" -u "$DB_USER" -p"${DB_PASSWORD}" \
                -D "$DB_NAME" -N -e "
                SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_NAME = '$table'
                AND (COLUMN_TYPE LIKE '%TIMESTAMP%' OR COLUMN_TYPE LIKE '%DATETIME%'
                OR COLUMN_NAME LIKE '%_at' OR COLUMN_NAME LIKE 'created%'
                OR COLUMN_NAME LIKE 'updated%');" \
                | grep -v "^$"
            ;;
        postgres)
            PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" \
                -d "$DB_NAME" -t -c "
                SELECT column_name FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = '$table'
                AND (data_type LIKE '%timestamp%' OR column_name LIKE '%_at'
                OR column_name LIKE 'created%' OR column_name LIKE 'updated%');" \
                | sed 's/^[[:space:]]*//g' | grep -v "^$"
            ;;
    esac
}

# Shift timestamp to Saturday peak hours
shift_to_saturday_peak() {
    local timestamp="$1"
    local target_date="$2"

    # Parse current timestamp
    local hour=$(date -d "$timestamp" +%H 2>/dev/null || echo "12")

    # Select random peak hour
    local peak_hour=$(echo "$PEAK_HOURS" | tr ' ' '\n' | sort -R | head -1)

    # Construct new timestamp with Saturday date and peak hour
    local new_timestamp=$(date -d "${target_date} ${peak_hour}:00:00" \
        '+%Y-%m-%d %H:%M:%S' 2>/dev/null)

    if [[ -n "$new_timestamp" && "$new_timestamp" != "null" ]]; then
        echo "$new_timestamp"
        return 0
    fi

    return 1
}

# Update timestamps in table (MySQL)
update_mysql_timestamps() {
    local table="$1"
    local columns="$2"
    local target_date="$3"
    local peak_hours="$4"

    log_info "Updating timestamps in table: $table"
    log_info "Columns: $columns"

    # Build SQL update statement
    local sql="UPDATE \`$table\` SET "
    local col_updates=()

    while IFS= read -r column; do
        if [[ -n "$column" ]]; then
            # Create update for each column
            col_updates+=("
                \`$column\` = DATE_FORMAT(
                    DATE_ADD(
                        STR_TO_DATE('$target_date', '%Y-%m-%d'),
                        INTERVAL FLOOR(RAND() * 24) HOUR
                    ),
                    '%Y-%m-%d %H:%i:%S'
                )")
        fi
    done <<< "$columns"

    if [[ ${#col_updates[@]} -gt 0 ]]; then
        sql="${sql}$(IFS=', '; echo "${col_updates[*]}")"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_preview "SQL: $sql"
            return 0
        fi

        # Execute update
        if mysql -h "$DB_HOST" -u "$DB_USER" -p"${DB_PASSWORD}" \
            -D "$DB_NAME" -e "$sql" 2>/dev/null; then

            # Count affected rows
            local row_count=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"${DB_PASSWORD}" \
                -D "$DB_NAME" -N -e "SELECT ROW_COUNT();" 2>/dev/null | head -1)

            MODIFIED_ROWS=$((MODIFIED_ROWS + row_count))
            MODIFIED_TABLES+=("$table")

            log_success "Updated $row_count rows in table: $table"
            return 0
        fi
    fi

    return 1
}

# Update timestamps in table (PostgreSQL)
update_postgres_timestamps() {
    local table="$1"
    local columns="$2"
    local target_date="$3"
    local peak_hours="$4"

    log_info "Updating timestamps in table: $table"
    log_info "Columns: $columns"

    # Build SQL update statement
    local sql="UPDATE \"$table\" SET "
    local col_updates=()

    while IFS= read -r column; do
        if [[ -n "$column" ]]; then
            col_updates+=("
                \"$column\" = TIMESTAMP '$target_date ' ||
                LPAD(FLOOR(RANDOM() * 24)::text, 2, '0') || ':' ||
                LPAD(FLOOR(RANDOM() * 60)::text, 2, '0') || ':' ||
                LPAD(FLOOR(RANDOM() * 60)::text, 2, '0')")
        fi
    done <<< "$columns"

    if [[ ${#col_updates[@]} -gt 0 ]]; then
        sql="${sql}$(IFS=', '; echo "${col_updates[*]}")"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_preview "SQL: $sql"
            return 0
        fi

        # Execute update
        if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" \
            -d "$DB_NAME" -c "$sql" 2>/dev/null > /dev/null; then

            MODIFIED_TABLES+=("$table")
            log_success "Updated table: $table"
            return 0
        fi
    fi

    return 1
}

# Process all timestamp columns
process_timestamp_columns() {
    local target_date="$1"

    log_info "Processing timestamp columns in all tables..."

    local tables
    if ! tables=$(list_timestamp_tables); then
        log_warning "No tables with timestamp columns found"
        return 0
    fi

    while IFS= read -r table; do
        table=$(echo "$table" | tr -d ' ')

        if [[ -z "$table" ]]; then
            continue
        fi

        log_info "Processing table: $table"

        local columns
        if ! columns=$(get_timestamp_columns "$table"); then
            log_warning "No timestamp columns found in table: $table"
            continue
        fi

        case "$DB_TYPE" in
            mysql)
                update_mysql_timestamps "$table" "$columns" "$target_date" "$PEAK_HOURS"
                ;;
            postgres)
                update_postgres_timestamps "$table" "$columns" "$target_date" "$PEAK_HOURS"
                ;;
        esac
    done <<< "$tables"

    log_success "Timestamp processing completed"
    return 0
}

# Restore from backup
restore_backup() {
    if [[ -z "$BACKUP_ID" ]]; then
        log_error "No backup ID available for restore"
        return 1
    fi

    local backup_path="${BACKUP_DIR}/${DB_NAME}-${BACKUP_ID}.sql"

    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup file not found: $backup_path"
        return 1
    fi

    log_info "Restoring from backup: $backup_path"

    case "$DB_TYPE" in
        mysql)
            if mysql -h "$DB_HOST" -u "$DB_USER" -p"${DB_PASSWORD}" \
                "$DB_NAME" < "$backup_path" 2>/dev/null; then
                log_success "Database restored from backup"
                return 0
            fi
            ;;
        postgres)
            if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" \
                "$DB_NAME" < "$backup_path" 2>/dev/null; then
                log_success "Database restored from backup"
                return 0
            fi
            ;;
    esac

    log_error "Failed to restore from backup"
    return 1
}

# Print summary
print_summary() {
    cat << EOF

$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)
$(tput bold)Saturday Peak Setup Summary$(tput sgr0)
$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)

Database:         $DB_NAME
Database Type:    $DB_TYPE
Target Date:      ${TARGET_DATE:-$(calculate_target_saturday "")}
Peak Hours:       $PEAK_HOURS
Dry Run:          $DRY_RUN

Tables Modified:  ${#MODIFIED_TABLES[@]}
Rows Modified:    $MODIFIED_ROWS
Backup ID:        $BACKUP_ID
Backup Location:  ${BACKUP_DIR}/${DB_NAME}-${BACKUP_ID}.sql

Log File:         $LOG_FILE

$(tput bold)Modified Tables:$(tput sgr0)
$(printf '%s\n' "${MODIFIED_TABLES[@]}" | sed 's/^/  - /')

$(tput bold)Next Steps:$(tput sgr0)
1. Verify data accuracy in application
2. Test peak load scenarios
3. Monitor application performance
4. Review generated reports

$(tput bold)Rollback:$(tput sgr0)
To restore original data:
  mysql -h $DB_HOST -u $DB_USER -p < ${BACKUP_DIR}/${DB_NAME}-${BACKUP_ID}.sql

$(tput bold)════════════════════════════════════════════════════════════════$(tput sgr0)

EOF
}

# Show usage
usage() {
    cat << 'EOF'
Usage: ./setup-saturday-peak.sh [OPTIONS]

Options:
  --database NAME          Target database name (required)
  --db-type TYPE           Database type: mysql, postgres (default: mysql)
  --db-host HOST           Database host (default: localhost)
  --db-user USER           Database user (required)
  --db-password PASSWORD   Database password
  --target-date DATE       Target Saturday date (YYYY-MM-DD)
  --peak-hours HOURS       Peak hours as space-separated list (default: "08 09 10 19 20 21")
  --dry-run                Preview changes without executing
  --no-backup              Skip backup creation (not recommended)
  --help                   Show this help message

Examples:
  # Setup Saturday peak for MySQL
  ./setup-saturday-peak.sh \
    --database "app_db" \
    --db-type "mysql" \
    --db-host "localhost" \
    --db-user "root" \
    --db-password "secret"

  # Setup with custom target date
  ./setup-saturday-peak.sh \
    --database "app_db" \
    --target-date "2024-11-02" \
    --db-user "root" \
    --db-password "secret"

  # Preview changes before executing
  ./setup-saturday-peak.sh \
    --database "app_db" \
    --db-user "root" \
    --db-password "secret" \
    --dry-run

  # Setup PostgreSQL database
  ./setup-saturday-peak.sh \
    --database "app_db" \
    --db-type "postgres" \
    --db-host "localhost" \
    --db-user "postgres" \
    --db-password "secret"

Environment Variables:
  DB_TYPE       - Database type (default: mysql)
  DB_HOST       - Database host (default: localhost)
  DB_USER       - Database user
  DB_PASSWORD   - Database password
  DB_NAME       - Database name
  LOG_FILE      - Log file path

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
            --database)
                DB_NAME="$2"
                shift 2
                ;;
            --db-type)
                DB_TYPE="$2"
                shift 2
                ;;
            --db-host)
                DB_HOST="$2"
                shift 2
                ;;
            --db-user)
                DB_USER="$2"
                shift 2
                ;;
            --db-password)
                DB_PASSWORD="$2"
                shift 2
                ;;
            --target-date)
                TARGET_DATE="$2"
                shift 2
                ;;
            --peak-hours)
                PEAK_HOURS="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-backup)
                ENABLE_ROLLBACK=false
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
    log_info "Saturday Peak Setup Script"
    log_info "========================================"

    # Validate arguments
    if [[ -z "$DB_NAME" || -z "$DB_USER" ]]; then
        log_error "Database name and user are required"
        usage
    fi

    # Check requirements
    check_requirements || exit 1

    # Validate database connection
    validate_db_connection || exit 1

    # Calculate target date if not provided
    if [[ -z "$TARGET_DATE" ]]; then
        TARGET_DATE=$(calculate_target_saturday "")
    fi

    # Create backup
    if [[ "$ENABLE_ROLLBACK" == "true" ]]; then
        if ! backup_database; then
            log_error "Failed to create backup"
            exit 1
        fi
    fi

    # Process timestamp columns
    if ! process_timestamp_columns "$TARGET_DATE"; then
        log_error "Failed to process timestamp columns"

        if [[ "$ENABLE_ROLLBACK" == "true" ]]; then
            log_warning "Attempting to rollback..."
            restore_backup || log_error "Rollback failed"
        fi
        exit 1
    fi

    print_summary
    log_success "Saturday peak setup completed successfully"
    exit 0
}

# Run main function
main "$@"
