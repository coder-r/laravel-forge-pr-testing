#!/bin/bash
set -euo pipefail

#######################################################
# Setup Cron Jobs for Automated Database Refresh
#######################################################
# Automates daily production database cloning and Saturday data setup
#######################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

#######################################################
# Cron Job Configurations
#######################################################

setup_daily_database_refresh() {
    log_info "Setting up daily database refresh (3 AM)..."

    # Create wrapper script that logs output
    cat > "${PROJECT_ROOT}/scripts/cron-daily-db-refresh.sh" << 'DAILY_SCRIPT'
#!/bin/bash
# Daily database refresh - runs at 3 AM
# Logs to: /var/log/forge-pr-testing/db-refresh.log

set -euo pipefail

LOG_DIR="/var/log/forge-pr-testing"
LOG_FILE="${LOG_DIR}/db-refresh-$(date +%Y%m%d).log"

# Create log directory if needed
mkdir -p "$LOG_DIR"

# Redirect all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "=========================================="
echo "Daily Database Refresh - $(date)"
echo "=========================================="

cd /home/dev/project-analysis/laravel-forge-pr-testing

# Step 1: Clone production database
echo ""
echo "Step 1: Cloning production database..."
if ./scripts/clone-production-database.sh; then
    echo "✅ Database cloning successful"
else
    echo "❌ Database cloning failed"
    exit 1
fi

# Step 2: Transform to Saturday peak data
echo ""
echo "Step 2: Transforming to Saturday peak data..."
if yes yes | ./scripts/saturday-peak-data.sh; then
    echo "✅ Saturday data transformation successful"
else
    echo "❌ Saturday data transformation failed"
    exit 1
fi

# Step 3: Verify data
echo ""
echo "Step 3: Verifying driver screen data..."
ssh forge@159.65.213.130 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge -e 'SELECT COUNT(*) as visible_orders FROM orders WHERE DATE(created_at) = DATE_ADD(CURDATE(), INTERVAL (6 - DAYOFWEEK(CURDATE())) DAY) AND HOUR(created_at) BETWEEN 17 AND 20;'"

echo ""
echo "=========================================="
echo "Daily Refresh Complete - $(date)"
echo "=========================================="
echo ""

# Clean up old logs (keep last 14 days)
find "$LOG_DIR" -name "db-refresh-*.log" -mtime +14 -delete 2>/dev/null || true
DAILY_SCRIPT

    chmod +x "${PROJECT_ROOT}/scripts/cron-daily-db-refresh.sh"
    log_success "Daily refresh script created"

    # Add to crontab
    local cron_entry="0 3 * * * ${PROJECT_ROOT}/scripts/cron-daily-db-refresh.sh"

    if crontab -l 2>/dev/null | grep -q "cron-daily-db-refresh.sh"; then
        log_warning "Cron job already exists, skipping..."
    else
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        log_success "Cron job added: Daily at 3 AM"
    fi
}

setup_pre_pr_refresh() {
    log_info "Setting up PR-triggered database refresh..."

    # GitHub Actions will call this before creating PR environment
    cat > "${PROJECT_ROOT}/scripts/cron-pr-triggered-refresh.sh" << 'PR_SCRIPT'
#!/bin/bash
# PR-triggered database refresh
# Called by GitHub Actions when PR is opened

set -euo pipefail

PR_NUMBER="${1:-unknown}"
LOG_DIR="/var/log/forge-pr-testing"
LOG_FILE="${LOG_DIR}/pr-${PR_NUMBER}-$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "=========================================="
echo "PR #${PR_NUMBER} Database Setup - $(date)"
echo "=========================================="

cd /home/dev/project-analysis/laravel-forge-pr-testing

# Clone fresh production data for this PR
./scripts/clone-production-database.sh

# Transform to Saturday peak
yes yes | ./scripts/saturday-peak-data.sh

echo ""
echo "✅ PR environment database ready"
echo "Log: $LOG_FILE"
echo ""
PR_SCRIPT

    chmod +x "${PROJECT_ROOT}/scripts/cron-pr-triggered-refresh.sh"
    log_success "PR-triggered refresh script created"
}

setup_weekly_full_refresh() {
    log_info "Setting up weekly full database refresh (Sunday 2 AM)..."

    cat > "${PROJECT_ROOT}/scripts/cron-weekly-full-refresh.sh" << 'WEEKLY_SCRIPT'
#!/bin/bash
# Weekly full refresh - Sundays at 2 AM
# - Clones production database
# - Clears old test databases
# - Updates all test environments

set -euo pipefail

LOG_DIR="/var/log/forge-pr-testing"
LOG_FILE="${LOG_DIR}/weekly-refresh-$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "=========================================="
echo "Weekly Full Refresh - $(date)"
echo "=========================================="

cd /home/dev/project-analysis/laravel-forge-pr-testing

# Step 1: Clean up old backups (keep last 10)
echo "Cleaning old backups..."
ls -t backups/keatchen_prod_*.sql 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
ls -t backups/keatchen_sanitized_*.sql 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true

# Step 2: Clone fresh production database
echo "Cloning production database..."
./scripts/clone-production-database.sh

# Step 3: Transform to Saturday peak
echo "Setting up Saturday peak data..."
yes yes | ./scripts/saturday-peak-data.sh

# Step 4: Report statistics
echo ""
echo "Statistics:"
ssh forge@159.65.213.130 "mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge << 'SQL'
SELECT
    'Total Orders' as metric,
    COUNT(*) as count
FROM orders
UNION ALL
SELECT
    'Saturday Peak Orders',
    COUNT(*)
FROM orders
WHERE DATE(created_at) = DATE_ADD(CURDATE(), INTERVAL (6 - DAYOFWEEK(CURDATE())) DAY)
  AND HOUR(created_at) BETWEEN 17 AND 20;
SQL
"

echo ""
echo "=========================================="
echo "Weekly Refresh Complete - $(date)"
echo "=========================================="
WEEKLY_SCRIPT

    chmod +x "${PROJECT_ROOT}/scripts/cron-weekly-full-refresh.sh"
    log_success "Weekly refresh script created"

    # Add to crontab (Sunday 2 AM)
    local cron_entry="0 2 * * 0 ${PROJECT_ROOT}/scripts/cron-weekly-full-refresh.sh"

    if crontab -l 2>/dev/null | grep -q "cron-weekly-full-refresh.sh"; then
        log_warning "Weekly cron job already exists, skipping..."
    else
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        log_success "Cron job added: Weekly on Sundays at 2 AM"
    fi
}

show_current_cron_jobs() {
    log_info "Current cron jobs for PR testing system:"
    echo ""

    crontab -l 2>/dev/null | grep -E "forge-pr-testing|clone-production|saturday-peak" || echo "No cron jobs found"

    echo ""
}

remove_all_cron_jobs() {
    log_warning "Removing all PR testing cron jobs..."

    crontab -l 2>/dev/null | grep -v "forge-pr-testing" | grep -v "clone-production" | grep -v "saturday-peak" | crontab - 2>/dev/null || true

    log_success "All PR testing cron jobs removed"
}

#######################################################
# Main Menu
#######################################################

show_menu() {
    echo ""
    echo "================================================"
    echo "  Cron Job Setup for PR Testing System"
    echo "================================================"
    echo ""
    echo "1. Setup Daily Refresh (3 AM)"
    echo "2. Setup Weekly Full Refresh (Sunday 2 AM)"
    echo "3. Setup PR-Triggered Refresh"
    echo "4. Setup All Cron Jobs"
    echo "5. Show Current Cron Jobs"
    echo "6. Remove All Cron Jobs"
    echo "7. Exit"
    echo ""
}

main() {
    if [ $# -eq 0 ]; then
        # Interactive mode
        while true; do
            show_menu
            read -p "Select option (1-7): " choice

            case $choice in
                1)
                    setup_daily_database_refresh
                    ;;
                2)
                    setup_weekly_full_refresh
                    ;;
                3)
                    setup_pre_pr_refresh
                    ;;
                4)
                    setup_daily_database_refresh
                    setup_weekly_full_refresh
                    setup_pre_pr_refresh
                    log_success "All cron jobs configured!"
                    ;;
                5)
                    show_current_cron_jobs
                    ;;
                6)
                    remove_all_cron_jobs
                    ;;
                7)
                    echo "Exiting..."
                    exit 0
                    ;;
                *)
                    log_warning "Invalid option. Please select 1-7."
                    ;;
            esac

            read -p "Press Enter to continue..."
        done
    else
        # Command-line mode
        case "$1" in
            daily)
                setup_daily_database_refresh
                ;;
            weekly)
                setup_weekly_full_refresh
                ;;
            pr)
                setup_pre_pr_refresh
                ;;
            all)
                setup_daily_database_refresh
                setup_weekly_full_refresh
                setup_pre_pr_refresh
                ;;
            show)
                show_current_cron_jobs
                ;;
            remove)
                remove_all_cron_jobs
                ;;
            *)
                echo "Usage: $0 {daily|weekly|pr|all|show|remove}"
                exit 1
                ;;
        esac
    fi
}

# Run main
main "$@"
