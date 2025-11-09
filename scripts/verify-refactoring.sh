#!/bin/bash

################################################################################
# verify-refactoring.sh
#
# Verification script for orchestrate-pr-system.sh refactoring
#
# Checks that:
#   - Library is properly sourced
#   - All library functions are called correctly
#   - No manual api_request calls remain
#   - Syntax is valid
#   - All expected functions exist
#
# Usage:
#   ./verify-refactoring.sh
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/orchestrate-pr-system.sh"
LIBRARY_FILE="$SCRIPT_DIR/lib/forge-api.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS_COUNT=0
FAIL_COUNT=0

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Orchestration Script Refactoring Verification"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS_COUNT++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL_COUNT++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Test 1: Files exist
test_files_exist() {
    info "Checking file existence..."

    if [[ -f "$TARGET_SCRIPT" ]]; then
        pass "Target script exists: $TARGET_SCRIPT"
    else
        fail "Target script missing: $TARGET_SCRIPT"
        return 1
    fi

    if [[ -f "$LIBRARY_FILE" ]]; then
        pass "Library file exists: $LIBRARY_FILE"
    else
        fail "Library file missing: $LIBRARY_FILE"
        return 1
    fi

    if [[ -x "$TARGET_SCRIPT" ]]; then
        pass "Target script is executable"
    else
        fail "Target script is not executable"
    fi
}

# Test 2: Syntax validation
test_syntax() {
    info "Validating bash syntax..."

    if bash -n "$TARGET_SCRIPT" 2>/dev/null; then
        pass "Script syntax is valid"
    else
        fail "Script has syntax errors"
        bash -n "$TARGET_SCRIPT"
        return 1
    fi
}

# Test 3: Library sourcing
test_library_sourcing() {
    info "Checking library sourcing..."

    if grep -q "source.*lib/forge-api.sh" "$TARGET_SCRIPT"; then
        pass "Library is sourced"
    else
        fail "Library source line not found"
        return 1
    fi

    if grep -q "forge_api_init" "$TARGET_SCRIPT"; then
        pass "forge_api_init is called"
    else
        fail "forge_api_init is not called"
    fi
}

# Test 4: No manual API calls remain
test_no_manual_api_calls() {
    info "Checking for manual API calls..."

    local manual_calls=$(grep -c "api_request.*POST\|api_request.*GET\|api_request.*PUT\|api_request.*DELETE" "$TARGET_SCRIPT" || true)

    if [[ $manual_calls -eq 0 ]]; then
        pass "No manual api_request calls found"
    else
        fail "Found $manual_calls manual api_request calls"
        warn "Manual API calls should use library functions"
        grep -n "api_request.*POST\|api_request.*GET\|api_request.*PUT\|api_request.*DELETE" "$TARGET_SCRIPT" || true
    fi
}

# Test 5: Library function usage
test_library_functions() {
    info "Checking library function usage..."

    local functions=(
        "create_server"
        "get_server"
        "list_servers"
        "create_site"
        "get_site"
        "create_database"
        "list_databases"
        "install_git_repository"
        "deploy_site"
        "update_environment"
        "create_worker"
        "obtain_letsencrypt_certificate"
        "get_deployment_log"
    )

    local found_count=0

    for func in "${functions[@]}"; do
        if grep -q "$func" "$TARGET_SCRIPT"; then
            ((found_count++))
        fi
    done

    if [[ $found_count -eq ${#functions[@]} ]]; then
        pass "All ${#functions[@]} library functions are used"
    else
        warn "Found $found_count/${#functions[@]} library functions"

        for func in "${functions[@]}"; do
            if ! grep -q "$func" "$TARGET_SCRIPT"; then
                echo "  Missing: $func"
            fi
        done
    fi
}

# Test 6: Function signatures
test_function_signatures() {
    info "Checking renamed functions..."

    local renamed_functions=(
        "create_site_on_server"
        "create_database_for_pr"
        "install_git_repo"
        "update_env_vars"
        "create_queue_worker"
        "obtain_ssl_cert"
        "deploy_code_to_site"
    )

    local found=0
    for func in "${renamed_functions[@]}"; do
        if grep -q "^${func}()" "$TARGET_SCRIPT"; then
            ((found++))
        fi
    done

    if [[ $found -eq ${#renamed_functions[@]} ]]; then
        pass "All renamed functions present"
    else
        warn "Found $found/${#renamed_functions[@]} renamed functions"
    fi
}

# Test 7: Check for JSON payloads
test_no_manual_json() {
    info "Checking for manual JSON payloads..."

    local json_count=$(grep -c "local payload=\$(cat <<EOF" "$TARGET_SCRIPT" || true)

    if [[ $json_count -eq 0 ]]; then
        pass "No manual JSON payloads found"
    else
        warn "Found $json_count manual JSON payloads (expected 0)"
        info "Library functions should handle JSON construction"
    fi
}

# Test 8: State management preserved
test_state_management() {
    info "Checking state management..."

    if grep -q "save_state()" "$TARGET_SCRIPT"; then
        pass "State management functions preserved"
    else
        fail "State management functions missing"
    fi

    if grep -q "execute_rollback()" "$TARGET_SCRIPT"; then
        pass "Rollback functions preserved"
    else
        fail "Rollback functions missing"
    fi
}

# Test 9: Logging preserved
test_logging() {
    info "Checking logging functions..."

    local log_functions=("log_info" "log_success" "log_error" "log_warning" "log_debug")
    local found=0

    for func in "${log_functions[@]}"; do
        if grep -q "${func}()" "$TARGET_SCRIPT"; then
            ((found++))
        fi
    done

    if [[ $found -eq ${#log_functions[@]} ]]; then
        pass "All logging functions preserved"
    else
        warn "Found $found/${#log_functions[@]} logging functions"
    fi
}

# Test 10: File size check
test_file_size() {
    info "Checking file size reduction..."

    local current_lines=$(wc -l < "$TARGET_SCRIPT")
    local backup_file="${TARGET_SCRIPT}.backup"

    if [[ -f "$backup_file" ]]; then
        local original_lines=$(wc -l < "$backup_file")
        local reduction=$((original_lines - current_lines))
        local percentage=$(echo "scale=1; ($reduction * 100) / $original_lines" | bc)

        if [[ $reduction -gt 0 ]]; then
            pass "Code reduced by $reduction lines (${percentage}%)"
            info "Original: $original_lines lines → Refactored: $current_lines lines"
        else
            warn "File size increased by $((current_lines - original_lines)) lines"
        fi
    else
        info "Backup file not found, skipping comparison"
        info "Current file: $current_lines lines"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Verification Summary"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo -e "  ${GREEN}Passed:${NC} $PASS_COUNT"
    echo -e "  ${RED}Failed:${NC} $FAIL_COUNT"
    echo ""

    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}✓ All verifications passed!${NC}"
        echo ""
        echo "The refactoring is complete and validated."
        echo "The orchestration script is ready for testing."
        echo ""
        return 0
    else
        echo -e "${RED}✗ Some verifications failed${NC}"
        echo ""
        echo "Please review the failures above and fix any issues."
        echo ""
        return 1
    fi
}

# Main execution
main() {
    print_header

    test_files_exist
    test_syntax
    test_library_sourcing
    test_no_manual_api_calls
    test_library_functions
    test_function_signatures
    test_no_manual_json
    test_state_management
    test_logging
    test_file_size

    print_summary
}

# Run verification
main
exit $?
