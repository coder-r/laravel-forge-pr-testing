#!/bin/bash
set -euo pipefail

#######################################################
# Saturday Peak Data Transformation Script
#######################################################
# Transforms production orders to simulate Saturday 6pm peak
# Goal: Show driver screen with 102 orders from Saturday evening
#######################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test Environment
TEST_HOST="159.65.213.130"
TEST_USER="forge"
TEST_DB="forge"
SSH_KEY="${FORGE_SSH_KEY:-$HOME/.ssh/id_rsa}"

# Target Saturday configuration
TARGET_SATURDAY="2025-11-09"  # Next Saturday
TARGET_TIME="18:00:00"        # 6pm peak time
ORDERS_TO_SHOW=102            # Number of orders for driver screen

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

analyze_production_data() {
    log_info "Analyzing production order patterns..."

    # Get order count by day of week from production data
    ssh -i "$SSH_KEY" "${TEST_USER}@${TEST_HOST}" << 'REMOTE_ANALYSIS'
#!/bin/bash
mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge << 'SQL'
-- Order distribution by day of week
SELECT
    DAYNAME(created_at) as day_name,
    COUNT(*) as order_count,
    MIN(created_at) as earliest,
    MAX(created_at) as latest
FROM orders
GROUP BY DAYNAME(created_at), DAYOFWEEK(created_at)
ORDER BY DAYOFWEEK(created_at);

-- Peak hour analysis
SELECT
    HOUR(created_at) as hour,
    COUNT(*) as order_count
FROM orders
WHERE DAYNAME(created_at) = 'Saturday'
GROUP BY HOUR(created_at)
ORDER BY order_count DESC
LIMIT 5;
SQL
REMOTE_ANALYSIS

    log_success "Production data analysis complete"
}

find_saturday_peak_orders() {
    log_info "Finding Saturday peak period orders..."

    ssh -i "$SSH_KEY" "${TEST_USER}@${TEST_HOST}" << 'REMOTE_FIND'
#!/bin/bash
mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge << 'SQL'
-- Find most recent Saturday with high order volume
SELECT
    DATE(created_at) as order_date,
    COUNT(*) as total_orders,
    COUNT(CASE WHEN HOUR(created_at) BETWEEN 17 AND 20 THEN 1 END) as peak_hours
FROM orders
WHERE DAYNAME(created_at) = 'Saturday'
GROUP BY DATE(created_at)
HAVING total_orders >= 80
ORDER BY order_date DESC
LIMIT 3;
SQL
REMOTE_FIND

    log_success "Saturday peak periods identified"
}

transform_timestamps() {
    log_info "Transforming timestamps to target Saturday..."
    log_info "Target: $TARGET_SATURDAY at $TARGET_TIME"
    log_warning "This will modify the test database (NOT production)"

    # Calculate the transformation
    ssh -i "$SSH_KEY" "${TEST_USER}@${TEST_HOST}" << REMOTE_TRANSFORM
#!/bin/bash
mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge << 'SQL'
-- Step 1: Backup original timestamps
CREATE TABLE IF NOT EXISTS orders_timestamp_backup AS
SELECT id, created_at, updated_at FROM orders;

-- Step 2: Find a good Saturday with enough orders
SET @source_saturday = (
    SELECT DATE(created_at)
    FROM orders
    WHERE DAYNAME(created_at) = 'Saturday'
    GROUP BY DATE(created_at)
    HAVING COUNT(*) >= 100
    ORDER BY DATE(created_at) DESC
    LIMIT 1
);

-- Step 3: Calculate time difference
SET @target_date = '${TARGET_SATURDAY} ${TARGET_TIME}';
SET @time_diff = TIMESTAMPDIFF(SECOND,
    CONCAT(@source_saturday, ' 18:00:00'),
    @target_date
);

-- Step 4: Transform timestamps for Saturday orders
UPDATE orders
SET
    created_at = DATE_ADD(created_at, INTERVAL @time_diff SECOND),
    updated_at = DATE_ADD(updated_at, INTERVAL @time_diff SECOND)
WHERE DATE(created_at) = @source_saturday;

-- Step 5: Show transformation results
SELECT
    'Transformation Complete' as status,
    COUNT(*) as orders_moved,
    MIN(created_at) as new_earliest,
    MAX(created_at) as new_latest
FROM orders
WHERE DATE(created_at) = '${TARGET_SATURDAY}';

-- Step 6: Show peak hour count
SELECT
    DATE(created_at) as order_date,
    HOUR(created_at) as hour,
    COUNT(*) as order_count
FROM orders
WHERE DATE(created_at) = '${TARGET_SATURDAY}'
GROUP BY DATE(created_at), HOUR(created_at)
ORDER BY hour;
SQL

echo ""
echo "✅ Timestamp transformation complete!"
echo "Orders are now positioned at: ${TARGET_SATURDAY} ${TARGET_TIME}"
REMOTE_TRANSFORM

    log_success "Timestamps transformed successfully"
}

verify_driver_screen_data() {
    log_info "Verifying driver screen will show correct data..."

    ssh -i "$SSH_KEY" "${TEST_USER}@${TEST_HOST}" << REMOTE_VERIFY
#!/bin/bash
mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge << 'SQL'
-- Orders that should appear on driver screen
SELECT
    '${TARGET_SATURDAY} 17:00 - 20:00' as time_window,
    COUNT(*) as visible_orders,
    COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending,
    COUNT(CASE WHEN status = 'confirmed' THEN 1 END) as confirmed,
    COUNT(CASE WHEN status = 'preparing' THEN 1 END) as preparing,
    COUNT(CASE WHEN status = 'ready' THEN 1 END) as ready,
    COUNT(CASE WHEN status = 'out_for_delivery' THEN 1 END) as out_for_delivery
FROM orders
WHERE DATE(created_at) = '${TARGET_SATURDAY}'
  AND HOUR(created_at) BETWEEN 17 AND 20;

-- Expected vs actual
SELECT
    ${ORDERS_TO_SHOW} as target_orders,
    COUNT(*) as actual_orders,
    CASE
        WHEN COUNT(*) >= ${ORDERS_TO_SHOW} THEN '✅ Target Met'
        ELSE '⚠️  Need More Orders'
    END as status
FROM orders
WHERE DATE(created_at) = '${TARGET_SATURDAY}'
  AND HOUR(created_at) BETWEEN 17 AND 20;
SQL
REMOTE_VERIFY

    log_success "Driver screen verification complete"
}

create_restore_script() {
    log_info "Creating restore script for rollback..."

    cat > "${SCRIPT_DIR}/restore-original-timestamps.sh" << 'RESTORE_SCRIPT'
#!/bin/bash
# Restore original timestamps if needed
ssh -i "${FORGE_SSH_KEY:-$HOME/.ssh/id_rsa}" forge@159.65.213.130 << 'REMOTE'
mysql -u forge -p'fXcAINwUflS64JVWQYC5' forge << 'SQL'
UPDATE orders o
INNER JOIN orders_timestamp_backup b ON o.id = b.id
SET o.created_at = b.created_at,
    o.updated_at = b.updated_at;

SELECT 'Timestamps restored' as status, COUNT(*) as orders_restored FROM orders;
SQL
REMOTE
RESTORE_SCRIPT

    chmod +x "${SCRIPT_DIR}/restore-original-timestamps.sh"
    log_success "Restore script created: restore-original-timestamps.sh"
}

#######################################################
# Main Execution
#######################################################

main() {
    echo ""
    echo "================================================"
    echo "  Saturday Peak Data Transformation"
    echo "================================================"
    echo ""
    echo "Target: ${TARGET_SATURDAY} at ${TARGET_TIME}"
    echo "Expected orders: ${ORDERS_TO_SHOW}+"
    echo "Database: ${TEST_HOST} (${TEST_DB})"
    echo ""
    log_warning "This will MODIFY test database timestamps"
    log_info "Production database will NOT be affected"
    echo ""

    read -p "Continue with transformation? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log_info "Transformation cancelled"
        exit 0
    fi

    analyze_production_data
    find_saturday_peak_orders
    transform_timestamps
    verify_driver_screen_data
    create_restore_script

    echo ""
    echo "================================================"
    echo "  ✅ Saturday Peak Data Ready!"
    echo "================================================"
    echo ""
    echo "Driver screen should now show 102+ orders"
    echo "Date: ${TARGET_SATURDAY}"
    echo "Time: 17:00 - 20:00 (peak hours)"
    echo ""
    echo "Test the driver app at:"
    echo "  http://159.65.213.130/driver"
    echo ""
    echo "To restore original timestamps:"
    echo "  ./scripts/restore-original-timestamps.sh"
    echo ""
}

# Run main function
main "$@"
